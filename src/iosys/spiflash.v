// read a block of content from spi flash
module spiflash #(
    parameter CLK_DIV = 2,
    parameter [23:0] ADDR = 1024*1024,
    parameter LEN = 1024
) (
    input clk,
    input resetn,

    output ncs,         // chip select
    input miso,         // master in slave out
    output mosi,        // mster out slave in
    output sck,         // spi clock

    input start,        // pulse to start reading from flash 
    output reg busy,
    output reg [7:0] dout,
    output reg dout_strb
);

reg [1:0] state;

reg ncs_buf = 1'b1;
assign ncs = ncs_buf;
reg [7:0] data_in;
wire [7:0] data_out;
reg spi_start;
wire spi_ready;

reg [20:0] cnt;         // transfer byte count, max 2MB

// spi #(.CLK_DIV(CLK_DIV)) spi (
//     .clk(clk), .resetn(resetn), .miso(miso), .mosi(mosi),
//     .sck(sck), .start(spi_start), .data_in(data_in), .data_out(data_out),
//     .busy(spi_busy), .new_data(new_data)
// );

SPI_Master #(.CLKS_PER_HALF_BIT(CLK_DIV)) spi (
  .i_Clk(clk), .i_Rst_L(resetn),
  .i_TX_Byte(data_in), .i_TX_DV(spi_start), .o_TX_Ready(spi_ready),
  .o_RX_DV(), .o_RX_Byte(data_out),
  .o_SPI_Clk(sck), .i_SPI_MISO(miso), .o_SPI_MOSI(mosi)
);

always @(posedge clk) begin
    if (~resetn) begin
        state <= 0;
        ncs_buf <= 1'b1;
    end else begin
        spi_start <= 0;
        dout_strb <= 0;
        case (state) 
        2'd0:
            if (start) begin
                ncs_buf <= 0;
                state <= 2'd1;
                cnt <= 0;
                busy <= 1;
            end
        2'd1: if (~spi_start && spi_ready) begin     // send READ (03h) command
            cnt <= cnt + 1;
            spi_start <= 1;
            case (cnt[2:0])
            3'd0: data_in <= 8'h03;
            3'd1: data_in <= ADDR[23:16];
            3'd2: data_in <= ADDR[15:8];
            3'd3: data_in <= ADDR[7:0];
            3'd4: begin
                // start receiving first byte
                state <= 2'd2;
                cnt <= 1;
                data_in <= 0;
            end
            default: ;
            endcase
        end
        2'd2: if (~spi_start && spi_ready) begin    // read back LEN bytes
            cnt <= cnt + 21'd1;
            if (cnt == LEN) begin
                state <= 2'd3;
                busy <= 0;
            end
            spi_start <= 1;
            dout <= data_out;
            dout_strb <= 1'b1;
        end
        2'd3: begin                             // finish
            ncs_buf <= 1'b1;
        end
        endcase
    end
end

endmodule


