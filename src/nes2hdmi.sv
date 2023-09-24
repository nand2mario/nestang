// NES video and sound to HDMI converter
// nand2mario, 2022.9

`timescale 1ns / 1ps

import configPackage::*;

module nes2hdmi (
	input clk,      // nes clock
	input resetn,

    // nes video signals
    input [5:0] color,
    input [8:0] cycle,
    input [8:0] scanline,
    input [15:0] sample,
    input aspect_8x7,       // 1: 8x7 pixel aspect ratio mode

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,
	input locked,

    // output [7:0] led,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);
    // flags
    logic asp8x7_on = 1'b1;

    // video stuff
    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    logic [7:0] ONE_THIRD[0:768];     // lookup table for divide-by-3

    logic active;
    logic r_active;
    logic [7:0] x;                    // NES pixel position
    wire [7:0] y;

    //
    // BRAM frame buffer
    //
    localparam MEM_DEPTH=256*240;
    localparam MEM_ABITS=16;

    logic [5:0] mem [0:256*240-1];
    logic [15:0] mem_portA_addr;
    logic [5:0] mem_portA_wdata;
    logic mem_portA_we;

    wire [15:0] mem_portB_addr;
    logic [5:0] mem_portB_rdata;

    logic initializing = 1;
    logic [7:0] init_y = 0;
    logic [7:0] init_x = 0; 

    // BRAM port A read/write
	always_ff @(posedge clk) begin
		if (mem_portA_we) begin
			mem[mem_portA_addr] <= mem_portA_wdata;
		end
	end

    // BRAM port B read
    always_ff @(posedge clk_pixel) begin
        mem_portB_rdata <= mem[mem_portB_addr];
    end

    initial begin
        $readmemb("background.txt", mem);
    end

    localparam [0:65] LOGO [0:12] = '{
        'b11110000110011111111001111001111111110000000000000000000000000000,
        'b11110000110011111111011111101111111110000000000000000000000000000,
        'b11111000110011100000011100100001110000000000000000000000000000000,
        'b11111000110011100000011100000001110000011111000111111100001111110,
        'b11011100110011111110001110000001110000110011100111001110011100111,
        'b11001110110011111110000111000001110000000011100110001110011000111,
        'b11001111110011000000000011100001110000111111100110001110111000111,
        'b11000111110011000000110011100001110001111111100110001110111000111,
        'b11000011110011111110111111100001100001110011100110001110011001111,
        'b11000011110011111110011111000001100000111111100110001110001111111,
        'b00000000000000000000000000000000000000000000000000000000000000111,
        'b00000000000000000000000000000000000000000000000000000000011001110,
        'b00000000000000000000000000000000000000000000000000000000011111100
    };

    // 
    // Data input and initial background loading
    //
    logic [8:0] r_scanline;
    logic [8:0] r_cycle;
    always @(posedge clk) begin
        if (~resetn) begin
            initializing <= 1;
            init_y <= 0;
            init_x <= 0;
            mem_portA_we <= 0;
        end else if (initializing) begin    // setup background at initialization
            init_x <= init_x + 1;
            init_y <= init_x == 255 ? init_y + 1 : init_y;
            if (init_y == 240)
                initializing <= 0;
            mem_portA_we <= 1;
            mem_portA_addr <= {init_y, init_x};
            if (init_x >= 96 && init_x <= 160 && init_y >= 212 && init_y <= 224 && LOGO[init_y - 212][init_x - 96])
                mem_portA_wdata <= 4;       // blue logo
            else
                mem_portA_wdata <= 13;      // black
        end else begin
            r_scanline <= scanline;
            r_cycle <= cycle;
            mem_portA_we <= 1'b0;
            if ((r_scanline != scanline || r_cycle != cycle) && scanline < 9'd240 && ~cycle[8]) begin
                mem_portA_addr <= {scanline[7:0], cycle[7:0]};
                mem_portA_wdata <= color;
                mem_portA_we <= 1'b1;
            end
        end
    end

    // audio stuff
//    localparam AUDIO_RATE=32000;        // weird only 32K sampling rate works
//    localparam AUDIO_RATE=96000;
    localparam AUDIO_RATE=48000;
    localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
    logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
    logic clk_audio;

    always_ff@(posedge clk_pixel) 
    begin
        if (audio_divider != AUDIO_CLK_DELAY - 1) 
            audio_divider++;
        else begin 
            clk_audio <= ~clk_audio; 
            audio_divider <= 0; 
        end
    end

    reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
    always @(posedge clk_pixel) begin       // crossing clock domain
        audio_sample_word0[0] <= sample;
        audio_sample_word[0] <= audio_sample_word0[0];
        audio_sample_word0[1] <= sample;
        audio_sample_word[1] <= audio_sample_word0[1];
    end

    //
    // Video
    //
    // We support both 1:1 pixel aspect ratio, and 8:7
    // - 7 NES pixels are mapped to 21 or 24 HDMI pixels horizontally in these 2 modes.
    // - For 8:7, the follows are "border" HDMI pixels (0 to 23) that combine 2 neighboring NES pixels
    //      3:  110,146  6: 219,37   10: 73,183; 
    //      13: 183,73   17: 37,219  20: 146,110
    //   For 1:1, there's no border pixels. Each NES pixel is expanded to 3 HDMI pixels.
    // - For 8:7, total width is 36*24 + 13 = 877. Therefore x goes from 201 to 1077.
    reg r2_active;
    reg [4:0] xs, r_xs, r2_xs;       // x step for each 7 NES pixel group, 0-23 for 8:7 pixel aspect ratio, or 0-20 for 1:1 pixel aspect ratio
    wire xload = asp8x7_on ? 
          (xs == 5'd0 || xs == 5'd3 || xs == 5'd6 || xs == 5'd10 || xs == 5'd13 || xs == 5'd17 || xs == 5'd20)
        : (xs == 5'd0 || xs == 5'd3 || xs == 5'd6 || xs == 5'd9 || xs == 5'd12 || xs == 5'd15 || xs == 5'd18);
    reg r_xload;
    // x is incremented whenver xload is 1
    assign y = ONE_THIRD[cy];
    assign mem_portB_addr = {y, x};
    // assign led = ~{2'b0, mem_portB_rdata}; 
    reg [23:0] NES_PALETTE [0:63];
    // Mix ratio of border pixels for 8x7 pixel aspect ratio
    reg [15:0] mixratio;
    reg mix;
    wire [15:0] next_mixratio = ~asp8x7_on ? 16'b0 :            // no mixing for 1:1 pixel aspect ratio
                           r_xs == 5'd3 ? {8'd110,8'd146} :
                           r_xs == 5'd6 ? {8'd219,8'd37} :
                           r_xs == 5'd10 ? {8'd73,8'd183} :
                           r_xs == 5'd13 ? {8'd183,8'd73} :
                           r_xs == 5'd17 ? {8'd37,8'd219} :
                           r_xs == 5'd20 ? {8'd146,8'd110} : 16'b0;
    wire next_mix = r_xs == 5'd3 || r_xs == 5'd6 || r_xs == 5'd10 || r_xs == 5'd13 || r_xs == 5'd17 || r_xs == 5'd20;
    reg [23:0] rgbv, r_rgbv;
    wire [15:0] rmix = r_rgbv[23:16]*mixratio[15:8] + rgbv[23:16]*mixratio[7:0];
    wire [15:0] gmix = r_rgbv[15:8]*mixratio[15:8] + rgbv[15:8]*mixratio[7:0];
    wire [15:0] bmix = r_rgbv[7:0]*mixratio[15:8] + rgbv[7:0]*mixratio[7:0];
    reg [23:0] rgb;     // actual RGB output

    // calc rgb value to hdmi
    always_ff @(posedge clk_pixel) begin
        if (asp8x7_on && cx == 11'd198 || ~asp8x7_on && cx == 11'd253)
            active <= 1'b1;
        if (asp8x7_on && cx == 11'd1075 || ~asp8x7_on && cx == 11'd1021)
            active <= 1'b0;

        // calculate pixel rgb through 3 cycles
        // 0 - load: xmem_portB_rdata = mem[{y,x}]
        r_xload <= xload;
        r_active <= active; r2_active <= r_active;
        r_xs <= xs; r2_xs <= r_xs;
        if (active) begin
            if (asp8x7_on)
                xs <= xs == 5'd23 ? 0 : xs + 1;
            else
                xs <= xs == 5'd20 ? 0 : xs + 1;
        end

        // 1 - look up palette and load mixratio
        if (r_active && r_xload) begin
            x <= x + 1;
            rgbv <= NES_PALETTE[mem_portB_rdata];
            r_rgbv <= rgbv;
        end
        mixratio <= next_mixratio;
        mix <= next_mix;

        // 2 - mix rgb and output
        if (r2_active) begin
            if (asp8x7_on && mix)
                rgb <= {rmix[15:8], gmix[15:8], bmix[15:8]};
            else
                rgb <= rgbv;
        end else
            rgb <= 24'b0;

        if (cx == 0) begin
            x <= 0;
            xs <= 0; r_xs <= 0; r2_xs <= 0;
        end
    end

    // HDMI output.
    logic[2:0] tmds;

    hdmi #( .VIDEO_ID_CODE(VIDEOID), 
            .DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE), 
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel), 
          .clk_pixel(clk_pixel), 
          .clk_audio(clk_audio),
          .rgb(rgb), 
          .reset( ~resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds), 
          .tmds_clock(tmdsClk), 
          .cx(cx), 
          .cy(cy),
          .frame_width( frameWidth ),
          .frame_height( frameHeight ) );

    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

    // divide by three lookup table
    genvar i;
    generate
        for (i = 0; i < 768; i = i + 1) begin : gen_one_third
            assign ONE_THIRD[i] = i / 3;
        end
    endgenerate

    // 2C02 palette: https://www.nesdev.org/wiki/PPU_palettes
    assign NES_PALETTE[0] = 24'h545454;  assign NES_PALETTE[1] = 24'h001e74;  assign NES_PALETTE[2] = 24'h081090;  assign NES_PALETTE[3] = 24'h300088;  
    assign NES_PALETTE[4] = 24'h440064;  assign NES_PALETTE[5] = 24'h5c0030;  assign NES_PALETTE[6] = 24'h540400;  assign NES_PALETTE[7] = 24'h3c1800;
    assign NES_PALETTE[8] = 24'h202a00;  assign NES_PALETTE[9] = 24'h083a00;  assign NES_PALETTE[10] = 24'h004000;  assign NES_PALETTE[11] = 24'h003c00;  
    assign NES_PALETTE[12] = 24'h00323c;  assign NES_PALETTE[13] = 24'h000000;  assign NES_PALETTE[14] = 24'h000000;  assign NES_PALETTE[15] = 24'h000000;
    assign NES_PALETTE[16] = 24'h989698;  assign NES_PALETTE[17] = 24'h084cc4;  assign NES_PALETTE[18] = 24'h3032ec;  assign NES_PALETTE[19] = 24'h5c1ee4;  
    assign NES_PALETTE[20] = 24'h8814b0;  assign NES_PALETTE[21] = 24'ha01464;  assign NES_PALETTE[22] = 24'h982220;  assign NES_PALETTE[23] = 24'h783c00;
    assign NES_PALETTE[24] = 24'h545a00;  assign NES_PALETTE[25] = 24'h287200;  assign NES_PALETTE[26] = 24'h087c00;  assign NES_PALETTE[27] = 24'h007628; 
    assign NES_PALETTE[28] = 24'h006678;  assign NES_PALETTE[29] = 24'h000000;  assign NES_PALETTE[30] = 24'h000000;  assign NES_PALETTE[31] = 24'h000000;
    assign NES_PALETTE[32] = 24'heceeec;  assign NES_PALETTE[33] = 24'h4c9aec;  assign NES_PALETTE[34] = 24'h787cec;  assign NES_PALETTE[35] = 24'hb062ec;  
    assign NES_PALETTE[36] = 24'he454ec;  assign NES_PALETTE[37] = 24'hec58b4;  assign NES_PALETTE[38] = 24'hec6a64;  assign NES_PALETTE[39] = 24'hd48820;
    assign NES_PALETTE[40] = 24'ha0aa00;  assign NES_PALETTE[41] = 24'h74c400;  assign NES_PALETTE[42] = 24'h4cd020;  assign NES_PALETTE[43] = 24'h38cc6c; 
    assign NES_PALETTE[44] = 24'h38b4cc;  assign NES_PALETTE[45] = 24'h3c3c3c;  assign NES_PALETTE[46] = 24'h000000;  assign NES_PALETTE[47] = 24'h000000;
    assign NES_PALETTE[48] = 24'heceeec;  assign NES_PALETTE[49] = 24'ha8ccec;  assign NES_PALETTE[50] = 24'hbcbcec;  assign NES_PALETTE[51] = 24'hd4b2ec;
    assign NES_PALETTE[52] = 24'hecaeec;  assign NES_PALETTE[53] = 24'hecaed4;  assign NES_PALETTE[54] = 24'hecb4b0;  assign NES_PALETTE[55] = 24'he4c490;
    assign NES_PALETTE[56] = 24'hccd278;  assign NES_PALETTE[57] = 24'hb4de78;  assign NES_PALETTE[58] = 24'ha8e290;  assign NES_PALETTE[59] = 24'h98e2b4;
    assign NES_PALETTE[60] = 24'ha0d6e4;  assign NES_PALETTE[61] = 24'ha0a2a0;  assign NES_PALETTE[62] = 24'h000000;  assign NES_PALETTE[63] = 24'h000000;

endmodule
