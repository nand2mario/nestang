// ****
// T65(b) core. In an effort to merge and maintain bug fixes ....
//
// Ver 315 SzGy April 2020
//   Reduced the IRQ detection delay when RDY is not asserted (NMI?)
//   Undocumented opcodes behavior change during not RDY and page boundary crossing (VICE tests - cpu/sha, cpu/shs, cpu/shxy)
//
// Ver 313 WoS January 2015
//   Fixed issue that NMI has to be first if issued the same time as a BRK instruction is latched in
//   Now all Lorenz CPU tests on FPGAARCADE C64 core (sources used: SVN version 1021) are OK! :D :D :D
//   This is just a starting point to go for optimizations and detailed fixes (the Lorenz test can't find)
//
// Ver 312 WoS January 2015
//   Undoc opcode timing fixes for $B3 (LAX iy) and $BB (LAS ay)
//   Added comments in MCode section to find handling of individual opcodes more easily
//   All "basic" Lorenz instruction test (individual functional checks, CPUTIMING check) work now with 
//       actual FPGAARCADE C64 core (sources used: SVN version 1021).
//
// Ver 305, 306, 307, 308, 309, 310, 311 WoS January 2015
//   Undoc opcode fixes (now all Lorenz test on instruction functionality working, except timing issues on $B3 and $BB):
//     SAX opcode
//     SHA opcode
//     SHX opcode
//     SHY opcode
//     SHS opcode
//     LAS opcode
//     alternate SBC opcode
//     fixed NOP with immediate param (caused Lorenz trap test to fail)
//     IRQ and NMI timing fixes (in conjuction with branches)
//
// Ver 304 WoS December 2014
//   Undoc opcode fixes:
//     ARR opcode
//     ANE/XAA opcode
//   Corrected issue with NMI/IRQ prio (when asserted the same time)
//
// Ver 303 ost(ML) July 2014
//   (Sorry for some scratchpad comments that may make little sense)
//   Mods and some 6502 undocumented instructions.
//   Not correct opcodes acc. to Lorenz tests (incomplete list):
//     NOPN    (nop)
//     NOPZX   (nop + byte 172)
//     NOPAX   (nop + word da  ...  da:  byte 0)
//     ASOZ    (byte $07 + byte 172)
//
// Ver 303,302 WoS April 2014
//     Bugfixes for NMI from foft
//     Bugfix for BRK command (and its special flag)
//
// Ver 300,301 WoS January 2014
//     More merging
//     Bugfixes by ehenciak added, started tidyup *bust*
//
// MikeJ March 2005
//      Latest version from www.fpgaarcade.com (original www.opencores.org)
// ****
//
// 65xx compatible microprocessor core
//
// FPGAARCADE SVN: $Id: T65.vhd 1347 2015-05-27 20:07:34Z wolfgang.scherr $
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
// ----- IMPORTANT NOTES -----
//
// Limitations:
//   65C02 and 65C816 modes are incomplete (and definitely untested after all 6502 undoc fixes)
//      65C02 supported : inc, dec, phx, plx, phy, ply
//      65D02 missing : bra, ora, lda, cmp, sbc, tsb*2, trb*2, stz*2, bit*2, wai, stp, jmp, bbr*8, bbs*8
//   Some interface signals behave incorrect
//   NMI interrupt handling not nice, needs further rework (to cycle-based encoding).
//
// Usage:
//   The enable signal allows clock gating / throttling without using the ready signal.
//   Set it to constant '1' when using the Clk input as the CPU clock directly.
//
//   TAKE CARE you route the DO signal back to the DI signal while R_W_n='0',
//   otherwise some undocumented opcodes won't work correctly.
//   EXAMPLE:
//      CPU : entity work.T65
//          port map (
//              R_W_n   => cpu_rwn_s,
//              [....all other ports....]
//              DI      => cpu_din_s,
//              DO      => cpu_dout_s
//          );
//      cpu_din_s <= cpu_dout_s when cpu_rwn_s='0' else 
//                   [....other sources from peripherals and memories...]
//
// ----- IMPORTANT NOTES -----
//
// no timescale needed

