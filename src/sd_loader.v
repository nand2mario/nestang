
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

// whether current sd_outbyte is valid NES data
assign dout = sd_outbyte;
assign dout_valid = sd_loading & sd_outen & (~is_last_sector | (sd_off < sd_romlen[8:0]));

sd_reader #(
    .CLK_DIV(3'd1),.SIMULATE(0)
) sd_reader_i (
    .rstn(resetn), .clk(clk),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
    .card_stat(),.card_type(),
    .rstart(sd_rstart), .rbusy(), .rdone(sd_rdone), .outen(sd_outen),
    .rsector({8'b0, sd_rsector}),
    .outaddr(), .outbyte(sd_outbyte)
);

// SD card loading process
reg [3:0] state;
localparam [3:0] SD_READ_META = 4'd1;       // getting meta-data, starting from sector 0
localparam [3:0] SD_READ_MENU = 4'd2;      
localparam [3:0] SD_UI = 4'd3;              // process user input
localparam [3:0] SD_READ_ROM = 4'd4;
localparam [3:0] SD_FAIL = 4'd14;
localparam [3:0] SD_DONE = 4'd15;
always @(posedge clk) begin
    if (~resetn) begin
        sd_rstart <= 1;
        sd_rsector <= 0;
        state <= SD_READ_META;
        sd_off <= 0;
        sd_loading <= 0;
        overlay <= 0;
    end else case (state)
    SD_READ_META: begin
        if (sd_outen) begin         // parse meta sector
            sd_off <= sd_off + 1;
            if (sd_off == 8'd0) magic[7:0] <= sd_outbyte;
            if (sd_off == 8'd1) magic[15:8] <= sd_outbyte;
            if (sd_off == 8'd2) magic[23:16] <= sd_outbyte;
            if (sd_off == 8'd3) magic[31:24] <= sd_outbyte;
            if (sd_off == 8'd4) prev_meta[7:0] <= sd_outbyte;
            if (sd_off == 8'd5) prev_meta[15:8] <= sd_outbyte;
            if (sd_off == 8'd6) prev_meta[23:16] <= sd_outbyte;
            if (sd_off == 8'd7) next_meta[7:0] <= sd_outbyte;
            if (sd_off == 8'd8) next_meta[15:8] <= sd_outbyte;
            if (sd_off == 8'd9) next_meta[23:16] <= sd_outbyte;
            if (sd_off == 8'd10) total[4:0] <= sd_outbyte[4:0];
            if (sd_off == 8'd11) begin
                background <= sd_outbyte[5:0];
                if (active + 1 > total)
                    active = total - 1;
            end
            if (sd_off == 8'd12) foreground <= sd_outbyte[5:0];
            if (sd_off >= 8'd16 && sd_off < 8'd176) begin
                if (sd_off[2:0] == 3'd0) x[sd_off[7:3] - 5'd2] <= sd_outbyte;
                if (sd_off[2:0] == 3'd1) y[sd_off[7:3] - 5'd2] <= sd_outbyte;
                if (sd_off[2:0] == 3'd2) rom_sector[sd_off[7:3] - 5'd2][7:0] <= sd_outbyte;
                if (sd_off[2:0] == 3'd3) rom_sector[sd_off[7:3] - 5'd2][15:8] <= sd_outbyte;
                if (sd_off[2:0] == 3'd4) rom_sector[sd_off[7:3] - 5'd2][23:16] <= sd_outbyte;
                if (sd_off[2:0] == 3'd5) rom_len[sd_off[7:3] - 5'd2][7:0] <= sd_outbyte;
                if (sd_off[2:0] == 3'd6) rom_len[sd_off[7:3] - 5'd2][15:8] <= sd_outbyte;
                if (sd_off[2:0] == 3'd7) rom_len[sd_off[7:3] - 5'd2][23:16] <= sd_outbyte;
            end
        end
        if (sd_rdone) begin
            if (magic != 32'h47_4E_41_54) begin        // "TANG" in reverse
                sd_rstart <= 0;
                state <= SD_FAIL;
            end else begin
                sd_rstart <= 1;
                sd_rsector[23:0] <= sd_rsector[23:0] + 23'd1;
                sd_off <= 0;
                overlay <= 1;           // takes over video display
                Y <= 0;
                X <= 0;
                state <= SD_READ_MENU;
            end
        end
    end
    SD_READ_MENU: begin
        if (sd_outen) begin
            color <= sd_outbyte;
            scanline <= Y;
            cycle <= X;
            X <= X + 8'd1;
            if (X == 8'd255)
                Y <= Y + 8'd1;
        end
        if (sd_rdone) begin
            if (Y < 240) begin
                sd_rstart <= 1;
                sd_rsector[23:0] <= sd_rsector[23:0] + 23'd1;
                sd_off <= 0;
            end else begin
                sd_rstart <= 0;
                cursor_now <= 0;
                cursor_dot <= 0;
                state <= SD_UI;
            end
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
            sd_rstart <= 1;
            sd_rsector <= rom_sector[active];
            sd_romlen <= rom_len[active];
            sd_last_sector <= rom_sector[active] + rom_len[active][23:9];
            sd_off <= 0;
            overlay <= 0;
            sd_loading <= 1;
            state <= SD_READ_ROM;
        end
    end
    SD_READ_ROM: begin
        if (sd_outen) begin
            // data handled by dout_valid, dout above
        end
        if (sd_rdone) begin
            if (is_last_sector) begin
                sd_loading <= 0;
                state <= SD_DONE;
            end else begin
                sd_rstart <= 1;
                sd_rsector[23:0] <= sd_rsector[23:0] + 1;
                sd_off <= 0;
                state <= SD_READ_ROM;
            end
        end
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