// ****
// T65(b) core. In an effort to merge and maintain bug fixes ....
//
// See list of changes in T65 top file (T65.vhd)...
//
// ****
// 65xx compatible microprocessor core
//
// FPGAARCADE SVN: $Id: T65_MCode.vhd 1234 2015-02-28 20:14:50Z wolfgang.scherr $
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

module T65_MCode(
input wire [1:0] Mode,
input wire BCD_en,
input wire [7:0] IR,
input wire [2:0] MCycle,
input wire [7:0] P,
input wire Rdy_mod,
output wire [2:0] LCycle,
output reg [4:0] ALU_Op,
output reg [3:0] Set_BusA_To,
output reg [1:0] Set_Addr_To,
output reg [3:0] Write_Data,
output reg [1:0] Jump,
output reg [1:0] BAAdd,
output reg [1:0] BAQuirk,
output reg BreakAtNA,
output reg ADAdd,
output reg AddY,
output reg PCAdd,
output reg Inc_S,
output reg Dec_S,
output reg LDA,
output reg LDP,
output reg LDX,
output reg LDY,
output reg LDS,
output reg LDDI,
output reg LDALU,
output reg LDAD,
output reg LDBAL,
output reg LDBAH,
output reg SaveP,
output reg Write
);

// "00" => 6502, "01" => 65C02, "10" => 65816
// T_Lcycle;
// T_Lcycle;
// T_ALU_Op;
// T_Set_BusA_To; 11 -- DI,A,X,Y,S,P,DA,DAO,DAX,AAX
// T_Set_Addr_To; 4 -- PC Adder,S,AD,BA
// T_Write_Data;  13 -- DL,A,X,Y,S,P,PCL,PCH,AX,AXB,XB,YB
// PC,++,DIDL,Rel
// None,DB Inc,BA Add,BA Adj
// None,And,Copy



