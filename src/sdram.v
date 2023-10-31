// Simple SDRAM controller for Tang Nano 20k and Tang Primer 25K
// nand2mario
// 
// 2023.10: added support for Tang Primer 25K
// 2023.3:  ported to use GW2AR-18's embedded 64Mbit SDRAM.
//          changed to byte-based access.
// 2022.9:  iniital version.
//
// This is a byte-based, low-latency and non-bursting controller for the embedded 
// SDRAM on Tang Nano 20K (64Mbit, 2K rows x 256 columns x 4 banks x 32 bits), 
// and memory module on Tang Primer 25K (512Mbit or 1Gbit, 4K/8K rows x 
// 1K columns x 4 banks x 16 bits).
//
// Under default settings (max 66.7Mhz):
// - Data read latency is 4 cycles. 
// - Read/write operations take 5 cycles to complete. There's no overlap between
//   reads/writes.
// - All reads/writes are done with auto-precharge. So user does not need to deal 
//   with row activations and precharges.
// - SDRAMs need periodic refreshes or they lose data. So they provide an 
//   "auto-refresh" function to do one row of refresh. This "auto-refresh" operation 
//   is controlled with the 'refresh' input. 4096 or more refreshes should happen 
//   in any 64ms for the memory to not lose data. So the main circuit should invoke 
//   auto-refresh at least once **every ~15us**.
//
// Finally you need a 180-degree phase-shifted clock signal (clk_sdram) for SDRAM. 
// This can be generated with PLL's clkoutp output.
//
// The default parameters work for tang nano 20k embedded sdram.
// For tang primer 25k's memory module, use:
// sdram #(.FREQ(FREQ), .DATA_WIDTH(16), .ROW_WIDTH(13), .COL_WIDTH(10), .BANK_WIDTH(2) ) 
//   u_sdram (
//     ...
//     .SDRAM_DQM()       // no DQM pins for memory module   
//   )

module sdram
#(
    // Clock frequency, max 66.7Mhz with current set of T_xx/CAS parameters.
    parameter         FREQ = 54_000_000,  
    parameter         DATA_WIDTH = 32,
    parameter         ROW_WIDTH = 11,  // 2K rows
    parameter         COL_WIDTH = 8,   // 256 words per row (1Kbytes)
    parameter         BANK_WIDTH = 2,  // 4 banks

    // Time delays for 66.7Mhz max clock (min clock cycle 15ns)
    // The SDRAM supports max 166.7Mhz (RP/RCD/RC need changes)
    parameter [3:0]   CAS  = 4'd2,     // 2/3 cycles, set in mode register
    parameter [3:0]   T_WR = 4'd2,     // 2 cycles, write recovery
    parameter [3:0]   T_MRD= 4'd2,     // 2 cycles, mode register set
    parameter [3:0]   T_RP = 4'd1,     // 15ns, precharge to active
    parameter [3:0]   T_RCD= 4'd1,     // 15ns, active to r/w
    parameter [3:0]   T_RC = 4'd4      // 60ns, ref/active to ref/active
)
(
    // SDRAM side interface
    inout [DATA_WIDTH-1:0]      SDRAM_DQ,
    output reg [ROW_WIDTH-1:0]  SDRAM_A,
    output reg [BANK_WIDTH-1:0] SDRAM_BA,
    output            SDRAM_nCS,    // not strictly necessary, always 0
    output reg        SDRAM_nWE,
    output reg        SDRAM_nRAS,
    output reg        SDRAM_nCAS,
    output            SDRAM_CLK,
    output            SDRAM_CKE,    // not strictly necessary, always 1
    output reg  [DATA_WIDTH/8-1:0] SDRAM_DQM,    // sdram module reuses A11 and A12 for DQM
    
    // Logic side interface
    input             clk,
    input             clk_sdram,    // phase shifted from clk (normally 180-degrees)
    input             resetn,
    input             rd,           // command: read
    input             wr,           // command: write
    input             refresh,      // command: auto refresh. 4096 refresh cycles in 64ms. Once per 15us.
    input      [25:0] addr,         // byte address (64MB total space)
    input       [7:0] din,          // data input
    output      [7:0] dout,         // data output
    output [DATA_WIDTH-1:0] dout_full, // 32/16-bit data output
    output reg        data_ready,   // available 6 cycles after wr is set
    output reg        busy          // 0: ready for next command
);

