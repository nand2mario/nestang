//
// NES top level for Sipeed Tang Primer 20K
// nand2mario, 2022.9
//

`timescale 1ns / 100ps

// Define this to use XMG SDRAM, undefine to use Mister SDRAM
//`define SDRAM_XMG

// Main clock frequency
localparam FREQ=37_800_000;        // at least 10x baudrate
// UART baudrate: BAUDRATE <= FREQ/10
localparam BAUDRATE=921600;

// define this to execute one NES cycle per 0.01 second and print the operation done
// `define STEP_TRACING

`ifdef VERILATOR
`define EMBED_GAME
`endif

// Module reads bytes and writes to proper address in ram.
// Done is asserted when the whole game is loaded.
// This parses iNES headers too.
module GameLoader(input clk, input reset,
                  input [7:0] indata, input indata_clk,
                  output reg [21:0] mem_addr, output [7:0] mem_data, output mem_write, output reg mem_refresh,
                  output [31:0] mapper_flags,
                  output reg done,
                  output error);

  reg [2:0] state = 0;
  reg [7:0] prgsize;
  reg [3:0] ctr;
  reg [7:0] ines[0:15]; // 16 bytes of iNES header
  reg [21:0] bytes_left;
  
  assign error = (state == 5);
  wire [7:0] prgrom = ines[4];
  wire [7:0] chrrom = ines[5];
  assign mem_data = indata;
  assign mem_write = !done && (bytes_left != 0) && indata_clk;

  wire [2:0] prg_size = prgrom <= 1  ? 0 :
                        prgrom <= 2  ? 1 : 
                        prgrom <= 4  ? 2 : 
                        prgrom <= 8  ? 3 : 
                        prgrom <= 16 ? 4 : 
                        prgrom <= 32 ? 5 : 
                        prgrom <= 64 ? 6 : 7;
                        
  wire [2:0] chr_size = chrrom <= 1  ? 0 : 
                        chrrom <= 2  ? 1 : 
                        chrrom <= 4  ? 2 : 
                        chrrom <= 8  ? 3 : 
                        chrrom <= 16 ? 4 : 
                        chrrom <= 32 ? 5 : 
                        chrrom <= 64 ? 6 : 7;
  
  wire [7:0] mapper = {ines[7][7:4], ines[6][7:4]};
  wire has_chr_ram = (chrrom == 0);
  assign mapper_flags = {16'b0, has_chr_ram, ines[6][0], chr_size, prg_size, mapper};
  always @(posedge clk) begin
    if (reset) begin
      state <= 0;
      done <= 0;
      ctr <= 0;
      mem_addr <= 0;  // Address for PRG
    end else begin
      case(state)
      // Read 16 bytes of ines header
      0: if (indata_clk) begin
           ctr <= ctr + 1;
           ines[ctr] <= indata;
           bytes_left <= {prgrom, 14'b0};           // Each prgrom is 16KB
           if (ctr == 4'b1111)
             state <= (ines[0] == 8'h4E) && (ines[1] == 8'h45) && (ines[2] == 8'h53) && (ines[3] == 8'h1A) && !ines[6][2] && !ines[6][3] ? 1 : 5;
         end
      1, 2: begin // Read the next |bytes_left| bytes into |mem_addr|
          if (bytes_left != 0) begin
            if (indata_clk) begin
              bytes_left <= bytes_left - 1;
              mem_addr <= mem_addr + 1;
            end
          end else if (state == 1) begin
            state <= 2;
            mem_addr <= 22'b10_0000_0000_0000_0000_0000;
            bytes_left <= {1'b0, chrrom, 13'b0};      // Each chrrom is 8KB
          end else if (state == 2) begin
            done <= 1;
          end
        end
      endcase
    end
  end

  // refresh logic
  // do 6 refresh after each write, (RAM needs one per 15us)
  // lowest baudrate=115200, 86.8us per byte
  // highest baudrate=921600, 10.85us per byte
  reg [7:0] cycles_since_write;
  always @(posedge clk) begin
    mem_refresh <= 1'b0;
    if (!done) begin
        cycles_since_write <= cycles_since_write == 8'd48 ? 8'd48 : cycles_since_write + 1;
        if (mem_write) begin
            cycles_since_write <= 0;
        end else if (cycles_since_write[2:0] == 3'b111) begin
            // do refresh on these cycles after a write: 7, 15, 23, 31, 39, 47
            mem_refresh <= 1'b1;
        end  
    end
    if (reset) cycles_since_write <= 8'd48;
  end
  
endmodule

`ifdef EMBED_GAME
// zf: Feed INES data to Game_Loader
module GameData (input clk, input reset, input start,
    output reg [7:0] odata, output reg odata_clk
    );

    // 24KB+ buffer for ROM
    reg [7:0] INES[24719:0];
    reg [21:0] INES_SIZE = 24719; 
    initial $readmemh("BattleCity.nes.hex", INES);

    reg [1:0] state = 0;
    reg [21:0] addr = 0;
    reg out_clk = 0;

    always @(posedge clk) begin
        if (reset) begin
            state <= 0;
            addr <= 0;  // odata gets INES[0]
            odata_clk <= 0;
        end else if (start && state == 0) begin
            // start loading
            state <= 1;
        end else if (state==1) begin
            if (addr == INES_SIZE) begin
                // we've just sent the last byte
                state <= 2;     // end of data
                odata_clk <= 0;
            end else begin
                // pump data to Game_Loader
