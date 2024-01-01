
// include from tang_primer_25k/config.sv and tang_nano_20k/config.sv

localparam FRAMEWIDTH = 1280;
localparam FRAMEHEIGHT = 720;
localparam TOTALWIDTH = 1650;
localparam TOTALHEIGHT = 750;
localparam SCALE = 5;
localparam VIDEOID = 4;
localparam VIDEO_REFRESH = 60.0;

localparam IDIV_SEL_X5 = 3;
localparam FBDIV_SEL_X5 = 54;
localparam ODIV_SEL_X5 = 2;
localparam DUTYDA_SEL_X5 = "1000";
localparam DYN_SDIV_SEL_X5 = 2;
  
localparam CLKFRQ = 74250;

localparam COLLEN = 80;
localparam AUDIO_BIT_WIDTH = 16;

localparam POWERUPNS = 100000000.0;
localparam CLKPERNS = (1.0/CLKFRQ)*1000000.0;
localparam int POWERUPCYCLES = $rtoi($ceil( POWERUPNS/CLKPERNS ));

// Main clock frequency
localparam FREQ=27_000_000;          // at least 10x baudrate
// localparam FREQ=37_800_000;

// UART baudrate: BAUDRATE <= FREQ/10
localparam BAUDRATE=115200;
// localparam BAUDRATE=921600;

// define this to execute one NES cycle per 0.01 second and print the operation done
// `define STEP_TRACING

`ifdef VERILATOR
`define EMBED_GAME
`endif

