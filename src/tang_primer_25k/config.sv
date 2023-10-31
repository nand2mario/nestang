`define RES_720P
`define GW_IDE
`define P25K

package configPackage;  

    // total space: 2B * 8K * 1K * 4 = 64MB
    localparam SDRAM_DATA_WIDTH = 16;     // 2 bytes per word
    localparam SDRAM_ROW_WIDTH = 13;      // 8K rows
    localparam SDRAM_COL_WIDTH = 10;      // 1K cols
    localparam SDRAM_BANK_WIDTH = 2;      // 4 banks

`include "../config.vh"

endpackage