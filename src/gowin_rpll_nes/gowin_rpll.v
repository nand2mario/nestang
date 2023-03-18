//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.05
//Part Number: GW2A-LV18PG256C8/I7
//Device: GW2A-18C
//Created Time: Fri May 06 23:06:50 2022

module Gowin_rPLL_nes (clkout, clkoutp, lock, reset, clkin);

output clkout;
output clkoutp;
output lock;
input reset;
input clkin;

wire clkoutd_o;
wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
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

// Target main clock: 5.369 * 5 = 26.845 Mhz

// 27 -> 27 Mhz, 1% off
defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.IDIV_SEL = 0;
defparam rpll_inst.FBDIV_SEL = 0;
defparam rpll_inst.ODIV_SEL = 32;

// 27 -> 37.8 Mhz, 0.6% deviation
//defparam rpll_inst.FCLKIN = "27";
//defparam rpll_inst.IDIV_SEL = 4;
//defparam rpll_inst.FBDIV_SEL = 6;
//defparam rpll_inst.ODIV_SEL = 16;

// 62.5 -> 37.5
//defparam rpll_inst.FCLKIN = "62.5";
//defparam rpll_inst.IDIV_SEL = 4;
//defparam rpll_inst.FBDIV_SEL = 2;
//defparam rpll_inst.ODIV_SEL = 16;

// 27 -> 27 Mhz
//defparam rpll_inst.FCLKIN = "27";
//defparam rpll_inst.IDIV_SEL = 4;   // IDIV is [0 ~ 8]
//defparam rpll_inst.FBDIV_SEL = 4;
//defparam rpll_inst.ODIV_SEL = 32;

defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.PSDA_SEL = "1000";
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
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule //Gowin_rPLL
