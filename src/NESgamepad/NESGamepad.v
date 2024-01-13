
// NES classic gamepad based on https://github.com/michael-swan/NES-Controller-SIPO
// fjpolo, 11.2023

module NESGamepad(
		input i_clk,
        input i_rst,
		// Device connections
		output o_data_clock,
		output o_data_latch,
		input i_serial_data,
		// Data output
		output reg [7:0] o_button_state,
		output o_data_available,
        output o_test_pin
   );
	parameter NUMBER_OF_STATES = 10;    // Latch -> 2 * 6uS
										// Data -> 8 * 2 * 6uS
										// Write -> 2 * 6uS
    parameter LAST_STATE = NUMBER_OF_STATES-1;
	
	// Unit Parameters //
	parameter Hz  = 1;
	parameter KHz = 1000*Hz;
	parameter MHz = 1000*KHz;
	
	// Context-sensitive Parameters //
	parameter MASTER_CLOCK_FREQUENCY = 27*MHz; // USER VARIABLE
	parameter OUTPUT_UPDATE_FREQUENCY = 120*Hz; // USER VARIABLE
    parameter LATCH_CYCLES = (12 / 1000000) * (1 / MASTER_CLOCK_FREQUENCY);
	parameter LATCH_12US_CYCLES = 324;
	
	// Clock divider register size
	// parameter DIVIDER_EXPONENT = log2( (MASTER_CLOCK_FREQUENCY / OUTPUT_UPDATE_FREQUENCY) / 10 ) - 2;
	parameter COUNTER_60Hz = 225000;	
	parameter COUNTER_12uS = 1620;	
	parameter COUNTER_12uS_HALF = 810;	
	parameter BUSY_CYCLES = 2 * NUMBER_OF_STATES * COUNTER_12uS;	

	// Keep track of the stage of the cycle
	reg [(LAST_STATE):0] cycle_stage;	// Latch 12uS -> Wait 6uS -> Data 8x12uS -> End
	reg [7:0] data;
	reg [20:0] clock_counter_60Hz;
	reg [20:0] clock_counter_12uS;
	wire clock_60Hz;
	wire clock_12uS;

	// Generate control signals for the three states
	wire latch_state = cycle_stage[0] & (clock_counter_60Hz <= (2 * NUMBER_OF_STATES * COUNTER_12uS + NUMBER_OF_STATES));
    wire data_state = cycle_stage[1] 
                    | cycle_stage[2] 
                    | cycle_stage[3] 
                    | cycle_stage[4] 
                    | cycle_stage[5] 
                    | cycle_stage[6] 
                    | cycle_stage[7]
                    | cycle_stage[8];	
    wire write_state = cycle_stage[9];
    
    // assign o_test_pin = wait_state; // TEST

	// Generate a clock for generating the data clock and sampling the controller's output
    initial cycle_stage = 1;
	initial data = 8'h00;
	initial clock_counter_60Hz = 0;
	initial clock_counter_12uS = 0;

    // Handle 60Hz clock counter
	always @(posedge i_clk) begin
        if(i_rst) begin
			clock_counter_60Hz <= 0;
		end else begin
			if(clock_counter_60Hz < (2 * COUNTER_60Hz)) begin
				clock_counter_60Hz <= clock_counter_60Hz + 1;
			end else begin
				clock_counter_60Hz <= 0;
			end
		end
	end

	// Handle 60Hz clock counter
	always @(posedge i_clk) begin
		if(i_rst) begin
			clock_counter_12uS <= 0;
			cycle_stage <= 1;
		end else begin
				if((clock_counter_60Hz > 0) && (clock_counter_60Hz <= (2 * NUMBER_OF_STATES * COUNTER_12uS + NUMBER_OF_STATES))) begin
				if(clock_counter_12uS < (2 * COUNTER_12uS)) begin
					clock_counter_12uS <= clock_counter_12uS + 1;
				end else begin
					clock_counter_12uS <= 0;
						if(cycle_stage < (1 << LAST_STATE) && (cycle_stage != 0))
							cycle_stage <= cycle_stage << 1;
						else
							cycle_stage <= 1;
				end
			end else begin
				clock_counter_12uS <= 0;
			end
		end
	end

	// Handle 60Hz clock
	assign clock_60Hz = (clock_counter_60Hz < COUNTER_60Hz);
    
    // Test buttons
    // assign o_test_pin = (cycle_stage == (1 << 0)) && (!i_serial_data) && (clock_12uS); // Test A Button
    // assign o_test_pin = (cycle_stage == (1 << 1)) && (!i_serial_data) && (clock_12uS); // Test A Button
    // assign o_test_pin = (cycle_stage == (1 << 2)) && (!i_serial_data) && (clock_12uS); // Test B Button
    // assign o_test_pin = (cycle_stage == (1 << 3)) && (!i_serial_data) && (clock_12uS); // Test Select Button
    // assign o_test_pin = (cycle_stage == (1 << 4)) && (!i_serial_data) && (clock_12uS); // Test Start Button
    // assign o_test_pin = (cycle_stage == (1 << 5)) && (!i_serial_data) && (clock_12uS); // Test Up Button
    // assign o_test_pin = (cycle_stage == (1 << 6)) && (!i_serial_data) && (clock_12uS); // Test Down Button
    // assign o_test_pin = (cycle_stage == (1 << 7)) && (!i_serial_data) && (clock_12uS); // Test Left Button
    // assign o_test_pin = (cycle_stage == (1 << 8)) && (!i_serial_data) && (clock_12uS); // Test Right Button

	// Handle 12uS clock and button output
	always @(posedge clock_12uS) begin
		if(i_rst) begin
			data <= 0;
		end else begin
            if(latch_state) begin
                data <= 8'h00;
            end else if(data_state) begin
				// data <= {!i_serial_data, data[7:1]};
				// data <= {data[6:0], !i_serial_data};
                case(cycle_stage)
                    (1 << 1): data[0] <= !i_serial_data;    // A
                    (1 << 2): data[1] <= !i_serial_data;    // B
                    (1 << 3): data[2] <= !i_serial_data;    // Select
                    (1 << 4): data[3] <= !i_serial_data;    // Start
                    (1 << 5): data[4] <= !i_serial_data;    // Up
                    (1 << 6): data[5] <= !i_serial_data;    // Down
                    (1 << 7): data[6] <= !i_serial_data;    // Left
                    (1 << 8): data[7] <= !i_serial_data;    // Right
                endcase
			end else if(write_state) begin
				o_button_state <= data;
				// o_button_state <= 8'b0010_0000;
			end
		end
	end

	// Handle 12uS clock
	assign clock_12uS = (clock_counter_12uS > 0) && (clock_counter_12uS <= COUNTER_12uS);

	// Assign outputs
	// assign o_data_latch = (clock_counter_60Hz <= (2 * COUNTER_12uS));
	assign o_data_latch = latch_state;
    assign o_data_clock = clock_60Hz & clock_12uS & !latch_state;
	assign o_data_available = write_state;

	//
	// Formal verification
	//
	`ifdef	FORMAL

		// Clock 60Hz
		always @(*)
			assert(clock_counter_60Hz <= (2 * COUNTER_60Hz));

		// Clock 12uS
		always @(*)
			assert(clock_counter_12uS <= (2 * COUNTER_12uS));

		// Cycle stage
		reg	f_valid_state;
		always @(*) begin
			f_valid_state = 0;
			case(cycle_stage)
				9'h01: f_valid_state = 1'b1;
				9'h02: f_valid_state = 1'b1;
				9'h04: f_valid_state = 1'b1;
				9'h08: f_valid_state = 1'b1;
				9'h10: f_valid_state = 1'b1;
				9'h20: f_valid_state = 1'b1;
				9'h40: f_valid_state = 1'b1;
				9'h80: f_valid_state = 1'b1;
				9'h100: f_valid_state = 1'b1;
			endcase
			assert(f_valid_state);
		end

	`endif


endmodule