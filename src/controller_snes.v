// A self-scanning SNES/NES controller interface
module controller_snes #(
    parameter FREQ = 21_500_000         // frequency of clk
)(
    input clk,
    input resetn,
    
    // I/O interface to actual controller
    output reg joy_strb,
    output joy_clk,
    input joy_data,     // 0: button pressed, needs to be pulled up

    // Button status, 1=pressed: (R L X A RT LT DN UP START SELECT Y B)
    output reg [11:0] buttons
);

/*

https://gamefaqs.gamespot.com/snes/916396-super-nintendo/faqs/5395

       ----------------------------- ---------------------
      |                             |                      \
      | (1)     (2)     (3)     (4) |   (5)     (6)     (7) |
      |                             |                      /
       ----------------------------- ---------------------

        Pin     Description             Color of wire in cable
        ===     ===========             ======================
        1       +5v                     White
        2       Data clock              Yellow
        3       Data latch              Orange
        4       Serial data             Red
        5       ?                       no wire
        6       ?                       no wire
        7       Ground                  Brown

Every 16.67ms (or about 60Hz), the SNES CPU sends out a 12us wide, positive
going data latch pulse on pin 3. This instructs the ICs in the controller
to latch the state of all buttons internally. Six microsenconds after the
fall of the data latch pulse, the CPU sends out 16 data clock pulses on
pin 2. These are 50% duty cycle with 12us per full cycle. The controllers
serially shift the latched button states out pin 4 on every rising edge
of the clock, and the CPU samples the data on every falling edge.

        Clock Cycle     Button Reported
        ===========     ===============
        1               B
        2               Y
        3               Select
        4               Start
        5               Up on joypad
        6               Down on joypad
        7               Left on joypad
        8               Right on joypad
        9               A
        10              X
        11              L
        12              R
        13              none (always high)
        14              none (always high)
        15              none (always high)
        16              none (always high)
*/

localparam TIME_6US = FREQ / 1000000 * 6;

reg joy_clk_reg = 1;
assign joy_clk = joy_clk_reg;

reg [2:0] state;
reg [$clog2(FREQ/1000*16)-1:0] cnt;           // max 16 ms
reg [3:0] bits;
reg [15:0] buttons_buf;

localparam [1:0] LATCH = 0;
localparam [1:0] CLK_HIGH = 1;
localparam [1:0] CLK_LOW = 2;
localparam [1:0] WAIT = 3;

always @(posedge clk) begin
    if (~resetn) begin
        joy_clk_reg <= 1;
        cnt <= 0;
        state <= 0;
    end else begin
        cnt <= cnt + 1;
        case (state)
        LATCH: begin         // send 12us-wide latch
            joy_strb <= 1;
            if (cnt == TIME_6US * 2 - 1) begin
                joy_strb <= 0;
                state <= CLK_HIGH;
                cnt <= 0;
                bits <= 0;
            end
        end

        CLK_HIGH: begin         // wait 6us, then joy_clk falls, sample bit
            if (cnt == TIME_6US - 1) begin
                joy_clk_reg <= 0;
                cnt <= 0;
                state <= CLK_LOW;
                buttons_buf <= {~joy_data, buttons_buf[15:1]};       // shift right
            end
        end

        CLK_LOW: begin         // wait 6us, then joy_clk rises
            if (cnt == TIME_6US - 1) begin
                joy_clk_reg <= 1;
                cnt <= 0;
                bits <= bits + 1;
                if (bits == 4'd15) begin     // scan complete
                    state <= 3;
                    // check if buttons_buf[15:12] are 0; if not, this is an NES controller
                    if (buttons_buf[15:12] != 4'b0000) begin
                        // NES controller
                        buttons <= {0, 0, 0, 0, buttons_buf[7:0]};
                    end else begin
                        // SNES controller
                        buttons <= buttons_buf[11:0];
                    end
                end else
                    state <= 1;
            end
        end        

        WAIT:               // wait 16ms, then start again
            if (cnt == FREQ / 1000 * 16 - 1) begin
                cnt <= 0;
                state <= 0;
            end

        endcase
    end
end

endmodule