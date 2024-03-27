// ****
// T65(b) core. In an effort to merge and maintain bug fixes ....
//
// See list of changes in T65 top file (T65.vhd)...
//
// ****
// 65xx compatible microprocessor core
//
// FPGAARCADE SVN: $Id: T65_ALU.vhd 1234 2015-02-28 20:14:50Z wolfgang.scherr $
//
// Copyright (c) 2002...2015
//               Daniel Wallner (jesus <at> opencores <dot> org)
//               Mike Johnson   (mikej <at> fpgaarcade <dot> com)
//               Wolfgang Scherr (WoS <at> pin4 <dot> at>
//               Morten Leikvoll ()
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author(s), but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
// Limitations :
//   See in T65 top file (T65.vhd)...
// no timescale needed

module T65_ALU(
input wire [1:0] Mode,
input wire BCD_en,
input wire [3:0] Op,
input wire [7:0] BusA,
input wire [7:0] BusB,
input wire [7:0] P_In,
output reg [7:0] P_Out,
output reg [7:0] Q
);

// "00" => 6502, "01" => 65C02, "10" => 65816
// T_ALU_OP;



// AddSub variables (temporary signals)
reg ADC_Z;
reg ADC_C;
reg ADC_V;
reg ADC_N;
reg [7:0] ADC_Q;
reg SBC_Z;
reg SBC_C;
reg SBC_V;
reg SBC_N;
reg [7:0] SBC_Q;
reg [7:0] SBX_Q;
parameter ALU_OP_OR = 5'b00000;
parameter ALU_OP_AND = 5'b00001;
parameter ALU_OP_EOR = 5'b00010;
parameter ALU_OP_ADC = 5'b00011;
parameter ALU_OP_EQ1 = 5'b00100;  // EQ1 does not change N,Z flags, EQ2/3 does.
parameter ALU_OP_EQ2 = 5'b00101;  // Not sure yet whats the difference between EQ2&3. They seem to do the same ALU op
parameter ALU_OP_CMP = 5'b00110;
parameter ALU_OP_SBC = 5'b00111;
parameter ALU_OP_ASL = 5'b01000;
parameter ALU_OP_ROL = 5'b01001;
parameter ALU_OP_LSR = 5'b01010;
parameter ALU_OP_ROR = 5'b01011;
parameter ALU_OP_BIT = 5'b01100;  //    ALU_OP_EQ3,  --"1101"
parameter ALU_OP_DEC = 5'b01110;
parameter ALU_OP_INC = 5'b01111;
parameter ALU_OP_ARR = 5'b10000;
parameter ALU_OP_ANC = 5'b10001;
parameter ALU_OP_SAX = 5'b10010;
parameter ALU_OP_XAA = 5'b10011;

  always @(P_In, BusA, BusB, BCD_en) begin : P3
    reg [6:0] AL;
    reg [6:0] AH;
    reg C;

    AL = ({BusA[3:0],P_In[Flag_C]}) + ({BusB[3:0],1'b1});
    AH = ({BusA[7:4],AL[5]}) + ({BusB[7:4],1'b1});
    // pragma translate_off
    // if is_x(std_logic_vector(AL)) then AL := "0000000"; end if;
    // if is_x(std_logic_vector(AH)) then AH := "0000000"; end if;
    // pragma translate_on
    if(AL[4:1] == 0 && AH[4:1] == 0) begin
      ADC_Z <= 1'b1;
    end
    else begin
      ADC_Z <= 1'b0;
    end
    if(AL[5:1] > 9 && P_In[Flag_D] == 1'b1 && BCD_en == 1'b1) begin
      AL[6:1] = AL[6:1] + 6;
    end
    C = AL[6] | AL[5];
    AH = ({BusA[7:4],C}) + ({BusB[7:4],1'b1});
    ADC_N <= AH[4];
    ADC_V <= (AH[4] ^ BusA[7]) &  ~(BusA[7] ^ BusB[7]);
    // pragma translate_off
    // if is_x(std_logic_vector(AH)) then AH := "0000000"; end if;
    // pragma translate_on
    if(AH[5:1] > 9 && P_In[Flag_D] == 1'b1 && BCD_en == 1'b1) begin
      AH[6:1] = AH[6:1] + 6;
    end
    ADC_C <= AH[6] | AH[5];
    ADC_Q <= {AH[4:1],AL[4:1]};
  end

  always @(Op, P_In, BusA, BusB, BCD_en) begin : P2
    reg [6:0] AL;
    reg [5:0] AH;
    reg C;
    reg CT;

    CT = 1'b0;
    // "0001" These OpCodes used to have LSB set
    if((Op == ALU_OP_AND || Op == ALU_OP_ADC || Op == ALU_OP_EQ2 || Op == ALU_OP_SBC || Op == ALU_OP_ROL || Op == ALU_OP_ROR || Op == ALU_OP_INC)) begin
      CT = 1'b1;
    end
    C = P_In[Flag_C] |  ~CT;
    //was: or not Op(0);
    AL = ({BusA[3:0],C}) - ({BusB[3:0],1'b1});
    AH = ({BusA[7:4],1'b0}) - ({BusB[7:4],AL[5]});
    // pragma translate_off
    // if is_x(std_logic_vector(AL)) then AL := "0000000"; end if;
    // if is_x(std_logic_vector(AH)) then AH := "000000"; end if;
    // pragma translate_on
    if(AL[4:1] == 0 && AH[4:1] == 0) begin
      SBC_Z <= 1'b1;
    end
    else begin
      SBC_Z <= 1'b0;
    end
    SBC_C <=  ~AH[5];
    SBC_V <= (AH[4] ^ BusA[7]) & (BusA[7] ^ BusB[7]);
    SBC_N <= AH[4];
    SBX_Q <= {AH[4:1],AL[4:1]};
    if(P_In[Flag_D] == 1'b1 && BCD_en == 1'b1) begin
      if(AL[5] == 1'b1) begin
        AL[5:1] = AL[5:1] - 6;
      end
      AH = ({BusA[7:4],1'b0}) - ({BusB[7:4],AL[6]});
      if(AH[5] == 1'b1) begin
        AH[5:1] = AH[5:1] - 6;
      end
    end
    SBC_Q <= {AH[4:1],AL[4:1]};
  end

  always @(Op, P_In, BusA, BusB, ADC_Z, ADC_C, ADC_V, ADC_N, ADC_Q, SBC_Z, SBC_C, SBC_V, SBC_N, SBC_Q, SBX_Q, BCD_en) begin : P1
    reg [7:0] Q_t;
    reg [7:0] Q2_t;

    // ORA, AND, EOR, ADC, NOP, LD, CMP, SBC
    // ASL, ROL, LSR, ROR, BIT, LD, DEC, INC
    P_Out <= P_In;
    Q_t = BusA;
    Q2_t = BusA;
    case(Op)
    ALU_OP_OR : begin
      Q_t = BusA | BusB;
    end
    ALU_OP_AND : begin
      Q_t = BusA & BusB;
    end
    ALU_OP_EOR : begin
      Q_t = BusA ^ BusB;
    end
    ALU_OP_ADC : begin
      P_Out[Flag_V] <= ADC_V;
      P_Out[Flag_C] <= ADC_C;
      Q_t = ADC_Q;
    end
    ALU_OP_CMP : begin
      P_Out[Flag_C] <= SBC_C;
    end
    ALU_OP_SAX : begin
      P_Out[Flag_C] <= SBC_C;
      Q_t = SBX_Q;
      // undoc: subtract (A & X) - (immediate)
    end
    ALU_OP_SBC : begin
      P_Out[Flag_V] <= SBC_V;
      P_Out[Flag_C] <= SBC_C;
      Q_t = SBC_Q;
      // undoc: subtract  (A & X) - (immediate), then decimal correction
    end
    ALU_OP_ASL : begin
      Q_t = {BusA[6:0],1'b0};
      P_Out[Flag_C] <= BusA[7];
    end
    ALU_OP_ROL : begin
      Q_t = {BusA[6:0],P_In[Flag_C]};
      P_Out[Flag_C] <= BusA[7];
    end
    ALU_OP_LSR : begin
      Q_t = {1'b0,BusA[7:1]};
      P_Out[Flag_C] <= BusA[0];
    end
    ALU_OP_ROR : begin
      Q_t = {P_In[Flag_C],BusA[7:1]};
      P_Out[Flag_C] <= BusA[0];
    end
    ALU_OP_ARR : begin
      Q_t = {P_In[Flag_C],BusA[7:1] & BusB[7:1]};
      P_Out[Flag_V] <= Q_t[5] ^ Q_t[6];
      Q2_t = Q_t;
      if(P_In[Flag_D] == 1'b1 && BCD_en == 1'b1) begin
        if((BusA[3:0] & BusB[3:0]) > 4'b0100) begin
          Q2_t[3:0] = (Q_t[3:0]) + 4'h6;
        end
        if((BusA[7:4] & BusB[7:4]) > 4'b0100) begin
          Q2_t[7:4] = (Q_t[7:4]) + 4'h6;
          P_Out[Flag_C] <= 1'b1;
        end
        else begin
          P_Out[Flag_C] <= 1'b0;
        end
      end
      else begin
        P_Out[Flag_C] <= Q_t[6];
      end
    end
    ALU_OP_BIT : begin
      P_Out[Flag_V] <= BusB[6];
    end
    ALU_OP_DEC : begin
      Q_t = (BusA) - 1;
    end
    ALU_OP_INC : begin
      Q_t = (BusA) + 1;
    end
    default : begin
      //EQ1,EQ2,EQ3 passes BusA to Q_t and P_in to P_out
    end
    endcase
    case(Op)
    ALU_OP_ADC : begin
      P_Out[Flag_N] <= ADC_N;
      P_Out[Flag_Z] <= ADC_Z;
    end
    ALU_OP_CMP,ALU_OP_SBC,ALU_OP_SAX : begin
      P_Out[Flag_N] <= SBC_N;
      P_Out[Flag_Z] <= SBC_Z;
    end
    ALU_OP_EQ1 : begin
      //dont touch P
    end
    ALU_OP_BIT : begin
      P_Out[Flag_N] <= BusB[7];
      if((BusA & BusB) == 8'b00000000) begin
        P_Out[Flag_Z] <= 1'b1;
      end
      else begin
        P_Out[Flag_Z] <= 1'b0;
      end
    end
    ALU_OP_ANC : begin
      P_Out[Flag_N] <= Q_t[7];
      P_Out[Flag_C] <= Q_t[7];
      if(Q_t == 8'b00000000) begin
        P_Out[Flag_Z] <= 1'b1;
      end
      else begin
        P_Out[Flag_Z] <= 1'b0;
      end
    end
    default : begin
      P_Out[Flag_N] <= Q_t[7];
      if(Q_t == 8'b00000000) begin
        P_Out[Flag_Z] <= 1'b1;
      end
      else begin
        P_Out[Flag_Z] <= 1'b0;
      end
    end
    endcase
    if(Op == ALU_OP_ARR) begin
      // handled above in ARR code
      Q <= Q2_t;
    end
    else begin
      Q <= Q_t;
    end
  end


endmodule
