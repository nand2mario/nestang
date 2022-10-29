// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

`define USE_RX2

`ifdef USE_RX2
//////////////////////////////////////////////////////////////////////
// File Downloaded from http://www.nandland.com
//////////////////////////////////////////////////////////////////////
// This file contains the UART Receiver.  This receiver is able to
// receive 8 bits of serial data, one start bit, one stop bit,
// and no parity bit.  When receive is complete o_rx_dv will be
// driven high for one clock cycle.
// 
// Set Parameter CLKS_PER_BIT as follows:
// CLKS_PER_BIT = (Frequency of i_Clock)/(Frequency of UART)
// Example: 10 MHz Clock, 115200 baud UART
// (10000000)/(115200) = 87

typedef logic [7:0] BYTE;

module uart_rx 
  #(parameter CLKS_PER_BIT)
  (
   input        i_Clock,
   input        i_Rx_Serial,
   output       o_Rx_DV,
   output [7:0] o_Rx_Byte
   );
    
  parameter s_IDLE         = 3'b000;
  parameter s_RX_START_BIT = 3'b001;
  parameter s_RX_DATA_BITS = 3'b010;
  parameter s_RX_STOP_BIT  = 3'b011;
  parameter s_CLEANUP      = 3'b100;
   
  reg           r_Rx_Data_R = 1'b1;
  reg           r_Rx_Data   = 1'b1;
   
  reg [7:0]     r_Clock_Count = 0;
  reg [2:0]     r_Bit_Index   = 0; //8 bits total
  reg [7:0]     r_Rx_Byte     = 0;
  reg           r_Rx_DV       = 0;
  reg [2:0]     r_SM_Main     = 0;
   
  // Purpose: Double-register the incoming data.
  // This allows it to be used in the UART RX Clock Domain.
  // (It removes problems caused by metastability)
  always @(posedge i_Clock)
    begin
      r_Rx_Data_R <= i_Rx_Serial;
      r_Rx_Data   <= r_Rx_Data_R;
    end
   
   
  // Purpose: Control RX state machine
  always @(posedge i_Clock)
    begin
       
      case (r_SM_Main)
        s_IDLE :
          begin
            r_Rx_DV       <= 1'b0;
            r_Clock_Count <= 0;
            r_Bit_Index   <= 0;
             
            if (r_Rx_Data == 1'b0)          // Start bit detected
              r_SM_Main <= s_RX_START_BIT;
            else
              r_SM_Main <= s_IDLE;
          end
         
        // Check middle of start bit to make sure it's still low
        s_RX_START_BIT :
          begin
            if (r_Clock_Count == BYTE'((CLKS_PER_BIT-1)/2))
              begin
                if (r_Rx_Data == 1'b0)
                  begin
                    r_Clock_Count <= 0;  // reset counter, found the middle
                    r_SM_Main     <= s_RX_DATA_BITS;
                  end
                else
                  r_SM_Main <= s_IDLE;
              end
            else
              begin
                r_Clock_Count <= r_Clock_Count + 1;
                r_SM_Main     <= s_RX_START_BIT;
              end
          end // case: s_RX_START_BIT
         
         
        // Wait CLKS_PER_BIT-1 clock cycles to sample serial data
        s_RX_DATA_BITS :
          begin
            if (r_Clock_Count < BYTE'(CLKS_PER_BIT-1))
              begin
                r_Clock_Count <= r_Clock_Count + 1;
                r_SM_Main     <= s_RX_DATA_BITS;
              end
            else
              begin
                r_Clock_Count          <= 0;
                r_Rx_Byte[r_Bit_Index] <= r_Rx_Data;
                 
                // Check if we have received all bits
                if (r_Bit_Index < 7)
                  begin
                    r_Bit_Index <= r_Bit_Index + 1;
                    r_SM_Main   <= s_RX_DATA_BITS;
                  end
                else
                  begin
                    r_Bit_Index <= 0;
                    r_SM_Main   <= s_RX_STOP_BIT;
                  end
              end
          end // case: s_RX_DATA_BITS
     
     
        // Receive Stop bit.  Stop bit = 1
        s_RX_STOP_BIT :
          begin
            // Wait CLKS_PER_BIT-1 clock cycles for Stop bit to finish
            if (r_Clock_Count < BYTE'(CLKS_PER_BIT-1))
              begin
                r_Clock_Count <= r_Clock_Count + 1;
                r_SM_Main     <= s_RX_STOP_BIT;
              end
            else
              begin
                r_Rx_DV       <= 1'b1;
                r_Clock_Count <= 0;
                r_SM_Main     <= s_CLEANUP;
              end
          end // case: s_RX_STOP_BIT
     
         
        // Stay here 1 clock
        s_CLEANUP :
          begin
            r_SM_Main <= s_IDLE;
            r_Rx_DV   <= 1'b0;
          end
         
         
        default :
          r_SM_Main <= s_IDLE;
         
      endcase
    end   
   
  assign o_Rx_DV   = r_Rx_DV;
  assign o_Rx_Byte = r_Rx_Byte;
   
endmodule // uart_rx

`else
// original implementation
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
`endif

// Decodes incoming UART signals and demuxes them into addr/data lines.
// Packet Format: 
//   1 byte checksum | 1 byte address | 1 byte count | (count + 1) data bytes
module UartDemux #(parameter FREQ=48_600_000, parameter BAUDRATE=115_200)
    (input clk, input RESET, input UART_RX, output reg [7:0] data, output reg [7:0] addr, 
    output reg write, output reg checksum_error);
  wire [7:0] indata;
  wire       insend;
`ifdef USE_RX2
  uart_rx #(.CLKS_PER_BIT(FREQ/BAUDRATE)) uart (clk, UART_RX, insend, indata);
`else
  Rs232Rx #(.WAIT(FREQ/BAUDRATE)) uart (clk, UART_RX, indata, insend);
`endif
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

