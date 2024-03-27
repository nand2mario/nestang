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
`ifndef PRIMER
    inout usbdm2,
    inout usbdp2,
`endif
//    output clk_usb,

    // NES gamepad
`ifdef NANO
    output NES_gamepad_data_clock,
    output NES_gampepad_data_latch,
    input NES_gampead_serial_data,
    output NES_gamepad_data_clock2,
    output NES_gampepad_data_latch2,
    input NES_gampead_serial_data2,
`endif

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

wire clk, fclk, clk_sdram, clk_usb;
assign O_sdram_clk = clk_sdram;

reg sys_resetn = 0;
reg [7:0] reset_cnt = 255;      // reset for 255 cycles before start everything
always @(posedge clk) begin
    reset_cnt <= reset_cnt == 0 ? 0 : reset_cnt - 1;
    if (reset_cnt == 0)
        sys_resetn <= ~s1 & ~reset2 & ~(nes_btn[5] && nes_btn[2]);    // 8BitDo Home button = Select + Down
end

`ifndef VERILATOR

// clk is 27Mhz
`ifdef PRIMER
  gowin_pll_27 pll27 (.clkin(sys_clk), .clkout0(clk), .clkout1(clk_sdram));      // Primer25K: PLL to generate 27Mhz from 50Mhz
`else
  gowin_pll_nes pll_nes(.clkin(sys_clk), .clkout(fclk), .clkoutp(clk_sdram), .clkoutd3(clk));

  wire clk = sys_clk;       // Nano20K: native 27Mhz system clock
  wire clk_sdram = ~clk;  
`endif

  // USB clock 12Mhz
//   gowin_pll_usb pll_usb(
//       .clkin(clk),
//       .clkout(clk_usb)       // 12Mhz usb clock
//   );

  // HDMI domain clocks
  wire clk_p;     // 720p pixel clock: 74.25 Mhz
  wire clk_p5;    // 5x pixel clock: 371.25 Mhz
  wire pll_lock;

  gowin_pll_hdmi pll_hdmi (
    .clkin(clk),
    .clkout(clk_p5),
    .lock(pll_lock)
  );

  CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(clk_p),
    .HCLKIN(clk_p5),
    .RESETN(sys_resetn & pll_lock),
    .CALIB(1'b0)
  );
`else   // VERILATOR
  // dummy clocks for verilator
  assign clk = sys_clk;
  assign fclk = sys_clk;
  assign clk_sdram = sys_clk;
`endif

  wire [5:0] color;
  wire [15:0] sample;
  wire [8:0] scanline;
  wire [8:0] cycle;
  wire [2:0] joypad_out;
  wire joypad_strobe = joypad_out[0];
  wire [1:0] joypad_clock;
  wire [4:0] joypad1_data, joypad2_data;

  wire [21:0] memory_addr_cpu, memory_addr_ppu;
  wire memory_read_cpu, memory_read_ppu;
  wire memory_write_cpu, memory_write_ppu;
  wire [7:0] memory_din_cpu, memory_din_ppu;
  wire [7:0] memory_dout_cpu, memory_dout_ppu;

  reg [7:0] joypad_bits, joypad_bits2;
  reg [1:0] last_joypad_clock;
  wire [31:0] dbgadr;
  wire [1:0] dbgctr;

  wire [1:0] nes_ce;

  wire loading;                 // from iosys
  wire [7:0] loader_do;
  wire loader_do_valid;
  
`ifdef VERILATOR
  // Static compiled-in game data 
  GameData game_data(
        .clk(clk), .reset(~sys_resetn), .start(1'b1), 
        .odata(loader_do), .odata_clk(loader_do_valid));
`endif

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

  wire [7:0] nes_btn  = {~joy_rx[0][5], ~joy_rx[0][7], ~joy_rx[0][6], ~joy_rx[0][4], 
                         ~joy_rx[0][3], ~joy_rx[0][0], ~joy_rx[1][6] | auto_square, ~joy_rx[1][5] | auto_triangle}
                        | usb_btn
                        | NES_gamepad_button_state;
  wire [7:0] nes_btn2 = {~joy_rx2[0][5], ~joy_rx2[0][7], ~joy_rx2[0][6], ~joy_rx2[0][4], 
                         ~joy_rx2[0][3], ~joy_rx2[0][0], ~joy_rx2[1][6] | auto_square2, ~joy_rx2[1][5] | auto_triangle2}
                         | usb_btn2
                         | NES_gamepad_button_state2;

  // NES gamepad
  wire [7:0]NES_gamepad_button_state;
  wire NES_gamepad_data_available;
  wire [7:0]NES_gamepad_button_state2;
  wire NES_gamepad_data_available2;

