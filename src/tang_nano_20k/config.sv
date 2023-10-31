`define RES_720P
`define GW_IDE
`define N20K

package configPackage;  

    // total space: 4B * 2K * 256 * 4 = 8MB
    localparam SDRAM_DATA_WIDTH = 32;     // 4 bytes per word
    localparam SDRAM_ROW_WIDTH = 11;      // 2K rows
    localparam SDRAM_COL_WIDTH = 8;       // 256 cols
    localparam SDRAM_BANK_WIDTH = 2;      // 4 banks

`include "../config.vh"

endpackage