// SPI master module for picorv32 similar to simpleuart.v
// This is mostly for sd card access.
//
// Registers:
// 0x200_0020: Byte reg. Write to initiate a byte transfer.
//             The lowest byte is transfered over SPI.
//             Then a read will return the received byte.
// 0x200_0024: Word transfer. Writes and reads 4 bytes.
//
// SPI clock is 1/4 of clk. SD_DAT[3:1]=3'b011 for SPI mode.
module simplespimaster (
	input clk,
	input resetn,

	// SPI mode: SD_DAT[3]=0, SD_DAT[2]=1, SD_DAT[1]=1
	output sck /* synthesis syn_keep=1*/,			// SD_SCK
	output mosi /* synthesis syn_keep=1*/,		// SD_CMD
	input  miso /* synthesis syn_keep=1*/,		// SD_DAT[0]
	// output cs,			// SD_DAT[3]

    input             reg_byte_we,  // 1: write-read a byte 
    input	      	  reg_word_we,	// 1: write-read a word

    input      [31:0] reg_di,
    output reg [31:0] reg_do,
    output            reg_wait
);

assign reg_wait = wait_buf & (reg_byte_we | reg_word_we);

reg [7:0] tx_byte;
wire [7:0] rx_byte /* synthesis syn_keep=1 */;
reg spi_start;

reg wait_buf = 1;
reg [1:0] cnt;  // how many bytes are already sent
reg reg_byte_we_r, reg_word_we_r;
reg active, new_request;

SPI_Master #(.CLKS_PER_HALF_BIT(2)) spi_io_master (
// SPI_Master #(.CLKS_PER_HALF_BIT(4)) spi_io_master (
  .i_Clk(clk), .i_Rst_L(resetn),
  .i_TX_Byte(tx_byte), .i_TX_DV(spi_start), .o_TX_Ready(spi_ready),
  .o_RX_DV(spi_rxdv), .o_RX_Byte(rx_byte),
  .o_SPI_Clk(sck), .i_SPI_MISO(miso), .o_SPI_MOSI(mosi)
);

// o_TX_Ready (spi_ready) is after o_RX_DV. so we only use spi_ready
always @(posedge clk) begin
    spi_start <= 0;
    wait_buf <= 1;
	if (~resetn) begin
        reg_byte_we_r <= 0;
        reg_word_we_r <= 0;
        cnt <= 0;
        active <= 0;
    end else begin
        reg new_request_t = reg_byte_we && ~reg_byte_we_r || reg_word_we && ~reg_word_we_r;
        if (new_request_t)
            new_request <= 1;
        reg_byte_we_r <= reg_byte_we;
        reg_word_we_r <= reg_word_we;
		if (spi_ready && ~spi_start && (new_request_t || new_request || active)) begin
            // send
            if (new_request || new_request_t) begin
                tx_byte <= reg_di[7:0];
                spi_start <= 1;
                active <= 1;
                new_request <= 0;
            end else if (reg_word_we && cnt != 2'd3) begin
	    		tx_byte <= reg_di[(cnt+1)*8 +: 8];
    			spi_start <= 1;
                cnt <= cnt + 2'd1;
            end else begin      // last byte is trasmitted, let CPU continue
                wait_buf <= 0;
                cnt <= 0;
                active <= 0;
            end

            // receive
            if (~new_request)
                reg_do[cnt*8 +: 8] <= rx_byte;
		end
	end
end

endmodule