`ifdef NANO
  NESGamepad nes_gamepad(
        .i_clk(clk),
        .i_rst(sys_resetn),
        .o_data_clock(NES_gamepad_data_clock),
        .o_data_latch(NES_gampepad_data_latch),
        .i_serial_data(NES_gampead_serial_data),
        .o_button_state(NES_gamepad_button_state),
        .o_data_available(NES_gamepad_data_available)
                        );

  NESGamepad nes_gamepad2(
        .i_clk(clk),
        .i_rst(sys_resetn),
        .o_data_clock(NES_gamepad_data_clock2),
        .o_data_latch(NES_gampepad_data_latch2),
        .i_serial_data(NES_gampead_serial_data2),
        .o_button_state(NES_gamepad_button_state2),
        .o_data_available(NES_gamepad_data_available2)
                        );
`endif

  // Joypad handling
  always @(posedge clk) begin
    if (joypad_strobe) begin
      joypad_bits <= nes_btn;
      joypad_bits2 <= nes_btn2;
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
      joypad_bits <= {1'b0, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
      joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
  end

  // Loader
  wire [21:0] loader_addr;
  wire [7:0] loader_write_data;
  reg loading_r;
  always @(posedge clk) loading_r <= loading;
  wire loader_reset = loading & ~loading_r;
  wire loader_write;
  wire [63:0] loader_flags;
  reg  [63:0] mapper_flags;
  wire loader_done, loader_fail;
  wire loader_busy, loaded;
  wire type_nes = 1'b1;  // (menu_index == 0) || (menu_index == {2'd0, 6'h1});
  wire type_bios = 1'b0; // (menu_index == 2);
  wire is_bios = 0;      //type_bios;
  wire type_fds = 1'b0;  // (menu_index == {2'd1, 6'h1});
  wire type_nsf = 1'b0;  // (menu_index == {2'd2, 6'h1});

  // Parses ROM data and store them for MemoryController to access
  GameLoader loader(
    .clk(clk), .reset(loader_reset), .downloading(loading), 
    .filetype({4'b0000, type_nsf, type_fds, type_nes, type_bios}),
    .is_bios(is_bios), .invert_mirroring(1'b0),
    .indata(loader_do), .indata_clk(loader_do_valid),

    .mem_addr(loader_addr), .mem_data(loader_write_data), .mem_write(loader_write),
    .bios_download(),
    .mapper_flags(loader_flags), .busy(loader_busy), .done(loader_done),
    .error(loader_fail), .rom_loaded(loaded)
  );

  // VRC6
  wire int_audio;
  wire ext_audio;
  assign int_audio = 1;
  assign ext_audio = (mapper_flags[7:0] == 19) | (mapper_flags[7:0] == 24) | (mapper_flags[7:0] == 26);

  // Main NES machine
  NES nes(
    .clk(clk), .reset_nes(reset_nes), .cold_reset(1'b0),
    .sys_type(system_type), .nes_div(nes_ce),
    .mapper_flags(mapper_flags),
    .sample(sample), .color(color),
    .joypad_out(joypad_out), .joypad_clock(joypad_clock), 
    .joypad1_data(joypad1_data), .joypad2_data(joypad2_data),

    .fds_busy(), .fds_eject(), .diskside_req(), .diskside(),        // disk system
	.audio_channels(5'b11111),  // enable all channels
    
	.cpumem_addr(memory_addr_cpu),
	.cpumem_read(memory_read_cpu),
	.cpumem_din(memory_din_cpu),
	.cpumem_write(memory_write_cpu),
	.cpumem_dout(memory_dout_cpu),
	.ppumem_addr(memory_addr_ppu),
	.ppumem_read(memory_read_ppu),
	.ppumem_write(memory_write_ppu),
	.ppumem_din(memory_din_ppu),
	.ppumem_dout(memory_dout_ppu),

    .cycle(cycle), .scanline(scanline),
    .int_audio(int_audio),    // VRC6
    .ext_audio(ext_audio)
  );

/*verilator tracing_off*/

sdram_nes sdram (
    .clk(fclk), .resetn(sys_resetn), .busy(sdram_busy),

    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), 
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n), 
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm), 

    // PPU
    .addrA(memory_addr_ppu), .weA(memory_write_ppu), .dinA(memory_dout_ppu),
    .oeA(memory_read_ppu), .doutA(memory_din_ppu),

    // CPU
    .addrB(loading ? loader_addr_mem : memory_addr_cpu), .weB(loader_write_mem || memory_write_cpu),
    .dinB(loading ? loader_write_data_mem : memory_dout_cpu),
    .oeB(~loading & memory_read_cpu), .doutB(memory_din_cpu),

    // IOSys risc-v softcore
    .rv_addr({rv_addr[20:2], rv_word}), .rv_din(rv_word ? rv_wdata[31:16] : rv_wdata[15:0]), 
    .rv_ds(rv_ds), .rv_dout(rv_dout), .rv_req(rv_req), .rv_req_ack(rv_req_ack), .rv_we(rv_wstrb != 0)
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

// IOSys for menu, rom loading...
localparam RV_IDLE_REQ0 = 3'd0;
localparam RV_WAIT0_REQ1 = 3'd1;
localparam RV_DATA0 = 3'd2;
localparam RV_WAIT1 = 3'd3;
localparam RV_DATA1 = 3'd4;
reg [2:0]   rvst;

wire        rv_valid;
reg         rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
reg  [15:0] rv_dout0;
wire [31:0] rv_rdata = {rv_dout, rv_dout0};
reg         rv_valid_r;
reg         rv_word;           // which word
reg         rv_req;
wire        rv_req_ack;
wire [15:0] rv_dout;
reg [1:0]   rv_ds;
reg         rv_new_req;

always @(posedge mclk) begin            // RV
    if (~resetn) begin
        rvst <= RV_IDLE_REQ0;
        rv_ready <= 0;
    end else begin
        reg write = rv_wstrb != 0;
        reg rv_new_req_t = rv_valid & ~rv_valid_r;
        if (rv_new_req_t) rv_new_req <= 1;

        rv_ready <= 0;
        rv_valid_r <= rv_valid;

        case (rvst)
        RV_IDLE_REQ0: if (rv_new_req || rv_new_req_t) begin
            rv_new_req <= 0;
            rv_req <= ~rv_req;
            if (write && rv_wstrb[1:0] == 2'b0) begin
                // shortcut for only writing the upper word
                rv_word <= 1;
                rv_ds <= rv_wstrb[3:2];
                rvst <= RV_WAIT1;
            end else begin
                rv_word <= 0;
                if (write)
                    rv_ds <= rv_wstrb[1:0];
                else
                    rv_ds <= 2'b11;
                rvst <= RV_WAIT0_REQ1;
            end
        end

        RV_WAIT0_REQ1: begin
            if (rv_req == rv_req_ack) begin
                rv_req <= ~rv_req;      // request 1
                rv_word <= 1;
                if (write) begin
                    rvst <= RV_WAIT1;
                    if (rv_wstrb[3:2] == 2'b0) begin
                        // shortcut for only writing the lower word
                        rv_req <= rv_req;
                        rv_ready <= 1;
                        rvst <= RV_IDLE_REQ0;
                    end
                    rv_ds <= rv_wstrb[3:2];
                end else begin
                    rv_ds <= 2'b11;
                    rvst <= RV_DATA0;
                end
            end
        end

        RV_DATA0: begin
            rv_dout0 <= rv_dout;
            rvst <= RV_WAIT1;
        end
            
        RV_WAIT1: 
            if (rv_req == rv_req_ack) begin
                if (write)  begin
                    rv_ready <= 1;
                    rvst <= RV_IDLE_REQ0;
                end else
                    rvst <= RV_DATA1;
            end

        RV_DATA1: begin
            rv_ready <= 1;
            rvst <= RV_IDLE_REQ0;
        end

        default:;
        endcase
    end
end

iosys iosys (
    .clk(mclk), .hclk(hclk), /*.clkref(DOTCLK),*/ .resetn(resetn),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(joy1_btns), .joy2(joy2_btns),

    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), 
    .ram_busy(sdram_busy),

    .rv_valid(rv_valid), .rv_ready(rv_ready), .rv_addr(rv_addr),
    .rv_wdata(rv_wdata), .rv_wstrb(rv_wstrb), .rv_rdata(rv_rdata),

    .flash_spi_cs_n(flash_spi_cs_n), .flash_spi_miso(flash_spi_miso),
    .flash_spi_mosi(flash_spi_mosi), .flash_spi_clk(flash_spi_clk),
    .flash_spi_wp_n(flash_spi_wp_n), .flash_spi_hold_n(flash_spi_hold_n),

    .uart_tx(UART_TXD), .uart_rx(UART_RXD),

    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3)
);

// Dualshock controller
dualshock_controller controller (
    .clk(clk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk), .O_psSEL(joystick_cs), .O_psTXD(joystick_mosi),
    .I_psRXD(joystick_miso),
    .O_RXD_1(joy_rx[0]), .O_RXD_2(joy_rx[1]), .O_RXD_3(),
    .O_RXD_4(), .O_RXD_5(), .O_RXD_6()
);

dualshock_controller controller2 (
    .clk(clk), .I_RSTn(1'b1),
    .O_psCLK(joystick_clk2), .O_psSEL(joystick_cs2), .O_psTXD(joystick_mosi2),
    .I_psRXD(joystick_miso2),
    .O_RXD_1(joy_rx2[0]), .O_RXD_2(joy_rx2[1]), 
    .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6()
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

`ifndef PRIMER
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

`endif

//assign led = ~{~UART_RXD, loader_done};
//assign led = ~{~UART_RXD, usb_conerr, loader_done};
// assign led = ~usb_btn;

reg [23:0] led_cnt;
always @(posedge clk) led_cnt <= led_cnt + 1;
assign led = {led_cnt[23], led_cnt[22]};

endmodule