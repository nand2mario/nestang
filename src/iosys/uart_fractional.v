// UART RX with fractional clock divider.
// Baud rate = frequency of `clk` / (DIV_NUM / DIV_DEN)
//
// Author: nand2mario, Feb 2025
module uart_rx_fractional #(
    parameter DIV_NUM = 25,
    parameter DIV_DEN = 1
)(
    input clk,
    input resetn,
    input rx,
    output reg [7:0] data,
    output reg valid
);

reg [1:0] state;
reg [$clog2(DIV_NUM)-1:0] cnt, cnt_next;
reg [2:0] bit_index;
reg [7:0] rx_data;

always @(posedge clk) begin
    if (!resetn) begin
        state <= 0;
        valid <= 0;
        data <= 0;
    end else begin
        reg cnt_overflow;
        cnt_next = cnt + DIV_DEN;
        cnt_overflow = cnt_next >= DIV_NUM;
        if (state != 0) 
            cnt <= cnt_overflow ? cnt_next - DIV_NUM : cnt_next;
        valid <= 0;
        case (state)
            0: begin // Idle
                if (!rx) begin
                    state <= 1;
                    cnt <= 0;
                    bit_index <= 0;
                    rx_data <= 0;
                end
            end
            1: begin // Start bit, wait half a bit time
                if (cnt_next >= DIV_NUM/2) begin
                    state <= 2;
                    cnt <= 0;
                end 
            end
            2: begin // Data bits
                if (cnt_overflow) begin
                    rx_data[bit_index] <= rx;
                    if (bit_index == 7) 
                        state <= 3;
                    else 
                        bit_index <= bit_index + 1;
                end
            end
            3: begin // Stop bit
                if (cnt_overflow) begin
                    valid <= 1;
                    data <= rx_data;
                    state <= 0;
                end
            end
        endcase
        
    end
end

endmodule 

module uart_tx_fractional #(
    parameter DIV_NUM = 25,
    parameter DIV_DEN = 1
)(
    input clk,
    input resetn,
    input [7:0] data,
    input valid,
    output reg tx,
    output ready
);

reg [3:0] state;
reg [$clog2(DIV_NUM)-1:0] cnt, cnt_next;
reg [2:0] bit_index;
reg [7:0] tx_data;

assign ready = (state == 0);

always @(posedge clk) begin
    if (!resetn) begin
        state <= 0;
        tx <= 1;
        cnt <= 0;
    end else begin
        reg cnt_overflow;
        cnt_next = cnt + DIV_DEN;
        cnt_overflow = cnt_next >= DIV_NUM;
        if (state != 0) 
            cnt <= cnt_overflow ? cnt_next - DIV_NUM : cnt_next;

        case (state)
            0: begin // Idle
                if (valid) begin
                    tx_data <= data;
                    state <= 1;
                    tx <= 0; // Start bit
                    cnt <= 0;
                end
            end
            1: begin // Start bit
                if (cnt_overflow) begin
                    state <= 2;
                    bit_index <= 0;
                    tx <= tx_data[0];
                end
            end
            2: begin // Data bits
                if (cnt_overflow) begin
                    if (bit_index == 7) begin
                        state <= 3;
                        tx <= 1; // Stop bit
                    end else begin
                        bit_index <= bit_index + 1;
                        tx <= tx_data[bit_index + 1];
                    end
                end
            end
            3: begin // Stop bit
                if (cnt_overflow) begin
                    state <= 0;
                end
            end
        endcase
    end
end

endmodule 