localparam DATA_BYTES = DATA_WIDTH / 8;
localparam OFF_WIDTH = $clog2(DATA_BYTES);  // address within word

// Tri-state DQ input/output
reg dq_oen;         // 0 means output
reg [DATA_WIDTH-1:0] dq_out;
assign SDRAM_DQ = dq_oen ? {DATA_WIDTH{1'bz}} : dq_out;
wire [DATA_WIDTH-1:0] dq_in = SDRAM_DQ;     // DQ input

reg [OFF_WIDTH-1:0] off;          // byte offset
reg [7:0] dout_buf;
assign dout = busy ? dq_in[off*8+7 -: 8] : dout_buf;
// assign dout = off == 0 ? dq_in[7:0] :
//               off == 1 ? dq_in[15:8] :
//               off == 2 ? dq_in[23:16] : dq_in[31:24];
assign dout_full = dq_in;
assign SDRAM_CLK = clk_sdram;
assign SDRAM_CKE = 1'b1;
assign SDRAM_nCS = 1'b0;

reg [2:0] state;
localparam INIT = 3'd0;
localparam CONFIG = 3'd1;
localparam IDLE = 3'd2;
localparam READ = 3'd3;
localparam WRITE = 3'd4;
localparam REFRESH = 3'd5;

// RAS# CAS# WE#
localparam CMD_SetModeReg=3'b000;
localparam CMD_AutoRefresh=3'b001;
localparam CMD_PreCharge=3'b010;
localparam CMD_BankActivate=3'b011;
localparam CMD_Write=3'b100;
localparam CMD_Read=3'b101;
localparam CMD_NOP=3'b111;

localparam [2:0] BURST_LEN = 3'b0;      // burst length 1
localparam BURST_MODE = 1'b0;           // sequential
localparam [10:0] MODE_REG = {4'b0, CAS[2:0], BURST_MODE, BURST_LEN};

reg cfg_now;            // pulse for configuration
reg [3:0] cycle;        // each operation (config/read/write) are max 7 cycles

//
// SDRAM state machine
//
always @(posedge clk) begin
    cycle <= cycle == 4'd15 ? 4'd15 : cycle + 4'd1;
    // defaults
    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP; 
    casex ({state, cycle})
        // wait 200 us on power-on
        {INIT, 4'bxxxx} : if (cfg_now) begin
            state <= CONFIG;
            cycle <= 0;
        end

        // configuration sequence
        //  cycle  / 0 \___/ 1 \___/ 2 \___/ ... __/ 6 \___/ ...___/10 \___/11 \___/ 12\___
        //  cmd            |PC_All |Refresh|       |Refresh|       |  MRD  |       | _next_
        //                 '-T_RP--`----  T_RC  ---'----  T_RC  ---'------T_MRD----'
        {CONFIG, 4'd0} : begin
            // precharge all
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
            SDRAM_A[10] <= 1'b1;
        end
        {CONFIG, T_RP} : begin
            // 1st AutoRefresh
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC} : begin
            // 2nd AutoRefresh
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC+T_RC} : begin
            // set register
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_SetModeReg;
            SDRAM_A[10:0] <= MODE_REG;
        end
        {CONFIG, T_RP+T_RC+T_RC+T_MRD} : begin
            state <= IDLE;
            busy <= 1'b0;              // init&config is done
        end
        
        // read/write/refresh
        {IDLE, 4'bxxxx}: if (rd | wr) begin
            // bank activate
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
            SDRAM_BA <= addr[ROW_WIDTH+COL_WIDTH+BANK_WIDTH-1+OFF_WIDTH : ROW_WIDTH+COL_WIDTH+OFF_WIDTH];    // bank id
            SDRAM_A <= addr[ROW_WIDTH+COL_WIDTH-1+OFF_WIDTH:COL_WIDTH+OFF_WIDTH];      // 12-bit row address
            state <= rd ? READ : WRITE;
            cycle <= 4'd1;
            busy <= 1'b1;
        end else if (refresh) begin
            // auto-refresh
            // no need for precharge-all b/c all our r/w are done with auto-precharge.
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
            state <= REFRESH;
            cycle <= 4'd1;
            busy <= 1'b1;
        end

        // read sequence
        //  cycle  / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  rd     /       \_______________________________
        //  cmd            |Active | Read  |  NOP  |  NOP  | _Next_
        //  DQ                                     |  Dout |
        //  data_ready ____________________________/       \_______   
        //  busy   ________/                               \_______
        //                 `-T_RCD-'------CAS------'
        {READ, T_RCD}: begin
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Read;
            SDRAM_A[10] <= 1'b1;        // set auto precharge
            SDRAM_A[9:0] <= {1'b0, addr[COL_WIDTH-1+OFF_WIDTH:OFF_WIDTH]};  // column address
            SDRAM_DQM <= 0;
`ifdef P25K
            SDRAM_A[12:11] <= 2'b0;     // A[12:11] is DQM for sdram module
`endif
            off <= addr[OFF_WIDTH-1:0];
        end
        {READ, T_RCD+CAS}: begin
            data_ready <= 1'b1;
            dout_buf <= dq_in[off*8+7 -: 8];
        end
        {READ, T_RCD+CAS+4'd1}: begin
            data_ready <= 1'b0;
            busy <= 0;
            state <= IDLE;
        end

        // write sequence
        //  cycle / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  wr    /       \_______________________________
        //  cmd           |Active | Write |  NOP  |  NOP  | _Next_
        //  DQ                    | Din   |
        //  busy   _______/                               \_______
        //                `-T_RCD-'-------T_WR+T_RP-------'
        {WRITE, T_RCD}: begin
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Write;
            SDRAM_A[10] <= 1'b1;        // set auto precharge
            SDRAM_A[9:0] <= {1'b0, addr[COL_WIDTH-1+OFF_WIDTH:OFF_WIDTH]};  // column address
`ifdef P25K
            SDRAM_A[12:11] <= addr[0] ? 2'b01 : 2'b10;
`endif
            SDRAM_DQM <= ~(1 << addr[OFF_WIDTH-1:0]);
            // SDRAM_DQM <= addr[1:0] == 2'd0 ? 4'b1110 :
            //              addr[1:0] == 2'd1 ? 4'b1101 :
            //              addr[1:0] == 2'd2 ? 4'b1011 : 4'b0111;     // only write the correct byte
            off <= addr[OFF_WIDTH-1:0];
            dq_out <= {DATA_BYTES{din}};
            dq_oen <= 1'b0;                 // DQ output on
        end
        {WRITE, T_RCD+4'd1}: begin
            // dq_oen <= 1'b1;
        end
        {WRITE, T_RCD+T_WR+T_RP}: begin  // 2+2+1
            dq_oen <= 1'b1;
            busy <= 0;
            state <= IDLE;
        end

        // refresh sequence
        //  cycle   / 0 \___/ 1 \___/ 2 \___/ 3 \___/ 4 \___/ 5 \___
        //  refresh /       \_______________________________
        //  cmd             |Refresh|  NOP  |  NOP  |  NOP  | _Next_
        //  busy     _______/                               \_______
        //                  `------------- T_RC ------------'
        {REFRESH, T_RC}: begin
            state <= IDLE;
            busy <= 0;
        end
    endcase

    if (~resetn) begin
        busy <= 1'b1;
        dq_oen <= 1'b1;         // turn off DQ output
        SDRAM_DQM <= 0;
`ifdef P25K
        SDRAM_A[12:11] <= 2'b0;
`endif
        state <= INIT;
    end
end


//
// Generate cfg_now pulse after initialization delay (normally 200us)
//
reg  [14:0]   rst_cnt;
reg rst_done, rst_done_p1, cfg_busy;
  
always @(posedge clk) begin
    if (~resetn) begin
        rst_cnt  <= 15'd0;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end else begin
        rst_done_p1 <= rst_done;
        cfg_now     <= rst_done & ~rst_done_p1;// Rising Edge Detect

        if (rst_cnt != FREQ / 1000 * 200 / 1000) begin      // count to 200 us
            rst_cnt  <= rst_cnt[14:0] + 1;
            rst_done <= 1'b0;
            cfg_busy <= 1'b1;
        end else begin
            rst_done <= 1'b1;
            cfg_busy <= 1'b0;
        end        
    end
end

endmodule