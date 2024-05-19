//-------------------------------------------------------------------
//                                                          
// PLAYSTATION CONTROLLER(DUALSHOCK TYPE) INTERFACE TOP          
//                                                          
// Version : 2.00                                           
//                                                          
// Copyright(c) 2003 - 2004 Katsumi Degawa , All rights reserved  
//                                                          
// Important !                                              
//                                                          
// This program is freeware for non-commercial use.         
// An author does no guarantee about this program.          
// You can use this under your own risk.                    
// 
// 2003.10.30          It is optimized . by K Degawa 
// 2023.12 nand2mario: rewrite without ripple clocks to improve stability
//                     remove fine-grained vibration control as we don't use it                                                   
//-------------------------------------------------------------------
`timescale 100ps/10ps		

// Protocol: https://store.curiousinventor.com/guides/PS2/
// - Full duplex (command and data at the same time)
// - On negedge of clock, the line start to change. 
//   On posedge, values are read. 
// - Command   0x01 0x42(cmd) 0x00   0x00        0x00
//   Data      0xFF 0x41      0x5A   0xFF(btns)  0xFF(btns)
//                    ^- mode + # of words

//--------- SIMULATION ---------------------------------------------- 
//`define	SIMULATION_1	
//
// Poll controller status every 2^Timer clock cycles
// 125Khz / 2^11 = 61Hz
//
// SONY PLAYSTATION® CONTROLLER INFORMATION
// https://gamesx.com/controldata/psxcont/psxcont.htm
//
// "The DS4 stock polling rate is 250Hz 3-4 ms compared to the SN30 which is 67-75Hz 13-18 ms"
// https://www.reddit.com/r/8bitdo/comments/u8z3ag/has_anyone_managed_to_get_their_controllers/
`ifdef SIMULATION_1
`define Timer_siz 18  
`else
`define Timer_siz 11
`endif

module dualshock_controller #(
   parameter    FREQ             // frequency of `clk`
) (
   input        clk,             // Any main clock faster than 1Mhz 
   input        I_RSTn,          //  MAIN RESET

   output       O_psCLK,         //  psCLK CLK OUT
   output       O_psSEL,         //  psSEL OUT       
   output       O_psTXD,         //  psTXD OUT
   input        I_psRXD,         //  psRXD IN

   output reg [7:0] O_RXD_1,         //  RX DATA 1 (8bit)
   output reg [7:0] O_RXD_2,         //  RX DATA 2 (8bit)
   output reg [7:0] O_RXD_3,         //  RX DATA 3 (8bit)
   output reg [7:0] O_RXD_4,         //  RX DATA 4 (8bit)
   output reg [7:0] O_RXD_5,         //  RX DATA 5 (8bit)
   output reg [7:0] O_RXD_6          //  RX DATA 6 (8bit) 
);

reg I_CLK;          // SPI clock at 125Khz 
                    // some cheap controllers cannot handle the nominal 250Khz
reg R_CE, F_CE;     // rising and falling edge pulses of I_CLK

localparam CLK_DELAY = FREQ / 125_000 / 2;
reg [$clog2(CLK_DELAY)-1:0] clk_cnt;

// Generate I_CLK, F_CE, R_CE
always @(posedge clk) begin
    clk_cnt <= clk_cnt + 1;
    R_CE <= 0;
    F_CE <= 0;
    if (clk_cnt == CLK_DELAY-1) begin
        I_CLK <= ~I_CLK;
        R_CE <= ~I_CLK;
        F_CE <= I_CLK;
        clk_cnt <= 0;
    end
end

wire   W_type = 1'b1;        // DIGITAL PAD 0, ANALOG PAD 1
wire   [3:0] W_byte_cnt;
wire   W_RXWT;
wire   W_TXWT;
wire   W_TXEN;
reg    [7:0]W_TXD_DAT;
wire   [7:0]W_RXD_DAT;

ps_pls_gan pls(
   .clk(clk), .R_CE(R_CE), .I_CLK(I_CLK), .I_RSTn(I_RSTn), .I_TYPE(W_type), 
   .O_RXWT(W_RXWT), .O_TXWT(W_TXWT), 
   .O_TXEN(W_TXEN), .O_psCLK(O_psCLK), 
   .O_psSEL(O_psSEL), .O_byte_cnt(W_byte_cnt), .Timer()
); 

ps_txd txd(
   .clk(clk), .F_CE(F_CE), .I_RSTn(I_RSTn),
   .I_WT(W_TXWT), .I_EN(W_TXEN), .I_TXD_DAT(W_TXD_DAT), .O_psTXD(O_psTXD)
);

ps_rxd rxd(
   .clk(clk), .R_CE(R_CE), .I_RSTn(I_RSTn),	
   .I_WT(W_RXWT), .I_psRXD(I_psRXD), .O_RXD_DAT(W_RXD_DAT)
);

// TX command generation
always @* begin
    case(W_byte_cnt)
     0:   W_TXD_DAT = 8'h01;
     1:   W_TXD_DAT = 8'h42;
     3:   W_TXD_DAT = 8'h00;       // or vibration command
     4:   W_TXD_DAT = 8'h00;       // or vibration command
    default: W_TXD_DAT = 8'h00;
    endcase
end

// RX data decoding

reg W_RXWT_r;

always @(posedge clk) begin
    W_RXWT_r <= W_RXWT;
    if (~W_RXWT && W_RXWT_r) begin  // record received value one cycle after RXWT
        case (W_byte_cnt)
         3: O_RXD_1 <= W_RXD_DAT;
         4: O_RXD_2 <= W_RXD_DAT;
         5: O_RXD_3 <= W_RXD_DAT;
         6: O_RXD_4 <= W_RXD_DAT;
         7: O_RXD_5 <= W_RXD_DAT;
         8: O_RXD_6 <= W_RXD_DAT;
         default:;
        endcase
    end
end

endmodule


// timing signal generation module
module ps_pls_gan(
    input clk,
    input R_CE,
    input I_CLK,
    input I_RSTn,
    input I_TYPE,

    output O_RXWT,              // pulse to input RX byte
    output O_TXWT,              // pulse to output TX byte
    output O_TXEN,
    output O_psCLK,             // SPI clock to send to controller
    output O_psSEL,             // 0: active 
    output reg [3:0] O_byte_cnt,// index for byte received
    output reg [`Timer_siz-1:0] Timer   // increment on rising edge of I_CLK
);

