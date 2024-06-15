// Spi flash module with two functions,
// 1. Inital program loading from flash
// 2. MMIO interface for R/W accesses to the flash
// 
// MMIO Registers:
// 0x200_0070: Byte reg. Write to initiate a byte transfer.
//             The lowest byte is transfered over SPI.
//             Then a read will return the received byte.
// 0x200_0074: Word transfer. Writes and reads 4 bytes.
// 0x200_0078: Control register (write-only). [0]=CS_N
//
// Chip is Winbond W25Q64
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

    // program loading at ADDR for LEN bytes
    input start,        // pulse to start loading from flash 
    output reg busy,
    output reg [7:0] dout,
    output reg dout_strb,

    // RV MMIO interface
    input             reg_byte_we,  // 1: write-read a byte 
    input	      	  reg_word_we,	// 1: write-read a word
    input             reg_ctrl_we,  // 1: write control register
    input      [31:0] reg_di,
    output reg [31:0] reg_do,
    output            reg_wait
);

reg [1:0] state;

reg ncs_buf = 1'b1;
assign ncs = ncs_buf;
reg [7:0] data_in;
wire [7:0] data_out;
reg spi_start;
wire spi_ready;

reg [20:0] cnt;         // transfer byte count, max 2MB

assign reg_wait = wait_buf & (reg_byte_we | reg_word_we);
reg wait_buf = 1;
reg reg_byte_we_r, reg_word_we_r;
reg active, new_request;

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
        reg new_request_t = reg_byte_we && ~reg_byte_we_r || reg_word_we && ~reg_word_we_r;
        reg_byte_we_r <= reg_byte_we;
        reg_word_we_r <= reg_word_we;
        if (new_request_t)
            new_request <= 1;

        if (reg_ctrl_we)
            ncs_buf <= reg_di[0];

        spi_start <= 0;
        wait_buf <= 1;
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
                ncs_buf <= 1'b1;
            end
            spi_start <= 1;
            dout <= data_out;
            dout_strb <= 1'b1;
        end
        2'd3: begin                                 // MMIO
            if (spi_ready && ~spi_start && (new_request_t || new_request || active)) begin
                // send
                if (new_request || new_request_t) begin
                    data_in <= reg_di[7:0];
                    spi_start <= 1;
                    active <= 1;
                    new_request <= 0;
                end else if (reg_word_we && cnt != 2'd3) begin
                    data_in <= reg_di[(cnt+1)*8 +: 8];
                    spi_start <= 1;
                    cnt <= cnt + 2'd1;
                end else begin      // last byte is transmitted, let CPU continue
                    wait_buf <= 0;
                    cnt <= 0;
                    active <= 0;
                end

                // receive
                if (~new_request)
                    reg_do[cnt*8 +: 8] <= data_out;
            end
        end
        endcase
    end
end

endmodule


