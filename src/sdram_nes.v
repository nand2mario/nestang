// Double-channel CL2 SDRAM controller for NES
// nand2mario 2024.3 | @fjpolo 2024.07
//
// clk_#    CPU/PPU     RISC-V      clkref
//   0      RAS1                      1
//   1      CAS1        DATA2         0
//   2                  RAS2/Refresh  0
//   3                                0
//   4      DATA1       CAS2          1
//   5                                1
// 
// CPU/PPU requests have to be issued on clkref==1, or they get lost.
// RISC-V requests use req/ack interface, so they can be issued anytime.
//
// For both Nano 20K (32-bit total 8MB) and Primer 25K (16-bit total 32MB)

`ifndef FORMAL
import configPackage::*;
`else
    localparam SDRAM_DATA_WIDTH = 16;
    localparam SDRAM_ROW_WIDTH = 13;
    localparam SDRAM_COL_WIDTH = 9;
    localparam SDRAM_BANK_WIDTH = 2;
`endif

module sdram_init_fsm (
    input wire clk,
    input wire resetn,
    input wire start,
    output reg busy,
    output reg [3:0] cmd,
    output reg [SDRAM_ROW_WIDTH-1:0] a,
    output reg [1:0] SDRAM_BA,
    output reg init_done
);

localparam [4:0] T_MRD = 5'd2;  // Mode Register Set delay
localparam [4:0] T_RP = 5'd2;   // Precharge delay
localparam [4:0] T_RC = 5'd6;   // Refresh cycle time

localparam CMD_NOP = 4'b1111;
localparam CMD_SetModeReg = 4'b0000;
localparam CMD_BankActivate = 4'b0011;
localparam CMD_AutoRefresh = 4'b0001;
localparam CMD_PreCharge = 4'b0010;

reg [15:0] cycle;
reg [10:0] MODE_REG;

initial cycle = 0;
initial cmd = CMD_NOP;

always @(posedge clk) begin
    if (~resetn) begin
        busy <= 1'b1;
        cmd <= CMD_NOP;
        cycle <= 0;
        init_done <= 1'b0;
    end else if (start) begin
        if(cycle == T_RP + T_RC + T_RC + T_MRD) begin
            busy <= 1'b0;
            init_done <= 1'b1;
        end else begin
            busy <= 1'b1;
            init_done <= 1'b0;
        end
        if (cycle == 0) begin
            // Precharge all
            cmd <= CMD_PreCharge;
            a[10] <= 1'b1;
            SDRAM_BA <= 0;
            cycle <= cycle + 1;
        end else if (cycle == T_RP) begin
            // First AutoRefresh
            cmd <= CMD_AutoRefresh;
            cycle <= cycle + 1;
        end else if (cycle == T_RP + T_RC) begin
            // Second AutoRefresh
            cmd <= CMD_AutoRefresh;
            cycle <= cycle + 1;
        end else if (cycle == T_RP + T_RC + T_RC) begin
            // Set Mode Register
            cmd <= CMD_SetModeReg;
            a[10:0] <= MODE_REG;
            SDRAM_BA <= 0;
            cycle <= cycle + 1;
        end else if (cycle == T_RP + T_RC + T_RC + T_MRD) begin
            // Initialization done
            cmd <= CMD_NOP;
        end else begin
            cycle <= cycle + 1;
        end
    end
end

//
// Formal Methods
//
`ifdef	FORMAL

    `ifdef F_SDRAM_INIT_FSM
        `define	ASSUME	assume
    `else
        `define	ASSUME	assert
    `endif

    // f_past_valid
    reg	f_past_valid;
    initial	f_past_valid = 1'b0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    // Initialization sequence
    // After reset (resetn), busy should be high until initialization is complete (init_done high).
    always @(posedge clk) begin
        if((f_past_valid)&&(~$past(resetn))) begin
            assert((busy)&&(~init_done));
        end
    end

    always @(*)
        if((!f_past_valid)||~(resetn)) begin
            assume(cmd == CMD_NOP);
            assume(~busy);
        end

    // cycle
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn))) begin
            assert(cycle <= (T_RP + T_RC + T_RC + T_MRD));
        end
    end

    // 
    // Contract
    // 
    wire [15:0] f_cycle;

    always @(*)
        assume(f_cycle == cycle);

    always @(posedge clk)
        if((f_past_valid)&&(~$past(resetn)))
            assume($fell(start));

    initial assert(cmd == CMD_NOP);

    //  After start signal is asserted, the module should execute the precharge (CMD_PreCharge), 
    // followed by two auto-refresh cycles (CMD_AutoRefresh), then set the mode register (CMD_SetModeReg), and finally indicate init_done
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn))) begin
            if($past(start))
                if(($past(f_cycle == 0))&&($past(start)))
                    assert(cmd == CMD_PreCharge);
            else
                if(($past(cycle) == (T_RP)))
                        assert((cmd == CMD_AutoRefresh)&&(busy)&&(~init_done));
                if(($past(cycle) == (T_RP + T_RC))&&($past(cmd) == CMD_AutoRefresh))
                        assert((cmd == CMD_AutoRefresh)&&(busy)&&(~init_done));
                if(($past(cycle) == (T_RP + T_RC + T_RC))&&($past(cmd) == CMD_AutoRefresh)&&(cycle == (T_RP + T_RC + T_RC + 1)))
                        assert((cmd == CMD_SetModeReg)&&(busy)&&(~init_done));
                if(($past(cycle) == (T_RP + T_RC + T_RC + T_MRD))&&($past(cmd) == CMD_SetModeReg)&&(cycle == (T_RP + T_RC + T_RC + 1)))
                        assert((cmd == CMD_NOP)&&(~busy)&&(init_done));
        end
    end

`endif // FORMAL

