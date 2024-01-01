// A bridge controller connecting SDRAM to NES.
// The main function is to 2 read buffers (dout_a and dout_b) for CPU and PPU
// nand2mario, 2022.10
// 
// Memory layout:
// Total address space 4MB
// $00_0000 - $1f_ffff: PRG ROM 2MB
// $20_0000 - $37_ffff: CHR ROM 1.5MB
// $38_0000 - $38_07ff: Internal RAM (2KB), and 126KB unused
// $3c_0000 - $3d_ffff: PRG RAM 128KB

import configPackage::*;

module MemoryController(
    input clk,                // Main logic clock
    input clk_sdram,          // 180-degree of clk
    input resetn,
    input read_a,             // Set to 1 to read from RAM
    input read_b,             // Set to 1 to read from RAM
    input write,              // Set to 1 to write to RAM
    input refresh,            // Set to 1 to auto-refresh RAM
    input [21:0] addr,        // Address to read / write
    input [7:0] din,          // Data to write
    output [7:0] dout_a,      // Last read data a, available 4 cycles after read_a is set
    output [7:0] dout_b,      // Last read data b, available 4 cycles after read_b is set
    output reg busy,          // 1 while an operation is in progress

    // debug interface
    output reg fail,          // timing mistake or sdram malfunction detected
    output reg [19:0] total_written,

    // Physical SDRAM interface
	inout  [SDRAM_DATA_WIDTH-1:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output [SDRAM_ROW_WIDTH-1:0] SDRAM_A,    // 13 bit multiplexed address bus
	output [SDRAM_BANK_WIDTH-1:0] SDRAM_BA,   // 4 banks
	output SDRAM_nCS,  // a single chip select
	output SDRAM_nWE,  // write enable
	output SDRAM_nRAS, // row address select
	output SDRAM_nCAS, // columns address select
	output SDRAM_CLK,
	output SDRAM_CKE,
    output [SDRAM_DATA_WIDTH/8-1:0] SDRAM_DQM
);

reg [22:0] MemAddr;
reg MemRD, MemWR, MemRefresh, MemInitializing;
reg [7:0] MemDin;
wire [7:0] MemDout;
reg [2:0] cycles;
reg r_read_a, r_read_b;
reg [7:0] da, db;
wire MemBusy, MemDataReady;

`ifndef VERILATOR

assign dout_a = (cycles == 3'd4 && r_read_a) ? MemDout : da;
assign dout_b = (cycles == 3'd4 && r_read_b) ? MemDout : db;

// SDRAM driver
sdram #(
    .FREQ(FREQ), .DATA_WIDTH(SDRAM_DATA_WIDTH), .ROW_WIDTH(SDRAM_ROW_WIDTH),
    .COL_WIDTH(SDRAM_COL_WIDTH), .BANK_WIDTH(SDRAM_BANK_WIDTH)
) u_sdram (
    .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
	.addr(busy ? MemAddr : {1'b0, addr}), .rd(busy ? MemRD : (read_a || read_b)), 
    .wr(busy ? MemWR : write), .refresh(busy ? MemRefresh : refresh),
	.din(busy ? MemDin : din), .dout(MemDout), .busy(MemBusy), .data_ready(MemDataReady),

    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), 
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
    .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
    .SDRAM_DQM(SDRAM_DQM)
);

always @(posedge clk) begin
    MemWR <= 1'b0; MemRD <= 1'b0; MemRefresh <= 1'b0;
    cycles <= cycles == 3'd7 ? 3'd7 : cycles + 3'd1;
    
    // Initiate read or write
    if (!busy) begin
        if (read_a || read_b || write || refresh) begin
            MemAddr <= {1'b0, addr};
            MemWR <= write;
            MemRD <= (read_a || read_b);
            MemRefresh <= refresh;
            busy <= 1'b1;
            MemDin <= din;
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
                    da <= MemDout;
                if (r_read_b)
                    db <= MemDout;
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
reg [7:0] dout_a_next;
reg [7:0] dout_b_next;
assign dout_a = dout_a_next;
assign dout_b = dout_b_next;

// in verilator model, our memory delay is 1-cycle
// busy is always 0
always @(posedge clk) begin
//    cycles <= cycles == 3'd7 ? 3'd7 : cycles + 3'd1;

    if (read_a) dout_a_next <= SIM_MEM[addr];
    if (read_b) dout_b_next <= SIM_MEM[addr];
    if (write) SIM_MEM[addr] <= din;

    if (~resetn) begin
        busy <= 1'b0;
    end
end
 
`endif

endmodule
