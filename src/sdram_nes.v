// Double-channel CL2 SDRAM controller for NES
// nand2mario 2024.3
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

import configPackage::*;

module sdram_nes #(
    // Clock frequency, max 66.7Mhz with current set of T_xx/CAS parameters.
    parameter         FREQ = 64_800_000,

    parameter [4:0]   CAS  = 4'd2,     // 2/3 cycles, set in mode register
    parameter [4:0]   T_WR = 4'd2,     // 2 cycles, write recovery
    parameter [4:0]   T_MRD= 4'd2,     // 2 cycles, mode register set
    parameter [4:0]   T_RP = 4'd2,     // 15ns, precharge to active
    parameter [4:0]   T_RCD= 4'd2,     // 15ns, active to r/w
    parameter [4:0]   T_RC = 4'd6      // 63ns, ref/active to ref/active
) (    
	inout  reg [SDRAM_DATA_WIDTH-1:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output     [SDRAM_ROW_WIDTH-1:0] SDRAM_A,    // 13 bit multiplexed address bus
	output reg [SDRAM_DATA_WIDTH/8-1:0] SDRAM_DQM,  // two byte masks
	output reg [1:0]  SDRAM_BA,   // two banks
	output            SDRAM_nCS,  // a single chip select
	output            SDRAM_nWE,  // write enable
	output            SDRAM_nRAS, // row address select
	output            SDRAM_nCAS, // columns address select
    output            SDRAM_CKE,

	// cpu/chipset interface
	input             clk,        // sdram clock
	input             resetn,
    input             clkref,
    output reg busy,

	input [21:0]      addrA,      // 4MB, bank 0/1
	input             weA,        // ppu requests write
	input [7:0]       dinA,       // data input from cpu
	input             oeA,        // ppu requests data
	output reg [7:0]  doutA,      // data output to cpu

	input [21:0]      addrB,      // 4MB, bank 0/1
	input             weB,        // cpu requests write
	input [7:0]       dinB,       // data input from ppu
	input             oeB,        // cpu requests data
	output reg [7:0]  doutB,      // data output to ppu

    // RISC-V softcore
    input      [20:1] rv_addr,      // 2MB RV memory space, bank 2
    input      [15:0] rv_din,       // 16-bit accesses
    input      [1:0]  rv_ds,
    output reg [15:0] rv_dout,
    input             rv_req,
    output reg        rv_req_ack,   // ready for new requests. read data available on NEXT mclk
    input             rv_we
);

localparam DQM_SIZE = SDRAM_DATA_WIDTH / 8;

// Tri-state DQ input/output
reg dq_oen;        // 0 means output
reg [SDRAM_DATA_WIDTH-1:0] dq_out;
assign SDRAM_DQ = dq_oen ? {SDRAM_DATA_WIDTH{1'bz}} : dq_out;
wire [SDRAM_DATA_WIDTH-1:0] dq_in = SDRAM_DQ;     // DQ input
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

localparam [2:0] BURST_LEN = 3'b0;      // burst length 1
localparam BURST_MODE = 1'b0;           // sequential
localparam [10:0] MODE_REG = {4'b0, CAS[2:0], BURST_MODE, BURST_LEN};
// 64ms/8192 rows = 7.8us -> 500 cycles@64.8MHz
localparam RFRSH_CYCLES = 9'd501;

// state
reg [16:0] cycle;       // one hot encoded
reg normal, setup;
reg cfg_now;            // pulse for configuration

// requests
reg [21:0] addr_latch[0:1];
reg [15:0] din_latch[0:1];
reg  [2:0] oe_latch;
reg  [2:0] we_latch;
reg  [1:0] ds[0:1];

localparam PORT_NONE  = 2'd0;

localparam PORT_A     = 2'd1;   // PPU
localparam PORT_B     = 2'd2;   // CPU

localparam PORT_RV    = 2'd1;

reg  [1:0] port[0:1];
reg  [1:0] next_port[0:1];
reg [21:0] next_addr[0:1];
reg [15:0] next_din[0:1];
reg  [1:0] next_ds[0:1];
reg  [2:0] next_we;
reg  [2:0] next_oe;

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
	else if (refresh_cnt == RFRSH_CYCLES)
		need_refresh <= 1;
end

// CPU/PPU: bank 0/1
always @(*) begin
	next_port[0] = PORT_NONE;
	next_addr[0] = 0;
	next_we[0] = 0;
	next_oe[0] = 0;
	next_ds[0] = 0;
	next_din[0] = 0;
    if (reqB) begin
		next_port[0] = PORT_B;
		next_addr[0] = addrB;
		next_din[0]  = {dinB, dinB};
		next_ds[0]   = {addrB[0], ~addrB[0]};
		next_we[0]   = weB;
		next_oe[0]   = oeB;
	end else if (reqA) begin
		next_port[0] = PORT_A;
		next_addr[0] = addrA;
		next_din[0] = {dinA, dinA};
		next_ds[0] = {addrA[0], ~addrA[0]};
		next_we[0] = weA;
		next_oe[0] = oeA;
	end 
end

// RV: bank 2
always @* begin
	next_port[1] = PORT_NONE;
	next_addr[1] = 0;
	next_we[1] = 0;
	next_oe[1] = 0;
	next_ds[1] = 0;
	next_din[1] = 0;
    if (rv_req ^ rv_req_ack) begin
		next_port[1] = PORT_RV;
		next_addr[1] = {rv_addr, 1'b0};
		next_we[1] = rv_we;
		next_oe[1] = ~rv_we;
		next_din[1] = rv_din;
		next_ds[1] = rv_ds;
	end 
end

//
// SDRAM state machine
//
always @(posedge clk) begin
    if (~resetn) begin
        busy <= 1'b1;
        dq_oen <= 1;
        SDRAM_DQM <= {DQM_SIZE{1'b1}};
        normal <= 0;
        setup <= 0;
    end else begin
        // defaults
        dq_oen <= 1'b1;
        SDRAM_DQM <= {DQM_SIZE{1'b1}};
        cmd <= CMD_NOP; 

        // wait 200 us on power-on
        if (~normal && ~setup && cfg_now) begin // wait 200 us on power-on
            setup <= 1;
            cycle <= 1;
        end 

        // setup process
        if (setup) begin
            cycle <= {cycle[15:0], 1'b0};       // cycle 0-16 for setup
            // configuration sequence
            if (cycle[0]) begin
                // precharge all
                cmd <= CMD_PreCharge;
                a[10] <= 1'b1;
                SDRAM_BA <= 0;
            end
            if (cycle[T_RP]) begin                  // 2
                // 1st AutoRefresh
                cmd <= CMD_AutoRefresh;
            end
            if (cycle[T_RP+T_RC]) begin             // 8
                // 2nd AutoRefresh
                cmd <= CMD_AutoRefresh;
            end
            if (cycle[T_RP+T_RC+T_RC]) begin        // 14
                // set register
                cmd <= CMD_SetModeReg;
                a[10:0] <= MODE_REG;
                SDRAM_BA <= 0;
            end
            if (cycle[T_RP+T_RC+T_RC+T_MRD]) begin  // 16
                setup <= 0;
                normal <= 1;
                cycle <= 1;
                busy <= 1'b0;               // init&config is done
            end
        end 
        if (normal) begin
            if (clkref & ~clkref_r)             // go to cycle 5 after clkref posedge
                cycle[5:0] <= 6'b10_0000;
            else
                cycle[5:0] <= {cycle[4:0], cycle[5]};
            refresh_cnt <= refresh_cnt + 1'd1;
            
            // RAS
            // CPU, PPU
            if (cycle[0]) begin
    			port[0] <= next_port[0];
                oeA_d <= oeA_d & oeA; weA_d <= weA_d & weA;
                oeB_d <= oeB_d & oeB; weB_d <= weB_d & weB;
                if (next_port[0] == PORT_A) begin
                    oeA_d <= oeA; weA_d <= weA;
                end
                if (next_port[0] == PORT_B) begin
                    oeB_d <= oeB; weB_d <= weB;
                end
	    		{ we_latch[0], oe_latch[0] } <= { next_we[0], next_oe[0] };
    			addr_latch[0] <= next_addr[0];
                SDRAM_BA <= next_addr[0][21];       // bank 0 or 1
                din_latch[0] <= next_din[0];
                ds[0] <= next_ds[0];
                if (next_port[0] != PORT_NONE) cmd <= CMD_BankActivate;
	    		a <= next_addr[0][20:10];
            end

            // bank 1 - RV
            if (cycle[2]) begin
                port[1] <= next_port[1];
                { we_latch[1], oe_latch[1] } <= { next_we[1], next_oe[1] };
                addr_latch[1] <= next_addr[1];
                a <= next_addr[1][20:10];
                SDRAM_BA <= 2'd2;
                din_latch[1] <= next_din[1];
                ds[1] <= next_ds[1];
                if (next_port[1] != PORT_NONE) begin 
                    cmd <= CMD_BankActivate; 
                end else if (!we_latch[0] && !oe_latch[0] && !we_latch[1] && !oe_latch[1] && need_refresh) begin
                    refresh_cnt <= 0;
                    cmd <= CMD_AutoRefresh;
                end
            end

            // CAS
            // CPU, PPU
            if (cycle[1] && (oe_latch[0] || we_latch[0])) begin
                cmd <= we_latch[0]?CMD_Write:CMD_Read;
                SDRAM_BA <= addr_latch[0][21];
`ifdef NANO  
                a <= addr_latch[0][9:2];
`else
                a <= addr_latch[0][9:1];
`endif
                a[10] <= 1'b1;                // auto precharge
                if (we_latch[0]) begin
                    dq_oen <= 0;
`ifdef NANO
                    SDRAM_DQM <= addr_latch[0][1] ? {~ds[0], 2'b11}  : {2'b11, ~ds[0]};
                    dq_out <= {din_latch[0], din_latch[0]};
`else
                    SDRAM_DQM <= ~ds[0];
                    dq_out <= din_latch[0];
`endif
                end else
                    SDRAM_DQM <= 0;
            end

            // RV
            if (cycle[4] && (oe_latch[1] || we_latch[1])) begin
                cmd <= we_latch[1]?CMD_Write:CMD_Read;
			    SDRAM_BA <= 2'd2;
`ifdef NANO
                a <= addr_latch[1][9:2];  
`else
                a <= addr_latch[1][9:1];  
`endif
                a[10] <= 1'b1;// auto precharge
                if (we_latch[1]) begin
                    dq_oen <= 0;
`ifdef NANO
                    SDRAM_DQM <= addr_latch[1][1] ? {~ds[1], 2'b11} : {2'b11, ~ds[1]};
                    dq_out <= {din_latch[1], din_latch[1]};
`else
                    SDRAM_DQM <= ~ds[1];
                    dq_out <= din_latch[1];
`endif
                end else
                    SDRAM_DQM <= 0;
                rv_req_ack <= rv_req;       // ack request
            end

            // read
            // CPU, PPU
            if (cycle[4] && oe_latch[0]) begin
                reg [7:0] dq_byte;
`ifdef NANO
                case (addr_latch[0][1:0])
                2'd0: dq_byte = dq_in[7:0];
                2'd1: dq_byte = dq_in[15:8];
                2'd2: dq_byte = dq_in[23:16];
                2'd3: dq_byte = dq_in[31:24];
                endcase
`else
                dq_byte = addr_latch[0][0] ? dq_in[15:8] : dq_in[7:0];
`endif

                case (port[0])
                PORT_A: doutA <= dq_byte;
                PORT_B: doutB <= dq_byte;
                default: ;
                endcase
            end

            // RV
            if (cycle[1] && oe_latch[1]) 
`ifdef NANO
                rv_dout <= addr_latch[1][1] ? dq_in[31:16] : dq_in[15:0];
`else
                rv_dout <= dq_in;
`endif
        end
    end
end

//
// Generate cfg_now pulse after initialization delay (normally 200us)
//
reg  [14:0]   rst_cnt;
reg rst_done, rst_done_p1, cfg_busy;
  
always @(posedge clk) begin
    if (~resetn) begin
        rst_cnt  <= 15'd0;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end else begin
        rst_done_p1 <= rst_done;
        cfg_now     <= rst_done & ~rst_done_p1;// Rising Edge Detect

        if (rst_cnt != FREQ / 1000 * 200 / 1000) begin      // count to 200 us
            rst_cnt  <= rst_cnt[14:0] + 15'd1;
            rst_done <= 1'b0;
            cfg_busy <= 1'b1;
        end else begin
            rst_done <= 1'b1;
            cfg_busy <= 1'b0;
        end        
    end
end

endmodule