endmodule

module sdram_refresh_fsm (
    input wire clk,
    input wire resetn,
    input wire start,
    output reg busy,
    output reg [3:0] cmd
);

localparam CMD_NOP = 4'b1111;
localparam CMD_AutoRefresh = 4'b0001;
localparam REFRSH_CYCLES = 9'd501;

reg [8:0] refresh_cnt;

initial refresh_cnt = 0;

always @(posedge clk) begin
    if (~resetn) begin
        busy <= 1'b0;
        refresh_cnt <= 0;
        cmd <= CMD_NOP;
    end else if (start && (refresh_cnt == REFRSH_CYCLES)) begin
        busy <= 1'b1;
        cmd <= CMD_AutoRefresh;
        refresh_cnt <= 0;
    end else if (busy) begin
        busy <= 1'b0;
        cmd <= CMD_NOP;
    end else begin
        refresh_cnt <= refresh_cnt + 1;
    end
end

//
// Formal Methods
//
`ifdef	FORMAL

    `ifdef F_SDRAM_REFRESH_FSM
        `define	ASSUME	assume
    `else
        `define	ASSUME	assert
    `endif

    // f_past_valid
    reg	f_past_valid;
    initial	f_past_valid = 1'b0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    // Reset
    // After reset (resetn), ensure that busy is low
    always @(posedge clk) begin
        if((f_past_valid)&&(~$past(resetn)))
            assert(~busy);
    end

    // Start
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            assume($fell(start));
    end
    // After asserting start, check that busy becomes high exactly when refresh_cnt reaches REFRSH_CYCLES
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            if($past(refresh_cnt == REFRSH_CYCLES))
                assert(busy);
            else if(refresh_cnt < REFRSH_CYCLES)
                assert(~busy);
    end


    // Cycle Counting
    //  Ensure that refresh_cnt increments correctly with each clock cycle when not in the busy state
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            assert(refresh_cnt <= REFRSH_CYCLES);
    end

    // 
    // Contract
    // 

    // State Transitions
    // Verify that cmd transitions correctly between CMD_NOP and CMD_AutoRefresh
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            if($past(refresh_cnt) == REFRSH_CYCLES)
                assert(cmd == CMD_AutoRefresh);
            else if(($past(refresh_cnt) == REFRSH_CYCLES)&&($past(cmd) == CMD_AutoRefresh))
                assert(cmd == CMD_NOP);
    end

