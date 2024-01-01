//
// NESTang top level
// nand2mario
//

// `timescale 1ns / 100ps

import configPackage::*;

module nestang_top (
    input sys_clk,

    // Button S1 and pin 48 are both resets
    input s1,
    input reset2,

    // UART
    input UART_RXD,
    output UART_TXD,

    // LEDs
    output [1:0] led,

    // SDRAM
    // For Primer 25K: https://github.com/MiSTer-devel/Hardware_MiSTer/blob/master/releases/sdram_xsds_3.0.pdf
    // For Nano 20K: 8MB 32-bit SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [SDRAM_DATA_WIDTH-1:0]    IO_sdram_dq,      // bidirectional data bus
    output [SDRAM_ROW_WIDTH-1:0] O_sdram_addr,     // multiplexed address bus
    output [1:0] O_sdram_ba,        // two banks
    output [SDRAM_DATA_WIDTH/8-1:0]   O_sdram_dqm,    

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

    // USB
    inout usbdm,
    inout usbdp,
`ifndef P25K
    inout usbdm2,
    inout usbdp2,
`endif
//    output clk_usb,

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);


reg sys_resetn = 0;
reg [7:0] reset_cnt = 255;      // reset for 255 cycles before start everything
always @(posedge clk) begin
    reset_cnt <= reset_cnt == 0 ? 0 : reset_cnt - 1;
    if (reset_cnt == 0)
        sys_resetn <= ~s1 & ~reset2;
end

`ifndef VERILATOR

// clk is 27Mhz
`ifdef P25K
  wire clk, clk_sdram;
  gowin_pll_27 pll27 (.clkin(sys_clk), .clkout0(clk), .clkout1(clk_sdram));      // Primer25K: PLL to generate 27Mhz from 50Mhz
`else
  wire clk = sys_clk;       // Nano20K: native 27Mhz system clock
  wire clk_sdram = ~clk;  
`endif
  wire clk_usb;

  // USB clock 12Mhz
  gowin_pll_usb pll_usb(
      .clkin(clk),
      .clkout(clk_usb)       // 12Mhz usb clock
  );

  // HDMI domain clocks
  wire clk_p;     // 720p pixel clock: 74.25 Mhz
  wire clk_p5;    // 5x pixel clock: 371.25 Mhz
  wire pll_lock;

  gowin_pll_hdmi pll_hdmi (
    .clkin(clk),
    .clkout(clk_p5),
    .lock(pll_lock)
  );

  gowin_clkdiv clk_div (
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
  wire [7:0] joy_rx[0:1], joy_rx2[0:1];     // 6 RX bytes for all button/axis state
  wire [7:0] usb_btn, usb_btn2;
  wire usb_btn_x, usb_btn_y, usb_btn_x2, usb_btn_y2;
  wire usb_conerr, usb_conerr2;
  wire auto_square, auto_triangle, auto_square2, auto_triangle2;
  // wire [7:0] nes_btn = usb_btn, nes_btn2 = 0;

  wire [7:0] nes_btn = {~joy_rx[0][5], ~joy_rx[0][7], ~joy_rx[0][6], ~joy_rx[0][4], 
                        ~joy_rx[0][3], ~joy_rx[0][0], ~joy_rx[1][6] | auto_square, ~joy_rx[1][5] | auto_triangle} |
                         usb_btn;
  wire [7:0] nes_btn2 = {~joy_rx2[0][5], ~joy_rx2[0][7], ~joy_rx2[0][6], ~joy_rx2[0][4], 
                         ~joy_rx2[0][3], ~joy_rx2[0][0], ~joy_rx2[1][6] | auto_square2, ~joy_rx2[1][5] | auto_triangle2} |
                         usb_btn2;

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
        .done(loader_done), .error(loader_fail), .loader_state(), .loader_bytes_left());

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

reg [7:0] sd_debug_reg;
wire [7:0] sd_debug_out;

