
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
		output o_data_available
   );
	parameter NUMBER_OF_STATES = 11;	// Latch -> 2 * 6uS
										// Data -> 8 * 2 * 6uS
										// Write -> 2 * 6uS
										// End -> Until next 60Hz posedge
	
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
	parameter COUNTER_12uS = 162;	
	parameter BUSY_CYCLES = 2 * NUMBER_OF_STATES * COUNTER_12uS;	

	// Keep track of the stage of the cycle
	reg [(NUMBER_OF_STATES-1):0] cycle_stage;	// Latch 12uS -> Wait 6uS -> Data 8x12uS -> End
	reg [7:0] data;
	reg [20:0] clock_counter_60Hz;
	reg [15:0] clock_counter_12uS;
	wire clock_60Hz;
	wire clock_12uS;

	// Generate control signals for the three states
	wire latch_state = cycle_stage[0];
    wire data_state = cycle_stage[1] | cycle_stage[2] | cycle_stage[3] | cycle_stage[4] | cycle_stage[5] | cycle_stage[6] | cycle_stage[7] | cycle_stage[8];	
    wire write_state = (cycle_stage[NUMBER_OF_STATES-2]);
	// wire end_state = (cycle_stage[NUMBER_OF_STATES-1]);


	// Generate a clock for generating the data clock and sampling the controller's output
    initial cycle_stage = 1;
	initial data = 0;
	initial clock_counter_60Hz = 0;
	initial clock_counter_12uS = 0;

    // Handle 60Hz clock counter
	always @(posedge i_clk) begin
        if(clock_counter_60Hz <= (2 * COUNTER_60Hz)) begin
            clock_counter_60Hz <= clock_counter_60Hz + 1;
        end else begin
            clock_counter_60Hz <= 0;
        end
	end

	// Handle 60Hz clock counter
	always @(posedge i_clk) begin
		if((clock_counter_60Hz > 0) && (clock_counter_60Hz < (2 * NUMBER_OF_STATES * COUNTER_12uS))) begin
			if(clock_counter_12uS <= (2 * COUNTER_12uS)) begin
				clock_counter_12uS <= clock_counter_12uS + 1;
			end else begin
				clock_counter_12uS <= 0;
				cycle_stage <= cycle_stage << 1;
					if(cycle_stage == 0)
						cycle_stage <= 1;
			end
		end else begin
			clock_counter_12uS <= 0;
		end
	end

	// Handle 60Hz clock
	assign clock_60Hz = (clock_counter_60Hz < COUNTER_60Hz);


	// Handle button output
	always @(posedge clock_12uS) begin
		if(i_rst) begin
			data <= 0;
		end else begin
			if(latch_state) begin
				data <= 0;
			end else if(data_state) begin 
				data <= {i_serial_data, data[7:1]};
			end else if(write_state) begin
				o_button_state <= data;
			end
		end
	end

	// Handle 12uS clock
	assign clock_12uS = (clock_counter_12uS <= COUNTER_12uS);

	// Assign outputs
	// assign o_data_latch = (clock_counter_60Hz <= (2 * COUNTER_12uS));
	assign o_data_latch = latch_state;
    assign o_data_clock = clock_60Hz & clock_12uS;
	assign o_data_available = write_state;

	//
	// Formal verification
	//
	`ifdef	FORMAL

		// Clock 60Hz
		always @(posedge i_clk)
			assert(clock_counter_60Hz < (2 * COUNTER_60Hz));

		// Clock 12uS
		always @(posedge i_clk)
			assert(clock_counter_12uS < (2 * COUNTER_12uS));

	`endif


endmodule