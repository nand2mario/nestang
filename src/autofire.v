
// Simple autofire mechanism. When 'btn' is high, 'out' will toggle betwen 1 and 0 at a rate of FIRERATE

module Autofire #(
    parameter FREQ = 37_800_000,
    parameter FIRERATE = 10
) (
    input clk,
    input resetn,
    input btn,
    input reg out
);

localparam DELAY = FREQ / FIRERATE / 2;
reg [$clog2(DELAY)-1:0] timer;

always @(posedge clk) begin
    if (~resetn) begin
        timer <= 0;
        out <= 0;
    end else begin
        if (btn) begin
            timer <= timer + 1;
            if (timer == 0) out <= ~out;
            if (timer == DELAY-1) timer <= 0;
        end else begin
            timer <= 0;
            out <= 0;
        end
    end
end

endmodule