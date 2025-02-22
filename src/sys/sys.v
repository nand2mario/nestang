// Sys - Tangcores system components 
// This manages slave SPI connection to the companion MCU, accepts ROM loading and other requests,
// and display the text overlay when needed.
// 
// Author: nand2mario, 1/2024

module sys #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1      // 1: nestang, 2: snestang
)
(
    input clk,                      // main logic clock
    // input clk50,                    // 50mhz clock for UART
    input hclk,                     // hdmi clock
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    input [11:0] joy1,              // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // joystick 2

    // ROM loading interface
    output reg [7:0] rom_loading,   // 0-to-1 loading starts, 1-to-0 loading is finished
    output reg [7:0] rom_do,        // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do
    
    output reg [31:0] core_config,

    // UART interface
    input  uart_rx,
    output uart_tx
);

localparam integer STR_LEN = 73; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tangcores;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20240101";

// Remove SPI parameters and add UART parameters
localparam CLK_FREQ = FREQ;
localparam BAUD_RATE = 1_000_000;

reg overlay_reg = 1;
assign overlay = overlay_reg;

// UART receiver signals
wire [7:0] rx_data;
wire rx_valid;

// UART transmitter signals
reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;

// Instantiate UART modules
uart_rx #(
    .DIV_NUM(CLK_FREQ/1000),
    .DIV_DEN(BAUD_RATE/1000)
) uart_receiver (
    .clk(clk),
    .resetn(resetn),
    .rx(uart_rx),
    .data(rx_data),
    .valid(rx_valid)
);

uart_tx #(
    .DIV_NUM(CLK_FREQ/1000),
    .DIV_DEN(BAUD_RATE/1000)
) uart_transmitter (
    .clk(clk),
    .resetn(resetn),
    .tx(uart_tx),
    .data(tx_data),
    .valid(tx_valid),
    .ready(tx_ready)
);

// Command processing state machine
localparam RECV_IDLE = 0;     // waiting for command
localparam RECV_PARAM = 1;    // receiving parameters
localparam RECV_RESPONSE_REQ = 2; // sending response
localparam RECV_RESPONSE_ACK = 3; // waiting for response ack
reg [2:0] recv_state;

// UART command buffer
reg [7:0] cmd_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;
reg [3:0] data_cnt;

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

reg send_config_string_req;
reg send_config_string_ack;

// Receive UART commands:
 // 1                       get core config string (null-terminated)
 // 2 x[31:0]               set core config status
 // 3 x[7:0]                turn overlay on/off
 // 4 x[7:0] y[7:0]         move text cursor to (x, y)
 // 5 <string>              display null-terminated string from cursor
 // 6 loading_state[7:0]    set loading state (rom_loading)
 // 7 len[23:0] <data>      load len bytes of data to rom_do