reg Branch;
reg ALUmore;

  always @(*) begin
    case(IR[7:5])
      3'b000 : Branch <=  ~P[Flag_N];
      3'b001 : Branch <= P[Flag_N];
      3'b010 : Branch <=  ~P[Flag_V];
      3'b011 : Branch <= P[Flag_V];
      3'b100 : Branch <=  ~P[Flag_C];
      3'b101 : Branch <= P[Flag_C];
      3'b110 : Branch <=  ~P[Flag_Z];
      default : Branch <= P[Flag_Z];
    endcase
  end

  always @(IR, MCycle, P, Branch, Mode, Rdy_mod, BCD_en) begin
    lCycle <= Cycle_1;
    Set_BusA_To <= Set_BusA_To_ABC;
    Set_Addr_To <= Set_Addr_To_PBR;
    Write_Data <= Write_Data_DL;
    Jump <= {2{1'b0}};
    BAAdd <= 2'b00;
    BAQuirk <= 2'b00;
    BreakAtNA <= 1'b0;
    ADAdd <= 1'b0;
    PCAdd <= 1'b0;
    Inc_S <= 1'b0;
    Dec_S <= 1'b0;
    LDA <= 1'b0;
    LDP <= 1'b0;
    LDX <= 1'b0;
    LDY <= 1'b0;
    LDS <= 1'b0;
    LDDI <= 1'b0;
    LDALU <= 1'b0;
    LDAD <= 1'b0;
    LDBAL <= 1'b0;
    LDBAH <= 1'b0;
    SaveP <= 1'b0;
    Write <= 1'b0;
    AddY <= 1'b0;
    ALUmore <= 1'b0;
    case(IR[7:5])
    3'b100 : begin
      // covers $8x,$9x
      case(IR[1:0])
      2'b00 : begin
        // IR: $80,$84,$88,$8C,$90,$94,$98,$9C
        Set_BusA_To <= Set_BusA_To_Y;
        if(IR[4:2] == 3'b111) begin
          //  SYA ($9C)
          if(Rdy_mod == 1'b0) begin
            Write_Data <= Write_Data_YB;
          end
          else begin
            Write_Data <= Write_Data_Y;
          end
        end
        else begin
          Write_Data <= Write_Data_Y;
        end
      end
      2'b10 : begin
        // IR: $82,$86,$8A,$8E,$92,$96,$9A,$9E
        Set_BusA_To <= Set_BusA_To_X;
        if(IR[4:2] == 3'b111) begin
          //  SXA ($9E)
          if(Rdy_mod == 1'b0) begin
            Write_Data <= Write_Data_XB;
          end
          else begin
            Write_Data <= Write_Data_X;
          end
        end
        else begin
          Write_Data <= Write_Data_X;
        end
      end
      2'b11 : begin
        // IR: $83,$87,$8B,$8F,$93,$97,$9B,$9F
        if(IR[4:2] == 3'b110) begin
          //  SHS ($9B)
          Set_BusA_To <= Set_BusA_To_AAX;
          LDS <= 1'b1;
        end
        else begin
          Set_BusA_To <= Set_BusA_To_ABC;
        end
        if(IR[4:2] == 3'b111 || IR[4:2] == 3'b110 || IR[4:2] == 3'b100) begin
          //  SHA ($9F, $93), SHS ($9B)
          if(Rdy_mod == 1'b0) begin
            Write_Data <= Write_Data_AXB;
          end
          else begin
            Write_Data <= Write_Data_AX;
          end
        end
        else begin
          Write_Data <= Write_Data_AX;
        end
      end
      default : begin
        // IR: $81,$85,$89,$8D,$91,$95,$99,$9D
        Write_Data <= Write_Data_ABC;
      end
      endcase
    end
    3'b101 : begin
      // covers $Ax,$Bx
      Set_BusA_To <= Set_BusA_To_DI;
      case(IR[1:0])
      2'b00 : begin
        // IR: $A0,$A4,$A8,$AC,$B0,$B4,$B8,$BC
        if(IR[4] != 1'b1 || IR[2] != 1'b0) begin
          //only for $A0,$A4,$A8,$AC or $B4,$BC
          LDY <= 1'b1;
        end
      end
      2'b01 : begin
        // IR: $A1,$A5,$A9,$AD,$B1,$B5,$B9,$BD
        LDA <= 1'b1;
      end
      2'b10 : begin
        // IR: $A2,$A6,$AA,$AE,$B2,$B6,$BA,$BE
        LDX <= 1'b1;
      end
      default : begin
        // IR: $A3,$A7,$AB,$AF,$B3,$B7,$BB,$BF (undoc)
        LDX <= 1'b1;
        LDA <= 1'b1;
        if(IR[4:2] == 3'b110) begin
          //  LAS (BB)
          Set_BusA_To <= Set_BusA_To_S;
          LDS <= 1'b1;
        end
      end
      endcase
    end
    3'b110 : begin
      // covers $Cx,$Dx
      case(IR[1:0])
      2'b00 : begin
        // IR: $C0,$C4,$C8,$CC,$D0,$D4,$D8,$DC
        if(IR[4] == 1'b0) begin
          //only for $Cx
          LDY <= 1'b1;
        end
        Set_BusA_To <= Set_BusA_To_Y;
      end
      default : begin
        // IR: $C1,$C5,$C9,$CD,$D1,$D5,$D9,$DD, $C2,$C6,$CA,$CE,$D2,$D6,$DA,$DE, $C3,$C7,$CB,$CF,$D3,$D7,$DB,$DF
        Set_BusA_To <= Set_BusA_To_ABC;
      end
      endcase
    end
    3'b111 : begin
      // covers $Ex,$Fx
      case(IR[1:0])
      2'b00 : begin
        // IR: $E0,$E4,$E8,$EC,$F0,$F4,$F8,$FC
        if(IR[4] == 1'b0) begin
          // only $Ex
          LDX <= 1'b1;
        end
        Set_BusA_To <= Set_BusA_To_X;
      end
      default : begin
        // IR: $E1,$E5,$E9,$ED,$F1,$F5,$F9,$FD, $E2,$E6,$EA,$EE,$F2,$F6,$FA,$FE, $E3,$E7,$EB,$EF,$F3,$F7,$FB,$FF
        Set_BusA_To <= Set_BusA_To_ABC;
      end
      endcase
    end
    default : begin
    end
    endcase
    if(IR[7:6] != 2'b10 && IR[1] == 1'b1 && (mode == 2'b00 || IR[0] == 1'b0)) begin
      //covers $0x-$7x, $Cx-$Fx x=2,3,6,7,A,B,E,F, for 6502 undocs
      if(IR == 8'heb) begin
        Set_BusA_To <= Set_BusA_To_ABC;
        // alternate SBC ($EB)
      end
      else begin
        Set_BusA_To <= Set_BusA_To_DI;
      end
    end
    case(IR[4:0])
        // IR: $00,$20,$40,$60,$80,$A0,$C0,$E0
    //     $08,$28,$48,$68,$88,$A8,$C8,$E8
    //     $0A,$2A,$4A,$6A,$8A,$AA,$CA,$EA
    //     $18,$38,$58,$78,$98,$B8,$D8,$F8
    //     $1A,$3A,$5A,$7A,$9A,$BA,$DA,$FA
    5'b00000,5'b01000,5'b01010,5'b11000,5'b11010 : begin
      // Implied
      case(IR)
      8'h00 : begin
        // BRK ($00)
        lCycle <= Cycle_6;
        case(MCycle)
        Cycle_1 : begin
          Set_Addr_To <= Set_Addr_To_SP;
          Write_Data <= Write_Data_PCH;
          Write <= 1'b1;
        end
        Cycle_2 : begin
          Dec_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
          Write_Data <= Write_Data_PCL;
          Write <= 1'b1;
        end
        Cycle_3 : begin
          Dec_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
          Write_Data <= Write_Data_P;
          Write <= 1'b1;
        end
        Cycle_4 : begin
          Dec_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_5 : begin
          LDDI <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_6 : begin
          Jump <= 2'b10;
        end
        default : begin
        end
        endcase
      end
      8'h20 : begin
        // JSR ($20)
        lCycle <= Cycle_5;
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
          LDDI <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_2 : begin
          Set_Addr_To <= Set_Addr_To_SP;
          Write_Data <= Write_Data_PCH;
          Write <= 1'b1;
        end
        Cycle_3 : begin
          Dec_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
          Write_Data <= Write_Data_PCL;
          Write <= 1'b1;
        end
        Cycle_4 : begin
          Dec_S <= 1'b1;
        end
        Cycle_5 : begin
          Jump <= 2'b10;
        end
        default : begin
        end
        endcase
      end
      8'h40 : begin
        // RTI ($40)
        lCycle <= Cycle_5;
        case(MCycle)
        Cycle_1 : begin
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_2 : begin
          Inc_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_3 : begin
          Inc_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
          Set_BusA_To <= Set_BusA_To_DI;
        end
        Cycle_4 : begin
          LDP <= 1'b1;
          Inc_S <= 1'b1;
          LDDI <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_5 : begin
          Jump <= 2'b10;
        end
        default : begin
        end
        endcase
      end
      8'h60 : begin
        // RTS ($60)
        lCycle <= Cycle_5;
        case(MCycle)
        Cycle_1 : begin
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_2 : begin
          Inc_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_3 : begin
          Inc_S <= 1'b1;
          LDDI <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
        end
        Cycle_4 : begin
          Jump <= 2'b10;
        end
        Cycle_5 : begin
          Jump <= 2'b01;
        end
        default : begin
        end
        endcase
      end
      8'h08,8'h48,8'h5a,8'hda : begin
        // PHP, PHA, PHY*, PHX*  ($08,$48,$5A,$DA)
        lCycle <= Cycle_2;
        if(Mode == 2'b00 && IR[1] == 1'b1) begin
          //2 cycle nop
          lCycle <= Cycle_1;
        end
        case(MCycle)
        Cycle_1 : begin
          if(mode != 2'b00 || IR[1] == 1'b0) begin
            //wrong on 6502
            Write <= 1'b1;
            case(IR[7:4])
            4'b0000 : begin
              Write_Data <= Write_Data_P;
            end
            4'b0100 : begin
              Write_Data <= Write_Data_ABC;
            end
            4'b0101 : begin
              if(Mode != 2'b00) begin
                Write_Data <= Write_Data_Y;
              end
              else begin
                Write <= 1'b0;
              end
            end
            4'b1101 : begin
              if(Mode != 2'b00) begin
                Write_Data <= Write_Data_X;
              end
              else begin
                Write <= 1'b0;
              end
            end
            default : begin
            end
            endcase
            Set_Addr_To <= Set_Addr_To_SP;
          end
        end
        Cycle_2 : begin
          Dec_S <= 1'b1;
        end
        default : begin
        end
        endcase
      end
      8'h28,8'h68,8'h7a,8'hfa : begin
        // PLP, PLA, PLY*, PLX* ($28,$68,$7A,$FA)
        lCycle <= Cycle_3;
        if(Mode == 2'b00 && IR[1] == 1'b1) begin
          //2 cycle nop
          lCycle <= Cycle_1;
        end
        case(IR[7:4])
        4'b0010 : begin
          //plp
          LDP <= 1'b1;
        end
        4'b0110 : begin
          //pla
          LDA <= 1'b1;
        end
        4'b0111 : begin
          //ply not for 6502
          if(Mode != 2'b00) begin
            LDY <= 1'b1;
          end
        end
        4'b1111 : begin
          //plx not for 6502
          if(Mode != 2'b00) begin
            LDX <= 1'b1;
          end
        end
        default : begin
        end
        endcase
        case(MCycle)
        Cycle_sync : begin
          if(Mode != 2'b00 || IR[1] == 1'b0) begin
            //wrong on 6502
            SaveP <= 1'b1;
          end
        end
        Cycle_1 : begin
          if(Mode != 2'b00 || IR[1] == 1'b0) begin
            //wrong on 6502
            Set_Addr_To <= Set_Addr_To_SP;
            LDP <= 1'b0;
          end
        end
        Cycle_2 : begin
          Inc_S <= 1'b1;
          Set_Addr_To <= Set_Addr_To_SP;
          LDP <= 1'b0;
        end
        Cycle_3 : begin
          Set_BusA_To <= Set_BusA_To_DI;
        end
        default : begin
        end
        endcase
      end
      8'ha0,8'hc0,8'he0 : begin
        // LDY, CPY, CPX ($A0,$C0,$E0)
        // Immediate
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
        end
        default : begin
        end
        endcase
      end
      8'h88 : begin
        // DEY ($88)
        LDY <= 1'b1;
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Set_BusA_To <= Set_BusA_To_Y;
        end
        default : begin
        end
        endcase
      end
      8'hca : begin
        // DEX ($CA)
        LDX <= 1'b1;
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Set_BusA_To <= Set_BusA_To_X;
        end
        default : begin
        end
        endcase
      end
      8'h1a,8'h3a : begin
        // INC*, DEC* ($1A,$3A)
        if(Mode != 2'b00) begin
          LDA <= 1'b1;
          // A
        end
        else begin
          lCycle <= Cycle_1;
          //undoc 2 cycle nop
        end
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Set_BusA_To <= Set_BusA_To_S;
        end
        default : begin
        end
        endcase
      end
      8'h0a,8'h2a,8'h4a,8'h6a : begin
        // ASL, ROL, LSR, ROR ($0A,$2A,$4A,$6A)
        LDA <= 1'b1;
        // A
        Set_BusA_To <= Set_BusA_To_ABC;
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
        end
        default : begin
        end
        endcase
      end
      8'h8a,8'h98 : begin
        // TYA, TXA ($8A,$98)
        LDA <= 1'b1;
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
        end
        default : begin
        end
        endcase
      end
      8'haa,8'ha8 : begin
        // TAX, TAY ($AA,$A8)
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Set_BusA_To <= Set_BusA_To_ABC;
        end
        default : begin
        end
        endcase
      end
      8'h9a : begin
        // TXS ($9A)
        LDS <= 1'b1;
        // will be set only in Cycle_sync
      end
      8'hba : begin
        // TSX ($BA)
        LDX <= 1'b1;
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Set_BusA_To <= Set_BusA_To_S;
        end
        default : begin
        end
        endcase
      end
      8'h80 : begin
        // undoc: NOP imm2 ($80)
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
        end
        default : begin
        end
        endcase
      end
      default : begin
        // others ($0A,$EA, $18,$38,$58,$78,$B8,$C8,$D8,$E8,$F8)
        case(MCycle)
        Cycle_sync : begin
        end
        default : begin
        end
        endcase
      end
      endcase
      // IR: $01,$21,$41,$61,$81,$A1,$C1,$E1
      //     $03,$23,$43,$63,$83,$A3,$C3,$E3
    end
    5'b00001,5'b00011 : begin
      // Zero Page Indexed Indirect (d,x)
      lCycle <= Cycle_5;
      if(IR[7:6] != 2'b10) begin
        // ($01,$21,$41,$61,$C1,$E1,$03,$23,$43,$63,$C3,$E3)
        LDA <= 1'b1;
        if(Mode == 2'b00 && IR[1] == 1'b1) begin
          lCycle <= Cycle_7;
        end
      end
      case(MCycle)
      Cycle_1 : begin
        Jump <= 2'b01;
        LDAD <= 1'b1;
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_2 : begin
        ADAdd <= 1'b1;
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_3 : begin
        BAAdd <= 2'b01;
        LDBAL <= 1'b1;
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_4 : begin
        LDBAH <= 1'b1;
        if(IR[7:5] == 3'b100) begin
          Write <= 1'b1;
        end
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_5 : begin
        if(Mode == 2'b00 && IR[1] == 1'b1 && IR[7:6] != 2'b10) begin
          Set_Addr_To <= Set_Addr_To_BA;
          Write <= 1'b1;
          LDDI <= 1'b1;
        end
      end
      Cycle_6 : begin
        Write <= 1'b1;
        LDALU <= 1'b1;
        SaveP <= 1'b1;
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_7 : begin
        ALUmore <= 1'b1;
        Set_BusA_To <= Set_BusA_To_ABC;
      end
      default : begin
      end
      endcase
      // IR: $09,$29,$49,$69,$89,$A9,$C9,$E9
    end
    5'b01001 : begin
      // Immediate
      if(IR[7:5] != 3'b100) begin
        // all except undoc. NOP imm2 (not $89)
        LDA <= 1'b1;
      end
      case(MCycle)
      Cycle_1 : begin
        Jump <= 2'b01;
      end
      default : begin
      end
      endcase
      // IR: $0B,$2B,$4B,$6B,$8B,$AB,$CB,$EB
    end
    5'b01011 : begin
      if(Mode == 2'b00) begin
        // Immediate undoc for 6500
        case(IR[7:5])
        3'b010,3'b011,3'b000,3'b001 : begin
          //ALR,ARR
          Set_BusA_To <= Set_BusA_To_DA;
          LDA <= 1'b1;
        end
        3'b100 : begin
          //XAA
          Set_BusA_To <= Set_BusA_To_DAX;
          LDA <= 1'b1;
        end
        3'b110 : begin
          //SAX (SBX)
          Set_BusA_To <= Set_BusA_To_AAX;
          LDX <= 1'b1;
        end
        3'b101 : begin
          //OAL
          if((BCD_en == 1'b1)) begin
            Set_BusA_To <= Set_BusA_To_DAO;
          end
          else begin
            Set_BusA_To <= Set_BusA_To_DI;
          end
          LDA <= 1'b1;
        end
        default : begin
          LDA <= 1'b1;
        end
        endcase
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
        end
        default : begin
        end
        endcase
      end
      // IR: $02,$22,$42,$62,$82,$A2,$C2,$E2
      //     $12,$32,$52,$72,$92,$B2,$D2,$F2
    end
    5'b00010,5'b10010 : begin
      // Immediate, SKB, KIL
      case(MCycle)
      Cycle_sync : begin
      end
      Cycle_1 : begin
        if(IR == 8'b10100010) begin
          // LDX ($A2)
          Jump <= 2'b01;
          LDX <= 1'b1;
          // Moved, Lorenz test showed X changing on SKB (NOPx)
        end
        else if(IR[7:4] == 4'b1000 || IR[7:4] == 4'b1100 || IR[7:4] == 4'b1110) begin
          // undoc: NOP imm2
          Jump <= 2'b01;
        end
        else begin
          // KIL !!!
        end
      end
      default : begin
      end
      endcase
      // IR: $04,$24,$44,$64,$84,$A4,$C4,$E4
    end
    5'b00100 : begin
      // Zero Page
      lCycle <= Cycle_2;
      case(MCycle)
      Cycle_sync : begin
        if(IR[7:5] == 3'b001) begin
          //24=BIT zpg
          SaveP <= 1'b1;
        end
      end
      Cycle_1 : begin
        Jump <= 2'b01;
        LDAD <= 1'b1;
        if(IR[7:5] == 3'b100) begin
          //84=sty zpg (the only write in this group)
          Write <= 1'b1;
        end
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_2 : begin
      end
      default : begin
      end
      endcase
      // IR: $05,$25,$45,$65,$85,$A5,$C5,$E5
      //     $06,$26,$46,$66,$86,$A6,$C6,$E6
      //     $07,$27,$47,$67,$87,$A7,$C7,$E7
    end
    5'b00101,5'b00110,5'b00111 : begin
      // Zero Page
      if(IR[7:6] != 2'b10 && IR[1] == 1'b1 && (mode == 2'b00 || IR[0] == 1'b0)) begin
        //covers 0x-7x,cx-fx x=2,3,6,7,a,b,e,f, for 6502 undocs
        // Read-Modify-Write
        lCycle <= Cycle_4;
        if(Mode == 2'b00 && IR[0] == 1'b1) begin
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
          LDAD <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_2 : begin
          LDDI <= 1'b1;
          if(Mode == 2'b00) begin
            //The old 6500 writes back what is just read, before changing. The 65c does another read
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_3 : begin
          LDALU <= 1'b1;
          SaveP <= 1'b1;
          Write <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_4 : begin
          if(Mode == 2'b00 && IR[0] == 1'b1) begin
            Set_BusA_To <= Set_BusA_To_ABC;
            ALUmore <= 1'b1;
            // For undoc DCP/DCM support
            LDDI <= 1'b1;
            // requires DIN to reflect DOUT!
          end
        end
        default : begin
        end
        endcase
      end
      else begin
        lCycle <= Cycle_2;
        if(IR[7:6] != 2'b10) begin
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
          LDAD <= 1'b1;
          if(IR[7:5] == 3'b100) begin
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_2 : begin
        end
        default : begin
        end
        endcase
      end
      // IR: $0C,$2C,$4C,$6C,$8C,$AC,$CC,$EC
    end
    5'b01100 : begin
      // Absolute
      if(IR[7:6] == 2'b01 && IR[4:0] == 5'b01100) begin
        // JMP ($4C,$6C)
        if(IR[5] == 1'b0) begin
          lCycle <= Cycle_2;
          case(MCycle)
          Cycle_1 : begin
            Jump <= 2'b01;
            LDDI <= 1'b1;
          end
          Cycle_2 : begin
            Jump <= 2'b10;
          end
          default : begin
          end
          endcase
        end
        else begin
          lCycle <= Cycle_4;
          case(MCycle)
          Cycle_1 : begin
            Jump <= 2'b01;
            LDDI <= 1'b1;
            LDBAL <= 1'b1;
          end
          Cycle_2 : begin
            LDBAH <= 1'b1;
            if(Mode != 2'b00) begin
              Jump <= 2'b10;
            end
            if(Mode == 2'b00) begin
              Set_Addr_To <= Set_Addr_To_BA;
            end
          end
          Cycle_3 : begin
            LDDI <= 1'b1;
            if(Mode == 2'b00) begin
              Set_Addr_To <= Set_Addr_To_BA;
              BAAdd <= 2'b01;
              // DB Inc
            end
            else begin
              Jump <= 2'b01;
            end
          end
          Cycle_4 : begin
            Jump <= 2'b10;
          end
          default : begin
          end
          endcase
        end
      end
      else begin
        lCycle <= Cycle_3;
        case(MCycle)
        Cycle_sync : begin
          if(IR[7:5] == 3'b001) begin
            //2c-BIT
            SaveP <= 1'b1;
          end
        end
        Cycle_1 : begin
          Jump <= 2'b01;
          LDBAL <= 1'b1;
        end
        Cycle_2 : begin
          Jump <= 2'b01;
          LDBAH <= 1'b1;
          if(IR[7:5] == 3'b100) begin
            //80, sty, the only write in this group
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_3 : begin
        end
        default : begin
        end
        endcase
      end
      // IR: $0D,$2D,$4D,$6D,$8D,$AD,$CD,$ED
      //     $0E,$2E,$4E,$6E,$8E,$AE,$CE,$EE
      //     $0F,$2F,$4F,$6F,$8F,$AF,$CF,$EF
    end
    5'b01101,5'b01110,5'b01111 : begin
      // Absolute
      if(IR[7:6] != 2'b10 && IR[1] == 1'b1 && (mode == 2'b00 || IR[0] == 1'b0)) begin
        // ($0E,$2E,$4E,$6E,$CE,$EE, $0F,$2F,$4F,$6F,$CF,$EF)
        // Read-Modify-Write
        lCycle <= Cycle_5;
        if(Mode == 2'b00 && IR[0] == 1'b1) begin
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
          LDBAL <= 1'b1;
        end
        Cycle_2 : begin
          Jump <= 2'b01;
          LDBAH <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_3 : begin
          LDDI <= 1'b1;
          if(Mode == 2'b00) begin
            //The old 6500 writes back what is just read, before changing. The 65c does another read
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_4 : begin
          Write <= 1'b1;
          LDALU <= 1'b1;
          SaveP <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_5 : begin
          if(Mode == 2'b00 && IR[0] == 1'b1) begin
            ALUmore <= 1'b1;
            // For undoc DCP/DCM support
            Set_BusA_To <= Set_BusA_To_ABC;
          end
        end
        default : begin
        end
        endcase
      end
      else begin
        lCycle <= Cycle_3;
        if(IR[7:6] != 2'b10) begin
          // all but $8D, $8E, $8F, $AD, $AE, $AF ($AD does set LDA in an earlier case statement)
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
          LDBAL <= 1'b1;
        end
        Cycle_2 : begin
          Jump <= 2'b01;
          LDBAH <= 1'b1;
          if(IR[7:5] == 3'b100) begin
            //8d
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_3 : begin
        end
        default : begin
        end
        endcase
      end
      // IR: $10,$30,$50,$70,$90,$B0,$D0,$F0
    end
    5'b10000 : begin
      // Relative
      // This circuit dictates when the last
      // microcycle occurs for the branch depending on
      // whether or not the branch is taken and if a page
      // is crossed...
      if((Branch == 1'b1)) begin
        lCycle <= Cycle_3;
        // We're done @ T3 if branching...upper
        // level logic will stop at T2 if no page cross
        // (See the Break signal)
      end
      else begin
        lCycle <= Cycle_1;
      end
      // This decodes the current microcycle and takes the
      // proper course of action...
      case(MCycle)
            // On the T1 microcycle, increment the program counter
      // and instruct the upper level logic to fetch the offset
      // from the Din bus and store it in the data latches. This
      // will be the last microcycle if the branch isn't taken.
      Cycle_1 : begin
        Jump <= 2'b01;
        // Increments the PC by one (PC will now be PC+2)
        // from microcycle T0.
        LDDI <= 1'b1;
        // Tells logic in top level (T65.vhd) to route
        // the Din bus to the memory data latch (DL)
        // so that the branch offset is fetched.
        // In microcycle T2, tell the logic in the top level to
        // add the offset.  If the most significant byte of the
        // program counter (i.e. the current "page") does not need
        // updating, we are done here...the Break signal at the
        // T65.vhd level takes care of that...
      end
      Cycle_2 : begin
        Jump <= 2'b11;
        // Tell the PC Jump logic to use relative mode.
        PCAdd <= 1'b1;
        // This tells the PC adder to update itself with
        // the current offset recently fetched from
        // memory.
        // The following is microcycle T3 :
        // The program counter should be completely updated
        // on this cycle after the page cross is detected.
        // We don't need to do anything here...
      end
      Cycle_3 : begin
      end
      default : begin
        // Do nothing.
      end
      endcase
      // IR: $11,$31,$51,$71,$91,$B1,$D1,$F1
      //     $13,$33,$53,$73,$93,$B3,$D3,$F3
    end
    5'b10001,5'b10011 : begin
      lCycle <= Cycle_5;
      if(IR[7:6] != 2'b10) begin
        // ($11,$31,$51,$71,$D1,$F1,$13,$33,$53,$73,$D3,$F3)
        LDA <= 1'b1;
        if(Mode == 2'b00 && IR[1] == 1'b1) begin
          lCycle <= Cycle_7;
        end
      end
      case(MCycle)
      Cycle_1 : begin
        Jump <= 2'b01;
        LDAD <= 1'b1;
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_2 : begin
        LDBAL <= 1'b1;
        BAAdd <= 2'b01;
        // DB Inc
        Set_Addr_To <= Set_Addr_To_ZPG;
      end
      Cycle_3 : begin
        Set_BusA_To <= Set_BusA_To_Y;
        BAAdd <= 2'b10;
        // BA Add
        LDBAH <= 1'b1;
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_4 : begin
        BAAdd <= 2'b11;
        // BA Adj
        if(IR[7:5] == 3'b100) begin
          Write <= 1'b1;
          if(IR[3:0] == 4'h3) begin
            BAQuirk <= 2'b10;
            // COPY
          end
        end
        else if(IR[1] == 1'b0 || IR == 8'hB3) begin
          // Dont do this on $x3, except undoc LAXiy $B3 (says real CPU and Lorenz tests)
          BreakAtNA <= 1'b1;
        end
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_5 : begin
        if(Mode == 2'b00 && IR[1] == 1'b1 && IR[7:6] != 2'b10) begin
          Set_Addr_To <= Set_Addr_To_BA;
          LDDI <= 1'b1;
          Write <= 1'b1;
        end
      end
      Cycle_6 : begin
        LDALU <= 1'b1;
        SaveP <= 1'b1;
        Write <= 1'b1;
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_7 : begin
        ALUmore <= 1'b1;
        Set_BusA_To <= Set_BusA_To_ABC;
      end
      default : begin
      end
      endcase
      // IR: $14,$34,$54,$74,$94,$B4,$D4,$F4
      //     $15,$35,$55,$75,$95,$B5,$D5,$F5
      //     $16,$36,$56,$76,$96,$B6,$D6,$F6
      //     $17,$37,$57,$77,$97,$B7,$D7,$F7
    end
    5'b10100,5'b10101,5'b10110,5'b10111 : begin
      // Zero Page, X
      if(IR[7:6] != 2'b10 && IR[1] == 1'b1 && (Mode == 2'b00 || IR[0] == 1'b0)) begin
        // ($16,$36,$56,$76,$D6,$F6, $17,$37,$57,$77,$D7,$F7)
        // Read-Modify-Write
        if(Mode == 2'b00 && IR[0] == 1'b1) begin
          LDA <= 1'b1;
        end
        lCycle <= Cycle_5;
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
          LDAD <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_2 : begin
          ADAdd <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_3 : begin
          LDDI <= 1'b1;
          if(Mode == 2'b00) begin
            // The old 6500 writes back what is just read, before changing. The 65c does another read
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_4 : begin
          LDALU <= 1'b1;
          SaveP <= 1'b1;
          Write <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
          if(Mode == 2'b00 && IR[0] == 1'b1) begin
            LDDI <= 1'b1;
          end
        end
        Cycle_5 : begin
          if(Mode == 2'b00 && IR[0] == 1'b1) begin
            ALUmore <= 1'b1;
            // For undoc DCP/DCM support
            Set_BusA_To <= Set_BusA_To_ABC;
          end
        end
        default : begin
        end
        endcase
      end
      else begin
        lCycle <= Cycle_3;
        if(IR[7:6] != 2'b10 && IR[0] == 1'b1) begin
          // dont LDA on undoc skip
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
          LDAD <= 1'b1;
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_2 : begin
          ADAdd <= 1'b1;
          // Added this check for Y reg. use, added undocs
          if((IR[3:1] == 3'b011)) begin
            // ($16,$36,$56,$76,$96,$B6,$D6,$F6,$17,$37,$57,$77,$97,$B7,$D7,$F7)
            AddY <= 1'b1;
          end
          if(IR[7:5] == 3'b100) begin
            // ($14,$34,$15,$35,$16,$36,$17,$37) the only write instruction
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_ZPG;
        end
        Cycle_3 : begin
        end
        default : begin
        end
        endcase
      end
      // IR: $19,$39,$59,$79,$99,$B9,$D9,$F9
      //     $1B,$3B,$5B,$7B,$9B,$BB,$DB,$FB
    end
    5'b11001,5'b11011 : begin
      // Absolute Y
      lCycle <= Cycle_4;
      if(IR[7:6] != 2'b10) begin
        LDA <= 1'b1;
        if(Mode == 2'b00 && IR[1] == 1'b1) begin
          lCycle <= Cycle_6;
        end
      end
      case(MCycle)
      Cycle_1 : begin
        Jump <= 2'b01;
        LDBAL <= 1'b1;
      end
      Cycle_2 : begin
        Jump <= 2'b01;
        Set_BusA_To <= Set_BusA_To_Y;
        BAAdd <= 2'b10;
        // BA Add
        LDBAH <= 1'b1;
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_3 : begin
        BAAdd <= 2'b11;
        // BA adj
        if(IR[7:5] == 3'b100) begin
          //99/9b
          Write <= 1'b1;
          if(IR[3:0] == 4'hB) begin
            BAQuirk <= 2'b01;
            // AND
          end
        end
        else if(IR[1] == 1'b0 || IR == 8'hBB) begin
          // Dont do this on $xB, except undoc $BB (says real CPU and Lorenz tests)
          BreakAtNA <= 1'b1;
        end
        Set_Addr_To <= Set_Addr_To_BA;
      end
      Cycle_4 : begin
        // just for undoc
        if(Mode == 2'b00 && IR[1] == 1'b1 && IR[7:6] != 2'b10) begin
          Set_Addr_To <= Set_Addr_To_BA;
          LDDI <= 1'b1;
          Write <= 1'b1;
        end
      end
      Cycle_5 : begin
        Write <= 1'b1;
        LDALU <= 1'b1;
        Set_Addr_To <= Set_Addr_To_BA;
        SaveP <= 1'b1;
      end
      Cycle_6 : begin
        ALUmore <= 1'b1;
        Set_BusA_To <= Set_BusA_To_ABC;
      end
      default : begin
      end
      endcase
      // IR: $1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC
      //     $1D,$3D,$5D,$7D,$9D,$BD,$DD,$FD
      //     $1E,$3E,$5E,$7E,$9E,$BE,$DE,$FE
      //     $1F,$3F,$5F,$7F,$9F,$BF,$DF,$FF
    end
    5'b11100,5'b11101,5'b11110,5'b11111 : begin
      // Absolute X
      if(IR[7:6] != 2'b10 && IR[1] == 1'b1 && (Mode == 2'b00 || IR[0] == 1'b0)) begin
        // ($1E,$3E,$5E,$7E,$DE,$FE, $1F,$3F,$5F,$7F,$DF,$FF)
        // Read-Modify-Write
        lCycle <= Cycle_6;
        if(Mode == 2'b00 && IR[0] == 1'b1) begin
          LDA <= 1'b1;
        end
        case(MCycle)
        Cycle_1 : begin
          Jump <= 2'b01;
          LDBAL <= 1'b1;
        end
        Cycle_2 : begin
          Jump <= 2'b01;
          Set_BusA_To <= Set_BusA_To_X;
          BAAdd <= 2'b10;
          // BA Add
          LDBAH <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_3 : begin
          BAAdd <= 2'b11;
          // BA adj
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_4 : begin
          LDDI <= 1'b1;
          if(Mode == 2'b00) begin
            //The old 6500 writes back what is just read, before changing. The 65c does another read
            Write <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_5 : begin
          LDALU <= 1'b1;
          SaveP <= 1'b1;
          Write <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_6 : begin
          if(Mode == 2'b00 && IR[0] == 1'b1) begin
            ALUmore <= 1'b1;
            Set_BusA_To <= Set_BusA_To_ABC;
          end
        end
        default : begin
        end
        endcase
      end
      else begin
        // ($1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC, $1D,$3D,$5D,$7D,$9D,$BD,$DD,$FD, $9E,$BE,$9F,$BF)
        lCycle <= Cycle_4;
        //Or 3 if not page crossing
        if(IR[7:6] != 2'b10) begin
          if(Mode != 2'b00 || IR[4] == 1'b0 || IR[1:0] != 2'b00) begin
            LDA <= 1'b1;
          end
        end
        case(MCycle)
        Cycle_sync : begin
        end
        Cycle_1 : begin
          Jump <= 2'b01;
          LDBAL <= 1'b1;
        end
        Cycle_2 : begin
          Jump <= 2'b01;
          // special case $BE which uses Y reg as index!!
          if((IR[7:6] == 2'b10 && IR[4:1] == 4'b1111)) begin
            Set_BusA_To <= Set_BusA_To_Y;
          end
          else begin
            Set_BusA_To <= Set_BusA_To_X;
          end
          BAAdd <= 2'b10;
          // BA Add
          LDBAH <= 1'b1;
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_3 : begin
          BAAdd <= 2'b11;
          // BA adj
          if(IR[7:5] == 3'b100) begin
            // ($9C,$9D,$9E,$9F)
            Write <= 1'b1;
            case(IR[1:0])
            2'b00,2'b10 : begin
              BAQuirk <= 2'b01;
              // AND
            end
            2'b11 : begin
              BAQuirk <= 2'b10;
              // COPY
            end
            default : begin
            end
            endcase
          end
          else begin
            BreakAtNA <= 1'b1;
          end
          Set_Addr_To <= Set_Addr_To_BA;
        end
        Cycle_4 : begin
        end
        default : begin
        end
        endcase
      end
    end
    default : begin
    end
    endcase
  end

  always @(IR, MCycle, Mode, ALUmore) begin
    // ORA, AND, EOR, ADC, NOP, LD, CMP, SBC
    // ASL, ROL, LSR, ROR, BIT, LD, DEC, INC
    case(IR[1:0])
    2'b00 : begin
      case(IR[4:2])
            // IR: $00,$20,$40,$60,$80,$A0,$C0,$E0
      //     $04,$24,$44,$64,$84,$A4,$C4,$E4
      //     $0C,$2C,$4C,$6C,$8C,$AC,$CC,$EC
      3'b000,3'b001,3'b011 : begin
        case(IR[7:5])
        3'b110,3'b111 : begin
          // CP ($C0,$C4,$CC,$E0,$E4,$EC)
          ALU_Op <= ALU_OP_CMP;
        end
        3'b101 : begin
          // LD ($A0,$A4,$AC)
          ALU_Op <= ALU_OP_EQ2;
        end
        3'b001 : begin
          // BIT ($20,$24,$2C - $20 is ignored, as its a jmp)
          ALU_Op <= ALU_OP_BIT;
        end
        default : begin
          // other, NOP/ST ($x0,$x4,$xC)
          ALU_Op <= ALU_OP_EQ1;
        end
        endcase
        // IR: $08,$28,$48,$68,$88,$A8,$C8,$E8
      end
      3'b010 : begin
        case(IR[7:5])
        3'b111,3'b110 : begin
          // IN ($C8,$E8)
          ALU_Op <= ALU_OP_INC;
        end
        3'b100 : begin
          // DEY ($88)
          ALU_Op <= ALU_OP_DEC;
        end
        default : begin
          // LD
          ALU_Op <= ALU_OP_EQ2;
        end
        endcase
        // IR: $18,$38,$58,$78,$98,$B8,$D8,$F8
      end
      3'b110 : begin
        case(IR[7:5])
        3'b100 : begin
          // TYA ($98)
          ALU_Op <= ALU_OP_EQ2;
        end
        default : begin
          ALU_Op <= ALU_OP_EQ1;
        end
        endcase
        // IR: $10,$30,$50,$70,$90,$B0,$D0,$F0
        //     $14,$34,$54,$74,$94,$B4,$D4,$F4
        //     $1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC
      end
      default : begin
        case(IR[7:5])
        3'b101 : begin
          // LD ($B0,$B4,$BC)
          ALU_Op <= ALU_OP_EQ2;
        end
        default : begin
          ALU_Op <= ALU_OP_EQ1;
        end
        endcase
      end
      endcase
    end
    2'b01 : begin
      // OR
      // case (to_integer(unsigned(IR(7 downto 5)))) is
      case(IR[7:5])
      3'b000 : begin
        // IR: $01,$05,$09,$0D,$11,$15,$19,$1D
        ALU_Op <= ALU_OP_OR;
      end
      3'b001 : begin
        // IR: $21,$25,$29,$2D,$31,$35,$39,$3D
        ALU_Op <= ALU_OP_AND;
      end
      3'b010 : begin
        // IR: $41,$45,$49,$4D,$51,$55,$59,$5D
        ALU_Op <= ALU_OP_EOR;
      end
      3'b011 : begin
        // IR: $61,$65,$69,$6D,$71,$75,$79,$7D
        ALU_Op <= ALU_OP_ADC;
      end
      3'b100 : begin
        // IR: $81,$85,$89,$8D,$91,$95,$99,$9D
        ALU_Op <= ALU_OP_EQ1;
        // STA
      end
      3'b101 : begin
        // IR: $A1,$A5,$A9,$AD,$B1,$B5,$B9,$BD
        ALU_Op <= ALU_OP_EQ2;
        // LDA
      end
      3'b110 : begin
        // IR: $C1,$C5,$C9,$CD,$D1,$D5,$D9,$DD
        ALU_Op <= ALU_OP_CMP;
      end
      default : begin
        // IR: $E1,$E5,$E9,$ED,$F1,$F5,$F9,$FD
        ALU_Op <= ALU_OP_SBC;
      end
      endcase
    end
    2'b10 : begin
      case(IR[7:5])
      3'b000 : begin
        // IR: $02,$06,$0A,$0E,$12,$16,$1A,$1E
        ALU_Op <= ALU_OP_ASL;
        if(IR[4:2] == 3'b110 && Mode != 2'b00) begin
          // 00011010,$1A -> INC acc, not on 6502
          ALU_Op <= ALU_OP_INC;
        end
      end
      3'b001 : begin
        // IR: $22,$26,$2A,$2E,$32,$36,$3A,$3E
        ALU_Op <= ALU_OP_ROL;
        if(IR[4:2] == 3'b110 && Mode != 2'b00) begin
          // 00111010,$3A -> DEC acc, not on 6502
          ALU_Op <= ALU_OP_DEC;
        end
      end
      3'b010 : begin
        // IR: $42,$46,$4A,$4E,$52,$56,$5A,$5E
        ALU_Op <= ALU_OP_LSR;
      end
      3'b011 : begin
        // IR: $62,$66,$6A,$6E,$72,$76,$7A,$7E
        ALU_Op <= ALU_OP_ROR;
      end
      3'b100 : begin
        // IR: $82,$86,$8A,$8E,$92,$96,$9A,$9E
        ALU_Op <= ALU_OP_BIT;
        if(IR[4:2] == 3'b010) begin
          // 10001010, $8A -> TXA
          ALU_Op <= ALU_OP_EQ2;
        end
        else begin
          // 100xxx10, $82,$86,$8E,$92,$96,$9A,$9E
          ALU_Op <= ALU_OP_EQ1;
        end
      end
      3'b101 : begin
        // IR: $A2,$A6,$AA,$AE,$B2,$B6,$BA,$BE
        ALU_Op <= ALU_OP_EQ2;
        // LDX
      end
      3'b110 : begin
        // IR: $C2,$C6,$CA,$CE,$D2,$D6,$DA,$DE
        ALU_Op <= ALU_OP_DEC;
      end
      default : begin
        // IR: $E2,$E6,$EA,$EE,$F2,$F6,$FA,$FE
        ALU_Op <= ALU_OP_INC;
      end
      endcase
    end
    default : begin
      // "11" undoc double alu ops
      case(IR[7:5])
            // IR: $A3,$A7,$AB,$AF,$B3,$B7,$BB,$BF
      3'b101 : begin
        if(IR == 8'hbb) begin
          //LAS
          ALU_Op <= ALU_OP_AND;
        end
        else begin
          ALU_Op <= ALU_OP_EQ2;
        end
        // IR: $03,$07,$0B,$0F,$13,$17,$1B,$1F
        //     $23,$27,$2B,$2F,$33,$37,$3B,$3F
        //     $43,$47,$4B,$4F,$53,$57,$5B,$5F
        //     $63,$67,$6B,$6F,$73,$77,$7B,$7F
        //     $83,$87,$8B,$8F,$93,$97,$9B,$9F
        //     $C3,$C7,$CB,$CF,$D3,$D7,$DB,$DF
        //     $E3,$E7,$EB,$EF,$F3,$F7,$FB,$FF
      end
      default : begin
        if(IR == 8'h6b) begin
          // ARR
          ALU_Op <= ALU_OP_ARR;
        end
        else if(IR == 8'h8b) begin
          // ARR
          ALU_Op <= ALU_OP_XAA;
          // we can't use the bit operation as we don't set all flags...
        end
        else if(IR == 8'h0b || IR == 8'h2b) begin
          // ANC
          ALU_Op <= ALU_OP_ANC;
        end
        else if(IR == 8'heb) begin
          // alternate SBC
          ALU_Op <= ALU_OP_SBC;
        end
        else if(ALUmore == 1'b1) begin
          case(IR[7:5])
          3'b000 : begin
            ALU_Op <= ALU_OP_OR;
          end
          3'b001 : begin
            ALU_Op <= ALU_OP_AND;
          end
          3'b010 : begin
            ALU_Op <= ALU_OP_EOR;
          end
          3'b011 : begin
            ALU_Op <= ALU_OP_ADC;
          end
          3'b100 : begin
            ALU_Op <= ALU_OP_EQ1;
            // STA
          end
          3'b101 : begin
            ALU_Op <= ALU_OP_EQ2;
            // LDA
          end
          3'b110 : begin
            ALU_Op <= ALU_OP_CMP;
          end
          default : begin
            ALU_Op <= ALU_OP_SBC;
          end
          endcase
        end
        else begin
          case(IR[7:5])
          3'b000 : begin
            ALU_Op <= ALU_OP_ASL;
          end
          3'b001 : begin
            ALU_Op <= ALU_OP_ROL;
          end
          3'b010 : begin
            ALU_Op <= ALU_OP_LSR;
          end
          3'b011 : begin
            ALU_Op <= ALU_OP_ROR;
          end
          3'b100 : begin
            ALU_Op <= ALU_OP_BIT;
          end
          3'b101 : begin
            ALU_Op <= ALU_OP_EQ2;
            // LDX
          end
          3'b110 : begin
            ALU_Op <= ALU_OP_DEC;
            if(IR[4:2] == 3'b010) begin
              // $6B
              ALU_Op <= ALU_OP_SAX;
              // special SAX (SBX) case
            end
          end
          default : begin
            ALU_Op <= ALU_OP_INC;
          end
          endcase
        end
      end
      endcase
    end
    endcase
  end


endmodule