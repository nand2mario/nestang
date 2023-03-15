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

  // MicroSD state and wires
  reg sd_rstart = 0;
  reg [31:0] sd_rsector;
  wire sd_rdone, sd_outen;
  wire [7:0] sd_outbyte;
  reg [23:0] sd_romlen;     // max 32K sectors (16MB)
  reg [8:0] sd_off;         // in-sector offset
  reg sd_loading, sd_last_sector;
  wire sd_nes_valid = sd_loading & sd_outen & 
                  (~sd_last_sector | (sd_off < sd_romlen[8:0]));
                          // whether current sd_outbyte is valid NES data

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
  wire [7:0] loader_input = sd_nes_valid ? sd_outbyte : uart_data;
  wire       loader_clk   = (uart_addr == 8'h37) && uart_write || sd_nes_valid;
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
  joy_rx[0:1] dualshock buttons: (L D R U St R3 L3 Se)  (□ X O △ R1 L1 R2 L2)
  nes_btn[0:1] NES buttons:      (A B	Select Start U D L R)
  O is A, X is B
  */
  wire [7:0] joy_rx[0:5];     // 6 RX bytes for all button/axis state
  wire [7:0] nes_btn = ~{joy_rx[0][5], joy_rx[0][7], joy_rx[0][6], joy_rx[0][4], 
                         joy_rx[0][3], joy_rx[0][0], joy_rx[1][6], joy_rx[1][5] };
  wire [7:0] nes_btn2 = 0;
  
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

// HDMI output
nes2hdmi u_hdmi (
    .clk(clk), .resetn(sys_resetn),
    .color(color), .cycle(cycle), .scanline(scanline), .sample(sample >> 1),
    .clk_pixel(clk_p), .clk_5x_pixel(clk_p5), .locked(pll_lock),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

// MicroSD
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode

sd_reader #(
    .CLK_DIV(3'd1),.SIMULATE(0)
) sd_reader_i (
    .rstn(sys_resetn), .clk(clk),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
    .card_stat(),.card_type(),
    .rstart(sd_rstart), .rbusy(), .rdone(sd_rdone), .outen(sd_outen),
    .rsector(sd_rsector),
    .outaddr(), .outbyte(sd_outbyte)
);

// SD card loading process
reg [3:0] sd_state;
localparam [3:0] SD_READ_META = 4'd1;     // getting meta-data from sector 0
localparam [3:0] SD_START_SECTOR = 4'd2;
localparam [3:0] SD_READ_NES = 4'd3;
localparam [3:0] SD_DONE = 4'd15;
always @(posedge clk) begin
    if (~sys_resetn) begin
        sd_rstart <= 1;
        sd_rsector <= 0;
        sd_state <= SD_READ_META;
        sd_off <= 0;
        sd_loading <= 0;
    end else case (sd_state)
    SD_READ_META: begin
        if (sd_outen) begin
            sd_off <= sd_off + 1;
            if (sd_off == 8'd0) sd_romlen[7:0] <= sd_outbyte;
            if (sd_off == 8'd1) sd_romlen[15:8] <= sd_outbyte;
            if (sd_off == 8'd2) sd_romlen[23:16] <= sd_outbyte;
        end
        if (sd_rdone) begin
            sd_rstart <= 0;     // turn off reading
            sd_off <= 0;
            sd_state <= SD_START_SECTOR;
        end
    end
    SD_START_SECTOR: begin 
        if (sd_rsector[14:0] > sd_romlen[23:9]) begin // sd_rsector is # of sectors finished
            sd_loading <= 0;
            sd_state = SD_DONE;
        end else begin      // start reading next sector
            sd_rsector[14:0] <= sd_rsector[14:0] + 1;
            sd_off <= 0;
            sd_rstart <= 1'b1;
            sd_loading <= 1;
            sd_last_sector <= (sd_rsector[14:0] == sd_romlen[23:9]);
            sd_state = SD_READ_NES;
        end
    end
    SD_READ_NES: begin
        if (sd_outen) begin
            // data handled by sd_nes_valid, loader_input above
        end
        if (sd_rdone) begin
            sd_rstart <= 0;
            sd_state <= SD_START_SECTOR;
        end
    end
    endcase
end

// Dualshock controller
reg sclk;                   // controller main clock at 250Khz
reg [6:0] sclk_cnt;         // FREQ / 250K / 2 = 75

// Generate sclk
always @(posedge clk) begin
    sclk_cnt <= sclk_cnt + 1;
    if (sclk_cnt == 7'd75) begin
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

//    if (timer == 0) begin
//        `print({joy_rx[0], joy_rx[1]}, 2);
//    end
//    if (timer == 20'b1000_0000_0000_0000_0000) begin
//        `print("\n", STR);
//    end

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