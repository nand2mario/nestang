// Simulation model of sdram_nes.v for Verilator
// mclk     /   \___/   \___/   \___/   \___/   \___/   \___
// clkref   |   1   |   0   |   1   |   0   |   1   |   0   |
// cpu/ppu  |  req  |       |  data |
//                          |  req  |       |  data |
// risc-v           |  req  |  ack  |  data |
//                                  |  req  |  ack  |  data |

import configPackage::*;

module sdram_snes
(
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
	input             clk,        // main clock @ 21.477Mhz
	input             resetn,
    input             clkref,
    output reg busy,

	input [20:0]      addrA,      // 21 bit byte address, bank 0
	input             weA,        // ppu requests write
	input [7:0]       dinA,       // data input from cpu
	input             oeA,        // ppu requests data
	output reg [7:0]  doutA,      // data output to cpu

	input [20:0]      addrB,      // 21 bit byte address, also bank 0
	input             weB,        // cpu requests write
	input [7:0]       dinB,       // data input from ppu
	input             oeB,        // cpu requests data
	output reg [7:0]  doutB,      // data output to ppu

    // RISC-V softcore
    input      [20:1] rv_addr,      // 2MB RV memory space, bank 1
    input      [15:0] rv_din,       // 16-bit accesses
    input      [1:0]  rv_ds,
    output reg [15:0] rv_dout,
    input             rv_req,
    output reg        rv_req_ack,   // ready for new requests. read data available on NEXT mclk
    input             rv_we
);

assign busy = 0;

reg [7:0] mem_cpu [2*1024*1024];       // 2MB
reg [15:0] mem_rv [1*1024*1024];       // 2MB

reg cycle;       
reg clkref_r;

always @(posedge clk) begin
    cycle <= ~cycle;
    clkref_r <= clkref;
    if (clkref & ~clkref_r)
        cycle <= 0;
end

localparam PORT_NONE = 0;

localparam PORT_A = 1;
localparam PORT_B = 2;

localparam PORT_RV = 1;

reg [1:0] port [2];
reg rv_req_r;
reg we_latch[2], oe_latch[2];
reg [7:0] doutA_pre, doutB_pre;
reg [15:0] rv_dout_pre;
reg rv_req_new;

always @(posedge clk) begin
    reg rv_req_new_t;
    rv_req_new_t = rv_req ^ rv_req_r;
    rv_req_r <= rv_req;
    rv_req_new <= rv_req_new_t;

    if (~resetn) begin
        port[0] <= 0;
        port[1] <= 0;
    end else begin

        // RAS
        if (cycle == 1'b1) begin
            if (oeB || weB) begin               // CPU
                port[0] <= PORT_B;
                {we_latch[0], oe_latch[0]} <= {weB, oeB};
                if (weB) begin
                    mem_cpu[addrB] <= dinB;
                    // $fdisplay(32'h80000002, "[%06x] <= %02x", addrB, dinB);
                end else
                    doutB_pre <= mem_cpu[addrB];
            end else if (oeA || weA) begin      // PPU
                port[0] <= PORT_A;
                {we_latch[0], oe_latch[0]} <= {weA, oeA};
                if (weA) begin
                    mem_cpu[addrA] <= dinA;
                    // $fdisplay(32'h80000002, "[%06x] <= %02x", addrA, dinA);
                end else
                    doutA_pre <= mem_cpu[addrA];
            end
        end

        if (cycle == 1'b0) begin
            if (rv_req_new_t || rv_req_new) begin               // RV
                rv_req_new <= 0;
                port[1] <= PORT_RV;
                {we_latch[1], oe_latch[1]} <= {rv_we, ~rv_we};
                if (rv_we) begin
                    mem_rv[rv_addr] <= rv_din;
                    // $fdisplay(32'h80000002, "RV[%04x] <= %02x", {rv_addr,1'b0}, rv_din);
                end else 
                    rv_dout_pre <= mem_rv[rv_addr];
            end
        end

        // CAS
        if (cycle == 1'b0) begin
            if (port[0] == PORT_B) begin                // CPU
                doutB <= doutB_pre; 
            end else if (port[0] == PORT_A) begin       // PPU
                doutA <= doutA_pre;
            end
            port[0] <= PORT_NONE;
        end
        
        if (cycle == 1'b1) begin
            if (port[1] == PORT_RV) begin               // RV
                rv_dout <= rv_dout_pre;
            end
            port[1] <= PORT_NONE;
        end

        // DATA is readied in CAS phase
    end
end

endmodule