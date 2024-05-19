
// convert dualshock to snes controller
module controller_ds2 #(parameter FREQ=21_600_000) (
    input clk,

    output [11:0] snes_buttons,     // (R L X A RT LT DN UP START SELECT Y B)

    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs
);

wire [7:0] rx0, rx1;

// JOYDATA:  BYsS UDLR   AXlr 0000
// Up: 0400, Down: 0200, Left: 0100, Right: 0080

//  dualshock buttons:  0:(L D R U St R3 L3 Se)  1:(□ X O △ R1 L1 R2 L2)
//  12 SNES buttons:    (RB LB X A RIGHT LEFT DOWN UP START SELECT Y B)
//                      A=O, B=X, X=△, Y=□
assign snes_buttons = {~rx1[3] | ~rx1[1], ~rx1[2] | ~rx1[0],   // RB LB
                        ~rx1[4], ~rx1[5], ~rx0[5], ~rx0[7],     // X A RIGHT LEFT
                        ~rx0[6], ~rx0[4], ~rx0[3], ~rx0[0],     // DOWN, UP, ST, SE
                        ~rx1[7], ~rx1[6]};                      // Y B 

// Dualshock controller
dualshock_controller #(.FREQ(FREQ)) ds (
    .clk(clk), .I_RSTn(1'b1),
    .O_psCLK(ds_clk), .O_psSEL(ds_cs), .O_psTXD(ds_mosi),
    .I_psRXD(ds_miso),
    .O_RXD_1(rx0), .O_RXD_2(rx1), .O_RXD_3(),
    .O_RXD_4(), .O_RXD_5(), .O_RXD_6()
);

endmodule