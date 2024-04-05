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

import t65::*;

module T65(
    input [1:0] Mode,   // "00" => 6502, "01" => 65C02, "10" => 65C816
    input BCD_en,       // '0' => 2A03/2A07, '1' => others

    input Res_n,
    input Enable,
    input Clk,
    input Rdy,
    input Abort_n,
    input IRQ_n,
    input NMI_n,
    input SO_n,
    output R_W_n,
    output Sync,
    output EF,
    output MF,
    output XF,
    output ML_n,
    output VP_n,
    output VDA,
    output VPA,
    output reg [23:0] A /* synthesis syn_keep=1 */,
    input [7:0] DI /* synthesis syn_keep=1 */,
    output [7:0] DO /* synthesis syn_keep=1 */,
    // 6502 registers (MSB) PC, SP, P, Y, X, A (LSB)
    output [63:0] Regs,
    // DEBUG
    T_t65_dbg DEBUG,
    output NMI_ack
);
  
// Registers
reg [15:0] ABC, X, Y;
reg [7:0] P = 0; 
reg [7:0] AD = 0; 
reg [7:0] DL = 0;
wire [7:0] PwithB;          //ML:New way to push P with correct B state to stack
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
T_ALU_OP ALU_Op_r;         
T_Write_Data Write_Data_r;     
T_Set_Addr_To Set_Addr_To_r;
wire [8:0] PCAdder;

reg RstCycle;
reg IRQCycle;
reg NMICycle;
reg IRQReq;
reg NMIReq;

reg SO_n_o;
reg IRQ_n_o;
reg NMI_n_o;
reg NMIAct;

wire Break;  

// ALU signals
reg [7:0] BusA;
reg [7:0] BusA_r;
reg [7:0] BusB;
reg [7:0] BusB_r;
wire [7:0] ALU_Q;
wire [7:0] P_Out;  

// Micro code outputs
wire [2:0] LCycle;
T_ALU_OP ALU_Op;  
T_Set_BusA_To Set_BusA_To;
T_Set_Addr_To Set_Addr_To;
T_Write_Data Write_Data;
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

reg NMI_entered;  

assign NMI_ack = NMIAct;

// gate Rdy with read/write to make an "OK, it's really OK to stop the processor 
assign really_rdy = Rdy |  ~(WRn_i);
assign Sync = MCycle == 3'b000 ? 1'b1 : 1'b0;
assign EF = EF_i;
assign MF = MF_i;
assign XF = XF_i;
assign R_W_n = WRn_i;
assign ML_n = IR[7:6] != 2'b10 && IR[2:1] == 2'b11 && MCycle[2:1] != 2'b00 ? 1'b0 : 1'b1;
assign VP_n = IRQCycle && (MCycle == 3'b101 || MCycle == 3'b110) ? 1'b0 : 1'b1;
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
    .Write(Write)
);

T65_ALU alu(
    .Mode(Mode_r),
    .BCD_en(BCD_en_r),
    .Op(ALU_Op_r),
    .BusA(BusA_r),
    .BusB(BusB),
    .P_In(P),
    .P_Out(P_Out),
    .Q(ALU_Q)
);

// the 65xx design requires at least two clock cycles before
// starting its reset sequence (according to datasheet)
always @(posedge Clk) begin
    if (~Res_n) begin
        Res_n_i <= 1'b0;
        Res_n_d <= 1'b0;
    end else begin
        Res_n_i <= Res_n_d;
        Res_n_d <= 1'b1;
    end
end