module T65(
input wire [1:0] Mode,
input wire BCD_en,
input wire Res_n,
input wire Enable,
input wire Clk,
input wire Rdy,
input wire Abort_n,
input wire IRQ_n,
input wire NMI_n,
input wire SO_n,
output wire R_W_n,
output wire Sync,
output wire EF,
output wire MF,
output wire XF,
output wire ML_n,
output wire VP_n,
output wire VDA,
output wire VPA,
output reg [23:0] A,
input wire [7:0] DI,
output wire [7:0] DO,
output wire [63:0] Regs,
output wire [7:0] DEBUG_I,
output wire [7:0] DEBUG_A,
output wire [7:0] DEBUG_X,
output wire [7:0] DEBUG_Y,
output wire [7:0] DEBUG_S,
output wire [7:0] DEBUG_P,
output wire NMI_ack,
output wire Instrnew,
input wire [63:0] SaveStateBus_Din,
input wire [9:0] SaveStateBus_Adr,
input wire SaveStateBus_wren,
input wire SaveStateBus_rst,
input wire SaveStateBus_load,
output wire [63:0] SaveStateBus_Dout
);

// "00" => 6502, "01" => 65C02, "10" => 65C816
// '0' => 2A03/2A07, '1' => others
// 6502 registers (MSB) PC, SP, P, Y, X, A (LSB)
// DEBUG   : out T_t65_dbg;
// savestates              



