// IOSys_bl616 - BL616-based IO system
// 
// This manages UART connection to the companion bl616 MCU, accepts ROM loading and other requests,
// and display the text overlay when needed.
// 
// Author: nand2mario, 2/2025

`define MCU_BL616

module iosys_bl616 #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1,     // 1: nestang, 2: snestang
    parameter [7:0] LOADING_STATE=0
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
    input [11:0] joy1,              // DS2/SNES joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // DS2/SNES joystick 2
    output reg [15:0] hid1,         // USB HID joystick 1
    output reg [15:0] hid2,         // USB HID joystick 2

    // ROM loading interface
    output [7:0] rom_loading,   // 0-to-1 loading starts, 1-to-0 loading is finished
    output reg [7:0] rom_do,        // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do

    // PCXT management interface
    output reg [15:0] mgmt_address,
    output reg        mgmt_read,
    input      [15:0] mgmt_readdata,
    output reg        mgmt_write,
    output reg [15:0] mgmt_writedata,
    input      [1:0]  fdd_request,      // [1]: write, [0]: read

    // Keyboard interface
    input reg  [7:0] kbd_data,
    output reg       kbd_data_valid,
    
    output reg [31:0] core_config,

    // UART interface
    input  uart_rx,
    output uart_tx
);

localparam integer STR_LEN = 73; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tangcores;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20240101";

// Remove SPI parameters and add UART parameters
localparam CLK_FREQ = FREQ;
localparam BAUD_RATE = 2_000_000;

reg overlay_reg = 1;
assign overlay = overlay_reg;

reg [7:0] rom_loading_reg = LOADING_STATE;
assign rom_loading = rom_loading_reg;

// UART receiver signals
wire [7:0] rx_data;
wire rx_valid;

// UART transmitter signals
reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;

// synchronize uart_rx to clk
reg uart_rx_r = 1, uart_rx_rr = 1;
always @(posedge clk) begin
    uart_rx_r <= uart_rx;
    uart_rx_rr <= uart_rx_r;
end

// Instantiate UART modules
async_receiver #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_receiver (
    .clk(clk),
    .RxD(uart_rx_rr),
    .RxD_data(rx_data),
    .RxD_data_ready(rx_valid)
);

async_transmitter #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_transmitter (
    .clk(clk),
    .TxD(uart_tx),
    .TxD_data(tx_data),
    .TxD_start(tx_valid),
    .TxD_busy(tx_busy)
);
assign tx_ready = ~tx_busy;

// Command processing state machine
localparam RECV_IDLE         = 7'b0000001; // waiting for command
localparam RECV_LEN1         = 7'b0000010; // receiving length msb
localparam RECV_LEN2         = 7'b0000100; // receiving length lsb
localparam RECV_CMD          = 7'b0001000; // receiving command
localparam RECV_PARAM        = 7'b0010000; // receiving parameters
localparam RECV_RESPONSE_REQ = 7'b0100000; // sending response
localparam RECV_RESPONSE_ACK = 7'b1000000; // waiting for response sending to finish 
reg [6:0] recv_state = RECV_IDLE;

// UART command buffer
reg [7:0] cmd_reg;
reg [15:0] len_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;
reg [15:0] data_cnt;
reg [3:0] kbd_len;

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

reg [7:0] response_type;
reg response_req;
reg response_ack;

// mgmt_* multiplex
reg mgmt_rx;
reg [15:0] mgmt_address_rx;
reg [15:0] mgmt_address_tx;
assign mgmt_address = mgmt_rx ? mgmt_address_rx : mgmt_address_tx;

localparam FDD_READY = 0;
localparam FDD_READ_WAIT = 1;
localparam FDD_DONE_WAIT = 2;

reg [1:0] fdd_state;
reg fdd_read_start, fdd_read_finish, fdd_write_finish;

// The TangCore bl616-fpga UART protocol
//
// Since 0.9, we've introduce a data frame to avoid spurious messages:
//
//         0xAA frame_len[15:0] payload_of_frame_len_bytes
//
// Command payloads from BL616 to FPGA:
// 0x01                       get core ID (response type 0x01, see below), frame_len = 1
// 0x02                       get core config string (response type 0x02, see below)
// 0x03 x[31:0]               set core config status
// 0x04 x[7:0] y[7:0]         move overlay text cursor to (x, y)
// 0x05 <string>              display string from cursor (len implied by frame header, =frame_len-1)
// 0x06 loading_state[7:0]    set loading state (0: core running, non-0: loading)
// 0x07 <data>                load data to rom_do (len implied by frame header)
// 0x08 x[7:0]                x[0]: turn overlay on/off
// 0x09 hid1[15:0] hid2[15:0] send USB joystick state to FPGA
// 0x0a <data_sector>         send a sector (512 bytes) of data to floppy data FIFO
// 0x0b addr[15:0] data[15:0] write to disk management interface (mgmt_address and mgmt_writedata)
// 0x0c <scancode>            send PS/2 scancode (len specified by frame header)
// 0x0d <string>              debug printf. core ignores this.
//
// Response payloads from FPGA to BL616:
// 0x01 core_id[7:0]          core ID
// 0x02 <string>              core config string (len specified by frame header)
// 0x03 joy1[15:0] joy2[15:0] every 20ms, send DS2/SNES joypad state to BL616
// 0x04 lba[15:0] <data_512>  write a sector to disk
// 0x05 lba[15:0]             read a sector from disk (followed by command 0x0a)

// UART RX: command processing
always @(posedge clk) begin
    if (!resetn) begin
        recv_state <= RECV_IDLE;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading_reg <= 0;
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
        mgmt_write <= 0;
        fdd_read_finish <= 0;
        mgmt_rx <= 0;
        kbd_data_valid <= 0;

        case (recv_state)

            RECV_IDLE: if (rx_valid && rx_data == 8'hAA) begin
                recv_state <= RECV_LEN1;
            end

            RECV_LEN1: if (rx_valid) begin
                len_reg[15:8] <= rx_data;
                if (rx_data < 8)                      // max frame length 2047
                    recv_state <= RECV_LEN2;
                else
                    recv_state <= RECV_IDLE;
            end

            RECV_LEN2: if (rx_valid) begin
                len_reg[7:0] <= rx_data;
                recv_state <= RECV_CMD;
            end

            RECV_CMD: if (rx_valid) begin
                cmd_reg <= rx_data;
                if (rx_data == 1 || rx_data == 2) 
                    recv_state <= RECV_RESPONSE_REQ;    // request sending core id / config string
                else if (len_reg > 1)
                    recv_state <= RECV_PARAM;
                else
                    recv_state <= RECV_IDLE;
                data_cnt <= 0;
            end
            
            RECV_PARAM: if (rx_valid) begin
                data_reg <= {data_reg[23:0], rx_data};
                data_cnt <= data_cnt + 1;
                // e.g. set_overlay x[7:0], the 1st param byte is the last 
                //      (data_cnt == 0, len_reg == 2)
                if (data_cnt + 2 == len_reg)
                    recv_state <= RECV_IDLE;
                
                case (cmd_reg)
                    3: begin
                        if (data_cnt == 3) begin    // Received 4 bytes
                            core_config <= {data_reg[23:0], rx_data};
                        end
                    end
                    4: case (data_cnt)              // cursor
                        0: cursor_x <= rx_data;
                        1: cursor_y <= rx_data;
                        default: ;
                    endcase
                    5: begin                        // print
                        x_wr <= cursor_x;
                        y_wr <= cursor_y;
                        char_wr <= rx_data;
                        if (cursor_x < 32) begin
                            cursor_x <= cursor_x + 1;
                            we <= 1;
                        end
                    end
                    6: begin
                        rom_loading_reg <= rx_data;
                        recv_state <= RECV_IDLE;    // Single byte command
                    end
                    7: begin
                        rom_do <= rx_data;
                        rom_do_valid <= 1;      // pulse data valid
                    end
                    8: begin
                        overlay_reg <= rx_data[0];
                    end
                    9: begin
                        case (data_cnt)
                            0: hid1[15:8] <= rx_data;
                            1: hid1[7:0] <= rx_data;
                            2: hid2[15:8] <= rx_data;
                            3: hid2[7:0] <= rx_data;
                            default: ;
                        endcase
                    end
                    'ha: begin                      // send read data to disk controller
                        mgmt_rx <= 1;
                        mgmt_address_rx <= 16'hf20f;
                        mgmt_writedata <= rx_data;
                        mgmt_write <= '1;
                        if (data_cnt == 511) 
                            fdd_read_finish <= 1;
                    end
                    'hb: begin                      // write disk controller register
                        mgmt_rx <= 1;
                        case (data_cnt)
                            0: mgmt_address_rx[15:8] <= rx_data;
                            1: mgmt_address_rx[7:0] <= rx_data;
                            2: mgmt_writedata[15:8] <= rx_data;
                            3: begin
                                mgmt_writedata[7:0] <= rx_data;
                                mgmt_write <= '1;
                            end
                            default: ;
                        endcase
                    end
                    'hc: begin                      // send PS/2 scancode to PCXT
                        kbd_data <= rx_data;
                        kbd_data_valid <= 1;
                    end
                    default: begin
                        // unknown command: consume all data and return
                    end
                endcase
            end

            RECV_RESPONSE_REQ:                      // request to send config string
                case (cmd_reg)
                    1,2: begin                      // 1: core ID, 2: config string
                        response_type <= cmd_reg;
                        response_req ^= 1;
                        recv_state <= RECV_RESPONSE_ACK;
                    end
                    default:
                        recv_state <= RECV_IDLE;
                endcase

            RECV_RESPONSE_ACK:                      // wait for TX to finish
                if (response_req == response_ack) begin
                    recv_state <= RECV_IDLE;
                end
        endcase
        
    end
end

localparam SEND_IDLE = 0;

localparam SEND_CORE_ID = 1;        // doubles as response type in message header
localparam SEND_CONFIG_STRING = 2;
localparam SEND_JOYPAD = 3;
localparam SEND_FDD_WRITE = 4;
localparam SEND_FDD_READ = 5;

localparam SEND_HEADER = 6;
localparam SEND_DONE = 7;

reg [2:0] send_state, send_state_next;
reg [$clog2(STR_LEN+1)-1:0] send_idx;
localparam JOY_UPDATE_INTERVAL = 50_000_000 / 50; // 20ms interval for 50Hz
reg [$clog2(JOY_UPDATE_INTERVAL+1)-1:0] joy_timer;
reg [15:0] joy1_reg;
reg [15:0] joy2_reg;
reg [15:0] resp_frame_len;

// UART TX: command responses, joystick updates and FDD requests
always @(posedge clk) begin
    if (!resetn) begin
        joy_timer <= 0;
        send_state <= 0;
    end else begin
        tx_valid <= 0;
        mgmt_read <= 0;
        fdd_read_start <= 0;
        fdd_write_finish <= 0;
        
        // Joypad state transmission logic
        joy_timer <= joy_timer == 0 ? 0 : joy_timer - 1;

        // UART transmission state machine
        case (send_state)
            SEND_IDLE: begin
                send_idx <= 0;
                if (joy_timer == 0 && (joy1 != joy1_reg || joy2 != joy2_reg)) begin
                    joy_timer <= JOY_UPDATE_INTERVAL;
                    joy1_reg <= joy1;
                    joy2_reg <= joy2;
                    send_state_next <= SEND_JOYPAD;
                    send_state <= SEND_HEADER;
                    resp_frame_len <= 5;
                end else if (fdd_request[1] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_WRITE;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 515;
                end else if (fdd_request[0] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_READ;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 3;
                end else if (response_req != response_ack) begin
                    if (response_type == 2) begin
                        send_state_next <= SEND_CONFIG_STRING;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= STR_LEN + 1;
                    end else if (response_type == 1) begin
                        send_state_next <= SEND_CORE_ID;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 2;
                    end
                end
            end

            SEND_HEADER: begin              // 4 byte header: 0xAA, resp_frame_len[15:0], resp_type[7:0]
                if (tx_ready && ~tx_valid) begin
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    case (send_idx[1:0])
                        0: tx_data <= 8'hAA;
                        1: tx_data <= resp_frame_len[15:8];
                        2: tx_data <= resp_frame_len[7:0];
                        3: begin
                            tx_data <= send_state_next;
                            send_state <= send_state_next;
                            send_idx <= 0;
                        end
                        default: ;
                    endcase
                end
            end

            SEND_CORE_ID: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CORE_ID[7:0];
                    tx_valid <= 1;
                    send_state <= SEND_IDLE;
                    response_ack <= response_req;
                end
            end

            SEND_CONFIG_STRING: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CONF_STR[8*(STR_LEN - send_idx - 1) +: 8];
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == STR_LEN-1) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            SEND_JOYPAD: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= joy1_reg[15:8]; // Joy1 high byte
                        1: tx_data <= joy1_reg[7:0];  // Joy1 low byte
                        2: tx_data <= joy2_reg[15:8]; // Joy2 high byte
                        3: tx_data <= joy2_reg[7:0];  // Joy2 low byte
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 3) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            // fdd write. Send {drive, sector} followed by 512 bytes data to bl616
            SEND_FDD_WRITE: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];  // sector number
                        1: begin
                            tx_data <= mgmt_readdata[7:0];  // sector number
                            mgmt_address_tx <= 16'hf20f;    // start reading FIFO data
                        end
                        default: begin 
                            tx_data <= mgmt_readdata[7:0];  // send FIFO data
                            mgmt_read <= '1;                // advance FIFO pointer
                        end
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 511+2) begin
                        send_state <= SEND_DONE;
                        response_ack <= response_req;
                        fdd_write_finish <= 1;              // notify FDD state machine
                    end
                end
            end

            // FDD read. Just second the sector number. BL616 will send the data later via command 0x0b.
            SEND_FDD_READ: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];
                        1: tx_data <= mgmt_readdata[7:0];
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 1) begin
                        send_state <= SEND_DONE;
                        response_ack <= response_req;
                        fdd_read_start <= 1;                // notify FDD state machine
                    end
                end
            end

            SEND_DONE: send_state <= SEND_IDLE;     // extra state for fdd_state to transition
        endcase
    end
end

// FDD state machine. UART TX only serves FDD requests when fdd_state == FDD_READY.
reg [3:0] fdd_cnt;
always @(posedge clk) begin
    if (!resetn) begin
        fdd_state <= FDD_READY;
    end else case (fdd_state)
        FDD_READY: begin
            if (fdd_read_start) begin
                fdd_state <= FDD_READ_WAIT;
            end else if (fdd_write_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_READ_WAIT: begin
            if (fdd_read_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_DONE_WAIT: begin            // delay 15 cycles before we serve floppy requests again
            fdd_cnt <= fdd_cnt - 1;
            if (fdd_cnt == 0) begin
                fdd_state <= FDD_READY;
            end
        end
    endcase
end

// text display
`ifndef SIM
wire [31:0] reg_char_di = {8'b0, x_wr, y_wr, char_wr};
wire [3:0] reg_char_we = {4{we}};

textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_di(reg_char_di), .reg_char_we(reg_char_we)
);
`endif

endmodule
