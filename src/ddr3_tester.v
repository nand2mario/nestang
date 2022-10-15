
// Verifying read/write of a initialized ddr3_controller
// Use this to end-to-end check whether the memory is working okay after initialization
module ddr3_tester #(
    parameter READ_LATENCY=3'd4 // default is 4 cycles read latency (for clk = 1/3 pclk)
) (
    input clk,                  // either pclk or divided pclk (e.g. 1/3 pclk) works
    input resetn,
    input start,                // a pulse will start the test process
    output reg running,
    output reg [3:0] state,
    output reg fail_high,       // higher byte failure detected
    output reg fail_low,        // lower byte failure detected
    
    // ddr3_controller interface
    output reg rd,
    output reg wr,
    output reg refresh,
    output reg [25:0] addr,
    output reg [15:0] din,
    input [15:0] dout,
    input data_ready,
    input busy
);

localparam SIZE = 64*1024;
localparam WIDTH = $clog2(SIZE);
typedef logic [WIDTH-1:0] T_ADDR;

//reg [3:0] state;
localparam INIT = 4'd0;
localparam WRITE_START = 4'd1;
localparam WRITE_WAIT = 4'd2;
localparam WRITE_REFRESH_START = 4'd3;
localparam WRITE_REFRESH_WAIT = 4'd4;
localparam READ_START = 4'd5;
localparam READ_WAIT = 4'd6;
localparam READ_REFRESH_START = 4'd7;
localparam READ_REFRESH_WAIT = 4'd8;
localparam FINISH = 4'd9;

wire [15:0] testdata = addr[15:0] ^ 16'h67bc;
wire match_high = testdata[15:8] == dout[15:8];
wire match_low = testdata[7:0] == dout[7:0];
reg [2:0] cycle;

typedef logic [3:0] NIB;

// The DDR3 test FSM
always @(posedge clk) begin
    
    rd <= 0; wr <= 0; refresh <= 0;
    cycle <= cycle + 1;
    if (~resetn) begin
        state <= INIT;
        fail_high <= 1'b1;          // fail initially 1
        fail_low <= 1'b1;
        running <= 0;

    end else case (state)
        INIT: if (start) begin
            state <= WRITE_START;
            addr <= 26'b0;
            running <= 1'b1;
            fail_high <= 0; fail_low <= 0;      // set fail to 0 once we started testing
        end
        
        WRITE_START: begin
            wr <= 1'b1;
            din <= testdata;
            state <= WRITE_WAIT;
        end

        WRITE_WAIT: if (~wr && ~busy)
            state <= WRITE_REFRESH_START;

        WRITE_REFRESH_START: begin
            refresh <= 1'b1;
            state <= WRITE_REFRESH_WAIT;
        end

        WRITE_REFRESH_WAIT: if (~refresh && ~busy) begin
            if (addr[WIDTH-1:0] == T_ADDR'(SIZE-1)) begin
                // all writes finished, start reading
                addr <= 0;
                state <= READ_START;
            end else begin
                // write next word
                addr[WIDTH-1:0] <= addr[WIDTH-1:0] + 1'b1;
                state <= WRITE_START;
            end
        end

        READ_START: begin
            rd <= 1'b1;
            state <= READ_WAIT;
            cycle <= 3'd1;
        end

        READ_WAIT: if (cycle == READ_LATENCY) begin
            if (!match_high)
                fail_high <= 1'b1;
            if (!match_low)
                fail_low <= 1'b1;

            if (!match_high || !match_low) begin
                running <= 0;
                state <= FINISH;
            end else
                state <= READ_REFRESH_START;
        end

        READ_REFRESH_START: begin
            refresh <= 1'b1;
            state <= READ_REFRESH_WAIT;
        end

        READ_REFRESH_WAIT: if (~refresh && ~busy) begin
            if (addr[WIDTH-1:0] == T_ADDR'(SIZE-1)) begin
                running <= 0;
                state <= FINISH;
            end else begin
                addr[WIDTH-1:0] <= addr[WIDTH-1:0] + 1'b1;
                state <= READ_START;
            end
        end
    endcase
end

endmodule