`define RES_720P
`define GW_IDE
`define MEGA60K
`define PRIMER
`define CONSOLE

`define USB1
`define USB2

`define CONTROLLER_DS2

package configPackage;  

    // Tang SDRAM v1.2: 2B * 8K * 512 * 4 = 32MB
    localparam SDRAM_DATA_WIDTH = 16;     // 2 bytes per word
    localparam SDRAM_ROW_WIDTH = 13;      // 8K rows
    localparam SDRAM_COL_WIDTH = 9;       // 512 cols
    localparam SDRAM_BANK_WIDTH = 2;      // 4 banks

endpackage