`endif // FORMAL

endmodule

module sdram_rw_fsm (
    input wire clk,
    input wire resetn,
    input wire start,
    input wire we,
    input wire [21:0] addr,
    input wire [15:0] din,
    output reg [15:0] dout,
    output reg busy,
    output reg [3:0] cmd,
    output reg [SDRAM_ROW_WIDTH-1:0] a,
    output reg [1:0] SDRAM_BA,
    output reg dq_oen,
    output reg [1:0] SDRAM_DQM
);

localparam CMD_NOP = 4'b1111;
localparam CMD_BankActivate = 4'b0011;
localparam CMD_Write = 4'b0100;
localparam CMD_Read = 4'b0101;

always @(posedge clk) begin
    if (~resetn) begin
        busy <= 1'b0;
        cmd <= CMD_NOP;
        dq_oen <= 1'b1;
    end else if (start) begin
        busy <= 1'b1;
        cmd <= CMD_BankActivate;
        SDRAM_BA <= addr[21:20];
        a <= addr[19:0];
    end else if (busy) begin
        if (we) begin
            cmd <= CMD_Write;
            dq_oen <= 1'b0;
            dout <= din;
        end else begin
            cmd <= CMD_Read;
            dq_oen <= 1'b1;
        end
        busy <= 1'b0;
    end else begin
        cmd <= CMD_NOP;
    end
end

//
// Formal Methods
//
`ifdef	FORMAL

    `ifdef F_SDRAM_RW_FSM
        `define	ASSUME	assume
    `else
        `define	ASSUME	assert
    `endif

    // f_past_valid
    reg	f_past_valid;
    initial	f_past_valid = 1'b0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    always @(posedge clk) begin
        if((f_past_valid)&&(~$past(resetn)))
            assume($fell(start));
    end

    // State Transitions:
    // After reset (resetn), ensure that busy is low, cmd is CMD_NOP, dq_oen is high, and dout is not driven (dout value is irrelevant)
    always @(posedge clk) begin
        if((f_past_valid)&&(~$past(resetn)))
            assert((~busy)&&(cmd == CMD_NOP));
    end
    // After asserting start, check that busy becomes high, cmd transitions to CMD_BankActivate, and appropriate values are assigned to SDRAM_BA and a.
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            if(($past(start))&&(~busy)) begin
                assume($fell(start));
                assert((busy)&&(cmd == CMD_BankActivate));
                assert(SDRAM_BA == $past(addr[21:20]));
                assert(a == $past(addr[19:0]));
            end
    end

    // 
    // Contract
    // 

    // Read
    // Verify that when we is not asserted (read operation) during the busy state, cmd transitions to CMD_Read and dq_oen remains enabled
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            if((~$past(start))&&($past(busy))&&($past(~we))) begin
                assert(cmd == CMD_Read);
                assert(dq_oen);
            end
    end
    // Write
    // Verify that when we is asserted during the busy state, cmd transitions to CMD_Write, dq_oen is low, and dout reflects the value of din.
    always @(posedge clk) begin
        if((f_past_valid)&&($past(resetn)))
            if((~$past(start))&&($past(busy))&&($past(we))) begin
                assert(cmd == CMD_Write);
                assert(~dq_oen);
                assert(dout == $past(din));
            end
    end

`endif // FORMAL

endmodule

module sdram_nes #(
    parameter         FREQ = 64_800_000,
    parameter [4:0]   CAS  = 4'd2,                  // 2/3 cycles, set in mode register
    parameter [4:0]   T_WR = 4'd2,                  // 2 cycles, write recovery
    parameter [4:0]   T_MRD= 4'd2,                  // 2 cycles, mode register set
    parameter [4:0]   T_RP = 4'd2,                  // 15ns, precharge to active
    parameter [4:0]   T_RCD= 4'd2,                  // 15ns, active to r/w
    parameter [4:0]   T_RC = 4'd6                   // 63ns, ref/active to ref/active  
) (    
	inout  reg [SDRAM_DATA_WIDTH-1:0] SDRAM_DQ,     // 16 bit bidirectional data bus
	output     [SDRAM_ROW_WIDTH-1:0] SDRAM_A,       // 13 bit multiplexed address bus
	output reg [SDRAM_DATA_WIDTH/8-1:0] SDRAM_DQM,  // two byte masks
	output reg [1:0]  SDRAM_BA,                     // two banks
	output            SDRAM_nCS,                    // a single chip select
	output            SDRAM_nWE,                    // write enable
	output            SDRAM_nRAS,                   // row address select
	output            SDRAM_nCAS,                   // columns address select
    output            SDRAM_CKE,
	
    // cpu/chipset interface
	input             clk,                          // sdram clock
	input             resetn,
    input             clkref,
    output reg busy,

	input [21:0]      addrA,                        // 4MB, bank 0/1
	input             weA,                          // ppu requests write
	input [7:0]       dinA,                         // data input from cpu
	input             oeA,                          // ppu requests data
	output reg [7:0]  doutA,                        // data output to cpu

	input [21:0]      addrB,                        // 4MB, bank 0/1
	input             weB,                          // cpu requests write
	input [7:0]       dinB,                         // data input from ppu
	input             oeB,                          // cpu requests data
	output reg [7:0]  doutB,                        // data output to ppu

    // RISC-V softcore
    input      [20:1] rv_addr,                      // 2MB RV memory space, bank 2
    input      [15:0] rv_din,                       // 16-bit accesses
    input      [1:0]  rv_ds,
    output reg [15:0] rv_dout,
    input             rv_req,
    output reg        rv_req_ack,                  // ready for new requests. read data available on NEXT mclk
    input             rv_we
);
localparam DQM_SIZE = SDRAM_DATA_WIDTH / 8;

