
module dpram #(
    parameter widthad_a,
    parameter width_a = 8
) (
    input [widthad_a-1:0] address_a,
    input [widthad_a-1:0] address_b,
    input clock_a,
    input clock_b,
    input [width_a-1:0] data_a, 
    input [width_a-1:0] data_b,
    input wren_a,
    input wren_b,
    input [width_a/8-1:0] byteena_a,
    input [width_a/8-1:0] byteena_b,
    output reg [width_a-1:0] q_a,
    output reg [width_a-1:0] q_b
);

localparam SIZE = 1 << widthad_a;

reg [width_a-1:0] mem [0:SIZE-1];

always @(posedge clock_a) begin
    if (wren_a)
        mem[address_a] <= data_a;
    else
        q_a <= mem[address_a];
end

always @(posedge clock_b) begin
    if (wren_b)
        mem[address_b] <= data_b;
    else
        q_b <= mem[address_b];
end

endmodule