/* verilator lint_off WIDTH */
                odata <= INES[addr];
/* verilator lint_on WIDTH */
                odata_clk <= 1;
                addr <= addr + 1;
            end
        end
    end
endmodule
`endif

// memeory controller is too large for trace

// Memory layout:
// Total address space 4MB
// $00_0000 - $0f_ffff: PRG ROM 1MB
// $20_0000 - $2f_ffff: CHR ROM 1MB
// $38_0000 - $38_07ff: Internal RAM (2KB), and 126KB unused
// $3c_0000 - $3d_ffff: PRG RAM 128KB
module MemoryController(
    input clk,
    input clk_sdram,
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

    // Physical SDRAM interface
	inout  [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output [1:0] SDRAM_BA,   // 4 banks
	output SDRAM_nCS,  // a single chip select
	output SDRAM_nWE,  // write enable
	output SDRAM_nRAS, // row address select
	output SDRAM_nCAS, // columns address select
	output SDRAM_CLK,
	output SDRAM_CKE
);

reg [24:0] MemAddr;
reg MemRD, MemWR, MemRefresh, MemInitializing;
reg [15:0] MemDin;
wire [15:0] MemDout;
reg [2:0] cycles;
reg r_read_a, r_read_b;
wire MemBusy, MemDataReady;


`ifndef VERILATOR

// SDRAM driver
sdram #(
`ifdef SDRAM_XMG
    .FREQ(FREQ), .ROW_WIDTH(12), .COL_WIDTH(9)      // total 8M words
`else
    .FREQ(FREQ), .ROW_WIDTH(13), .COL_WIDTH(10)     // total 32M words
`endif
) u_sdram (
    .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
	.addr(MemAddr), .rd(MemRD), .wr(MemWR), .refresh(MemRefresh),
	.din(MemDin), .dout(MemDout), .busy(MemBusy), .data_ready(MemDataReady),

    .SDRAM_DQ(SDRAM_DQ),   // 16 bit bidirectional data bus
    .SDRAM_A(SDRAM_A),    // 13 bit multiplexed address bus
    .SDRAM_BA(SDRAM_BA),   // two banks
    .SDRAM_nCS(SDRAM_nCS),  // a single chip select
    .SDRAM_nWE(SDRAM_nWE),  // write enable
    .SDRAM_nRAS(SDRAM_nRAS), // row address select
    .SDRAM_nCAS(SDRAM_nCAS), // columns address select
    .SDRAM_CLK(SDRAM_CLK),
    .SDRAM_CKE(SDRAM_CKE)
);

always @(posedge clk) begin
    MemWR <= 1'b0; MemRD <= 1'b0; MemRefresh <= 1'b0;
    cycles <= cycles == 3'd7 ? 3'd7 : cycles + 3'd1;
    
    // Initiate read or write
    if (!busy) begin
        if (read_a || read_b || write || refresh) begin
            MemAddr <= {3'b0, addr};
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
        if (cycles == 3'd5) begin
            busy <= 0;
            if (r_read_a || r_read_b) begin
                if (~MemDataReady)      // assert data ready
                    fail <= 1'b1;
                if (r_read_a) 
                    dout_a <= MemDout[7:0];
                if (r_read_b)
                    dout_b <= MemDout[7:0];
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

module NES_Tang20k(
    input sys_clk,
    input sys_resetn,

    // Set D7 to 1 to load game data
    input d7,

    // UART
    input UART_RXD,
    output UART_TXD,

    // 16 LEDs
    output [7:0] led,  // down
    output [7:0] led2,  // up

    // SDRAM
	inout  [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output [1:0] SDRAM_BA,   // two banks
	output SDRAM_nCS,  // a single chip select
	output SDRAM_nWE,  // write enable
	output SDRAM_nRAS, // row address select
	output SDRAM_nCAS, // columns address select
	output SDRAM_CLK,
	output SDRAM_CKE,

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

`ifndef VERILATOR
  // NES PPU clock 5.369 * 9 = 48.321
  Gowin_rPLL_nes pll_nes(
    .clkin(sys_clk),       // 27Mhz system clock
    .clkout(clk),          // MHZ main clock
    .clkoutp(clk_sdram)    // MHZ main clock phase shifted
  );

  wire clk_p;     // 720p pixel clock: 74.25 Mhz
  wire clk_p5;    // 5x pixel clock: 371.25 Mhz
  wire pll_lock;

  Gowin_rPLL_hdmi pll_hdmi (
    .clkin(sys_clk),
    .clkout(clk_p5),
    .lock(pll_lock)
  );

  Gowin_CLKDIV clk_div (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
  );
