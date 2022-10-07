//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.05
//Part Number: GW2A-LV18PG256C8/I7
//Device: GW2A-18C
//Created Time: Fri May 06 23:06:50 2022

module Gowin_rPLL_nes (clkout, clkoutp, clkoutd, clkoutd3, lock, reset, clkin);

output clkout;
output clkoutp;
output lock;
input reset;
input clkin;
output clkoutd;
output clkoutd3;

wire gw_gnd;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd),
    .CLKOUTD3(clkoutd3),
    .RESET(reset),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

// Clock targets:
// NES PPU clock:               nclk = 5.369 Mhz
// Main clock:                  clk  = 5.369 * 6 = 32.214 Mhz
// DDR3 controller clock:       pclk = clk * 3 = 96.642 Mhz
// DDR3 memory clock:           fclk = pclk * 4 = 386.568 Mhz

// fclk 387Mhz, 0.11% deviation
defparam rpll_inst.FBDIV_SEL = 42;
defparam rpll_inst.IDIV_SEL = 2;
defparam rpll_inst.ODIV_SEL = 2;

// DDR3_CK (clkoutp) is 90-degree phase shifted fclk
defparam rpll_inst.PSDA_SEL = "0100";

// pclk (clkoutd) is 1/4 of fclk
defparam rpll_inst.DYN_SDIV_SEL = 4;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";

// clkoutd3 is 1/3 of fclk (used later to get main clock)
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";

// Other parameters
defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.DYN_DA_EN = "false";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DEVICE = "GW2A-18C";

endmodule //Gowin_rPLL