// Tri-state DQ input/output
reg dq_oen;        
reg [SDRAM_DATA_WIDTH-1:0] dq_out;
assign SDRAM_DQ = dq_oen ? {SDRAM_DATA_WIDTH{1'bz}} : dq_out;
wire [SDRAM_DATA_WIDTH-1:0] dq_in = SDRAM_DQ;     
reg [3:0] cmd;
reg [SDRAM_ROW_WIDTH-1:0] a;
assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;
assign SDRAM_A = a;

assign SDRAM_CKE = 1'b1;

// CS# RAS# CAS# WE#
localparam CMD_NOP=4'b1111;
localparam CMD_SetModeReg=4'b0000;
localparam CMD_BankActivate=4'b0011;
localparam CMD_Write=4'b0100;
localparam CMD_Read=4'b0101;
localparam CMD_AutoRefresh=4'b0001;
localparam CMD_PreCharge=4'b0010;

localparam [2:0] BURST_LEN = 3'b0;      
localparam BURST_MODE = 1'b0;           
localparam [10:0] MODE_REG = {4'b0, CAS[2:0], BURST_MODE, BURST_LEN};
localparam REFRSH_CYCLES = 9'd501;

// Initialization FSM states
localparam INIT_IDLE = 3'd0, INIT_PRECHARGE = 3'd1, INIT_REFRESH1 = 3'd2, INIT_REFRESH2 = 3'd3, INIT_MODE_SET = 3'd4, INIT_DONE = 3'd5;
reg [2:0] init_state;
reg [8:0] cycle;  // Increase the bit width to handle larger values

reg cfg_now;  // Configuration now signal

// Request FSM states
localparam REQ_IDLE = 3'd0, REQ_ACTIVATE = 3'd1, REQ_READ_WRITE = 3'd2, REQ_WAIT = 3'd3;
reg [2:0] req_state_cpu, req_state_rv;

// Request Latches and Flags
reg [21:0] addr_latch[0:1];
reg [15:0] din_latch[0:1];
reg  [2:0] oe_latch;
reg  [2:0] we_latch;
reg  [1:0] ds[0:1];
reg [1:0] port[0:1];
reg oeA_d, oeB_d, weA_d, weB_d;
wire reqA = (~oeA_d & oeA) || (~weA_d & weA);
wire reqB = (~oeB_d & oeB) || (~weB_d & weB);
reg clkref_r;
always @(posedge clk) clkref_r <= clkref;

reg [8:0]  refresh_cnt;
reg        need_refresh = 1'b0;

always @(posedge clk) begin
    if (refresh_cnt == 0)
        need_refresh <= 0;
    else if (refresh_cnt == REFRSH_CYCLES)
        need_refresh <= 1;
end

// Generate cfg_now signal: Set cfg_now high for one cycle after reset
always @(posedge clk or negedge resetn) begin
    if (~resetn) begin
        cfg_now <= 1'b1;
    end else begin
        cfg_now <= 1'b0;
    end
end

// Initialization and CPU/PPU Request FSM
reg fsm_initialized;

initial fsm_initialized = 1'b0;

always @(posedge clk or negedge resetn) begin
    if (~resetn) begin
        fsm_initialized <= 1'b0;
        init_state <= INIT_IDLE;
        req_state_cpu <= REQ_IDLE;
        cmd <= CMD_NOP;
        cycle <= 1;
        SDRAM_DQM <= {DQM_SIZE{1'b1}}; // Initialize SDRAM_DQM
    // Initialization FSM
    end else if(!fsm_initialized) begin
        cycle <= cycle + 1;
        case (init_state)
            INIT_IDLE: begin
                if (cfg_now) begin
                    init_state <= INIT_PRECHARGE;
                    cycle <= 1;
                end
            end
            INIT_PRECHARGE: begin
                cmd <= CMD_PreCharge;
                a[10] <= 1'b1;
                SDRAM_BA <= 0;
                init_state <= INIT_REFRESH1;
                cycle <= 1; // Reset cycle
                SDRAM_DQM <= {DQM_SIZE{1'b1}}; // Set DQM to high impedance
            end
            INIT_REFRESH1: begin
                if (cycle == T_RP) begin
                    cmd <= CMD_AutoRefresh;
                    init_state <= INIT_REFRESH2;
                    cycle <= 1; // Reset cycle
                end
            end
            INIT_REFRESH2: begin
                if (cycle == T_RC) begin
                    cmd <= CMD_AutoRefresh;
                    init_state <= INIT_MODE_SET;
                    cycle <= 1; // Reset cycle
                end
            end
            INIT_MODE_SET: begin
                if (cycle == T_RC) begin
                    cmd <= CMD_SetModeReg;
                    a[10:0] <= MODE_REG;
                    SDRAM_BA <= 0;
                    init_state <= INIT_DONE;
                    cycle <= 1; // Reset cycle
                end
            end
            INIT_DONE: begin
                if (cycle == T_MRD) begin
                    fsm_initialized <= 1'b1;
                    busy <= 1'b0;
                    init_state <= INIT_IDLE;
                end
            end
        endcase
    // CPU/PPU Request FSM
    end else begin
        cycle <= cycle + 1;
        case (req_state_cpu)
            REQ_IDLE: begin
                if (reqA || reqB) begin
                    addr_latch[0] <= reqA ? addrA : addrB;
                    din_latch[0] <= reqA ? {dinA, dinA} : {dinB, dinB};
                    ds[0] <= reqA ? {addrA[0], ~addrA[0]} : {addrB[0], ~addrB[0]};
                    we_latch[0] <= reqA ? weA : weB;
                    oe_latch[0] <= reqA ? oeA : oeB;
                    SDRAM_BA <= addr_latch[0][21];
                    req_state_cpu <= REQ_ACTIVATE;
                    cycle <= 1;
                    SDRAM_DQM <= {DQM_SIZE{1'b1}}; // Set DQM to high impedance
                end
            end
            REQ_ACTIVATE: begin
                cmd <= CMD_BankActivate;
                a <= addr_latch[0];
                req_state_cpu <= REQ_READ_WRITE;
                cycle <= 1;
            end
            REQ_READ_WRITE: begin
                if (cycle == T_RCD) begin
                    cmd <= we_latch[0] ? CMD_Write : CMD_Read;
                    dq_out <= we_latch[0] ? din_latch[0] : {8{1'bz}};
                    dq_oen <= we_latch[0] ? 1'b0 : 1'b1;
                    doutA <= dq_in[7:0];
                    doutB <= dq_in[7:0];
                    req_state_cpu <= REQ_WAIT;
                    cycle <= 1;
                end
            end
            REQ_WAIT: begin
                if (cycle == T_WR) begin
                    req_state_cpu <= REQ_IDLE;
                    SDRAM_DQM <= {DQM_SIZE{1'b1}}; // Set DQM to high impedance
                end
            end
        endcase
    end
end

//
// Formal Methods
//
`ifdef	FORMAL

    `ifdef F_SDRAM
        `define	ASSUME	assume
    `else
        `define	ASSUME	assert
    `endif

    // f_past_valid
    reg	f_past_valid;
    initial	f_past_valid = 1'b0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    // 
    // Contract
    // 

`endif // FORMAL

endmodule
