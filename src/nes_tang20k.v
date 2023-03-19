//
// NES top level for Sipeed Tang Nano 20K
// nand2mario
//

// `timescale 1ns / 100ps

module NES_Tang20k(
    input sys_clk,
    // input sys_resetn,
    // input d7,
    // Button S1
    input s1,

    // UART
    input UART_RXD,
    output UART_TXD,

    // LEDs
    output [1:0] led,

    // SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [31:0] IO_sdram_dq,       // 32 bit bidirectional data bus
    output [10:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output [1:0] O_sdram_ba,        // two banks
    output [3:0] O_sdram_dqm,       // 32/4

    // MicroSD
    output sd_clk,
    inout sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,     // 1
    output sd_dat2,     // 1
    output sd_dat3,     // 1

    // Dualshock game controller
    output joystick_clk,
    output joystick_mosi,
    input joystick_miso,
    output reg joystick_cs,
    output joystick_clk2,
    output joystick_mosi2,
    input joystick_miso2,
    output reg joystick_cs2,

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

`include "nes_tang20k.vh"

reg sys_resetn = 0;
always @(posedge clk) begin
    sys_resetn <= ~s1;
end

`ifndef VERILATOR
// NES PPU clock 5.369 * 7 = 37.6
Gowin_rPLL_nes pll_nes(
    .clkin(sys_clk),
    .clkout(clk),          // FREQ main clock
    .clkoutp(clk_sdram)    // FREQ main clock phase shifted
);

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
`else   // VERILATOR
  // dummy clocks for verilator
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

  wire [7:0] sd_dout;
  wire sd_dout_valid;

  // UART
  wire [7:0] uart_data;
  wire [7:0] uart_addr;
  wire       uart_write;
  wire       uart_error;
`ifndef VERILATOR
UartDemux #(.FREQ(FREQ), .BAUDRATE(BAUDRATE)) uart_demux(
    clk, 1'b0, UART_RXD, uart_data, uart_addr, uart_write, uart_error
);
`endif

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
  wire [7:0] loader_input = sd_dout_valid ? sd_dout : uart_data;
  wire       loader_clk   = (uart_addr == 8'h37) && uart_write || sd_dout_valid;
  wire loader_reset = ~sys_resetn | loader_conf[0];
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

  /*
  joy_rx[0:1] dualshock buttons: 0:(L D R U St R3 L3 Se)  1:(□ X O △ R1 L1 R2 L2)
  nes_btn[0:1] NES buttons:      (R L D U START SELECT B A)
  O is A, X is B
  */
  wire [7:0] joy_rx[0:5], joy_rx2[0:1];     // 6 RX bytes for all button/axis state
  wire auto_square, auto_triangle, auto_square2, auto_triangle2;
  wire [7:0] nes_btn = {~joy_rx[0][5], ~joy_rx[0][7], ~joy_rx[0][6], ~joy_rx[0][4], 
                         ~joy_rx[0][3], ~joy_rx[0][0], ~joy_rx[1][6] | auto_square, ~joy_rx[1][5] | auto_triangle};
  wire [7:0] nes_btn2 = {~joy_rx2[0][5], ~joy_rx2[0][7], ~joy_rx2[0][6], ~joy_rx2[0][4], 
                         ~joy_rx2[0][3], ~joy_rx2[0][0], ~joy_rx2[1][6] | auto_square2, ~joy_rx2[1][5] | auto_triangle2};
  
  // Joypad handling
  always @(posedge clk) begin
    if (joypad_strobe) begin
      joypad_bits <= loader_btn | nes_btn;
      joypad_bits2 <= loader_btn_2 | nes_btn2;
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
  // nes_ce  / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 0 \___
  // MemCtrl |mem_cmd|ACTIVE | RD/WR |       |  Dout |run_mem|
  // NES                                     |run_nes|
  //                 `-------- read delay = 4 -------'
  wire reset_nes = !loader_done;
  wire run_mem = (nes_ce == 0) && !reset_nes;       // memory runs at clock cycle #0
  wire run_nes = (nes_ce == 4) && !reset_nes;       // nes runs at clock cycle #4

  // For debug
  reg [21:0] last_addr;
  reg [7:0] last_din;
  reg [7:0] last_dout;
  reg last_write;   // if 0, then we did a read
  reg last_idle;

  reg tick_seen;

  // NES is clocked at every 5th cycle.
  always @(posedge clk) begin
`ifdef VERILATOR
    nes_ce <= nes_ce == 4'd4 ? 0 : nes_ce + 1;
`else
  `ifndef STEP_TRACING
    nes_ce <= nes_ce == 4'd4 ? 0 : nes_ce + 1;    
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
    if (nes_ce == 4'd4 && !reset_nes) begin
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
        .refresh((~memory_read_cpu && ~memory_read_ppu && ~memory_write && ~loader_write) && run_mem || nes_ce == 4'd7 || (loader_refresh && ~loader_write)),
        .addr(loader_write ? loader_addr : memory_addr),
        .din(loader_write ? loader_write_data : memory_dout),
        .dout_a(memory_din_cpu), .dout_b(memory_din_ppu),
        .busy(ram_busy), .fail(ram_fail), .total_written(ram_total_written),

        .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), .SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n), 
        .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
);
/*verilator tracing_on*/

`ifndef VERILATOR

wire menu_overlay;
wire [5:0] menu_color;
wire [7:0] menu_scanline, menu_cycle;

// HDMI output
nes2hdmi u_hdmi (
    .clk(clk), .resetn(sys_resetn),
    .color(menu_overlay ? menu_color : color), .cycle(menu_overlay ? menu_cycle : cycle), 
    .scanline(menu_overlay ? menu_scanline : scanline), .sample(sample >> 1),
    .clk_pixel(clk_p), .clk_5x_pixel(clk_p5), .locked(pll_lock),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

wire [4:0] sd_active, sd_total;
wire [23:0] sd_rsector, sd_last_sector;
SDLoader #(.FREQ(FREQ)) sd_loader (
    .clk(clk), .resetn(sys_resetn),
    .overlay(menu_overlay), .color(menu_color), .scanline(menu_scanline),
    .cycle(menu_cycle),
    .nes_btn(loader_btn | nes_btn | loader_btn_2 | nes_btn2), 
    .dout(sd_dout), .dout_valid(sd_dout_valid),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),

    .debug_active(sd_active), .debug_total(sd_total),
    .debug_sd_rsector(sd_rsector), .debug_sd_last_sector(sd_last_sector)
);