SDLoader #(.FREQ(FREQ)) sd_loader (
    .clk(clk), .resetn(sys_resetn),
    .overlay(menu_overlay), .color(menu_color), .scanline(menu_scanline),
    .cycle(menu_cycle),
    .nes_btn(loader_btn | nes_btn | loader_btn_2 | nes_btn2), 
    .dout(sd_dout), .dout_valid(sd_dout_valid),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),

    .debug_reg(sd_debug_reg), .debug_out(sd_debug_out)
);

// Dualshock controller
dualshock_controller controller (
    .clk(clk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk), .O_psSEL(joystick_cs), .O_psTXD(joystick_mosi),
    .I_psRXD(joystick_miso),
    .O_RXD_1(joy_rx[0]), .O_RXD_2(joy_rx[1]), .O_RXD_3(),
    .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    // config=1, mode=1(analog), mode_en=1
    .I_CONF_SW(1'b0), .I_MODE_SW(1'b1), .I_MODE_EN(1'b0),
    .I_VIB_SW(2'b00)     // no vibration
);

dualshock_controller controller2 (
    .clk(clk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk2), .O_psSEL(joystick_cs2), .O_psTXD(joystick_mosi2),
    .I_psRXD(joystick_miso2),
    .O_RXD_1(joy_rx2[0]), .O_RXD_2(joy_rx2[1]), 
    .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .I_CONF_SW(1'b0), .I_MODE_SW(1'b1), .I_MODE_EN(1'b0),
    .I_VIB_SW(2'b00)     // no vibration
);

Autofire af_square (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx[1][7] | usb_btn_y), .out(auto_square));            // B
Autofire af_triangle (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx[1][4] | usb_btn_x), .out(auto_triangle));        // A
Autofire af_square2 (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx2[1][7] | usb_btn_y2), .out(auto_square2));
Autofire af_triangle2 (.clk(clk), .resetn(sys_resetn), .btn(~joy_rx2[1][4] | usb_btn_x2), .out(auto_triangle2));

//   usb_btn:      (R L D U START SELECT B A)
wire [1:0] usb_type, usb_type2;
wire usb_report, usb_report2;
usb_hid_host usb_controller (
    .usbclk(clk_usb), .usbrst_n(sys_resetn),
    .usb_dm(usbdm), .usb_dp(usbdp),	.typ(usb_type), .report(usb_report), 
    .game_l(usb_btn[6]), .game_r(usb_btn[7]), .game_u(usb_btn[4]), .game_d(usb_btn[5]), 
    .game_a(usb_btn[0]), .game_b(usb_btn[1]), .game_x(usb_btn_x), .game_y(usb_btn_y), 
    .game_sel(usb_btn[2]), .game_sta(usb_btn[3]),
    // ignore keyboard and mouse input
    .key_modifiers(), .key1(), .key2(), .key3(), .key4(),
    .mouse_btn(), .mouse_dx(), .mouse_dy(),
    .dbg_hid_report()
);

`ifndef P25K
usb_hid_host usb_controller2 (
    .usbclk(clk_usb), .usbrst_n(sys_resetn),
    .usb_dm(usbdm2), .usb_dp(usbdp2),	.typ(usb_type2), .report(usb_report2), 
    .game_l(usb_btn2[6]), .game_r(usb_btn2[7]), .game_u(usb_btn2[4]), .game_d(usb_btn2[5]), 
    .game_a(usb_btn2[0]), .game_b(usb_btn2[1]), .game_x(usb_btn_x2), .game_y(usb_btn_y2), 
    .game_sel(usb_btn2[2]), .game_sta(usb_btn2[3]),
    // ignore keyboard and mouse input
    .key_modifiers(), .key1(), .key2(), .key3(), .key4(),
    .mouse_btn(), .mouse_dx(), .mouse_dy(),
    .dbg_hid_report()
);
`endif

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

reg [19:0] timer;           // 37 times per second
always @(posedge clk) timer <= timer + 1;
reg [7:0] debug_cnt = 0;

// `define SD_REPORT
// `define DS2_REPORT

always@(posedge clk)begin
    state_0<={2'b0, loader_done};
    state_1<=state_0;

    // status for SD file browsing
`ifdef SD_REPORT
    if (debug_cnt < 100) begin
        case (timer)
        20'h00000: begin
          debug_cnt <= debug_cnt + 1;
          `print("sd: file_total=", STR);
          sd_debug_reg = 2;
        end
        20'h10000: begin 
          `print(sd_debug_out, 1);
          sd_debug_reg = 1;
        end
        20'h20000: `print(sd_debug_out, 1);
        20'h30000: begin
          `print(", file_start=", STR);
          sd_debug_reg = 3;      
        end
        20'h40000: `print(sd_debug_out, 1);
        20'h50000: begin
          `print(", active=", STR);
          sd_debug_reg = 4;      
        end
        20'h60000: `print(sd_debug_out, 1);
        20'h70000: begin
          `print(", total=", STR);
          sd_debug_reg = 5;      
        end
        20'h80000: `print(sd_debug_out, 1);
        20'h80000: begin
          `print(", state=", STR);
          sd_debug_reg = 6;      
        end
        20'ha0000: `print(sd_debug_out, 1);
        20'hb0000: `print(", buttons=", STR);
        20'hc0000: `print({nes_btn, nes_btn2}, 2);
        20'hf0000: `print("\n", STR);
        endcase
    end
`endif

`ifdef DS2_REPORT
//  joy_rx[0:1] dualshock buttons: 0:(L D R U St R3 L3 Se)  1:(□ X O △ R1 L1 R2 L2)

    case (timer)
    20'h00000: `print("controller1=", STR);
    20'h10000: `print({joy_rx[0], joy_rx[1]}, 2);
    20'h20000: `print(", controller2=", STR);
    20'h30000: `print({joy_rx2[0], joy_rx2[1]}, 2);
    20'h40000: `print(", usb_btn=", STR);
    20'h50000: `print(usb_btn, 1);
    20'hf0000: `print("\n", STR);
    endcase

`endif

    if (uart_demux.write)
        recv_packets <= recv_packets + 1;        

    if(state_0==state_1) begin //stable value
        state_old<=state_new;

        if(state_old!=state_new)begin//state changes
            if(state_new==3'd0) `print("NES_Tang starting...\n", STR);
            if(state_new==3'd1) `print("Game loading done.\n", STR);
        end
    end

`ifdef HID_REPORT
    if (timer == 20'h00000)
      `print("hid=", STR);
    if (timer == 20'h10000)
      `print(dbg_hid_report, 8);
    if (timer == 20'h20000)
      `print(", vidpid=", STR);
    if (timer == 20'h30000)
      `print({dbg_vid, dbg_pid}, 4);
    if (timer == 20'h40000)
      `print(", dev=", STR);
    if (timer == 20'h50000)
      `print({4'b0, dbg_dev}, 1);
    if (timer == 20'h60000)
      `print(", ds2[2]=", STR);
    if (timer == 20'h70000)
      `print({joy_rx[0], joy_rx[1], joy_rx2[0], joy_rx2[1]}, 4);
    if (timer == 20'h80000)
      `print(", usb_btn[2]=", STR);
    if (timer == 20'h90000)
      `print({usb_btn, usb_btn2}, 2);

    if (timer == 20'hf0000)
      `print("\n", STR);
`endif

`ifdef PRINT_SD
    if (sd_state != sd_state0) begin
        if (sd_state == SD_READ_META) begin
            `print("Reading SDcard\n", STR);
        end
        if (sd_state == SD_START_SECTOR) begin
            if (sd_rsector[15:0] == 16'b0) begin
                `print(sd_romlen, 3);
            end else 
                `print(sd_rsector[15:0], 2);
        end
        sd_state0 <= sd_state;
    end
`endif

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
       `print("System Reset\nWelcome to NESTang\n",STR);
        debug_cnt <= 0;
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

//assign led = ~{~UART_RXD, loader_done};
//assign led = ~{~UART_RXD, usb_conerr, loader_done};
// assign led = ~usb_btn;

reg [23:0] led_cnt;
always @(posedge clk) led_cnt <= led_cnt + 1;
assign led = {led_cnt[23], led_cnt[22]};

endmodule