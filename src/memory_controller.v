// Connects DDR3 controller to NES

// Memory layout:
// Total address space 4MB
// $00_0000 - $0f_ffff: PRG ROM 1MB
// $20_0000 - $2f_ffff: CHR ROM 1MB
// $38_0000 - $38_07ff: Internal RAM (2KB), and 126KB unused
// $3c_0000 - $3d_ffff: PRG RAM 128KB
module MemoryController(
    input clk,                // Main logic clock (1/3 of pclk)
    input pclk,               // DDR3 controller clock 96.75Mhz
    input fclk,               // DDR3 memory clock 387Mhz
    input ck,                 // Phase-shifted fclk
    input resetn,
    input read_a,             // Set to 1 to read from RAM
    input read_b,             // Set to 1 to read from RAM
    input write,              // Set to 1 to write to RAM
    input refresh,            // Set to 1 to auto-refresh RAM
    input [21:0] addr,        // Address to read / write
    input [7:0] din,          // Data to write
    output reg [7:0] dout_a,  // Last read data a, available 2 cycles after read_a is set
    output reg [7:0] dout_b,  // Last read data b, available 2 cycles after read_b is set
    output reg busy,          // 1 while an operation is in progress
    output reg fail,          // timing mistake or sdram malfunction detected

    // debug interface
    output reg [19:0] total_written,
    output reg [7:0] debug,
    output write_level_done,
    output [7:0] wstep,
    output read_calib_done,
    output [1:0] rclkpos,
    output [2:0] rclksel,

    // Physical DDR3 interface
    inout  [15:0] DDR3_DQ,   // 16 bit bidirectional data bus
    inout  [1:0] DDR3_DQS,   // DQ strobe for high and low bytes
    output [13:0] DDR3_A,    // 14 bit multiplexed address bus
    output [2:0] DDR3_BA,    // 3 banks
    output DDR3_nCS,  // a single chip select
    output DDR3_nWE,  // write enable
    output DDR3_nRAS, // row address select
    output DDR3_nCAS, // columns address select
    output DDR3_CK,
    output DDR3_nRESET,
    output DDR3_CKE,
    output DDR3_ODT,
    output [1:0] DDR3_DM
);

reg [25:0] MemAddr;
reg MemRD, MemWR, MemRefresh, MemInitializing;
reg [15:0] MemDin;
wire [15:0] MemDout;
reg [2:0] cycles;
reg r_read_a, r_read_b;
wire MemBusy, MemDataReady;


`ifndef VERILATOR

// DDR3 driver
ddr3_controller #(
    .ROW_WIDTH(13), .COL_WIDTH(10), .BANK_WIDTH(3)
) u_ddr3 (
    .pclk(pclk), .fclk(fclk), .ck(ck), .resetn(resetn),
	.addr(MemAddr), .rd(MemRD), .wr(MemWR), .refresh(MemRefresh),
	.din(MemDin), .dout(MemDout), .busy(MemBusy), .data_ready(MemDataReady),
    .write_level_done(write_level_done), .wstep(wstep),       // write leveling status
    .read_calib_done(read_calib_done), .rclkpos(rclkpos), .rclksel(rclksel),        // read calibration status

    .DDR3_nRESET(DDR3_nRESET),
    .DDR3_DQ(DDR3_DQ),      // 16 bit bidirectional data bus
    .DDR3_DQS(DDR3_DQS),    // DQ strobes
    .DDR3_A(DDR3_A),        // 13 bit multiplexed address bus
    .DDR3_BA(DDR3_BA),      // two banks
    .DDR3_nCS(DDR3_nCS),    // a single chip select
    .DDR3_nWE(DDR3_nWE),    // write enable
    .DDR3_nRAS(DDR3_nRAS),  // row address select
    .DDR3_nCAS(DDR3_nCAS),  // columns address select
    .DDR3_CK(DDR3_CK),
    .DDR3_CKE(DDR3_CKE),
    .DDR3_ODT(DDR3_ODT),
    .DDR3_DM(DDR3_DM)
);

always @(posedge clk) begin
    MemWR <= 1'b0; MemRD <= 1'b0; MemRefresh <= 1'b0;
    cycles <= cycles == 3'd7 ? 3'd7 : cycles + 3'd1;
    
    // Initiate read or write
    if (!busy) begin
        if (read_a || read_b || write || refresh) begin
            MemAddr <= {4'b0, addr};
            MemWR <= write;
            MemRD <= (read_a || read_b);
            MemRefresh <= refresh;
            busy <= 1'b1;
            MemDin <= {din, din};
            cycles <= 3'd1;
            r_read_a <= read_a;
            r_read_b <= read_b;

            if (write) total_written <= total_written + 1;
        end 
    end else if (MemInitializing) begin
        if (~MemBusy) begin
            // initialization is done
            MemInitializing <= 1'b0;
            busy <= 1'b0;
        end
    end else begin
        // Wait for operation to finish and latch incoming data on read.
        if (cycles == 3'd4) begin
            busy <= 0;
            if (r_read_a || r_read_b) begin
                if (~MemDataReady)      // assert data ready
                    fail <= 1'b1;
                if (r_read_a) 
//                    dout_a <= MemDout[15:8];
                    dout_a <= MemDout[7:0];
                if (r_read_b)
//                    dout_b <= MemDout[15:8];
                    dout_b <= MemDout[7:0];
                debug <= MemDout[15:8] ^ MemDout[7:0];         // unused dout[] leads to compile errors
                r_read_a <= 1'b0;
                r_read_b <= 1'b0;
            end
        end
    end

    if (~resetn) begin
        busy <= 1'b1;
        fail <= 1'b0;
        total_written <= 0;
        MemInitializing <= 1'b1;
    end
end

`else

// memory model for verilator 
reg [7:0] SIM_MEM [0:1024*1024*4-1];

// in verilator model, our memory delay is 1-cycle
// busy is always 0
always @(posedge clk) begin
//    cycles <= cycles == 3'd7 ? 3'd7 : cycles + 3'd1;

    if (read_a) dout_a <= SIM_MEM[addr];
    if (read_b) dout_b <= SIM_MEM[addr];
    if (write) SIM_MEM[addr] <= din;

    if (~resetn) begin
        busy <= 1'b0;
    end
end
 
`endif

endmodule
