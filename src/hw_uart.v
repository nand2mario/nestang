// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module Rs232Tx(input clk, output UART_TX, input [7:0] data, input send, output reg uart_ovf, output reg sending);
  reg [9:0] sendbuf = 9'b000000001;
  //reg sending;
  reg [13:0] timeout;
  assign UART_TX = sendbuf[0];
 
  always @(posedge clk) begin
    if (send && sending)
      uart_ovf <= 1;
  
    if (send && !sending) begin
      sendbuf <= {1'b1, data, 1'b0};
      sending <= 1;
      timeout <= 100 - 1; // 115200
    end else begin
      timeout <= timeout - 1;
    end
    
    if (sending && timeout == 0) begin
      timeout <= 100 - 1; // 115200
      if (sendbuf[8:0] == 9'b000000001)
        sending <= 0;
      else
        sendbuf <= {1'b0, sendbuf[9:1]};
    end
  end
endmodule

/* verilator lint_off WIDTH */
module Rs232Rx #(parameter [9:0] WAIT = 10) (input clk, input UART_RX, output [7:0] data, output send);
/* verilator lint_on WIDTH */

  reg [8:0] recvbuf;
  reg [9:0] timeout = WAIT/2 - 1;
  reg recving;
  reg data_valid = 0;
  assign data = recvbuf[7:0];
  assign send = data_valid;
  always @(posedge clk) begin
    data_valid <= 0;
    timeout <= timeout - 1;
    if (timeout == 0) begin
      timeout <= WAIT - 1;
      recvbuf <= (recving ? {UART_RX, recvbuf[8:1]} : 9'b100000000);
      recving <= 1;
      if (recving && recvbuf[0]) begin
        recving <= 0;
        data_valid <= UART_RX;
      end
    end
    // Once we see a start bit we want to wait
    // another half period for it to become stable.
    if (!recving && UART_RX)
      timeout <= WAIT/2 - 1;
  end
endmodule

// Decodes incoming UART signals and demuxes them into addr/data lines.
// Packet Format: 
//   1 byte checksum | 1 byte address | 1 byte count | (count + 1) data bytes
module UartDemux #(parameter FREQ=48_600_000, parameter BAUDRATE=115_200)
    (input clk, input RESET, input UART_RX, output reg [7:0] data, output reg [7:0] addr, 
    output reg write, output reg checksum_error);
  wire [7:0] indata;
  wire       insend;
  Rs232Rx #(.WAIT(FREQ/BAUDRATE)) uart (clk, UART_RX, indata, insend);
  reg [1:0] state = 0;
  reg [7:0] cksum;
  reg [7:0] count;
  wire [7:0] new_cksum = cksum + indata;
  always @(posedge clk) if (RESET) begin
    write <= 0;
    state <= 0;
    count <= 0;
    cksum <= 0;
    addr <= 0;
    data <= 0;
    checksum_error <= 0;
  end else begin
    write <= 0;
    if (insend) begin
      cksum <= new_cksum;
      count <= count - 8'd1;
      if (state == 0) begin
        state <= 1;
        cksum <= indata;
      end else if (state == 1) begin
        addr <= indata;
        state <= 2;
      end else if (state == 2) begin
        count <= indata;
        state <= 3;
      end else begin
        data <= indata;
        write <= 1;
        if (count == 1) begin
          state <= 0;
          if (new_cksum != 0)
            checksum_error <= 1;
        end
      end
    end
  end
endmodule

