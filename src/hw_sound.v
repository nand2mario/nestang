// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

// CLK is 24Mhz. MCLK is divided by two (12Mhz). 24Mhz divide by 16 produces SCLK.
// Divide by 48 produces LRCK.
// produce LRCK = 32kHz. We output 16-bit samples, but internally the DAC
// is in 24-bit mode. SCLK ratio is 48 * 32kHz.
module SoundDriver(input CLK, input [15:0] write_data, input write_left, input write_right,
                   output AUD_MCLK, output AUD_LRCK, output AUD_SCK, output AUD_SDIN);
  reg lrck;
  reg [15:0] leftbuf;
  reg [15:0] rightbuf;
  reg [16:0] currbuf;
  reg [3:0] sclk_div;
  reg [4:0] bitcnt_24;   // Counts 0-23
  wire [4:0] bitcnt_24_new = bitcnt_24 + 1;
  always @(posedge CLK) begin
    // Buffer one sample of each channel.
    if (write_left)  leftbuf <= write_data;
    if (write_right) rightbuf <= write_data;
    // Divide 24MHz by 16 to produce the SCLK frequency (48 * 32000) as well
    // as the 12MHz MCLK frequency.
    sclk_div <= sclk_div + 1;
    // Output new bits on the falling edge of MCLK so that values are
    // stable once MCLK rises.
    if (sclk_div == 4'b1111) begin
      // This runs at the SCLK frequency. Output next bit.
      currbuf <= {currbuf[15:0], 1'b0};
      bitcnt_24 <= bitcnt_24_new;
      if (bitcnt_24_new[4:3] == 2'b11) begin
        bitcnt_24[4:3] <= 2'b00; // 24 -> 0
        lrck <= !lrck;
        currbuf[15:0] <= lrck ? leftbuf : rightbuf;
      end
    end
  end
  assign AUD_MCLK = sclk_div[0];
  assign AUD_SCK = 1; // Internal emphasis turned off
  assign AUD_SDIN = currbuf[16];
  assign AUD_LRCK = lrck;
endmodule
