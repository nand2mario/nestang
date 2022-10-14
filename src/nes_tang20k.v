//
// NES top level for Sipeed Tang Primer 20K
// nand2mario, 2022.9
//

`timescale 1ns / 100ps

// Main clock frequency
localparam FREQ=32_250_000;
localparam BAUDRATE=921600;         // UART baudrate: BAUDRATE <= FREQ/10
//localparam BAUDRATE=115200;         // FIXME: for now, dock version is built with 115K baudrate

// define this to execute one NES cycle per 0.01 second and print the operation done
//`define STEP_TRACING

`ifdef VERILATOR
`define EMBED_GAME
`endif

module NES_Tang20k(
    input sys_clk,
    input sys_resetn,
    input d7,

    // UART
    input UART_RXD,
    output UART_TXD,

    // 16 LEDs
    output [7:0] led,   // bottom right 
    output [7:0] led2,  // top right 

    // onboard DDR3
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
    output [1:0] DDR3_DM,

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

`ifndef VERILATOR
  // NES domain clocks
  Gowin_rPLL_nes pll_nes(
    .clkin(sys_clk),        // 27Mhz system clock
    .clkout(fclk),          // 387Mhz, DDR3 memory clock
    .clkoutd(pclk),         // 96.75Mhz, DDR3 controller clock
    .clkoutd3(clk_d3),
    .clkoutp(ck),           // DDR3 CK clock (90-degree phase-shifted fclk)
    .lock(nes_lock)
  );

  CLKDIV u_div (
    .CLKOUT(clk),           // 32.25Mhz, NES clock
    .HCLKIN(clk_d3),
    .RESETN(sys_resetn & nes_lock)
  );
  defparam u_div.DIV_MODE = "4";

  // HDMI domain clocks
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
    .resetn(sys_resetn & pll_lock)
  );
