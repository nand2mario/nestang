//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.9 (64-bit)
//Part Number: GW5A-LV25MG121NC1/I0
//Device: GW5A-25
//Device Version: A
//Created Time: Sun Mar 31 00:24:37 2024

module gowin_pll_nes (clkout0, clkout1, clkout2, clkin);

output clkout0;
output clkout1;
output clkout2;
input clkin;

wire lock;
wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;
wire clkfbout;
wire [7:0] mdrdo;
wire gw_gnd;

assign gw_gnd = 1'b0;

PLLA PLLA_inst (
    .LOCK(lock),
    .CLKOUT0(clkout0),
    .CLKOUT1(clkout1),
    .CLKOUT2(clkout2),
    .CLKOUT3(clkout3),
    .CLKOUT4(clkout4),
    .CLKOUT5(clkout5),
    .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout),
    .MDRDO(mdrdo),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .RESET(gw_gnd),
    .PLLPWD(gw_gnd),
    .RESET_I(gw_gnd),
    .RESET_O(gw_gnd),
    .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
    .PSDIR(gw_gnd),
    .PSPULSE(gw_gnd),
    .SSCPOL(gw_gnd),
    .SSCON(gw_gnd),
    .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .MDCLK(gw_gnd),
    .MDOPC({gw_gnd,gw_gnd}),
    .MDAINC(gw_gnd),
    .MDWDI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam PLLA_inst.FCLKIN = "50";
defparam PLLA_inst.IDIV_SEL = 2;
defparam PLLA_inst.FBDIV_SEL = 1;
defparam PLLA_inst.ODIV0_SEL = 57;
defparam PLLA_inst.ODIV1_SEL = 19;
defparam PLLA_inst.ODIV2_SEL = 19;
defparam PLLA_inst.ODIV3_SEL = 8;
defparam PLLA_inst.ODIV4_SEL = 8;
defparam PLLA_inst.ODIV5_SEL = 8;
defparam PLLA_inst.ODIV6_SEL = 8;
defparam PLLA_inst.MDIV_SEL = 49;
defparam PLLA_inst.MDIV_FRAC_SEL = 0;
defparam PLLA_inst.ODIV0_FRAC_SEL = 0;
defparam PLLA_inst.CLKOUT0_EN = "TRUE";
defparam PLLA_inst.CLKOUT1_EN = "TRUE";
defparam PLLA_inst.CLKOUT2_EN = "TRUE";
defparam PLLA_inst.CLKOUT3_EN = "FALSE";
defparam PLLA_inst.CLKOUT4_EN = "FALSE";
defparam PLLA_inst.CLKOUT5_EN = "FALSE";
defparam PLLA_inst.CLKOUT6_EN = "FALSE";
defparam PLLA_inst.CLKFB_SEL = "INTERNAL";
defparam PLLA_inst.CLKOUT0_DT_DIR = 1'b1;
defparam PLLA_inst.CLKOUT1_DT_DIR = 1'b1;
defparam PLLA_inst.CLKOUT2_DT_DIR = 1'b1;
defparam PLLA_inst.CLKOUT3_DT_DIR = 1'b1;
defparam PLLA_inst.CLKOUT0_DT_STEP = 0;
defparam PLLA_inst.CLKOUT1_DT_STEP = 0;
defparam PLLA_inst.CLKOUT2_DT_STEP = 0;
defparam PLLA_inst.CLKOUT3_DT_STEP = 0;
defparam PLLA_inst.CLK0_IN_SEL = 1'b0;
defparam PLLA_inst.CLK0_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK1_IN_SEL = 1'b0;
defparam PLLA_inst.CLK1_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK2_IN_SEL = 1'b0;
defparam PLLA_inst.CLK2_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK3_IN_SEL = 1'b0;
defparam PLLA_inst.CLK3_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK4_IN_SEL = 2'b00;
defparam PLLA_inst.CLK4_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK5_IN_SEL = 1'b0;
defparam PLLA_inst.CLK5_OUT_SEL = 1'b0;
defparam PLLA_inst.CLK6_IN_SEL = 1'b0;
defparam PLLA_inst.CLK6_OUT_SEL = 1'b0;
defparam PLLA_inst.DYN_DPA_EN = "FALSE";
defparam PLLA_inst.CLKOUT0_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT0_PE_FINE = 0;
defparam PLLA_inst.CLKOUT1_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT1_PE_FINE = 0;
defparam PLLA_inst.CLKOUT2_PE_COARSE = 11;
defparam PLLA_inst.CLKOUT2_PE_FINE = 7;
defparam PLLA_inst.CLKOUT3_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT3_PE_FINE = 0;
defparam PLLA_inst.CLKOUT4_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT4_PE_FINE = 0;
defparam PLLA_inst.CLKOUT5_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT5_PE_FINE = 0;
defparam PLLA_inst.CLKOUT6_PE_COARSE = 0;
defparam PLLA_inst.CLKOUT6_PE_FINE = 0;
defparam PLLA_inst.DYN_PE0_SEL = "FALSE";
defparam PLLA_inst.DYN_PE1_SEL = "FALSE";
defparam PLLA_inst.DYN_PE2_SEL = "FALSE";
defparam PLLA_inst.DYN_PE3_SEL = "FALSE";
defparam PLLA_inst.DYN_PE4_SEL = "FALSE";
defparam PLLA_inst.DYN_PE5_SEL = "FALSE";
defparam PLLA_inst.DYN_PE6_SEL = "FALSE";
defparam PLLA_inst.DE0_EN = "FALSE";
defparam PLLA_inst.DE1_EN = "FALSE";
defparam PLLA_inst.DE2_EN = "FALSE";
defparam PLLA_inst.DE3_EN = "FALSE";
defparam PLLA_inst.DE4_EN = "FALSE";
defparam PLLA_inst.DE5_EN = "FALSE";
defparam PLLA_inst.DE6_EN = "FALSE";
defparam PLLA_inst.RESET_I_EN = "FALSE";
defparam PLLA_inst.RESET_O_EN = "FALSE";
defparam PLLA_inst.ICP_SEL = 6'bXXXXXX;
defparam PLLA_inst.LPF_RES = 3'bXXX;
defparam PLLA_inst.LPF_CAP = 2'b00;
defparam PLLA_inst.SSC_EN = "FALSE";

endmodule //gowin_pll_nes