`else

wire clk = sys_clk;
wire clk_sdram = sys_clk;

`endif

  wire [5:0] color;
  wire [15:0] sample;
  wire [8:0] scanline;
  wire [8:0] cycle;

  // internal wiring and state
  wire joypad_strobe;
  wire [1:0] joypad_clock;
  wire [21:0] memory_addr;      // 4MB address space
  wire memory_read_cpu, memory_read_ppu;
  wire memory_write;
  wire [7:0] memory_din_cpu, memory_din_ppu;
  wire [7:0] memory_dout;
  reg [7:0] joypad_bits, joypad_bits2;
  reg [1:0] last_joypad_clock;
  wire [31:0] dbgadr;
  wire [1:0] dbgctr;
  reg [3:0] nes_ce = 0;
  wire [15:0] SW = 16'b1111_1111_1111_1111;   // every switch is on

  // UART
  wire [7:0] uart_data;
  wire [7:0] uart_addr;
  wire       uart_write;
  wire       uart_error;
  UartDemux  
        #(.FREQ(FREQ), .BAUDRATE(BAUDRATE)) 
        uart_demux(clk, 1'b0, UART_RXD, uart_data, uart_addr, uart_write, uart_error);

  // ROM loader
  reg  [7:0] loader_conf;     // bit 0 is reset

`ifdef EMBED_GAME
  // Static compiled-in game data 
  wire [7:0] loader_input;
  wire loader_clk;
  wire loader_reset = ~sys_resetn;
  GameData game_data(.clk(clk), .reset(~sys_resetn), .start(1'b1), .odata(loader_input), .odata_clk(loader_clk));
`else
  // Dynamic game loading from UART
  wire [7:0] loader_input = uart_data;
  wire       loader_clk   = (uart_addr == 8'h37) && uart_write;
  wire loader_reset = loader_conf[0];
`endif

  reg  [7:0] loader_btn, loader_btn_2;
  always @(posedge clk) begin
    if (uart_addr == 8'h35 && uart_write)
      loader_conf <= uart_data;
    if (uart_addr == 8'h40 && uart_write)
      loader_btn <= uart_data;
    if (uart_addr == 8'h41 && uart_write)
      loader_btn_2 <= uart_data;
  end

  // Joypad handling
  always @(posedge clk) begin
    if (joypad_strobe) begin
      joypad_bits <= loader_btn;
      joypad_bits2 <= loader_btn_2;
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
      joypad_bits <= {1'b0, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
      joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
  end

  wire [21:0] loader_addr;
  wire [7:0] loader_write_data;
  wire loader_write;
  wire [31:0] mapper_flags;
  wire loader_done, loader_fail, loader_refresh;

  // Parses ROM data and store them for MemoryController to access
  GameLoader loader(
        .clk(clk), .reset(loader_reset), .indata(loader_input), .indata_clk(loader_clk),
        .mem_addr(loader_addr), .mem_data(loader_write_data), .mem_write(loader_write),
        .mem_refresh(loader_refresh), .mapper_flags(mapper_flags), 
        .done(loader_done), .error(loader_fail));

  // The NES machine
  // nes_ce  / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___/ 6 \___/ 0 \___
  // MemCtrl |run_mem|mem_cmd|       |       |       |  Dout |       |run_mem|
  // NES                                                     |run_nes|
  //                 `-------- read delay = 4 -------'
  wire reset_nes = !loader_done;
  wire run_mem = (nes_ce == 0) && !reset_nes;       // memory runs at clock cycle #0
  wire run_nes = (nes_ce == 6) && !reset_nes;       // nes runs at clock cycle #7


  // For debug
  reg [21:0] last_addr;
  reg [7:0] last_din;
  reg [7:0] last_dout;
  reg last_write;   // if 0, then we did a read
  reg last_idle;

  reg tick_seen;

  // NES is clocked at every 7th cycle.
  always @(posedge clk) begin

`ifdef VERILATOR
    nes_ce <= nes_ce == 4'd6 ? 0 : nes_ce + 1;
`else

  `ifndef STEP_TRACING
    nes_ce <= nes_ce == 4'd6 ? 0 : nes_ce + 1;    
  `else
    // single stepping every 0.01 second
    // - when waiting for a tick, nes_ce loops between 7 and 13 and 
    //   issues memory refresh on #7
    // - when a tick is seen, nes_ce goes back to 0
    nes_ce <= nes_ce == 4'd13 ? 4'd7 : nes_ce + 1;
    if (tick) tick_seen <= 1'b1;
    if (nes_ce == 4'd13 && tick_seen) begin
        nes_ce <= 0;
        tick_seen <= 1'b0;
    end
  `endif
`endif
    // log memory access result for debug
    if (nes_ce == 4'd6 && !reset_nes) begin
        if (memory_write || memory_read_cpu || memory_read_ppu) begin
            last_addr <= memory_addr;
            last_dout <= memory_read_cpu ? memory_din_cpu : memory_din_ppu;
            last_din <= memory_dout;
            last_write <= memory_write;
            last_idle <= 1'b0;
        end else begin
            // memory is idle this cycle
            last_idle <= 1'b1;
        end
    end else if (loader_write) begin
        last_write <= 1'b1;
        last_addr <= loader_addr;
        last_din <= loader_write_data;
    end
  end

  // Main NES machine
  NES nes(clk, reset_nes, run_nes,
          mapper_flags,
          sample, color,
          joypad_strobe, joypad_clock, {joypad_bits2[0], joypad_bits[0]},
          SW[4:0],
          memory_addr,
          memory_read_cpu, memory_din_cpu,
          memory_read_ppu, memory_din_ppu,
          memory_write, memory_dout,
          cycle, scanline
        );

/*verilator tracing_off*/
  // Combine RAM and ROM data to a single address space for NES to access
  wire ram_busy, ram_fail;
  wire [19:0] ram_total_written;
  MemoryController memory(.clk(clk), .clk_sdram(clk_sdram), .resetn(sys_resetn),
        .read_a(memory_read_cpu && run_mem), 
        .read_b(memory_read_ppu && run_mem),
        .write(memory_write && run_mem || loader_write),
        .refresh((~memory_read_cpu && ~memory_read_ppu && ~memory_write && ~loader_write) && run_mem || nes_ce == 4'd7 || loader_refresh),
        .addr(loader_write ? loader_addr : memory_addr),
        .din(loader_write ? loader_write_data : memory_dout),
        .dout_a(memory_din_cpu), .dout_b(memory_din_ppu),
        .busy(ram_busy), .fail(ram_fail), .total_written(ram_total_written),

        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS),	
        .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), 
        .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE)
);
/*verilator tracing_on*/


`ifndef VERILATOR

// HDMI output
nes2hdmi u_hdmi (
	.clk(clk),
	.resetn(sys_resetn),

    .color(color),
    .cycle(cycle),
    .scanline(scanline),
    .sample(sample >> 1),

	.clk_pixel(clk_p),
	.clk_5x_pixel(clk_p5),
	.locked(pll_lock),

	.tmds_clk_n(tmds_clk_n),
	.tmds_clk_p(tmds_clk_p),
	.tmds_d_n(tmds_d_n),
	.tmds_d_p(tmds_d_p)
);


//Print Controll -------------------------------------------

`include "print.v"
defparam tx.uart_freq=BAUDRATE;
defparam tx.clk_freq=FREQ;
assign print_clk = clk;
assign UART_TXD = uart_txp;

reg[3:0] state_0;
reg[3:0] state_1;
reg[3:0] state_old = 3'd7;
wire[3:0] state_new = state_1;

reg [7:0] print_counters = 0, print_counters_p;

reg tick;       // pulse every 0.01 second
reg print_stat; // pulse every 2 seconds

reg [15:0] recv_packets = 0;
reg [15:0] indata_clk_count = 0;

always@(posedge clk)begin
    state_0<={2'b0, loader_done};
    state_1<=state_0;

    if (uart_demux.write)
        recv_packets <= recv_packets + 1;        

    if(state_0==state_1) begin //stable value
        state_old<=state_new;

        if(state_old!=state_new)begin//state changes
            if(state_new==3'd0) `print("NES_Tang starting...\n", STR);
            if(state_new==3'd1) `print("Game loading done.\n", STR);
        end
    end

`ifdef COLOR_TRACING
    // print some color values
    if (loader_done && tick)
        print_counters <= 8'd1;
    print_counters_p <= print_counters;
    if (print_state == PRINT_IDLE_STATE && print_counters == print_counters_p && print_counters != 0) begin
        case (print_counters)
        8'd1: `print({7'b0, scanline}, 2);
        8'd2: `print("  ", STR);
        8'd3: `print({7'b0, cycle}, 2);
        8'd4: `print("  ", STR);
        8'd5: `print({2'b0, color}, 1);
        8'd6: `print("  ", STR);
        8'd255: `print("\n", STR);
        endcase
        print_counters <= print_counters == 8'd255 ? 0 : print_counters + 1;
    end
`endif

    // print stats every 2 seconds normally, or every 0.01 second before game data is ready
//    if (print_stat || (~loader_done && tick))
`ifdef STEP_TRACING
    if (tick)
        print_counters <= 8'd1;
    print_counters_p <= print_counters;
    if (print_state == PRINT_IDLE_STATE && print_counters == print_counters_p && print_counters != 0) begin
        case (print_counters)
        8'd1: `print("loader_done=", STR);
        8'd2: `print({7'b0, loader_done}, 1);
        8'd3: if (~last_idle) `print(", last memory operation: <write=", STR);
        8'd6: if (~last_idle) `print({7'b0, last_write}, 1);
        8'd7: if (~last_idle) `print(", addr=", STR);
        8'd8: if (~last_idle) `print({2'b0, last_addr}, 3);
        8'd9: if (~last_idle) `print(", din=", STR);
        8'd10: if (~last_idle) `print(last_din, 1);
        8'd11: if (~last_idle) `print(", dout=", STR);
        8'd12: if (~last_idle) `print(last_dout, 1);
        8'd13: if (~last_idle) `print(">", STR);
        8'd14: `print(", total_written=", STR);
        8'd15: `print({4'b0, ram_total_written}, 3);
        8'd16: `print(", ram_busy=", STR);
        8'd17: `print({7'b0, ram_busy}, 1);
        8'd18: `print(", ram_fail=", STR);
        8'd19: `print({7'b0, ram_fail}, 1);

        8'd255: `print("\n\n", STR);
        endcase
        print_counters <= print_counters == 8'd255 ? 0 : print_counters + 1;
    end
`endif

    if(~sys_resetn) `print("System Reset\nWelcome to NES_Tang\n",STR);
end

reg [19:0] tick_counter;
reg [9:0] stat_counter;
always @(posedge clk) begin
    tick <= tick_counter == 0;
    tick_counter <= tick_counter == 0 ? FREQ/100 : tick_counter - 1;

    print_stat <= 0;
    if (tick) begin
        print_stat <= stat_counter == 0;
        stat_counter <= stat_counter == 0 ? 200 : stat_counter - 1;
    end
end
//Print Controll -------------------------------------------

`endif


  assign led = ~{loader_done, ~UART_RXD, color};
  assign led2 = ~sample[15:8];

endmodule