// Dualshock controller
reg sclk;                   // controller main clock at 250Khz
localparam SCLK_DELAY = FREQ / 250_000 / 2;
reg [$clog2(SCLK_DELAY)-1:0] sclk_cnt;         // FREQ / 250K / 2 = 75

// Generate sclk
always @(posedge clk) begin
    sclk_cnt <= sclk_cnt + 1;
    if (sclk_cnt == SCLK_DELAY-1) begin
        sclk = ~sclk;
        sclk_cnt <= 0;
    end
end

dualshock_controller controller (
    .I_CLK250K(sclk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk), .O_psSEL(joystick_cs), .O_psTXD(joystick_mosi),
    .I_psRXD(joystick_miso),
    .O_RXD_1(joy_rx[0]), .O_RXD_2(joy_rx[1]), .O_RXD_3(joy_rx[2]),
    .O_RXD_4(joy_rx[3]), .O_RXD_5(joy_rx[4]), .O_RXD_6(joy_rx[5]),
    // config=1, mode=1(analog), mode_en=1
    .I_CONF_SW(1'b1), .I_MODE_SW(1'b1), .I_MODE_EN(1'b1),
    .I_VIB_SW(2'b00), .I_VIB_DAT(8'hff)     // no vibration
);

dualshock_controller controller2 (
    .I_CLK250K(sclk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk2), .O_psSEL(joystick_cs2), .O_psTXD(joystick_mosi2),
    .I_psRXD(joystick_miso2),
    .O_RXD_1(joy_rx2[0]), .O_RXD_2(joy_rx2[1]), 
    .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .I_CONF_SW(1'b1), .I_MODE_SW(1'b1), .I_MODE_EN(1'b1),
    .I_VIB_SW(2'b00), .I_VIB_DAT(8'hff)     // no vibration
);

Autofire af_square (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx[1][7]), .out(auto_square));
Autofire af_triangle (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx[1][4]), .out(auto_triangle));
Autofire af_square2 (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx2[1][7]), .out(auto_square2));
Autofire af_triangle2 (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx2[1][4]), .out(auto_triangle2));

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

reg tick;       // pulse every 0.01 second
reg print_stat; // pulse every 2 seconds

reg [15:0] recv_packets = 0;
reg [15:0] indata_clk_count = 0;

reg [3:0] sd_state0 = 0;

reg [19:0] timer;           // 27 times per second
always @(posedge clk) timer <= timer + 1;

always@(posedge clk)begin
    state_0<={2'b0, loader_done};
    state_1<=state_0;

/*
    if (timer == 0) begin
//        `print({joy_rx[0], joy_rx[1]}, 2);
//        `print({nes_btn, nes_btn2}, 2);
        `print({3'b0, sd_active, 3'b0, sd_total, sd_rsector, sd_last_sector}, 8);
    end
    if (timer == 20'b1000_0000_0000_0000_0000) begin
        `print("\n", STR);
    end
*/

    if (uart_demux.write)
        recv_packets <= recv_packets + 1;        

    if(state_0==state_1) begin //stable value
        state_old<=state_new;

        if(state_old!=state_new)begin//state changes
            if(state_new==3'd0) `print("NES_Tang starting...\n", STR);
            if(state_new==3'd1) `print("Game loading done.\n", STR);
        end
    end

//    if (sd_state != sd_state0) begin
//        if (sd_state == SD_READ_META) begin
//            `print("Reading SDcard\n", STR);
//        end
//        if (sd_state == SD_START_SECTOR) begin
//            if (sd_rsector[15:0] == 16'b0) begin
//                `print(sd_romlen, 3);
//            end else 
//                `print(sd_rsector[15:0], 2);
//        end
//        sd_state0 <= sd_state;
//    end

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

    if(~sys_resetn) begin
       `print("System Reset\nWelcome to NES_Tang\n",STR);
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

assign led = ~{~UART_RXD, loader_done};

endmodule