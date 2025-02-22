`timescale 1ns / 1ps

module tb_uart;
    parameter CLK_FREQ = 21_477_000;
    parameter BAUD_RATE = 2_000_000;
    parameter CLK_PERIOD = 1e9 / CLK_FREQ;
    
    reg clk;
    reg resetn;
    
    // TX signals
    reg [7:0] tx_data;
    reg tx_valid;
    wire tx_ready;
    wire txd;
    
    // RX signals
    wire [7:0] rx_data;
    wire rx_valid;
    
    // Test control
    reg [7:0] received_data;
    reg data_received;
    
    // Instantiate DUTs
    uart_tx #(
        .DIV_NUM(CLK_FREQ / 1000),
        .DIV_DEN(BAUD_RATE / 1000)
    ) u_tx (
        .clk(clk),
        .resetn(resetn),
        .data(tx_data),
        .valid(tx_valid),
        .tx(txd),
        .ready(tx_ready)
    );
    
    uart_rx #(
        .DIV_NUM(CLK_FREQ / 1000),
        .DIV_DEN(BAUD_RATE / 1000)
    ) u_rx (
        .clk(clk),
        .resetn(resetn),
        .rx(txd),
        .data(rx_data),
        .valid(rx_valid)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Main test sequence
    initial begin
        // Initialize inputs
        clk = 0;
        resetn = 0;
        tx_data = 0;
        tx_valid = 0;
        data_received = 0;
        
        // Create VCD dump file
        $dumpfile("tb_uart.vcd");
        $dumpvars(0, tb_uart);
        $dumpvars(1, tb_uart.u_tx);
        $dumpvars(1, tb_uart.u_rx);
        
        // Reset sequence
        #100;
        resetn = 1;
        #100;
        
        // Test 1: Basic transmission
        $display("[TEST 1] Sending 0x55");
        tx_data = 8'h55;
        tx_valid = 1;
        wait(tx_ready == 0); // Wait for transmission start
        tx_valid = 0;
        wait(rx_valid);
        if(rx_data !== 8'h55) $error("Test 1 failed: Received 0x%h, expected 0x55", rx_data);
        else $display("Test 1 passed");
        #1000;
        
        // Test 2: Full byte pattern
        $display("[TEST 2] Sending 0xAA");
        tx_data = 8'hAA;
        tx_valid = 1;
        wait(tx_ready == 0);
        tx_valid = 0;
        wait(rx_valid);
        if(rx_data !== 8'hAA) $error("Test 2 failed: Received 0x%h, expected 0xAA", rx_data);
        else $display("Test 2 passed");
        #1000;
        
        // Test 3: Random data test
        for(integer i = 0; i < 10; i++) begin
            logic [7:0] test_byte = $urandom();
            $display("[TEST 3.%0d] Sending 0x%h", i, test_byte);
            tx_data = test_byte;
            tx_valid = 1;
            wait(tx_ready == 0);
            tx_valid = 0;
            wait(rx_valid);
            if(rx_data !== test_byte) begin
                $error("Test 3.%0d failed: Received 0x%h, expected 0x%h", 
                      i, rx_data, test_byte);
            end
            else $display("Test 3.%0d passed", i);
            #1000;
        end
        
        // Test 4: Back-to-back transmission
        $display("[TEST 4] Back-to-back transmission test");
        fork
            begin // Receiver
                for(integer i = 0; i < 5; i++) begin
                    wait(rx_valid);
                    $display("Received byte %0d: 0x%h", i, rx_data);
                    #1;
                end
            end
            begin // Transmitter
                for(integer i = 0; i < 5; i++) begin
                    tx_data = 8'h30 + i;
                    tx_valid = 1;
                    wait(tx_ready == 0);
                    tx_valid = 0;
                    wait(tx_ready == 1);
                end
            end
        join
        
        #1000;
        $display("All tests completed");
        $finish;
    end
    
endmodule 