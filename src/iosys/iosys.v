// IOSys - PicoRV32-based IO subsystem for snestang
//
// IOSys provides the following functionality,
// - Menu system
// - ROM file loading
// - Configuration options
// - (Future) USB controller handling
// - (Future) Savestate handling
//
// This is similar to the IO controller of MIST, or HPS of MiSTer.
//
// The softcore runs RV32I at 21.6Mhz and uses SDRAM as main memory. Firmware is 
// loaded from SPI flash on the board. Firmware source is in /snestang/firmware.
// 
// Author: nand2mario, 1/2024

`ifndef PICORV32_REGS
`ifdef PICORV32_V
`error "iosys.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs
`endif

`ifndef PICOSOC_MEM
`define PICOSOC_MEM picosoc_mem
`endif

// this macro can be used to check if the verilog files in your
// design are read in the correct order.
`define PICOSOC_V

module iosys #(
    `include "wishbone_slaves.vh",
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1      // 1: nestang, 2: snestang
)
(
    input clk,                      // SNES mclk
    input hclk,                     // hdmi clock
    // input clkref,                   // 1/2 of clk 
    input resetn,

    // OSD display interface
    output overlay,
    input [10:0] overlay_x,         // 720p
    input [9:0] overlay_y,
    output [15:0] overlay_color,    // BGR5, [15] is opacity
    input [11:0] joy1,              // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // joystick 2

    // ROM loading interface
    output reg rom_loading,         // 0-to-1 loading starts, 1-to-0 loading is finished
    output [7:0] rom_do,            // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do
    
    // 32-bit wide memory interface for risc-v softcore
    // 0x_xxxx~6x_xxxx is RV RAM, 7x_xxxx is BSRAM
    output rv_valid,                // 1: active memory access
    input rv_ready,                 // pulse when access is done
    output [22:0] rv_addr,          // 8MB memory space
    output [31:0] rv_wdata,         // 32-bit write data
    output [3:0] rv_wstrb,          // 4 byte write strobe
    input [31:0] rv_rdata,          // 32-bit read data

    input ram_busy,                 // iosys starts after SDRAM initialization

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input  flash_spi_miso,          // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

    // UART
    input uart_rx,
    output uart_tx,

    // SD card
    output sd_clk,
    inout  sd_cmd,                  // MOSI
    input  sd_dat0,                 // MISO
    output sd_dat1,                 // 1
    output sd_dat2,                 // 1
    output sd_dat3,                 // 0 for SPI mode

    // Enhanced APU
    output o_reg_enhanced_apu,

    // Wishbone master
	//	The return bus wires
	input	wire            i_wb_ack, 
    input	wire            i_wb_stall, 
    input	wire    [31:0]  i_wb_idata,
    input	wire            i_wb_err, 
    // The bus control output wires
	output  wire            o_wb_cyc,
    output	wire            o_wb_stb,
    output	wire            o_wb_we,
    input	wire            o_wb_err, 
    output	wire    [1:0]   o_wb_addr, 
    output	wire    [128:0] o_wb_odata, 
    output	wire    [3:0]   o_wb_sel,

    // Cheats
    output wire o_cheats_enabled,
    output wire o_cheats_loaded,
    // Debug
    output wire [1:0] o_dbg_led,
    // System Type
    output wire [1:0] o_sys_type,
    // Aspect Ratio
    output wire o_reg_aspect_ratio
);

/* verilator lint_off PINMISSING */
/* verilator lint_off WIDTHTRUNC */

localparam FIRMWARE_SIZE = 256*1024;

reg flash_loaded;
reg flash_loading;
reg [20:0] flash_addr = {21{1'b1}};

reg flash_start;
wire [7:0] flash_dout;
wire flash_out_strb;
assign flash_spi_hold_n = 1;
assign flash_spi_wp_n = 1;      // disable write protection
reg [7:0] flash_d;
reg [3:0] flash_wstrb;
reg flash_wr;
wire [31:0] spiflash_reg_do;
wire spiflash_reg_wait;

// BSRAM - Use internal BRAM
localparam NES_BSRAM_SIZE = 32'h2000;
reg [7:0] reg_save_bsram;
reg [7:0] reg_load_bsram;
reg [7:0] reg_bsram [NES_BSRAM_SIZE-1:0];

always @(posedge clk) begin
    if (~resetn) begin
        flash_loaded <= 0;
        flash_addr = {21{1'b1}};
    end else begin
        flash_start <= 0;
        flash_wr <= 0;

        if (~flash_loaded && ~flash_loading && ~ram_busy) begin
            // start loading
            flash_start <= 1;
            flash_loading <= 1;
        end

        if (flash_loading) begin
            if (flash_out_strb) begin
                reg [20:0] next_addr = flash_addr + 1;
                flash_addr <= next_addr;
                flash_d <= flash_dout;
                flash_wr <= 1;

                case (next_addr[1:0])
                2'b00: flash_wstrb <= 4'b0001;
                2'b01: flash_wstrb <= 4'b0010;
                2'b10: flash_wstrb <= 4'b0100;
                2'b11: flash_wstrb <= 4'b1000;
                endcase

                if (next_addr == FIRMWARE_SIZE-1) begin
                    flash_loading <= 0;
                    flash_loaded <= 1;
                end
            end
        end
    end
end

// picorv32 softcore
wire mem_valid /* synthesis syn_keep=1 */;
wire mem_ready;
wire [31:0] mem_addr /* synthesis syn_keep=1 */, mem_wdata /* synthesis syn_keep=1 */;
wire [3:0] mem_wstrb /* synthesis syn_keep=1 */;
wire [31:0] mem_rdata /* synthesis syn_keep=1 */;

reg ram_ready /* synthesis syn_keep=1 */;
reg [31:0] ram_rdata;

wire        ram_sel = mem_valid && mem_addr[31:23] == 0;

wire        textdisp_reg_char_sel /* synthesis syn_keep=1 */= mem_valid && (mem_addr == 32'h 0200_0000);

wire        simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h 0200_0010);
wire [31:0] simpleuart_reg_div_do;

wire        simpleuart_reg_dat_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0014);
wire [31:0] simpleuart_reg_dat_do;
wire        simpleuart_reg_dat_wait;

wire        simplespimaster_reg_byte_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h0200_0020);
wire        simplespimaster_reg_word_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h0200_0024);
wire [31:0] simplespimaster_reg_do;
wire        simplespimaster_reg_wait /* synthesis syn_keep=1 */;

wire        romload_reg_ctrl_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0030);       // write 1 to start loading, 0 to finish loading
wire        romload_reg_data_sel /* synthesis syn_keep=1 */ = mem_valid && (mem_addr == 32'h 0200_0034);       // write once to load 4 bytes

wire        joystick_reg_sel = mem_valid && (mem_addr == 32'h 0200_0040);

wire        time_reg_sel = mem_valid && (mem_addr == 32'h0200_0050);        // milli-seconds since start-up (overflows in 49 days)
wire        cycle_reg_sel = mem_valid && (mem_addr == 32'h0200_0054);       // cycles counter (overflows every 200 seconds)

wire        id_reg_sel = mem_valid && (mem_addr == 32'h0200_0060);

wire        id_reg_enhanced_apu_sel = mem_valid && (mem_addr == 32'h0200_0080);

wire        spiflash_reg_byte_sel = mem_valid && (mem_addr == 32'h0200_0070);
wire        spiflash_reg_word_sel = mem_valid && (mem_addr == 32'h0200_0074);
wire        spiflash_reg_ctrl_sel = mem_valid && (mem_addr == 32'h0200_0078);
wire        id_reg_enhanced_apu_sel = mem_valid && (mem_addr == 32'h0200_0080);

// Cheats
wire        reg_cheats_enabled_sel = mem_valid && (mem_addr == 32'h0200_00A0);
wire        reg_cheats_loaded_sel = mem_valid && (mem_addr == 32'h0200_00C0);
wire        id_reg_cheats_sel_3 = mem_valid && (mem_addr == 32'h0200_00E0);     // MMSB
wire        id_reg_cheats_sel_2 = mem_valid && (mem_addr == 32'h0200_0100);
wire        id_reg_cheats_sel_1 = mem_valid && (mem_addr == 32'h0200_0120);
wire        id_reg_cheats_sel_0 = mem_valid && (mem_addr == 32'h0200_0140);     // LLSB
wire        id_reg_cheats_data_ready_sel = mem_valid && (mem_addr == 32'h0200_0160);

// BSRAM
wire        id_reg_save_bsram = mem_valid && (mem_addr == 32'h0200_0180);
wire        id_reg_load_bsram = mem_valid && (mem_addr == 32'h0200_01A0);

// System Type
wire        id_reg_sys_type = mem_valid && (mem_addr == 32'h0200_01C0);

// Aspect Ratio
wire        id_reg_aspect_ratio = mem_valid && (mem_addr == 32'h0200_01E0);

// Timer Interrupts
wire        id_reg_timer_interrupts = mem_valid && (mem_addr == 32'h0200_0200);
// Timer0 Load Register
wire        id_reg_timer0_load_value = mem_valid && (mem_addr == 32'h0200_0220);

assign mem_ready = ram_ready || textdisp_reg_char_sel || simpleuart_reg_div_sel || 
            romload_reg_ctrl_sel || romload_reg_data_sel || joystick_reg_sel || time_reg_sel || id_reg_sel || cycle_reg_sel || id_reg_sel ||
            id_reg_enhanced_apu_sel || 
            reg_cheats_enabled_sel || reg_cheats_loaded_sel || id_reg_cheats_data_ready_sel ||
            id_reg_save_bsram || id_reg_load_bsram ||
            id_reg_sys_type ||
            id_reg_aspect_ratio ||
            id_reg_timer_interrupts || 
            id_reg_timer0_load_value ||
            id_reg_cheats_sel_0 || id_reg_cheats_sel_1 || id_reg_cheats_sel_2 || id_reg_cheats_sel_3 ||
            (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait) ||
            ((simplespimaster_reg_byte_sel || simplespimaster_reg_word_sel) && !simplespimaster_reg_wait) ||
            (spiflash_reg_byte_sel || spiflash_reg_word_sel) && !spiflash_reg_wait ||
            spiflash_reg_ctrl_sel;

assign mem_rdata = ram_ready ? ram_rdata :
        joystick_reg_sel ? {4'b0, joy2, 4'b0, joy1} :
        simpleuart_reg_div_sel ? simpleuart_reg_div_do :
        simpleuart_reg_dat_sel ? simpleuart_reg_dat_do : 
        time_reg_sel ? time_reg :
        cycle_reg_sel ? cycle_reg :
        id_reg_sel ? {16'b0, CORE_ID} :
        id_reg_enhanced_apu_sel ? reg_enhanced_apu :
        reg_cheats_enabled_sel ? {31'h0, reg_cheats_enabled} :
        reg_cheats_loaded_sel ? {31'h0, reg_cheats_loaded} :
        id_reg_cheats_data_ready_sel ? {31'h0, reg_cheats_data_ready} :
        id_reg_save_bsram ? {31'h0, reg_save_bsram} :
        id_reg_load_bsram ? {31'h0, reg_load_bsram} :
        id_reg_sys_type ? {30'b00_0000_0000_0000, reg_sys_type} :
        id_reg_aspect_ratio ? {31'b000_0000_0000_0000, reg_aspect_ratio} :
        id_reg_timer_interrupts ? {reg_timer_interrupts} :
        id_reg_timer0_load_value ? {reg_timer0_load_value} :
        id_reg_cheats_sel_3 ? reg_cheats[128:96] :
        id_reg_cheats_sel_2 ? reg_cheats[95:64] :
        id_reg_cheats_sel_1 ? reg_cheats[63:32] :
        id_reg_cheats_sel_0 ? reg_cheats[31:0] :
        (simplespimaster_reg_byte_sel | simplespimaster_reg_word_sel) ? simplespimaster_reg_do : 
        (spiflash_reg_byte_sel | spiflash_reg_word_sel) ? spiflash_reg_do :
        32'h 0000_0000;

picorv32 #(
    // .ENABLE_MUL(1),
    // .ENABLE_DIV(1),
    // .COMPRESSED_ISA(1)
    .CATCH_ILLINSN(0),
    .ENABLE_COUNTERS (0),
    .ENABLE_COUNTERS64 (0),
    .CATCH_MISALIGN (0),
    .TWO_STAGE_SHIFT(0)
) rv32 (
    .clk(clk), .resetn(resetn & flash_loaded),
    .mem_valid(mem_valid), .mem_ready(mem_ready), .mem_addr(mem_addr), 
    .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata)
);

// text display @ 0x0200_0000
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .reg_char_we(textdisp_reg_char_sel ? mem_wstrb : 4'b0),
    .reg_char_di(mem_wdata) 
);

// toggle overlay display on/off
reg overlay_buf = 1;
assign overlay = overlay_buf;
always @(posedge clk) begin
    if (~resetn) begin
        overlay_buf <= 1;
    end else begin
        if (textdisp_reg_char_sel && mem_wstrb[0]) begin
            case (mem_wdata[25:24])
            2'd1: overlay_buf <= 1;
            2'd2: overlay_buf <= 0;
            default: ;
            endcase
        end 
    end
end

// uart @ 0x0200_0010
simpleuart simpleuart (
    .clk         (clk         ),
    .resetn      (resetn       ),

    .ser_tx      (uart_tx      ),
    .ser_rx      (uart_rx      ),

    .reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b0),
    .reg_div_di  (mem_wdata),
    .reg_div_do  (simpleuart_reg_div_do),

    .reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b0),
    .reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
    .reg_dat_di  (mem_wdata),
    .reg_dat_do  (simpleuart_reg_dat_do),
    .reg_dat_wait(simpleuart_reg_dat_wait)
);

// spi sd card @ 0x0200_0020
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 0;
simplespimaster simplespi (
    .clk(clk), .resetn(resetn),
    .sck(sd_clk), .mosi(sd_cmd), .miso(sd_dat0),
    .reg_byte_we(simplespimaster_reg_byte_sel ? mem_wstrb[0] : 1'b0),
    .reg_word_we(simplespimaster_reg_word_sel ? mem_wstrb[0] : 1'b0),
    .reg_di(mem_wdata),
    .reg_do(simplespimaster_reg_do),
    .reg_wait(simplespimaster_reg_wait)
);

// ROM loading I/O. 2 cycles for a byte and 2 cycles idles.
reg [3:0] rom_cnt;
reg [31:0] rom_do_buf;
assign rom_do = rom_do_buf[7:0];
always @(posedge clk) begin
    if (rom_cnt != 0)
        rom_cnt <= rom_cnt - 2'd1;
    // data register
    if (romload_reg_data_sel && mem_wstrb) begin
        rom_do_buf <= mem_wdata;
        rom_cnt <= 4'd15;
        rom_do_valid <= 1;
    end
    if (rom_cnt[1:0] == 2'd3)
        rom_do_valid <= 0;
    if (rom_cnt[1:0] == 2'd0 && rom_cnt[3:2] != 0) begin
        rom_do_buf[23:0] <= rom_do_buf[31:8];
        rom_do_valid <= 1;
    end
end
always @(posedge clk) begin
    if (romload_reg_ctrl_sel && mem_wstrb) begin
        // control register
        if (mem_wdata[7:0] == 8'd1)
            rom_loading <= 1;
        if (mem_wdata[7:0] == 8'd0)
            rom_loading <= 0;
    end    
end

// SPI flash @ 0x02000_0070
// Load 256KB of ROM from flash address 0x500000 into SDRAM at address 0x0
spiflash #(.ADDR(24'h500000), .LEN(FIRMWARE_SIZE)) flash (
    .clk(clk), .resetn(resetn),
    .ncs(flash_spi_cs_n), .miso(flash_spi_miso), .mosi(flash_spi_mosi),
    .sck(flash_spi_clk), 

    .start(flash_start), .dout(flash_dout), .dout_strb(flash_out_strb), .busy(),

    .reg_byte_we(spiflash_reg_byte_sel ? mem_wstrb[0] : 1'b0),
    .reg_word_we(spiflash_reg_word_sel ? mem_wstrb[0] : 1'b0),
    .reg_ctrl_we(spiflash_reg_ctrl_sel ? mem_wstrb[0] : 1'b0),
    .reg_di(mem_wdata), .reg_do(spiflash_reg_do), .reg_wait(spiflash_reg_wait)
);

// RV memory access
assign rv_addr = flash_loading ? flash_addr : mem_addr;
assign rv_wdata = flash_loading ? {flash_d, flash_d, flash_d, flash_d} : mem_wdata;
assign rv_wstrb = flash_loading ? flash_wstrb : mem_wstrb;
assign ram_rdata = rv_rdata;
assign rv_valid = flash_loading ? flash_wr : (mem_valid & ram_sel);
assign ram_ready = rv_ready;

// Time counter register
reg [31:0] time_reg, cycle_reg;
reg [$clog2(FREQ/1000)-1:0] time_cnt;
always @(posedge clk) begin
    if (~resetn) begin
        time_reg <= 0;
        time_cnt <= 0;
    end else begin
        cycle_reg <= cycle_reg + 1;
        time_cnt <= time_cnt + 1;
        if (time_cnt == FREQ/1000-1) begin
            time_cnt <= 0;
            time_reg <= time_reg + 1;
        end
    end
end

// Enhanced RAM register
reg reg_enhanced_apu;
always @(posedge clk) begin
    if(~resetn) begin
        reg_enhanced_apu <= 0;
    end
    if(mem_addr == 32'h0200_0080) begin
            reg_enhanced_apu <= mem_wdata;
    end
end

assign o_reg_enhanced_apu = reg_enhanced_apu;

// assign led = ~{2'b0, (^ total_refresh[7:0]), s0, flash_cnt[12]};     // flash while loading

// Enhanced RAM register
reg reg_enhanced_apu;
always @(posedge clk) begin
    if(~resetn) begin
        reg_enhanced_apu <= 0;
    end
    if(mem_addr == 32'h0200_0080) begin
            reg_enhanced_apu <= mem_wdata;
    end
end

assign o_reg_enhanced_apu = reg_enhanced_apu;

//
// Cheat engine
//
reg reg_cheats_enabled;
reg reg_cheats_loaded_last;
reg reg_cheats_loaded;
reg reg_cheats_enabled_last;
reg reg_cheats_data_ready;
reg reg_cheats_data_ready_last;
reg [128:0] reg_cheats;
reg [128:0] reg_cheats_last;
reg reg_cheats_data_sent;

wire reg_cheats_enabled_stb;
wire reg_cheats_loaded_stb;
wire reg_cheats_data_ready_stb;
wire reg_cheats_stb;

initial reg_cheats_enabled = 1'b0;
initial reg_cheats_enabled_last = 1'b0;
initial reg_cheats_loaded = 1'b0;
initial reg_cheats_loaded_last = 1'b0;
initial reg_cheats_data_ready = 1'b0;
initial reg_cheats_data_ready_last = 1'b0;
initial reg_cheats = 0;
initial reg_cheats_last = 0;

assign reg_cheats_enabled_stb = (reg_cheats_enabled_last != reg_cheats_enabled);
assign reg_cheats_loaded_stb = (reg_cheats_loaded_last != reg_cheats_loaded);
assign reg_cheats_data_ready_stb = (reg_cheats_data_ready_last != reg_cheats_data_ready);
assign reg_cheats_stb = (reg_cheats_last != reg_cheats);

always @(posedge clk) begin
    if(~resetn)
        reg_cheats <= 0;
    else begin
        if(mem_addr == 32'h0200_00A0)
            reg_cheats_enabled <= mem_wdata[0];
        if(mem_addr == 32'h0200_00C0)
            reg_cheats_loaded <= mem_wdata[0];
      if(mem_addr == 32'h0200_00E0)
            reg_cheats[127:96] <= mem_wdata;
        if(mem_addr == 32'h0200_0100)
            reg_cheats[95:64] <= mem_wdata;
        if(mem_addr == 32'h0200_0120)
            reg_cheats[63:32] <= mem_wdata;
        if(mem_addr == 32'h0200_0140)
            reg_cheats[31:0] <= mem_wdata;
        if(mem_addr == 32'h0200_0160)
            reg_cheats_data_ready <= mem_wdata[0];

       
        if(reg_cheats_enabled_stb)
            reg_cheats_enabled_last <= reg_cheats_enabled;
        if(reg_cheats_loaded_stb)
            reg_cheats_loaded_last <= reg_cheats_loaded;
        if(reg_cheats_stb)
            reg_cheats_last <= reg_cheats;  
        if(reg_cheats_loaded_stb)
            reg_cheats_data_ready_last <= reg_cheats_data_ready;
        else if((reg_cheats_data_ready)&&(~wb_cyc))
            reg_cheats_data_ready <= 1'b0;
    end
end

assign o_cheats_enabled = reg_cheats_enabled;
assign o_cheats_loaded = reg_cheats_loaded;

//
// Wishbone master
//
reg [1:0] wb_addr;
reg [128:0] wb_odata;
reg wb_we;
reg wb_cyc;
reg wb_stb;
reg wb_err;

initial wb_err = 1'b0;
initial	wb_cyc = 1'b0;
initial	wb_stb = 1'b0;


always @(posedge clk) begin
    if((~resetn)||(i_wb_err)) begin
        wb_cyc <= 1'b0;
	    wb_stb <= 1'b0;
        if(~resetn) begin
            // ToDo: reset stuff
        end
    end else begin
        // ToDo: Do bus stuff
        // cheats_data
        if((reg_cheats_enabled)&&(reg_cheats_data_ready)&&(~i_wb_stall)&&(~wb_cyc)) begin
            // wb_addr <= WISHBONE_SLAVE_ADDRESS_CHEATS_DATA;
            wb_addr <= 2'h01;
            wb_odata <= reg_cheats;
            wb_we <= 1'b1;
            wb_cyc <= 1'b1;
            wb_stb <= 1'b1;
        end
        if(wb_cyc) begin
            wb_addr <= 0;
            wb_we <= 1'b0;
            wb_stb <= 1'b0;
            if(i_wb_ack)
                wb_cyc <= 1'b0;
        end
    end
end

assign o_wb_addr = wb_addr;
assign o_wb_odata = wb_odata;
assign o_wb_we = wb_we;
assign o_wb_stb = wb_stb;
assign o_wb_cyc = wb_cyc;

// BSRAM
always @(posedge clk) begin
    if((mem_addr >= 32'h0000_6000)&&(mem_addr < 32'h0000_8000))
        reg_bsram[mem_addr[15:0] - 32'h6000] <= mem_wdata[7:0];
end
always @(posedge clk) begin
        if((mem_addr >= 32'h0000_6000)&&(mem_addr < 32'h0000_8000))
            reg_save_bsram <= mem_wdata[7:0];
end

reg dbg_led;
initial dbg_led = 1'b1;
always @(posedge clk)
    if(reg_load_bsram)
        dbg_led <= ~dbg_led;

assign o_dbg_led[0] = ~reg_load_bsram;
assign o_dbg_led[1] = dbg_led;

// System Type
reg [1:0] reg_sys_type;
initial reg_sys_type = 2'b00;   // NTSC/Dendy
always @(posedge clk) begin
    if(~resetn)
        reg_sys_type <= 2'b00;
    else begin
        if(mem_addr == 32'h0200_01C0)
            reg_sys_type <= mem_wdata[1:0];
    end
end

assign o_sys_type = reg_sys_type;

// Aspect Ratio
reg reg_aspect_ratio;
initial reg_aspect_ratio = 1'b0;    // 1:1
always @(posedge clk) begin
    if(~resetn)
        reg_aspect_ratio <= 1'b0;
    else begin
        if(mem_addr == 32'h0200_01E0)
            reg_aspect_ratio <= mem_wdata[0];
    end
end

assign o_reg_aspect_ratio = reg_aspect_ratio;

// Timer Interrupts
reg [31:0] reg_timer_interrupts;
initial reg_timer_interrupts <= 32'h0;
always @(posedge clk)
    if(~resetn)
        reg_timer_interrupts <= 32'h0;
    else begin
        if(mem_addr == 32'h0200_0200)
            reg_timer_interrupts <= mem_wdata[31:0];
        if(timer0_counter == reg_timer0_load_value)
            reg_timer_interrupts <= reg_timer_interrupts & 32'h01;
    end

// Timer0
reg [31:0] timer0_counter;
reg [31:0] reg_timer0_load_value;
initial timer0_counter = 32'h0;
initial reg_timer0_load_value = 32'h0;
// Write register
always @(posedge clk)
    if(~resetn)
        reg_timer0_load_value <= 32'h0;
    else
        if(mem_addr == 32'h0200_0220)
            reg_timer0_load_value <= mem_wdata[31:0];
// Counter
always @(posedge clk)
    if(~resetn)
        timer0_counter <= 32'h0;
    else if(timer0_counter < reg_timer0_load_value)
        timer0_counter <= timer0_counter + 1;
    else
        timer0_counter <= 32'h0;

endmodule

module picosoc_regs (
	input clk, wen,
	input [5:0] waddr,
	input [5:0] raddr1,
	input [5:0] raddr2,
	input [31:0] wdata,
	output [31:0] rdata1,
	output [31:0] rdata2
);
	reg [31:0] regs [0:31];

	always @(posedge clk)
		if (wen) regs[waddr[4:0]] <= wdata;

	assign rdata1 = regs[raddr1[4:0]];
	assign rdata2 = regs[raddr2[4:0]];
endmodule