parameter Timer_size = `Timer_siz;

reg RXWT, TXWT;
reg psCLK_gate;                 // 0: send I_CLK on wire
reg psSEL;          

// increment timer on I_CLK rising edge
always @(posedge clk) begin
    if (~I_RSTn) 
        Timer <= 0;
    else if (R_CE) 
        Timer <= Timer+1;
end

always @(posedge clk) begin
    if (~I_RSTn) begin
        psCLK_gate <= 1;
        RXWT     <= 0;
        TXWT     <= 0;
    end else begin
        TXWT <= 0;
        RXWT <= 0;
        if (R_CE) begin
            case (Timer[4:0])
             9:  TXWT <= 1;         // pulse to set byte to send
             12: psCLK_gate <= 0;   // send 8 cycles of clock: 
             20: begin
                    psCLK_gate <= 1;   // 13,14,15,16,17,18,19,20
                    RXWT <= 1;         // pulse to get received byte
                end
            default:;
            endcase
        end
    end
end

always @(posedge clk) begin
    if (~I_RSTn)
        psSEL <= 1;
    else if (R_CE) begin	
        if (Timer == 0)
            psSEL <= 0;
        else if ((I_TYPE == 0)&&(Timer == 158)) // end of byte 4
            psSEL <= 1;
        else if ((I_TYPE == 1)&&(Timer == 286)) // end of byte 9
            psSEL <= 1;
    end
end

always @(posedge clk) begin             // update O_byte_cnt
    if (!I_RSTn)
        O_byte_cnt <= 0;
    else if (R_CE) begin
        if (Timer == 0)
            O_byte_cnt <= 0;
        else begin 
            if (Timer[4:0] == 31) begin         // received a byte
                if (I_TYPE == 0 && O_byte_cnt == 5)
                    O_byte_cnt <= O_byte_cnt;
                else if (I_TYPE == 1 && O_byte_cnt == 9)
                    O_byte_cnt <= O_byte_cnt;
                else
                    O_byte_cnt <= O_byte_cnt + 4'd1;
            end    
        end
    end
end

assign O_psCLK = psCLK_gate | I_CLK | psSEL;
assign O_psSEL = psSEL;
assign O_RXWT  = ~psSEL & RXWT;
assign O_TXWT  = ~psSEL & TXWT;
assign O_TXEN  = ~psSEL & ~psCLK_gate;

endmodule

// receiver
module ps_rxd(
   input            clk,
   input            R_CE,       // one bit is transmitted on rising edge
   input            I_RSTn,	
   input            I_WT,       // pulse to output byte to O_RXD_DAT
   input            I_psRXD,
   output reg [7:0] O_RXD_DAT
);

reg     [7:0]   sp;

always @(posedge clk)
    if (~I_RSTn) begin
        sp <= 1;
        O_RXD_DAT <= 1;
    end else begin
        if (R_CE)         // posedge I_CLK
            sp <= { I_psRXD, sp[7:1]};
        if (I_WT)     
            O_RXD_DAT <= sp;
    end

endmodule

// transmitter
module ps_txd (
   input       clk,
   input       F_CE,       // transmit on falling edge of I_CLK
   input       I_RSTn,
   input       I_WT,       // pulse to load data to transmit
   input       I_EN,       // 1 to do transmission
   input [7:0] I_TXD_DAT,  // byte to transmit, lowest bit first
   output  reg O_psTXD     // output pin
);

reg   [7:0] ps;            // data buffer

always @(posedge clk) begin
   if (~I_RSTn) begin 
      O_psTXD <= 1;
      ps      <= 0;
   end else begin
      if (I_WT)
         ps  <= I_TXD_DAT;
      if (F_CE) begin       // bit is sent on falling edge of I_CLK
         if (I_EN) begin
            O_psTXD <= ps[0];
            ps      <= {1'b1, ps[7:1]};
         end else begin
            O_psTXD <= 1'd1;
            ps  <= ps;
         end
      end 
   end 	
end

endmodule