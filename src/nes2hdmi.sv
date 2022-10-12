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

    // osd
    input osd_enable,       // 1: OSD display is on
    input [11:0] osd_addr,  // byte address into osd buffer, {Y[6:0],X[4:0]}, total 4KB
    input [7:0] osd_din,    // data input
    input osd_we,           // write enable

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

    // video stuff
    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    logic [7:0] ONE_THIRD[0:768];     // lookup table for divide-by-3

    wire active;
    logic r_active;
    wire [7:0] x;                // cx: 256-1023 -> x : 0-255
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
   
    // BRAM port A read/write
	always_ff @(posedge clk) begin
		if (mem_portA_we) begin
			mem[mem_portA_addr] <= mem_portA_wdata;
		end
	end

    // BRAM port B read
    always_ff @(posedge clk_pixel) begin
        mem_portB_rdata <= mem[mem_portB_addr];
//        mem_portB_rdata <= mem_portB_addr[13:8];
    end

    initial begin
        $readmemb("nes_fb_testpattern_palette.txt", mem);
    end

    // OSD buffer, 32Kbits, 256*128 mono
    //
    localparam OSD_WIDTH=256;   // 32*8
    localparam OSD_HEIGHT=128;  // 16*8
    logic [7:0] osd [0:OSD_WIDTH*OSD_HEIGHT/8-1];       // each byte is 8-pixel on same scanline
    wire [11:0] osd_raddr;      // port B: hdmi read
    logic [7:0] osd_sr;         // shift register for current 8 pixels

    // OSD port A write
    always_ff @(posedge clk) begin
        if (osd_we) begin
            osd[osd_addr] <= osd_din;
        end
    end 
    // 
    // Data input
    //
    logic [8:0] r_scanline;
    logic [8:0] r_cycle;
    always @(posedge clk) begin
        r_scanline <= scanline;
        r_cycle <= cycle;
        mem_portA_we <= 1'b0;
        if ((r_scanline != scanline || r_cycle != cycle) && scanline < 9'd240 && ~cycle[8]) begin
            mem_portA_addr <= {scanline[7:0], cycle[7:0]};
            mem_portA_wdata <= color;
            mem_portA_we <= 1'b1;
        end
    end

    // audio stuff
    logic [10:0] audio_divider;
    logic clk_audio;

    localparam AUDIO_RATE=32000;

    always_ff@(posedge clk_pixel) 
    begin
        if (audio_divider != CLKFRQ * 1000 / AUDIO_RATE / 2 - 11'd1) 
            audio_divider++; //generated from clk_pixel 27.0000MHz/281=48042,70Hz ; 27.0000MHz/306=44117,64Hz
        else begin 
            clk_audio <= ~clk_audio; 
            audio_divider <= 0; 
        end
    end

    wire [15:0] audio_sample_word [1:0];
    assign audio_sample_word[0] = sample;
    assign audio_sample_word[1] = sample;

    assign active = cx >= 11'd256 && cx < 11'd1024;
    assign x = ONE_THIRD[cx - 256];
    assign y = ONE_THIRD[cy];
    assign mem_portB_addr = {y, x};
    // assign led = ~{2'b0, mem_portB_rdata}; 
    logic [23:0] NES_PALETTE [0:63];
    logic [23:0] rgb;

    // OSD
    localparam OX = 3;          // OSD scale
    localparam OSD_LEFT = 640 - 128*OX;
    localparam OSD_RIGHT = 640 + 128*OX;
    localparam OSD_TOP = 360 - 64*OX;
    localparam OSD_BOTTOM = 360 + 64*OX;
    wire osd_active = osd_enable && cx >= OSD_LEFT && cx < OSD_RIGHT && cy >= OSD_TOP && cy < OSD_BOTTOM;
    logic r_osd_active;
    wire [7:0] ox = ONE_THIRD[cx - OSD_LEFT];
    wire [6:0] oy = ONE_THIRD[cy - OSD_TOP];
    assign osd_raddr = {oy[6:0], ox[7:3]};
    reg [4:0] osd_cnt;  // 0 - 23, load new byte at 0, shifts at 3, 6, 9, 12, 15, 18, 21

    // calc rgb value to hdmi
    always_ff @(posedge clk_pixel) begin
        r_active <= active; r_osd_active <= osd_active;
        if (osd_active) begin    // load or shift left osd_sr, and put on screen next cycle
            osd_cnt <= osd_cnt == 5'd23 ? 0 : osd_cnt + 1;
            if (osd_cnt == 5'b0)
                osd_sr <= osd[osd_raddr];
            if (osd_cnt == 5'd3 || osd_cnt == 5'd6 || osd_cnt == 5'd9 || osd_cnt == 5'd12
                || osd_cnt == 5'd15 || osd_cnt == 5'd18 || osd_cnt == 5'd21)
                osd_sr <= {1'b0, osd_sr[7:1]};
        end

        if (r_osd_active)
            rgb <= osd_sr[0] ? 24'h808080 : 24'h260604;
        else if (r_active)
            rgb <= NES_PALETTE[mem_portB_rdata];
        else
            rgb <= 24'b0;

        if (cx == 0) begin      // reset osd_cnt at each new line
            osd_cnt <= 0;
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