// Command processing state machine (RX)
always @(posedge clk) begin
    if (!resetn) begin
        recv_state <= RECV_IDLE;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading <= 0;
        rom_remain <= 0;
        core_config <= 0;
        data_cnt <= 0;
        x_wr <= 0;
        y_wr <= 0;
        char_wr <= 0;
        we <= 0;
        cursor_x <= 0;
        cursor_y <= 0;
    end else begin
        rom_do_valid <= 0;
        we <= 0;

        case (recv_state)
            RECV_IDLE: if (rx_valid) begin
                cmd_reg <= rx_data;
                if (rx_data == 1)
                    recv_state <= RECV_RESPONSE_REQ;
                else
                    recv_state <= RECV_PARAM;
                data_cnt <= 0;
            end
            
            RECV_PARAM: if (rx_valid) begin
                data_reg <= {data_reg[23:0], rx_data};
                data_cnt <= data_cnt + 1;
                
                case (cmd_reg)
                    2: begin
                        if (data_cnt == 3) begin // Received 4 bytes
                            core_config <= {data_reg[23:0], rx_data};
                            recv_state <= RECV_IDLE;
                        end
                    end
                    3: begin
                        overlay_reg <= rx_data[0];
                        recv_state <= RECV_IDLE;    // Single byte command
                    end
                    4: case (data_cnt)
                        0: cursor_x <= rx_data;
                        1: begin
                            cursor_y <= rx_data;
                            recv_state <= RECV_IDLE;
                        end
                        default: recv_state <= RECV_IDLE;
                    endcase
                    5: begin
                        if (rx_data == 0) begin // Null terminator
                            recv_state <= RECV_IDLE;
                        end else begin
                            x_wr <= cursor_x;
                            y_wr <= cursor_y;
                            char_wr <= rx_data;
                            if (cursor_x < 32) begin
                                cursor_x <= cursor_x + 1;
                                we <= 1;
                            end
                        end
                    end
                    6: begin
                        rom_loading <= rx_data;
                        recv_state <= RECV_IDLE;    // Single byte command
                    end
                    7: begin
                        if (data_cnt >= 3 && rom_remain == 0) begin
                            recv_state <= RECV_IDLE;
                        end
                    end
                    default:
                        recv_state <= RECV_IDLE;
                endcase
            end

            RECV_RESPONSE_REQ:                   // request to send config string
                if (cmd_reg == 1) begin         
                    send_config_string_req ^= 1;
                    recv_state <= RECV_RESPONSE_ACK;
                end else begin
                    recv_state <= RECV_IDLE;
                end

            RECV_RESPONSE_ACK:                  // wait for TX to finish
                if (send_config_string_req == send_config_string_ack) begin
                    recv_state <= RECV_IDLE;
                end
        endcase
        
    end
end

localparam SEND_IDLE = 0;
localparam SEND_CONFIG_STRING = 1;
localparam SEND_JOYPAD = 2;

reg [1:0] send_state;
reg [2:0] send_idx;
localparam JOY_UPDATE_INTERVAL = 50_000_000 / 50; // 20ms interval for 50Hz
reg [31:0] joy_timer;
reg [15:0] joy1_reg;
reg [15:0] joy2_reg;

// UART transmission logic (TX)
always @(posedge clk) begin
    if (!resetn) begin
        joy_timer <= 0;
        send_state <= 0;
    end else begin
        tx_valid <= 0;
        
        // Joypad state transmission logic
        joy_timer <= joy_timer + 1;
        if (joy_timer >= JOY_UPDATE_INTERVAL) begin
            joy_timer <= 0;
            joy1_reg <= joy1;
            joy2_reg <= joy2;
        end

        // UART transmission state machine
        case (send_state)
            SEND_IDLE: begin
                if (joy_timer >= JOY_UPDATE_INTERVAL) begin
                    send_state <= SEND_JOYPAD;
                    send_idx <= 0;
                end else if (send_config_string_req != send_config_string_ack) begin
                    send_state <= SEND_CONFIG_STRING;
                    send_idx <= 0;
                end
            end

            SEND_CONFIG_STRING: begin
                if (tx_ready && ~tx_valid) begin
                    if (send_idx == STR_LEN) begin
                        tx_data <= 8'h00;  // Null terminator
                        tx_valid <= 1;
                        send_state <= SEND_IDLE;
                        send_config_string_ack <= send_config_string_req;
                    end else begin
                        tx_data <= CONF_STR[8*(STR_LEN - send_idx - 1) +: 8];
                        tx_valid <= 1;
                        send_idx <= send_idx + 1;
                    end
                end
            end

            SEND_JOYPAD: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= 8'h01; // Start byte
                        1: tx_data <= joy1_reg[7:0]; // Joy1 low byte
                        2: tx_data <= joy1_reg[15:8]; // Joy1 high byte
                        3: tx_data <= joy2_reg[7:0]; // Joy2 low byte
                        4: tx_data <= joy2_reg[15:8]; // Joy2 high byte
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 4) begin
                        send_state <= SEND_IDLE;
                        send_config_string_ack <= send_config_string_req;
                    end
                end
            end
        endcase
    end
end

// text display
`ifndef SIM
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .x_wr(x_wr), .y_wr(y_wr), .char_wr(char_wr),
    .we(we)
);
`endif

endmodule
