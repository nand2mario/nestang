//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.11.01 (64-bit)
//Part Number: GW5AST-LV138PG484AC1/I0
//Device: GW5AST-138
//Device Version: B
//Created Time: Thu Mar  6 21:19:04 2025

module gowin_pll_hdmi (clkout, clkin);

output clkout;
input clkin;

wire lock;
wire clkout1;
wire clkout2;
wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;
wire clkfbout;
wire gw_vcc;
wire gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

PLL PLL_inst (
    .LOCK(lock),
    .CLKOUT0(clkout),
    .CLKOUT1(clkout1),
    .CLKOUT2(clkout2),
    .CLKOUT3(clkout3),
    .CLKOUT4(clkout4),
    .CLKOUT5(clkout5),
    .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .RESET(gw_gnd),
    .PLLPWD(gw_gnd),
    .RESET_I(gw_gnd),
    .RESET_O(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .MDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .MDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL0({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL0_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL1({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL2({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL3({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL4({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL5({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL6({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT0({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT1({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT2({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT3({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ICPSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .LPFRES({gw_gnd,gw_gnd,gw_gnd}),
    .LPFCAP({gw_gnd,gw_gnd}),
    .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
    .PSDIR(gw_gnd),
    .PSPULSE(gw_gnd),
    .ENCLK0(gw_vcc),
    .ENCLK1(gw_vcc),
    .ENCLK2(gw_vcc),
    .ENCLK3(gw_vcc),
    .ENCLK4(gw_vcc),
    .ENCLK5(gw_vcc),
    .ENCLK6(gw_vcc),
    .SSCPOL(gw_gnd),
    .SSCON(gw_gnd),
    .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd})
);

defparam PLL_inst.FCLKIN = "27";
defparam PLL_inst.IDIV_SEL = 1;
defparam PLL_inst.FBDIV_SEL = 1;
defparam PLL_inst.ODIV0_SEL = 4;
defparam PLL_inst.ODIV1_SEL = 8;
defparam PLL_inst.ODIV2_SEL = 8;
defparam PLL_inst.ODIV3_SEL = 8;
defparam PLL_inst.ODIV4_SEL = 8;
defparam PLL_inst.ODIV5_SEL = 8;
defparam PLL_inst.ODIV6_SEL = 8;
defparam PLL_inst.MDIV_SEL = 55;
defparam PLL_inst.MDIV_FRAC_SEL = 0;
defparam PLL_inst.ODIV0_FRAC_SEL = 0;
defparam PLL_inst.CLKOUT0_EN = "TRUE";
defparam PLL_inst.CLKOUT1_EN = "FALSE";
defparam PLL_inst.CLKOUT2_EN = "FALSE";
defparam PLL_inst.CLKOUT3_EN = "FALSE";
defparam PLL_inst.CLKOUT4_EN = "FALSE";
defparam PLL_inst.CLKOUT5_EN = "FALSE";
defparam PLL_inst.CLKOUT6_EN = "FALSE";
defparam PLL_inst.CLKFB_SEL = "INTERNAL";
defparam PLL_inst.CLKOUT0_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT1_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT2_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT3_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT0_DT_STEP = 0;
defparam PLL_inst.CLKOUT1_DT_STEP = 0;
defparam PLL_inst.CLKOUT2_DT_STEP = 0;
defparam PLL_inst.CLKOUT3_DT_STEP = 0;
defparam PLL_inst.CLK0_IN_SEL = 1'b0;
defparam PLL_inst.CLK0_OUT_SEL = 1'b0;
defparam PLL_inst.CLK1_IN_SEL = 1'b0;
defparam PLL_inst.CLK1_OUT_SEL = 1'b0;
defparam PLL_inst.CLK2_IN_SEL = 1'b0;
defparam PLL_inst.CLK2_OUT_SEL = 1'b0;
defparam PLL_inst.CLK3_IN_SEL = 1'b0;
defparam PLL_inst.CLK3_OUT_SEL = 1'b0;
defparam PLL_inst.CLK4_IN_SEL = 2'b00;
defparam PLL_inst.CLK4_OUT_SEL = 1'b0;
defparam PLL_inst.CLK5_IN_SEL = 1'b0;
defparam PLL_inst.CLK5_OUT_SEL = 1'b0;
defparam PLL_inst.CLK6_IN_SEL = 1'b0;
defparam PLL_inst.CLK6_OUT_SEL = 1'b0;
defparam PLL_inst.DYN_DPA_EN = "FALSE";
defparam PLL_inst.CLKOUT0_PE_COARSE = 0;
defparam PLL_inst.CLKOUT0_PE_FINE = 0;
defparam PLL_inst.CLKOUT1_PE_COARSE = 0;
defparam PLL_inst.CLKOUT1_PE_FINE = 0;
defparam PLL_inst.CLKOUT2_PE_COARSE = 0;
defparam PLL_inst.CLKOUT2_PE_FINE = 0;
defparam PLL_inst.CLKOUT3_PE_COARSE = 0;
defparam PLL_inst.CLKOUT3_PE_FINE = 0;
defparam PLL_inst.CLKOUT4_PE_COARSE = 0;
defparam PLL_inst.CLKOUT4_PE_FINE = 0;
defparam PLL_inst.CLKOUT5_PE_COARSE = 0;
defparam PLL_inst.CLKOUT5_PE_FINE = 0;
defparam PLL_inst.CLKOUT6_PE_COARSE = 0;
defparam PLL_inst.CLKOUT6_PE_FINE = 0;
defparam PLL_inst.DYN_PE0_SEL = "FALSE";
defparam PLL_inst.DYN_PE1_SEL = "FALSE";
defparam PLL_inst.DYN_PE2_SEL = "FALSE";
defparam PLL_inst.DYN_PE3_SEL = "FALSE";
defparam PLL_inst.DYN_PE4_SEL = "FALSE";
defparam PLL_inst.DYN_PE5_SEL = "FALSE";
defparam PLL_inst.DYN_PE6_SEL = "FALSE";
defparam PLL_inst.DE0_EN = "FALSE";
defparam PLL_inst.DE1_EN = "FALSE";
defparam PLL_inst.DE2_EN = "FALSE";
defparam PLL_inst.DE3_EN = "FALSE";
defparam PLL_inst.DE4_EN = "FALSE";
defparam PLL_inst.DE5_EN = "FALSE";
defparam PLL_inst.DE6_EN = "FALSE";
defparam PLL_inst.RESET_I_EN = "FALSE";
defparam PLL_inst.RESET_O_EN = "FALSE";
defparam PLL_inst.ICP_SEL = 6'bXXXXXX;
defparam PLL_inst.LPF_RES = 3'bXXX;
defparam PLL_inst.LPF_CAP = 2'b00;
defparam PLL_inst.SSC_EN = "FALSE";
defparam PLL_inst.DYN_IDIV_SEL = "FALSE";
defparam PLL_inst.DYN_FBDIV_SEL = "FALSE";
defparam PLL_inst.DYN_MDIV_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV0_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV1_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV2_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV3_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV4_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV5_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV6_SEL = "FALSE";
defparam PLL_inst.DYN_DT0_SEL = "FALSE";
defparam PLL_inst.DYN_DT1_SEL = "FALSE";
defparam PLL_inst.DYN_DT2_SEL = "FALSE";
defparam PLL_inst.DYN_DT3_SEL = "FALSE";
defparam PLL_inst.DYN_ICP_SEL = "FALSE";
defparam PLL_inst.DYN_LPF_SEL = "FALSE";

endmodule //gowin_pll_hdmi
