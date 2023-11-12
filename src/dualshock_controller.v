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
// 2023.11 nand2mario: stop using signal as clock for ps_rxd to improve stability
//                     remove fine-grained vibration control as we don't use it//                                                        
//-------------------------------------------------------------------
`timescale 100ps/10ps		

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
   parameter    FREQ = 27_000_000   // frequency of `clk`
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
   output reg [7:0] O_RXD_6,         //  RX DATA 6 (8bit) 

   input        I_CONF_SW,       //  Dualshook Config  ACTIVE-HI
   input        I_MODE_SW,       //  Dualshook Mode Set DIGITAL PAD 0, ANALOG PAD 1
   input        I_MODE_EN,       //  Dualshook Mode Control  OFF 0, ON 1
   input [1:0]  I_VIB_SW         //  Vibration SW  VIB_SW[0] Small Moter OFF 0, ON 1
                                 //                VIB_SW[1] Bic Moter   OFF 0, ON 1 (Dualshook Only)
);

reg I_CLK;  // nand2mario: Controller CLK at 125Khz 
            // some cheap controllers cannot handle the nominal 250Khz
localparam CLK_DELAY = FREQ / 125_000 / 2;
reg [$clog2(CLK_DELAY)-1:0] clk_cnt;

// Generate I_CLK
always @(posedge clk) begin
    clk_cnt <= clk_cnt + 1;
    if (clk_cnt == CLK_DELAY-1) begin
        I_CLK = ~I_CLK;
        clk_cnt <= 0;
    end
end

wire   W_scan_seq_pls;
wire   W_type;
wire   [3:0]W_byte_cnt;
wire   W_RXWT;
wire   W_TXWT;
wire   W_TXSET;
wire   W_TXEN;
wire   [7:0]W_TXD_DAT;
wire   [7:0]W_RXD_DAT;
wire   W_conf_ent;

ps_pls_gan pls(
   .I_CLK(I_CLK), .I_RSTn(I_RSTn), .I_TYPE(W_type),              // DEGITAL PAD 0: ANALOG PAD 1:
   .O_SCAN_SEQ_PLS(W_scan_seq_pls), .O_RXWT(W_RXWT), .O_TXWT(W_TXWT), .O_TXSET(W_TXSET),
   .O_TXEN(W_TXEN), .O_psCLK(O_psCLK), .O_psSEL(O_psSEL), .O_byte_cnt(W_byte_cnt),
   .Timer()
); 

txd_commnd_EZ cmd(
   .I_CLK(W_TXSET), .I_RSTn(I_RSTn),
   .I_BYTE_CNT(W_byte_cnt), .I_MODE(), .I_VIB_SW(I_VIB_SW), .I_VIB_DAT(),
   .I_RXD_DAT(), .O_TXD_DAT(W_TXD_DAT), .O_TYPE(W_type), .O_CONF_ENT(W_conf_ent)
);

ps_txd txd(
   .I_CLK(I_CLK), .I_RSTn(I_RSTn),
   .I_WT(W_TXWT), .I_EN(W_TXEN), .I_TXD_DAT(W_TXD_DAT), .O_psTXD(O_psTXD)
);

ps_rxd rxd(
   .clk(clk), .I_CLK(O_psCLK),.I_RSTn(I_RSTn),	
   .I_WT(W_RXWT), .I_psRXD(I_psRXD), .O_RXD_DAT(W_RXD_DAT)
);

//----------   RXD DATA DEC  ----------------------------------------

reg   W_rxd_mask;
always @(posedge W_scan_seq_pls) 
   W_rxd_mask <= ~W_conf_ent;

always @(negedge W_RXWT) begin
   if (W_rxd_mask) begin
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

module txd_commnd_EZ(
   input I_CLK,
   input I_RSTn,
   input [3:0] I_BYTE_CNT,
   input [2:0] I_MODE,
   input [1:0] I_VIB_SW,
   input [7:0] I_VIB_DAT,
   input [7:0] I_RXD_DAT,
   output reg [7:0] O_TXD_DAT,
   output O_TYPE,
   output O_CONF_ENT
);

assign O_TYPE = 1'b1;
assign O_CONF_ENT = 1'b0;
always @(posedge I_CLK or negedge I_RSTn) begin
   if (~I_RSTn) begin
      O_TXD_DAT <= 8'h00;
   end else begin
      case(I_BYTE_CNT)
         0:O_TXD_DAT <= 8'h01;
         1:O_TXD_DAT <= 8'h42;
         3:begin
              if(I_VIB_SW) O_TXD_DAT <= 8'h40;
              else         O_TXD_DAT <= 8'h00;
           end
         4:begin
              if(I_VIB_SW) O_TXD_DAT <= 8'h01;
              else         O_TXD_DAT <= 8'h00;
           end
       default: O_TXD_DAT <= 8'h00;
      endcase
   end
end

endmodule

module ps_pls_gan(
   input I_CLK,
   input I_RSTn,
   input I_TYPE,

   output reg O_SCAN_SEQ_PLS,
   output O_RXWT,
   output O_TXWT,
   output O_TXSET,
   output O_TXEN,
   output O_psCLK,
   output O_psSEL,
   output reg [3:0] O_byte_cnt,
   output reg [`Timer_siz-1:0] Timer
);