`else
  // dummy clocks for verilator
  wire clk = sys_clk;
  wire pclk = sys_clk;
  wire fclk = sys_clk;
  wire ck = sys_clk;
  wire nes_lock = 1'b1;

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

  reg osd_enable;
  reg [11:0] osd_addr;
  wire [7:0] osd_din = uart_data;
  wire osd_we = uart_write && uart_addr == 8'h82;

  // UART
  wire [7:0] uart_data;
  wire [7:0] uart_addr;
  wire       uart_write;
  wire       uart_error;
  UartDemux  
        #(.FREQ(FREQ), .BAUDRATE(BAUDRATE)) 
        uart_demux(clk, 1'b0, UART_RXD, uart_data, uart_addr, uart_write, uart_error);
//        uart_demux(clk, ~sys_resetn, UART_RXD, uart_data, uart_addr, uart_write, uart_error);

  // ROM loader
  reg  [7:0] loader_conf;     // bit 0 is reset

`ifdef EMBED_GAME
  // Static compiled-in game data 
  wire [7:0] loader_input;
  wire loader_clk;
  wire loader_reset = ~sys_resetn;
  GameData game_data(
        .clk(clk), .reset(~sys_resetn), .start(1'b1), 
        .odata(loader_input), .odata_clk(loader_clk));
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

    // OSD update
    if (uart_addr == 8'h80 && uart_write) // load osd address lower byte
      osd_addr[7:0] <= uart_data;
    if (uart_addr == 8'h81 && uart_write) // load osd address higher byte
      osd_addr[11:8] <= uart_data[3:0];
    if (uart_addr == 8'h82 && uart_write) // one byte of osd data
      osd_addr <= osd_addr + 1;
    if (uart_addr == 8'h83 && uart_write) // turn osd on or off
      osd_enable <= uart_data[0];
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
  // nes_ce  / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___/ 0 \___/
  // MemCtrl |run_mem|mem_cmd|       |       |  Dout |       |run_mem|
  // NES                                             |run_nes|
  //                 `---- read delay = 3 ---'
  wire reset_nes = !loader_done;
  wire run_mem = (nes_ce == 0) && !reset_nes;       // memory runs at clock cycle #0
  wire run_nes = (nes_ce == 5) && !reset_nes;       // nes runs at clock cycle #5

  // For debug
  reg [21:0] last_addr;
  reg [7:0] last_din;
  reg [7:0] last_dout;
  reg last_write;   // if 0, then we did a read
  reg last_idle;

  reg tick_seen;

  // NES is clocked at every 6th cycle.
  always @(posedge clk) begin

`ifdef VERILATOR
    nes_ce <= nes_ce == 4'd5 ? 0 : nes_ce + 1;
`else

  `ifndef STEP_TRACING
    nes_ce <= nes_ce == 4'd5 ? 0 : nes_ce + 1;    
  `else
    // single stepping every 0.01 second
    // - when waiting for a tick, nes_ce loops between 6 and 13 and 
    //   issues memory refresh on #6
    // - when a tick is seen, nes_ce goes back to 0
    nes_ce <= nes_ce == 4'd13 ? 4'd6 : nes_ce + 1;
    if (tick) tick_seen <= 1'b1;
    if (nes_ce == 4'd13 && tick_seen) begin
        nes_ce <= 0;
        tick_seen <= 1'b0;
    end
  `endif
`endif
    // log memory access result for debug
    if (nes_ce == 4'd5 && !reset_nes) begin
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
  reg mem_resetn = 1'b1;            // reset DDR3 after 100ms when intialization failed
  wire ram_busy, ram_fail;
  wire [19:0] ram_total_written;
  wire [7:0] ram_debug, wstep;
  wire [1:0] rclkpos;
  wire [2:0] rclksel;
  MemoryController memory(.clk(clk), .pclk(pclk), .fclk(fclk), .ck(ck), .resetn(sys_resetn & nes_lock & mem_resetn),
        .read_a(memory_read_cpu && run_mem), 
        .read_b(memory_read_ppu && run_mem),
        .write(memory_write && run_mem || loader_write),
        .refresh(loader_done ? ~memory_read_cpu && ~memory_read_ppu && ~memory_write && run_mem || nes_ce == 4'd6
                    : loader_refresh),
        .addr(loader_write ? loader_addr : memory_addr),
        .din(loader_write ? loader_write_data : memory_dout),
        .dout_a(memory_din_cpu), .dout_b(memory_din_ppu),
        .busy(ram_busy), .fail(ram_fail), .total_written(ram_total_written),
        .debug(ram_debug), .write_level_done(write_level_done), .wstep(wstep),
        .read_calib_done(read_calib_done), .rclkpos(rclkpos), .rclksel(rclksel),

        .DDR3_DQ(DDR3_DQ), .DDR3_DQS(DDR3_DQS), .DDR3_A(DDR3_A), .DDR3_BA(DDR3_BA), 
        .DDR3_nCS(DDR3_nCS), .DDR3_nWE(DDR3_nWE), .DDR3_nRAS(DDR3_nRAS), .DDR3_nCAS(DDR3_nCAS), 
        .DDR3_CK(DDR3_CK), .DDR3_nRESET(DDR3_nRESET), .DDR3_CKE(DDR3_CKE), 
        .DDR3_ODT(DDR3_ODT), .DDR3_DM(DDR3_DM)
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

    .osd_enable(osd_enable),
    .osd_addr(osd_addr),
    .osd_din(osd_din),
    .osd_we(osd_we),

    .clk_pixel(clk_p),
    .clk_5x_pixel(clk_p5),
    .locked(pll_lock),

    .tmds_clk_n(tmds_clk_n),
    .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n),
    .tmds_d_p(tmds_d_p)
);

// Memory initialization control
// After reset, every 100ms we check whether memory is successsfully intialized.
// If not we reset the whole machine, print a message and hope it will finally succeed.
reg [$clog2(FREQ/10+1)-1:0] meminit_cnt;
reg meminit_check;      // pulse when memory initialization is checked
reg write_level_done_p, read_calib_done_p;
reg [7:0] wstep_p;
reg [1:0] rclkpos_p;
reg [2:0] rclksel_p;
always @(posedge clk) begin
    meminit_cnt <= meminit_cnt == 0 ? 0 : meminit_cnt - 1;
    mem_resetn <= 1'b1;
    meminit_check <= 0;
    if (meminit_cnt == 1) begin
        meminit_check <= 1'b1;
        write_level_done_p <= write_level_done; read_calib_done_p <= read_calib_done;
        wstep_p <= wstep; rclkpos_p <= rclkpos; rclksel_p <= rclksel;
        if (~write_level_done || ~read_calib_done) begin
            // reset DDR3 controller
            mem_resetn <= 0;
            meminit_cnt <= FREQ/10;         // check again in 0.1 sec
        end
    end

    if (~sys_resetn || ~nes_lock) begin
        meminit_cnt <= FREQ/10;
        meminit_check <= 1'b0;
        mem_resetn <= 1'b1;
    end
end

//
// Print control
//
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
reg [7:0] print_mem = 0, print_mem_p;

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
            if(state_new==3'd0) `print("NES_Tang restarting...\n", STR);
            if(state_new==3'd1) `print("Game loading done.\n", STR);
        end
    end

    if (meminit_check) begin
        print_mem <= 8'd1;
    end
    print_mem_p <= print_mem;
    if (print_state == PRINT_IDLE_STATE && print_mem == print_mem_p && print_mem != 0) begin
        case (print_mem)
        8'd1: if (write_level_done_p && read_calib_done_p) 
                `print("DDR3 initialization successful.\n{wstep[7:0],rclkpos[3:0],rclksel[3:0]}=", STR);
              else
                `print("DDR3 initialization failed. Retrying...\n{wstep[7:0],rclkpos[3:0],rclksel[3:0]}=", STR);
        8'd2: `print({wstep_p,2'b0,rclkpos_p, 1'b0, rclksel_p}, 2);
        8'd3: `print("\n", STR);
        endcase
        print_mem <= print_mem == 8'd4 ? 0 : print_mem + 1;
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

`ifdef STEP_TRACING
    // print stats every 2 seconds normally, or every 0.01 second before game data is ready
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

    if(~sys_resetn) begin
//        `print("System Reset\nWelcome to NES_Tang\n",STR);
        `print(ram_debug, 1);
    end
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

`endif


//  assign led = ~{loader_done, ram_busy, uart_error, 5'b0};
 assign led = ~{loader_done, ram_busy, uart_error, color[4:0]};
//  assign led2 = ~sample[15:8];
//  assign led2 = ~{6'b0, ram_fail, ram_busy};
  assign led2 = ~loader_addr[15:8];

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