always @(posedge Clk) begin
    if (~Res_n_i) begin
        PC <= 0;        // Program Counter
        IR <= 0;
        S <= 0;         // Dummy
        PBR <= 0;
        DBR <= 0;

        Mode_r <= 0;
        BCD_en_r <= 1;
        ALU_Op_r <= ALU_OP_BIT;
        Write_Data_r <= Write_Data_DL;
        Set_Addr_To_r <= Set_Addr_To_PBR;

        WRn_i <= 1;
        EF_i <= 1;
        MF_i <= 1;
        XF_i <= 1;

        NMICycle <= 0;
        IRQCycle <= 0;
    end else if (Enable) begin
        // some instructions behavior changed by the Rdy line. Detect this at the correct cycles.
        if (MCycle == 3'b000) 
            rdy_mod <= 1'b0;
        else if (((MCycle == 3'b011 && IR != 8'h93) || (MCycle == 3'b100 && IR == 8'h93)) && ~Rdy) 
            rdy_mod <= 1'b1;

        if (really_rdy) begin
            WRn_i <=  ~Write | RstCycle;

            PBR <= {8{1'b1}};   // Dummy
            DBR <= {8{1'b1}};   // Dummy
            EF_i <= 1'b0;       // Dummy
            MF_i <= 1'b0;       // Dummy
            XF_i <= 1'b0;       // Dummy

            if (MCycle == 3'b0) begin
                Mode_r <= Mode;
                BCD_en_r <= BCD_en;

                if (~IRQReq && ~NMIReq) 
                    PC <= PC + 1;

                if (IRQReq || NMIReq) 
                    IR <= 8'b0;
                else 
                    IR <= DI;

                IRQCycle <= 0;
                NMICycle <= 0;
                if (NMIReq)
                    NMICycle <= 1;
                else if (IRQReq)
                    IRQCycle <= 1;

                if (LDS)        // LAS won't work properly if not limited to machine cycle 0
                    S[7:0] <= ALU_Q;
            end

            ALU_Op_r <= ALU_Op;
            Write_Data_r <= Write_Data;
            if (Break) 
                Set_Addr_To_r <= Set_Addr_To_PBR;
            else 
                Set_Addr_To_r <= Set_Addr_To;

            if (Inc_S) 
                S <= S + 1;
            if (Dec_S && (~RstCycle || Mode == 2'b0))   // Decrement during reset - 6502 only?
                S <= S - 1;

            if (IR == 8'b0 && MCycle == 3'b001 && ~IRQCycle && ~NMICycle) 
                PC <= PC + 1;

            //
            // jump control logic
            //
            case (Jump)
            2'b01 : 
                PC <= PC + 1;
            2'b10 : 
                PC <= {DI,DL};
            2'b11 : begin
                if (PCAdder[8]) begin
                    if (DL[7] == 1'b0) 
                        PC[15:8] <= PC[15:8] + 1;
                    else 
                        PC[15:8] <= PC[15:8] - 1;
                end
                PC[7:0] <= PCAdder[7:0];
            end
            default : ;
            endcase
        end
    end
end

assign PCAdder = PCAdd ? PC[7:0] + {DL[7], DL} : {1'b0, PC[7:0]};

always @(posedge Clk) begin
    reg [7:0] tmpP;     //Lets try to handle loading P at mcycle=0 and set/clk flags at same cycle

    if (~Res_n_i) begin
        P <= 0;         // ensure we have nothing set on reset      
    end else if (Enable) begin
        tmpP = P;
        if (really_rdy) begin
            if (MCycle == 3'b000) begin
                if (LDA) 
                    ABC[7:0] <= ALU_Q;
                if (LDX) 
                    X[7:0] <= ALU_Q;
                if (LDY) 
                    Y[7:0] <= ALU_Q;
                if ((LDA | LDX | LDY)) 
                    tmpP = P_Out;
            end
            if (SaveP) 
                tmpP = P_Out;
            if (LDP) 
                tmpP = ALU_Q;
            if (IR[4:0] == 5'b11000) begin
                case (IR[7:5])
                3'b000 : //0x18(clc)
                    tmpP[Flag_C] = 1'b0;
                3'b001 : //0x38(sec)
                    tmpP[Flag_C] = 1'b1;
                3'b010 : //0x58(cli)
                    tmpP[Flag_I] = 1'b0;
                3'b011 : //0x78(sei)
                    tmpP[Flag_I] = 1'b1;
                3'b101 : //0xb8(clv)
                    tmpP[Flag_V] = 1'b0;
                3'b110 : //0xd8(cld)
                    tmpP[Flag_D] = 1'b0;
                3'b111 : //0xf8(sed)
                    tmpP[Flag_D] = 1'b1;
                default : ;
                endcase
            end
            tmpP[Flag_B] = 1'b1;
            if (IR == 8'b0 && MCycle == 3'b100 && ~RstCycle)   //This should happen after P has been pushed to stack
                tmpP[Flag_I] = 1'b1;
            if (RstCycle) begin
                tmpP[Flag_I] = 1'b1;
                tmpP[Flag_D] = 1'b0;
            end
            tmpP[Flag_1] = 1'b1;

            P <= tmpP;          //new way
        end
    end

    // act immediately on SO pin change
    // The signal is sampled on the trailing edge of phi1 and must be externally synchronized (from datasheet)
    SO_n_o <= SO_n;
    if (SO_n_o && ~SO_n)
        P[Flag_V] <= 1'b1;

  end

  //-------------------------------------------------------------------------
  //
  // Buses
  //
  //-------------------------------------------------------------------------
  
  always @(posedge Clk) begin
    if (~Res_n_i) begin
        BusA_r <= 0;
        BusB <= 0;
        BusB_r <= 0;
        AD <= 0;
        BAL <= 0;
        BAH <= 0;
        DL <= 0;
    end else if (Enable) begin
        if (really_rdy) begin
            NMI_entered <= 1'b0;
            BusA_r <= BusA;
            BusB <= DI;

            // not really nice, but no better way found yet !
            if (Set_Addr_To_r == Set_Addr_To_PBR || Set_Addr_To_r == Set_Addr_To_ZPG) 
                BusB_r <= (DI[7:0]) + 1;        // required for SHA

            case (BAAdd)
            2'b01 : begin
                // BA Inc
                AD <= (AD) + 1;
                BAL <= (BAL) + 1;
            end
            2'b10 : 
                // BA Add
                BAL <= (BAL[7:0]) + (BusA);
            2'b11 : 
                // BA Adj
                if (BAL[8]) begin
                    // Handle quirks with some undocumented opcodes crossing page boundary
                    case (BAQuirk)
                    2'b00 : BAH <= (BAH) + 1;   // no quirk
                    2'b01 : BAH <= ((BAH) + 1) & DO_r;
                    2'b10 : BAH <= DO_r;
                    default : ;
                    endcase
                end
            default : ;
            endcase

            // modified to use Y register as well
            if (ADAdd) begin
                if ((AddY)) 
                    AD <= (AD) + (Y[7:0]);
                else 
                    AD <= (AD) + (X[7:0]);
            end

            if (IR == 8'b00000000) begin
                BAL <= {9{1'b1}};
                BAH <= {8{1'b1}};
                if (RstCycle) 
                    BAL[2:0] <= 3'b100;
                else if (NMICycle || (NMIAct && MCycle == 3'b100) || NMI_entered) begin
                    BAL[2:0] <= 3'b010;
                    if (MCycle == 3'b100) 
                        NMI_entered <= 1'b1;
                end else 
                    BAL[2:0] <= 3'b110;
                if (Set_Addr_To_r == Set_Addr_To_BA) 
                    BAL[0] <= 1'b1;
            end

            if (LDDI) 
                DL <= DI;
            if (LDALU) 
                DL <= ALU_Q;
            if (LDAD) 
                AD <= DI;
            if (LDBAL) 
                BAL[7:0] <= DI;
            if (LDBAH) 
                BAH <= DI;
        end
    end
end

assign Break = (BreakAtNA & ~BAL[8]) | (PCAdd &  ~PCAdder[8]);

always @(*) begin
    case (Set_BusA_To)
    Set_BusA_To_DI :    BusA = DI;
    Set_BusA_To_ABC :   BusA = ABC[7:0];
    Set_BusA_To_X :     BusA = X[7:0];
    Set_BusA_To_Y :     BusA = Y[7:0];
    Set_BusA_To_S :     BusA = S[7:0];
    Set_BusA_To_P :     BusA = P;
    Set_BusA_To_DA :    BusA = ABC[7:0] & DI;
    Set_BusA_To_DAO :   BusA = (ABC[7:0] | 8'hee) & DI;            //ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
    Set_BusA_To_DAX :   BusA = (ABC[7:0] | 8'hee) & DI & X[7:0];   //XAA, ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
    Set_BusA_To_AAX :   BusA = ABC[7:0] & X[7:0];                  //SAX, SHA
    Set_BusA_To_DONTCARE : BusA = {8{1'bX}};                       //Can probably remove this
    default:            BusA = {8{1'bX}};
    endcase
end

always @(*) begin
    case (Set_Addr_To_r)
    Set_Addr_To_SP :    A = {16'b1, S[7:0]};
    Set_Addr_To_ZPG :   A = {DBR, 8'b0, AD};
    Set_Addr_To_BA :    A = {8'b0, BAH, BAL[7:0]};
    Set_Addr_To_PBR :   A = {PBR, PC[15:8], PCAdder[7:0]};
    endcase
end

// This is the P that gets pushed on stack with correct B flag. I'm not sure if NMI also clears B, but I guess it does.
assign PwithB = (IRQCycle || NMICycle) ? P & 8'hef : P;
assign DO = DO_r;

always @(*) begin
    case (Write_Data_r)
    Write_Data_DL :     DO_r = DL;
    Write_Data_ABC :    DO_r = ABC[7:0];
    Write_Data_X :      DO_r = X[7:0];
    Write_Data_Y :      DO_r = Y[7:0];
    Write_Data_S :      DO_r = S[7:0];
    Write_Data_P :      DO_r = PwithB;
    Write_Data_PCL :    DO_r = PC[7:0];
    Write_Data_PCH :    DO_r = PC[15:8];
    Write_Data_AX :     DO_r = ABC[7:0] & X[7:0];
    Write_Data_AXB :    DO_r = ABC[7:0] & X[7:0] & BusB_r[7:0];   // no better way found yet...
    Write_Data_XB :     DO_r = X[7:0] & BusB_r[7:0];               // no better way found yet...
    Write_Data_YB :     DO_r = Y[7:0] & BusB_r[7:0];               // no better way found yet...
    Write_Data_DONTCARE : DO_r = {8{1'bX}};                    //Can probably remove this
    default:            DO_r = {8{1'bX}};
    endcase
end

  //-----------------------------------------------------------------------
  //
  // Main state machine
  //
  //-----------------------------------------------------------------------
  
always @(posedge Clk) begin
    if (~Res_n_i) begin
        MCycle <= 1;
        RstCycle <= 1;
        NMIAct <= 0;
        IRQReq <= 0;
        NMIReq <= 0;
    end else if (Enable) begin
        if (really_rdy) begin
            if (MCycle == LCycle || Break) begin
                MCycle <= 3'b0;
                RstCycle <= 1'b0;
            end else
                MCycle <= MCycle + 1;

            if (IR[4:0] != 5'b10000 || Jump != 2'b11) begin     // taken branches delay the interrupts
                if (NMIAct && IR != 8'h00)
                    NMIReq <= 1;
                else
                    NMIReq <= 0;

                if (~IRQ_n_o && ~P[Flag_I])
                    IRQReq <= 1;
                else
                    IRQReq <= 0;
            end
        end

        IRQ_n_o <= IRQ_n;
        NMI_n_o <= NMI_n;

        //detect NMI even if not rdy    
        if (NMI_n_o && ~NMI_n) 
            NMIAct <= 1'b1;
        // we entered NMI during BRK instruction
        if (NMI_entered) begin
            NMIAct <= 1'b0;
        end
    end
  end

endmodule