parameter Timer_size = `Timer_siz;

reg RXWT, TXWT, TXSET;
reg psCLK_gate, psSEL;

always @(posedge I_CLK or negedge I_RSTn) begin
   if (~I_RSTn) Timer <= 0;
   else         Timer <= Timer+1;
end

always @(posedge I_CLK or negedge I_RSTn) begin
   if (~I_RSTn) 
      O_SCAN_SEQ_PLS <= 0;
   else begin
      if (Timer == 0) O_SCAN_SEQ_PLS <= 1; 
	   else            O_SCAN_SEQ_PLS <= 0;            
   end
end

always @(posedge I_CLK or negedge I_RSTn)
begin
   if (~I_RSTn) begin
      psCLK_gate <= 1;
      RXWT     <= 0;
	   TXWT     <= 0;
	   TXSET    <= 0;
   end else begin
      case (Timer[4:0])
         6:  TXSET <= 1;
         8:  TXSET <= 0;
         9:  TXWT <= 1;
         11: TXWT <= 0;
         12: psCLK_gate <= 0;
         20: psCLK_gate <= 1;
         21: RXWT <= 1;
         23: RXWT <= 0;
      default:;
      endcase
   end
end

always @(posedge I_CLK or negedge I_RSTn) begin  
   if (~I_RSTn)
      psSEL <= 1;
   else begin	
      if (O_SCAN_SEQ_PLS == 1)
         psSEL <= 0;
      else if ((I_TYPE == 0)&&(Timer == 158))
         psSEL <= 1;
      else if ((I_TYPE == 1)&&(Timer == 286))
         psSEL <= 1;
   end
end

always @(posedge I_CLK or negedge I_RSTn) begin  
   if(! I_RSTn)
      O_byte_cnt <= 0;
   else begin
      if (O_SCAN_SEQ_PLS == 1)
         O_byte_cnt <= 0;
      else begin 
         if (Timer[4:0] == 5'b11111)begin
            if (I_TYPE == 0 && O_byte_cnt == 5)
               O_byte_cnt <= O_byte_cnt;
            else if (I_TYPE == 1 && O_byte_cnt == 9)
               O_byte_cnt <= O_byte_cnt;
            else
               O_byte_cnt <= O_byte_cnt+1;
         end    
      end
   end
end

assign O_psCLK = psCLK_gate | I_CLK | psSEL;
assign O_psSEL = psSEL;
assign O_RXWT  = ~psSEL & RXWT;
assign O_TXSET = ~psSEL & TXSET;
assign O_TXWT  = ~psSEL & TXWT;
assign O_TXEN  = ~psSEL & ~psCLK_gate;

endmodule

// receiver
module ps_rxd(
   input            clk,
   input            I_CLK,
   input            I_RSTn,	
   input            I_WT,
   input            I_psRXD,
   output reg [7:0] O_RXD_DAT
);

reg     [7:0]sp;
reg I_CLK_r;
reg I_WT_r;

always @(posedge clk or negedge I_RSTn)
   if (~I_RSTn) begin
      sp <= 1;
      O_RXD_DAT <= 1;
   end else begin
      I_CLK_r <= I_CLK;
      if (I_CLK & ~I_CLK_r)      // posedge I_CLK
         sp <= { I_psRXD, sp[7:1]};
      I_WT_r <= I_WT;
      if (I_WT & ~I_WT_r)        // posedge I_WT
         O_RXD_DAT <= sp;
   end

endmodule

// transmitter
module ps_txd (
   input       I_CLK,
   input       I_RSTn,
   input       I_WT,       // pulse to start transmission
   input       I_EN,
   input [7:0] I_TXD_DAT,  // byte to transmit, lowest bit first
   output  reg O_psTXD     // output pin
);

reg   [7:0] ps;            // data buffer

always@(negedge I_CLK or negedge I_RSTn)
begin
   if (~I_RSTn) begin 
      O_psTXD <= 1;
      ps      <= 0;
   end else begin
      if (I_WT)
         ps  <= I_TXD_DAT;
      else begin
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