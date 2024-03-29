package t65;

localparam Flag_C = 0;
localparam Flag_Z = 1;
localparam Flag_I = 2;
localparam Flag_D = 3;
localparam Flag_B = 4;
localparam Flag_1 = 5;
localparam Flag_V = 6;
localparam Flag_N = 7;

typedef logic [2:0] T_LCycle;
localparam Cycle_sync = 3'd0;
localparam Cycle_1 = 3'd1;
localparam Cycle_2 = 3'd2;
localparam Cycle_3 = 3'd3;
localparam Cycle_4 = 3'd4;
localparam Cycle_5 = 3'd5;
localparam Cycle_6 = 3'd6;
localparam Cycle_7 = 3'd7;

typedef enum logic [3:0] {
    Set_BusA_To_DI,
    Set_BusA_To_ABC,
    Set_BusA_To_X,
    Set_BusA_To_Y,
    Set_BusA_To_S,
    Set_BusA_To_P,
    Set_BusA_To_DA,
    Set_BusA_To_DAO,
    Set_BusA_To_DAX,
    Set_BusA_To_AAX,
    Set_BusA_To_DONTCARE
} T_Set_BusA_To;

typedef enum logic [1:0] {
    Set_Addr_To_PBR,
    Set_Addr_To_SP,
    Set_Addr_To_ZPG,
    Set_Addr_To_BA    
} T_Set_Addr_To;

typedef enum logic [3:0] {
    Write_Data_DL,
    Write_Data_ABC,
    Write_Data_X,
    Write_Data_Y,
    Write_Data_S,
    Write_Data_P,
    Write_Data_PCL,
    Write_Data_PCH,
    Write_Data_AX,
    Write_Data_AXB,
    Write_Data_XB,
    Write_Data_YB,
    Write_Data_DONTCARE
} T_Write_Data;

typedef enum logic [4:0] {
    ALU_OP_OR,  
    ALU_OP_AND, 
    ALU_OP_EOR, 
    ALU_OP_ADC, 
    ALU_OP_EQ1, // EQ1 does not change N,Z flags, EQ2/3 does.
    ALU_OP_EQ2, // Not sure yet whats the difference between EQ2&3. They seem to do the same ALU op
    ALU_OP_CMP, 
    ALU_OP_SBC, 
    ALU_OP_ASL, 
    ALU_OP_ROL, 
    ALU_OP_LSR, 
    ALU_OP_ROR, 
    ALU_OP_BIT, 
//    ALU_OP_EQ3,
    ALU_OP_DEC, 
    ALU_OP_INC, 
    ALU_OP_ARR,
    ALU_OP_ANC,
    ALU_OP_SAX,
    ALU_OP_XAA    
} T_ALU_OP;

typedef struct packed {
    logic [7:0] I;
    logic [7:0] A;
    logic [7:0] X;
    logic [7:0] Y;
    logic [7:0] S;
    logic [7:0] P;
} T_t65_dbg;

function T_LCycle CycleNext(T_LCycle c);
    T_LCycle r;
    case (c)
    Cycle_sync: r = Cycle_1;
    Cycle_1: r = Cycle_2;
    Cycle_2: r = Cycle_3;
    Cycle_3: r = Cycle_4;
    Cycle_4: r = Cycle_5;
    Cycle_5: r = Cycle_6;
    Cycle_6: r = Cycle_7;
    default: r = Cycle_sync;
    endcase
    return r;
endfunction

endpackage