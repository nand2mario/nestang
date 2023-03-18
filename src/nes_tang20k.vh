// Main clock frequency
localparam FREQ=27_000_000;          // at least 10x baudrate
// localparam FREQ=37_800_000;

// UART baudrate: BAUDRATE <= FREQ/10
localparam BAUDRATE=921600;

// define this to execute one NES cycle per 0.01 second and print the operation done
// `define STEP_TRACING

`ifdef VERILATOR
`define EMBED_GAME
`endif