// Registers
reg [15:0] ABC; reg [15:0] X; reg [15:0] Y;
reg [7:0] P = 8'h00; reg [7:0] AD = 8'h00; reg [7:0] DL = 8'h00;
wire [7:0] PwithB;  //ML:New way to push P with correct B state to stack
reg [7:0] BAH;
reg [8:0] BAL;
reg [7:0] PBR;
reg [7:0] DBR;
reg [15:0] PC;
reg [15:0] S;
reg EF_i;
reg MF_i;
reg XF_i;
reg [7:0] IR;
reg [2:0] MCycle;
reg [7:0] DO_r;
reg [1:0] Mode_r;
reg BCD_en_r;
reg [4:0] ALU_Op_r;  // T_ALU_Op;
reg [3:0] Write_Data_r;  // T_Write_Data;
reg [1:0] Set_Addr_To_r;  // T_Set_Addr_To;
wire [8:0] PCAdder;
reg RstCycle;
reg IRQCycle;
reg NMICycle;
reg SO_n_o;
reg IRQ_n_o;
reg NMI_n_o;
reg NMIAct;
wire Break;  // ALU signals
reg [7:0] BusA;
reg [7:0] BusA_r;
reg [7:0] BusB;
reg [7:0] BusB_r;
wire [7:0] ALU_Q;
wire [7:0] P_Out;  // Micro code outputs
wire [2:0] LCycle;
wire [4:0] ALU_Op;  // 18 T_ALU_Op;
wire [3:0] Set_BusA_To;  // 11 T_Set_BusA_To;
wire [2:0] Set_Addr_To;  // 4 T_Set_Addr_To;
wire [3:0] Write_Data;  // 13 T_Write_Data;
wire [1:0] Jump;
wire [1:0] BAAdd;
wire [1:0] BAQuirk;
wire BreakAtNA;
wire ADAdd;
wire AddY;
wire PCAdd;
wire Inc_S;
wire Dec_S;
wire LDA;
wire LDP;
wire LDX;
wire LDY;
wire LDS;
wire LDDI;
wire LDALU;
wire LDAD;
wire LDBAL;
wire LDBAH;
wire SaveP;
wire Write;
reg Res_n_i;
reg Res_n_d;
reg rdy_mod;  // RDY signal turned off during the instruction
wire really_rdy;
reg WRn_i;
reg NMI_entered;  // savestates
wire [63:0] reg_wired_or_0;
wire [63:0] reg_wired_or_1;
wire [63:0] reg_wired_or_2;
wire [63:0] SS_1;
wire [63:0] SS_1_BACK;
wire [63:0] SS_2;
wire [63:0] SS_2_BACK;
wire [63:0] SS_3;
wire [63:0] SS_3_BACK;
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

  // XXX
  // iREG_SAVESTATE_T80_1 : entity work.eReg_SavestateV generic map (0, x"E064000000000000") port map (Clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, reg_wired_or_0, SS_1_BACK, SS_1);  
  // iREG_SAVESTATE_T80_2 : entity work.eReg_SavestateV generic map (1, x"0000012000000001") port map (Clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, reg_wired_or_1, SS_2_BACK, SS_2);  
  // iREG_SAVESTATE_T80_3 : entity work.eReg_SavestateV generic map (2, x"0000000000000000") port map (Clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, reg_wired_or_2, SS_3_BACK, SS_3);  
  assign SaveStateBus_Dout = reg_wired_or_0 | reg_wired_or_1 | reg_wired_or_2;
  assign NMI_ack = NMIAct;
  // gate Rdy with read/write to make an "OK, it's really OK to stop the processor 
  assign really_rdy = Rdy |  ~(WRn_i);
  assign Sync = MCycle == 3'b000 ? 1'b1 : 1'b0;
  assign EF = EF_i;
  assign MF = MF_i;
  assign XF = XF_i;
  assign R_W_n = WRn_i;
  assign ML_n = IR[7:6] != 2'b10 && IR[2:1] == 2'b11 && MCycle[2:1] != 2'b00 ? 1'b0 : 1'b1;
  assign VP_n = IRQCycle == 1'b1 && (MCycle == 3'b101 || MCycle == 3'b110) ? 1'b0 : 1'b1;
  assign VDA = Set_Addr_To_r != Set_Addr_To_PBR ? 1'b1 : 1'b0;
  assign VPA = Jump[1] == 1'b0 ? 1'b1 : 1'b0;
  // debugging signals
  assign DEBUG.I = IR;
  assign DEBUG.A = ABC[7:0];
  assign DEBUG.X = X[7:0];
  assign DEBUG.Y = Y[7:0];
  assign DEBUG.S = S[7:0];
  assign DEBUG.P = P;
  assign Regs = {PC,S,P,Y[7:0],X[7:0],ABC[7:0]};
  T65_MCode mcode(
      //inputs
    .Mode(Mode_r),
    .BCD_en(BCD_en_r),
    .IR(IR),
    .MCycle(MCycle),
    .P(P),
    .Rdy_mod(rdy_mod),
    //outputs
    .LCycle(LCycle),
    .ALU_Op(ALU_Op),
    .Set_BusA_To(Set_BusA_To),
    .Set_Addr_To(Set_Addr_To),
    .Write_Data(Write_Data),
    .Jump(Jump),
    .BAAdd(BAAdd),
    .BAQuirk(BAQuirk),
    .BreakAtNA(BreakAtNA),
    .ADAdd(ADAdd),
    .AddY(AddY),
    .PCAdd(PCAdd),
    .Inc_S(Inc_S),
    .Dec_S(Dec_S),
    .LDA(LDA),
    .LDP(LDP),
    .LDX(LDX),
    .LDY(LDY),
    .LDS(LDS),
    .LDDI(LDDI),
    .LDALU(LDALU),
    .LDAD(LDAD),
    .LDBAL(LDBAL),
    .LDBAH(LDBAH),
    .SaveP(SaveP),
    .Write(Write));

  T65_ALU alu(
      .Mode(Mode_r),
    .BCD_en(BCD_en_r),
    .Op(ALU_Op_r),
    .BusA(BusA_r),
    .BusB(BusB),
    .P_In(P),
    .P_Out(P_Out),
    .Q(ALU_Q));

  // the 65xx design requires at least two clock cycles before
  // starting its reset sequence (according to datasheet)
  always @(posedge Res_n, posedge Clk) begin
    if(Res_n == 1'b0) begin
      Res_n_i <= 1'b0;
      Res_n_d <= 1'b0;
    end else begin
      Res_n_i <= Res_n_d;
      Res_n_d <= 1'b1;
    end
  end

  assign SS_1_BACK[15:0] = PC;
  assign SS_1_BACK[23:16] = IR;
  assign SS_1_BACK[31:24] = S[7:0];
  assign SS_1_BACK[39:32] = PBR;
  assign SS_1_BACK[47:40] = DBR;
  assign SS_1_BACK[49:48] = Mode_r;
  assign SS_1_BACK[50] = BCD_en_r;
  assign SS_1_BACK[54:51] = 0;
  // XXX std_logic_vector(to_unsigned(T_ALU_Op'POS(ALU_Op_r), 4));     
  assign SS_1_BACK[58:55] = 0;
  // XXX std_logic_vector(to_unsigned(T_Write_Data'POS(Write_Data_r), 4));  
  assign SS_1_BACK[60:59] = 0;
  // XXX std_logic_vector(to_unsigned(T_Set_Addr_To'POS(Set_Addr_To_r), 2));  
  assign SS_1_BACK[61] = WRn_i;
  assign SS_1_BACK[62] = EF_i;
  assign SS_1_BACK[63] = MF_i;
  assign SS_2_BACK[0] = XF_i;
  assign SS_2_BACK[1] = rdy_mod;
  always @(posedge Clk) begin
    if(Res_n_i == 1'b0) begin
      PC <= SS_1[15:0];
      // (others => '0');  -- Program Counter
      IR <= SS_1[23:16];
      // "00000000";
      S[15:8] <= {8{1'b0}};
      // Dummy
      S[7:0] <= SS_1[31:24];
      // (others => '0');       -- Dummy
      PBR <= SS_1[39:32];
      // (others => '0');
      DBR <= SS_1[47:40];
      // (others => '0');                                                    
      Mode_r <= SS_1[49:48];
      // (others => '0');
      BCD_en_r <= SS_1[50];
      // '1';
      ALU_Op_r <= 0;
      //XXX T_ALU_Op'VAL(to_integer(unsigned(SS_1(54 downto 51))));  -- ALU_OP_BIT; -- "1100"
      Write_Data_r <= 0;
      //XXX T_Write_Data'VAL(to_integer(unsigned(SS_1(58 downto 55))));  -- Write_Data_DL; -- "0000"
      Set_Addr_To_r <= 0;
      //XXX T_Set_Addr_To'VAL(to_integer(unsigned(SS_1(60 downto 59)))); -- Set_Addr_To_PBR; -- "00"
      WRn_i <= SS_1[61];
      // '1';
      EF_i <= SS_1[62];
      // '1';
      MF_i <= SS_1[63];
      // '1';
      XF_i <= SS_2[0];
      // '1';
    end
    else if((SaveStateBus_load == 1'b1)) begin
      rdy_mod <= SS_2[1];
    end
    else if((Enable == 1'b1)) begin
      // some instructions behavior changed by the Rdy line. Detect this at the correct cycles.
      if(MCycle == 3'b000) begin
        rdy_mod <= 1'b0;
      end
      else if(((MCycle == 3'b011 && IR != 8'h93) || (MCycle == 3'b100 && IR == 8'h93)) && Rdy == 1'b0) begin
        rdy_mod <= 1'b1;
      end
      if((really_rdy == 1'b1)) begin
        WRn_i <=  ~Write | RstCycle;
        PBR <= {8{1'b1}};
        // Dummy
        DBR <= {8{1'b1}};
        // Dummy
        EF_i <= 1'b0;
        // Dummy
        MF_i <= 1'b0;
        // Dummy
        XF_i <= 1'b0;
        // Dummy
        if(MCycle == 3'b000) begin
          Mode_r <= Mode;
          BCD_en_r <= BCD_en;
          if(IRQCycle == 1'b0 && NMICycle == 1'b0) begin
            PC <= PC + 1;
          end
          if(IRQCycle == 1'b1 || NMICycle == 1'b1) begin
            IR <= 8'b00000000;
          end
          else begin
            IR <= DI;
          end
          if(LDS == 1'b1) begin
            // LAS won't work properly if not limited to machine cycle 0
            S[7:0] <= ALU_Q;
          end
        end
        ALU_Op_r <= ALU_Op;
        Write_Data_r <= Write_Data;
        if(Break == 1'b1) begin
          Set_Addr_To_r <= Set_Addr_To_PBR;
        end
        else begin
          Set_Addr_To_r <= Set_Addr_To;
        end
        if(Inc_S == 1'b1) begin
          S <= S + 1;
        end
        if(Dec_S == 1'b1 && (RstCycle == 1'b0 || Mode == 2'b00)) begin
          // 6502 only?
          S <= S - 1;
        end
        if(IR == 8'b00000000 && MCycle == 3'b001 && IRQCycle == 1'b0 && NMICycle == 1'b0) begin
          PC <= PC + 1;
        end
        //
        // jump control logic
        //
        case(Jump)
        2'b01 : begin
          PC <= PC + 1;
        end
        2'b10 : begin
          PC <= {DI,DL};
        end
        2'b11 : begin
          if(PCAdder[8] == 1'b1) begin
            if(DL[7] == 1'b0) begin
              PC[15:8] <= PC[15:8] + 1;
            end
            else begin
              PC[15:8] <= PC[15:8] - 1;
            end
          end
          PC[7:0] <= PCAdder[7:0];
        end
        default : begin
        end
        endcase
      end
    end
  end

  assign PCAdder = PCAdd == 1'b1 ? (PC[7:0]) + ({DL[7],DL}) : {1'b0,PC[7:0]};
  assign SS_2_BACK[9:2] = P;
  assign SS_2_BACK[17:10] = ABC[7:0];
  assign SS_2_BACK[25:18] = X[7:0];
  assign SS_2_BACK[33:26] = Y[7:0];
  assign SS_2_BACK[34] = IRQ_n_o;
  assign SS_2_BACK[35] = NMI_n_o;
  assign SS_2_BACK[36] = SO_n_o;
  always @(posedge Clk) begin : P1
    reg [7:0] tmpP;
  //Lets try to handle loading P at mcycle=0 and set/clk flags at same cycle

    if(Res_n_i == 1'b0) begin
      P <= SS_2[9:2];
      // x"00"; -- ensure we have nothing set on reset      
    end
    else if((SaveStateBus_load == 1'b1)) begin
      ABC[7:0] <= SS_2[17:10];
      X[7:0] <= SS_2[25:18];
      Y[7:0] <= SS_2[33:26];
      IRQ_n_o <= SS_2[34];
      NMI_n_o <= SS_2[35];
      SO_n_o <= SS_2[36];
    end
    else if((Enable == 1'b1)) begin
      tmpP = P;
      if((really_rdy == 1'b1)) begin
        if(MCycle == 3'b000) begin
          if(LDA == 1'b1) begin
            ABC[7:0] <= ALU_Q;
          end
          if(LDX == 1'b1) begin
            X[7:0] <= ALU_Q;
          end
          if(LDY == 1'b1) begin
            Y[7:0] <= ALU_Q;
          end
          if((LDA | LDX | LDY) == 1'b1) begin
            tmpP = P_Out;
          end
        end
        if(SaveP == 1'b1) begin
          tmpP = P_Out;
        end
        if(LDP == 1'b1) begin
          tmpP = ALU_Q;
        end
        if(IR[4:0] == 5'b11000) begin
          case(IR[7:5])
          3'b000 : begin
            //0x18(clc)
            tmpP[Flag_C] = 1'b0;
          end
          3'b001 : begin
            //0x38(sec)
            tmpP[Flag_C] = 1'b1;
          end
          3'b010 : begin
            //0x58(cli)
            tmpP[Flag_I] = 1'b0;
          end
          3'b011 : begin
            //0x78(sei)
            tmpP[Flag_I] = 1'b1;
          end
          3'b101 : begin
            //0xb8(clv)
            tmpP[Flag_V] = 1'b0;
          end
          3'b110 : begin
            //0xd8(cld)
            tmpP[Flag_D] = 1'b0;
          end
          3'b111 : begin
            //0xf8(sed)
            tmpP[Flag_D] = 1'b1;
          end
          default : begin
          end
          endcase
        end
        tmpP[Flag_B] = 1'b1;
        if(IR == 8'b00000000 && MCycle == 3'b100 && RstCycle == 1'b0) begin
          //This should happen after P has been pushed to stack
          tmpP[Flag_I] = 1'b1;
        end
        if(RstCycle == 1'b1) begin
          tmpP[Flag_I] = 1'b1;
          tmpP[Flag_D] = 1'b0;
        end
        tmpP[Flag_1] = 1'b1;
        P <= tmpP;
        //new way
      end
      // detect irq even if not rdy
      if(IR[4:0] != 5'b10000 || Jump != 2'b01 || really_rdy == 1'b0) begin
        // delay interrupts during branches (checked with Lorenz test and real 6510), not best way yet, though - but works...
        IRQ_n_o <= IRQ_n;
      end
      // detect nmi even if not rdy
      if(IR[4:0] != 5'b10000 || Jump != 2'b01) begin
        // delay interrupts during branches (checked with Lorenz test and real 6510) not best way yet, though - but works...
        NMI_n_o <= NMI_n;
      end
    end
    // act immediately on SO pin change
    // The signal is sampled on the trailing edge of phi1 and must be externally synchronized (from datasheet)
    SO_n_o <= SO_n;
    if(SO_n_o == 1'b1 && SO_n == 1'b0) begin
      P[Flag_V] <= 1'b1;
    end
  end

  //-------------------------------------------------------------------------
  //
  // Buses
  //
  //-------------------------------------------------------------------------
  assign SS_3_BACK[7:0] = BusA_r;
  assign SS_3_BACK[15:8] = BusB;
  assign SS_3_BACK[23:16] = BusB_r;
  assign SS_3_BACK[31:24] = AD;
  assign SS_3_BACK[40:32] = BAL;
  assign SS_3_BACK[48:41] = BAH;
  assign SS_3_BACK[56:49] = DL;
  assign SS_3_BACK[57] = NMI_entered;
  assign SS_3_BACK[63:58] = {6{1'b0}};
  // free to use
  always @(posedge Clk) begin
    if(Res_n_i == 1'b0) begin
      BusA_r <= SS_3[7:0];
      // (others => '0');
      BusB <= SS_3[15:8];
      // (others => '0');
      BusB_r <= SS_3[23:16];
      // (others => '0');
      AD <= SS_3[31:24];
      // (others => '0');
      BAL <= SS_3[40:32];
      // (others => '0');
      BAH <= SS_3[48:41];
      // (others => '0');
      DL <= SS_3[56:49];
      // (others => '0');
    end
    else if((SaveStateBus_load == 1'b1)) begin
      NMI_entered <= SS_3[57];
    end
    else if((Enable == 1'b1)) begin
      if((really_rdy == 1'b1)) begin
        NMI_entered <= 1'b0;
        BusA_r <= BusA;
        BusB <= DI;
        // not really nice, but no better way found yet !
        if(Set_Addr_To_r == Set_Addr_To_PBR || Set_Addr_To_r == Set_Addr_To_ZPG) begin
          BusB_r <= (DI[7:0]) + 1;
          // required for SHA
        end
        case(BAAdd)
        2'b01 : begin
          // BA Inc
          AD <= (AD) + 1;
          BAL <= (BAL) + 1;
        end
        2'b10 : begin
          // BA Add
          BAL <= (BAL[7:0]) + (BusA);
        end
        2'b11 : begin
          // BA Adj
          if(BAL[8] == 1'b1) begin
            // Handle quirks with some undocumented opcodes crossing page boundary
            case(BAQuirk)
            2'b00 : begin
              BAH <= (BAH) + 1;
              // no quirk
            end
            2'b01 : begin
              BAH <= ((BAH) + 1) & DO_r;
            end
            2'b10 : begin
              BAH <= DO_r;
            end
            default : begin
            end
            endcase
          end
        end
        default : begin
        end
        endcase
        // modified to use Y register as well
        if(ADAdd == 1'b1) begin
          if((AddY == 1'b1)) begin
            AD <= (AD) + (Y[7:0]);
          end
          else begin
            AD <= (AD) + (X[7:0]);
          end
        end
        if(IR == 8'b00000000) begin
          BAL <= {9{1'b1}};
          BAH <= {8{1'b1}};
          if(RstCycle == 1'b1) begin
            BAL[2:0] <= 3'b100;
          end
          else if(NMICycle == 1'b1 || (NMIAct == 1'b1 && MCycle == 3'b100) || NMI_entered == 1'b1) begin
            BAL[2:0] <= 3'b010;
            if(MCycle == 3'b100) begin
              NMI_entered <= 1'b1;
            end
          end
          else begin
            BAL[2:0] <= 3'b110;
          end
          if(Set_addr_To_r == Set_Addr_To_BA) begin
            BAL[0] <= 1'b1;
          end
        end
        if(LDDI == 1'b1) begin
          DL <= DI;
        end
        if(LDALU == 1'b1) begin
          DL <= ALU_Q;
        end
        if(LDAD == 1'b1) begin
          AD <= DI;
        end
        if(LDBAL == 1'b1) begin
          BAL[7:0] <= DI;
        end
        if(LDBAH == 1'b1) begin
          BAH <= DI;
        end
      end
    end
  end

  assign Break = (BreakAtNA &  ~BAL[8]) | (PCAdd &  ~PCAdder[8]);
  always @(*) begin
    case(Set_BusA_To)
      Set_BusA_To_DI : BusA <= DI;
      Set_BusA_To_ABC : BusA <= ABC[7:0];
      Set_BusA_To_X : BusA <= X[7:0];
      Set_BusA_To_Y : BusA <= Y[7:0];
      Set_BusA_To_S : BusA <= S[7:0];
      Set_BusA_To_P : BusA <= P;
      Set_BusA_To_DA : BusA <= ABC[7:0] & DI;
      Set_BusA_To_DAO : BusA <= (ABC[7:0] | 8'hee) & DI;
  //ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
      Set_BusA_To_DAX : BusA <= (ABC[7:0] | 8'hee) & DI & X[7:0];
  //XAA, ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
      Set_BusA_To_AAX : BusA <= ABC[7:0] & X[7:0];
  //SAX, SHA
      Set_BusA_To_DONTCARE : BusA <= {8{1'bX}};
    endcase
  end

  //Can probably remove this
  always @(*) begin
    case(Set_Addr_To_r)
      Set_Addr_To_SP : A <= {16'b0000000000000001,S[7:0]};
      Set_Addr_To_ZPG : A <= {DBR,8'b00000000,AD};
      Set_Addr_To_BA : A <= {8'b00000000,BAH,BAL[7:0]};
      Set_Addr_To_PBR : A <= {PBR,PC[15:8],PCAdder[7:0]};
    endcase
  end

  // This is the P that gets pushed on stack with correct B flag. I'm not sure if NMI also clears B, but I guess it does.
  assign PwithB = (IRQCycle == 1'b1 || NMICycle == 1'b1) ? P & 8'hef : P;
  assign DO = DO_r;
  always @(*) begin
    case(Write_Data_r)
      Write_Data_DL : DO_r <= DL;
      Write_Data_ABC : DO_r <= ABC[7:0];
      Write_Data_X : DO_r <= X[7:0];
      Write_Data_Y : DO_r <= Y[7:0];
      Write_Data_S : DO_r <= S[7:0];
      Write_Data_P : DO_r <= PwithB;
      Write_Data_PCL : DO_r <= PC[7:0];
      Write_Data_PCH : DO_r <= PC[15:8];
      Write_Data_AX : DO_r <= ABC[7:0] & X[7:0];
      Write_Data_AXB : DO_r <= ABC[7:0] & X[7:0] & BusB_r[7:0];
  // no better way found yet...
      Write_Data_XB : DO_r <= X[7:0] & BusB_r[7:0];
  // no better way found yet...
      Write_Data_YB : DO_r <= Y[7:0] & BusB_r[7:0];
  // no better way found yet...
      Write_Data_DONTCARE : DO_r <= {8{1'bX}};
    endcase
  end

  //Can probably remove this
  //-----------------------------------------------------------------------
  //
  // Main state machine
  //
  //-----------------------------------------------------------------------
  assign SS_2_BACK[39:37] = MCycle;
  assign SS_2_BACK[40] = RstCycle;
  assign SS_2_BACK[41] = IRQCycle;
  assign SS_2_BACK[42] = NMICycle;
  assign SS_2_BACK[43] = NMIAct;
  assign SS_2_BACK[63:44] = {20{1'b0}};
  // free to use
  assign Instrnew = (MCycle == LCycle && Break == 1'b0) ? 1'b1 : 1'b0;
  always @(posedge Clk) begin
    if(Res_n_i == 1'b0) begin
      MCycle <= SS_2[39:37];
      // "001";
      RstCycle <= SS_2[40];
      // '1';
      IRQCycle <= SS_2[41];
      // '0';
      NMICycle <= SS_2[42];
      // '0';
      NMIAct <= SS_2[43];
      // '0';
    end
    else if((Enable == 1'b1)) begin
      if((really_rdy == 1'b1)) begin
        if(MCycle == LCycle || Break == 1'b1) begin
          MCycle <= 3'b000;
          RstCycle <= 1'b0;
          IRQCycle <= 1'b0;
          NMICycle <= 1'b0;
          if(NMIAct == 1'b1 && IR != 8'h00) begin
            // delay NMI further if we just executed a BRK
            NMICycle <= 1'b1;
            NMIAct <= 1'b0;
            // reset NMI edge detector if we start processing the NMI
          end
          else if(IRQ_n_o == 1'b0 && P[Flag_I] == 1'b0) begin
            IRQCycle <= 1'b1;
          end
        end
        else begin
          MCycle <= (MCycle) + 1;
        end
      end
      //detect NMI even if not rdy    
      if(NMI_n_o == 1'b1 && (NMI_n == 1'b0 && (IR[4:0] != 5'b10000 || Jump != 2'b01))) begin
        // branches have influence on NMI start (not best way yet, though - but works...)
        NMIAct <= 1'b1;
      end
      // we entered NMI during BRK instruction
      if(NMI_entered == 1'b1) begin
        NMIAct <= 1'b0;
      end
    end
  end


endmodule
