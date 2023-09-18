
// Display root directory content from MicroSD card 
// Allow user to choose a ROM, then load it into nes

module SDLoader #(
    parameter FREQ = 27_000_000
) (
    input clk,
    input resetn,

    output reg overlay,         // SD loader is working. This override display
    output reg [5:0] color,
    output reg [7:0] scanline,  // y 
    output reg [7:0] cycle,     // x
    
    input [7:0] nes_btn,        // gamepad input for menu navigation

    output [7:0] dout,          // ROM data is streamed out through dout.  
    output dout_valid,          // pulse 1 when dout is valid

    // SD card physical interface
    output sd_clk,
    inout  sd_cmd,              // MOSI
    input  sd_dat0,             // MISO
    output sd_dat1,             // 1
    output sd_dat2,             // 1
    output sd_dat3,             // 1
    
    // debug
    input [7:0] debug_reg,
    output reg [7:0] debug_out
);

`include "font.vh"

localparam [5:0] COLOR_BACK=13, COLOR_CURSOR=55, COLOR_TEXT=56;
reg [4:0] active;           // within the page
reg [11:0] file_total;      // max 4095 files
reg [11:0] file_start = 1;  // file number is 1-based
wire [4:0] total = file_total < file_start ? 0 :        // number of files in this page
                   file_total >= file_start + 19 ? 20 : file_total - file_start + 1;
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
reg [23:0] sd_romlen;     // max 32K sectors (16MB)
wire sd_outen;
wire [7:0] sd_outbyte;
reg sd_loading;
reg sd_op = 0;
wire sd_done;
reg sd_restart = 0;
reg [11:0] sd_file;
wire [7:0] sd_list_name[0:51];
wire [7:0] sd_list_namelen;
wire [11:0] sd_list_file;
wire sd_list_en;

// whether current sd_outbyte is valid NES data
assign dout = sd_outbyte;
assign dout_valid = sd_loading & sd_outen;

sd_file_list_reader #(
    .CLK_DIV(3'd1),.SIMULATE(0)
) sd_reader_i (
    .rstn(resetn & ~sd_restart), .clk(clk),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
    .card_stat(),.card_type(),.filesystem_type(),
    .op(sd_op), .read_file(sd_file), .done(sd_done),
    .list_name(sd_list_name), .list_namelen(sd_list_namelen), 
    .list_file_num(sd_list_file), .list_en(sd_list_en),
    .outen(sd_outen), .outbyte(sd_outbyte),
    .debug_read_done(), .debug_read_sector_no(),
    .debug_filesystem_state()
);

// SD card loading process
reg [3:0] state;
localparam [3:0] SD_READ_DIR = 4'd1;        // getting meta-data, starting from sector 0
localparam [3:0] SD_UI = 4'd3;              // process user input
localparam [3:0] SD_READ_ROM = 4'd4;
localparam [3:0] SD_FAIL = 4'd14;
localparam [3:0] SD_DONE = 4'd15;
reg [7:0] X = 15, Y = 40;                   // current X and Y
wire [7:0] nx = X == 255 ? 16 : X+1;
wire [7:0] ny = X == 255 ? (Y == 200 ? 200 : Y+1) : Y;
wire [7:0] ch = (nx >> 3) - 2;              // current char
wire [7:0] fn = (ny >> 3) - 5;              // current file, 0 - 19

always @(posedge clk) begin
    if (~resetn) begin
        sd_op <= 0;                 // list root dir
        state <= SD_READ_DIR;
        sd_loading <= 0;
        overlay <= 0;
        file_start <= 1;
    end else begin
        sd_restart <= 0;
        overlay <= 0;
        case (state)
        SD_READ_DIR: begin
            if (sd_list_en) begin       // found a dir entry, draw onto screen
                // starting from col=2, row=5, 8x8 chars, 20 lines, 30 wide
                file_total <= sd_list_file;                       // update file count
                if (sd_list_file >= file_start && sd_list_file < file_start + 20) begin
                    X <= 15;
                    Y <= 40 + ((sd_list_file - file_start) << 3);
                    overlay <= 0;
                end
            end else if (sd_done) begin
                state <= SD_UI;
            end else if (Y < 200) begin
                // fill in actual pixels, one pixel per clock cycle
                // so one file name takes 30*64=1920 cycles
                overlay <= 1;
                if (fn + file_start == sd_list_file) begin
                    if (FONT[sd_list_name[ch]][ny[2:0]][nx[2:0]])
                        color <= COLOR_TEXT;    // yellow
                    else
                        color <= COLOR_BACK;    // black
                end else color <= 13;
                X <= nx; cycle <= nx;
                Y <= ny; scanline <= ny;
            end
        end
        SD_UI: begin                    // UP and DOWN to choose rom and A to load
            if (pad == PAD_UP && active != 0)
                active = active - 1;
            else if (pad == PAD_DOWN && active != total-1)
                active = active + 1;
            else if (pad == PAD_RIGHT && file_start + 20 <= file_total) begin // navigate to next/prev menu
                file_start <= file_start + 20;
                sd_restart <= 1;
                state <= SD_READ_DIR;
            end else if (pad == PAD_LEFT && file_start > 1) begin
                file_start <= file_start - 20;
                sd_restart <= 1;
                state <= SD_READ_DIR;
            end

            // paint cursor, one dot per clock
            overlay <= 1;
            {cursor_now, cursor_dot} <= {cursor_now, cursor_dot} + 1;
            if (cursor_now == total-1 && cursor_dot == 6'd63) begin
                cursor_now <= 0;
                cursor_dot <= 0;            
            end
            if (cursor_now == active && total != 0) begin
                color <= CURSOR[cursor_dot] ? COLOR_CURSOR : COLOR_BACK;
            end else
                color <= COLOR_BACK;
            scanline <= 40 + (cursor_now<<3) + cursor_dot[5:3];
            cycle <= cursor_dot[2:0];

            if (nes_btn[0] && total != 0) begin     // select ROM and start loading
                sd_op <= 1;
                sd_file <= active + file_start;
                sd_restart <= 1;                    // restart controller to exec read command
                overlay <= 0;
                sd_loading <= 1;
                state <= SD_READ_ROM;
            end
        end
        SD_READ_ROM: begin
            if (sd_outen) begin
                // data handled by dout_valid, dout above
            end else if (sd_done)
                sd_loading <= 0;                    // loading is finished
        end
        endcase
    end
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

always @* begin
    case (debug_reg)
    8'h1: debug_out = file_total[7:0];
    8'h2: debug_out = file_total[11:8];
    8'h3: debug_out = file_start;
    8'h4: debug_out = active;
    8'h5: debug_out = total;
    8'h6: debug_out = state;
    default: debug_out = 0;
    endcase
end

endmodule