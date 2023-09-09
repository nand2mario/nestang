
// Load menu and games from MicroSD card
// Display a menu for user to choose a ROM.

module SDLoader #(
    parameter FREQ = 27_000_000
) (
    input clk,
    input resetn,

    output reg overlay,         // SD loader is working. This override display
    output reg [5:0] color,
    output reg [7:0] scanline,  // y 
    output reg [7:0] cycle,     // x
    
    input [7:0] nes_btn,    // gamepad input for menu navigation

    output [7:0] dout,  // ROM data is streamed out through dout.  
    output dout_valid,  // pulse 1 when dout is valid

    // SD card physical interface
    output sd_clk,
    inout  sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,     // 1
    output sd_dat2,     // 1
    output sd_dat3,      // 1
    
    // debug
    output [4:0] debug_active,
    output [4:0] debug_total,
    output [23:0] debug_sd_rsector,
    output [23:0] debug_sd_last_sector
);

`include "font.vh"

reg [31:0] magic;
reg [23:0] prev_meta, next_meta;
reg [7:0] x[0:19], y[0:19];
reg [23:0] rom_sector[0:19], rom_len[0:19];
reg [5:0] background, foreground;
reg [4:0] active, total;
reg [4:0] cursor_now;   // current cursor under refresh
reg [5:0] cursor_dot;   // RRRCCC
localparam [63:0] CURSOR = {8'b00000000,        // actual glyph is flipped horizontally
                            8'b00000011,
                            8'b00001111,
                            8'b00111111,
                            8'b11111111,
                            8'b00111111,
                            8'b00001111,
                            8'b00000011};

assign debug_active = active;
assign debug_total = total;
assign debug_sd_rsector = sd_rsector;
assign debug_sd_last_sector = sd_last_sector;

reg[2:0] pad;  // de-bounced pulse for joypad 
localparam [2:0] PAD_CENTER = 3'd0;
localparam [2:0] PAD_UP = 3'd1;
localparam [2:0] PAD_DOWN = 3'd2;
localparam [2:0] PAD_LEFT = 3'd3;
localparam [2:0] PAD_RIGHT = 3'd4;

// MicroSD
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode

// state and wires
reg [7:0] X, Y;           // current X and Y
reg sd_rstart = 0;
reg [23:0] sd_rsector, sd_last_sector;
reg [23:0] sd_romlen;     // max 32K sectors (16MB)
wire sd_rdone, sd_outen;
wire [7:0] sd_outbyte;
reg [8:0] sd_off;         // in-sector offset
reg sd_loading;
assign is_last_sector = sd_rsector == sd_last_sector;
//assign meta_idx = sd_off[7:3] - 5'd2;     // index of 8-byte entries from offset 16
reg [1:0] sd_cmd;
reg [9:0] sd_file;
wire [7:0] sd_list_name[0:51];
wire [7:0] sd_list_namelen;
wire [9:0] sd_list_file;
wire sd_list_en;

// whether current sd_outbyte is valid NES data
assign dout = sd_outbyte;
assign dout_valid = sd_loading & sd_outen & (~is_last_sector | (sd_off < sd_romlen[8:0]));

sd_file_list_reader #(
    .CLK_DIV(3'd1),.SIMULATE(0)
) sd_reader_i (
    .rstn(resetn), .clk(clk),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
    .card_stat(),.card_type(),
    .cmd(sd_cmd), .read_file(sd_file),
    .list_name(sd_list_file), .list_namelen(sd_list_namelen), 
    .list_file_num(sd_list_file), .list_en(sd_list_en),
    .outen(sd_outen), .outbyte(sd_outbyte)
);

// SD card loading process
reg [3:0] state;
localparam [3:0] SD_READ_DIR = 4'd1;       // getting meta-data, starting from sector 0
localparam [3:0] SD_UI = 4'd3;              // process user input
localparam [3:0] SD_READ_ROM = 4'd4;
localparam [3:0] SD_FAIL = 4'd14;
localparam [3:0] SD_DONE = 4'd15;
always @(posedge clk) begin
    wire [7:0] nx = X == 255 ? 10 : X+1;
    wire [7:0] ny = X == 255 ? (Y == 200 ? 200 : Y+1) : Y;
    wire [5:0] ch = (nx >> 3) - 2;
    wire [5:0] fn = (ny >> 3) - 5;
    
    if (~resetn) begin
        sd_cmd <= 1;                // list root dir
        state <= SD_READ_META;
        sd_loading <= 0;
        overlay <= 0;
    end else case (state)
    SD_READ_DIR: begin
        if (sd_list_en) begin       // found a dir entry, draw onto screen
            // starting from col=2, row=5, 8x8 chars, 20 lines, 30 wide
            if (sd_list_num < 20) begin
                X <= 9;
                Y <= 40 + sd_list_num << 3;
                overlay <= 0;
            end
        end else begin
            // fill in actual pixels, one pixel per clock cycle
            // so one file name takes 30*64=1920 cycles
            overlay <= 1;
            if (fn == sd_list_num && ch < sd_list_namelen) begin
                if (FONT[sd_list_name[ch]][ny[2:0]][nx[2:0]])
                    color <= 55;    // bright yellow
                else
                    color <= 13;    // black
            end else color <= 13;
            X <= nx;
            Y <= ny;
        end
    end
    SD_UI: begin                    // UP and DOWN to choose rom and A to load
        if (pad == PAD_UP && active != 0)
            active = active - 1;
        else if (pad == PAD_DOWN && active != total-1)
            active = active + 1;
        else if (pad == PAD_RIGHT || pad == PAD_LEFT) begin // navigate to next/prev menu
            sd_rstart <= 1;
            sd_rsector <= pad == PAD_RIGHT ? next_meta : prev_meta;
            state <= SD_READ_META;
            sd_off <= 0;
        end

        // paint cursor, one dot per clock
        {cursor_now, cursor_dot} <= {cursor_now, cursor_dot} + 1;
        if (cursor_now == total-1 && cursor_dot == 6'd63) begin
            cursor_now <= 0;
            cursor_dot <= 0;            
        end
        if (cursor_now == active && total != 0) begin
            color <= CURSOR[cursor_dot] ? foreground : background;
        end else
            color <= background;
        scanline <= y[cursor_now] + cursor_dot[5:3];
        cycle <= x[cursor_now] + cursor_dot[2:0];

        if (nes_btn[0] && total != 0) begin       // select ROM and start loading
            sd_cmd <= 2;
            sd_file <= active;
            overlay <= 0;
            sd_loading <= 1;
            state <= SD_READ_ROM;
        end
    end
    SD_READ_ROM: begin
        if (sd_outen) begin
            // data handled by dout_valid, dout above
        end
        // TODO: needs to turn sd_loading off
    end
    endcase
end

// process keyboard input
// nes_btn: (R L D U START SELECT B A)
reg [$clog2(FREQ/5+1)-1:0] debounce;   // 50ms debounce
wire deb = debounce == 0;
always @(posedge clk) begin
    pad <= PAD_CENTER;                  // pulse
    if (~resetn) begin
        pad <= 0;
        debounce = 0;
    end else begin
        debounce = debounce == 0 ? 0 : debounce-1;
        if (nes_btn[7] && deb) begin 
            pad <= PAD_RIGHT;
            debounce <= FREQ/5;
        end
        if (nes_btn[6] && deb) begin 
            pad <= PAD_LEFT;
            debounce <= FREQ/5;
        end
        if (nes_btn[5] && deb) begin 
            pad <= PAD_DOWN;
            debounce <= FREQ/5;
        end
        if (nes_btn[4] && deb) begin 
            pad <= PAD_UP;
            debounce <= FREQ/5;
        end
    end
end

endmodule