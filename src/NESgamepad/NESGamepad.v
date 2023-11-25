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
	parameter DIVIDER_EXPONENT_60Hz = 225000;	
	parameter DIVIDER_EXPONENT_12uS = 324;	
	parameter COUNTER_ENABLE_12uS_CLOCK = 449713;	

	// Keep track of the stage of the cycle
	reg [(NUMBER_OF_STATES-1):0] cycle_stage;	// Latch 12uS -> Wait 6uS -> Data 8x12uS -> End
	reg [7:0] data;
	reg [19:0] clock_counter_60Hz;
	reg [10:0] clock_counter_12uS;
	reg [19:0] clock_enable_counter_12uS;
	wire clock_60Hz;
	wire clock_12uS;

	// Generate control signals for the three phases
	// wire latch_phase = cycle_stage[0];
	wire latch_phase = cycle_stage[0];
	wire data_phase = (!cycle_stage[0] & !cycle_stage[NUMBER_OF_STATES-2] & !cycle_stage[NUMBER_OF_STATES-1]) ? 1 : 0;
	wire write_phase = (cycle_stage[NUMBER_OF_STATES-2]);
	wire end_phase = (cycle_stage[NUMBER_OF_STATES-1]);
	assign o_data_available = (cycle_stage[NUMBER_OF_STATES-1]);

	// Generate a clock for generating the data clock and sampling the controller's output
    initial cycle_stage = 1;
	initial data = 0;
	initial clock_counter_60Hz = 0;
	initial clock_counter_12uS = 0;

	// Handle 60Hz clock counter - Sample every 60Hz
	always @(posedge i_clk) begin
		if(i_rst) begin
			clock_counter_60Hz <= 0;
		end else begin
			if(clock_counter_60Hz <= (2 * DIVIDER_EXPONENT_60Hz)) begin
				clock_counter_60Hz <= clock_counter_60Hz + 1;
			end else
				clock_counter_60Hz <= 0;
		end
	end

	// Handle 60Hz clock
	assign clock_60Hz = clock_counter_60Hz <= DIVIDER_EXPONENT_60Hz;

	// Handle 12uS clock counter
	always @(posedge i_clk) begin
		if(i_rst) begin
			clock_counter_12uS <= 0;
		end else begin
			if(clock_counter_12uS <= (2 * DIVIDER_EXPONENT_12uS)) begin
				clock_counter_12uS <= clock_counter_12uS + 1;
			end else
				clock_counter_12uS <= 0;
		end
	end

	// Handle 12uS clock enable
	always @(posedge i_clk) begin
		if(i_rst) begin
			clock_enable_counter_12uS <= 0;
		end else begin
			if(clock_counter_12uS < (2 * COUNTER_ENABLE_12uS_CLOCK)) begin
				clock_enable_counter_12uS <= clock_enable_counter_12uS + 1;
			end else begin
				clock_enable_counter_12uS <= 0;
			end
		end
	end

	// Handle 12uS clock
	assign clock_12uS = (clock_counter_60Hz <= DIVIDER_EXPONENT_12uS);
//	assign clock_12uS = (clock_counter_60Hz <= DIVIDER_EXPONENT_12uS) & (clock_enable_counter_12uS < (2 * 11 * DIVIDER_EXPONENT_12uS));

	// Handle cycle_stage - depending on clock_12uS
	always @(posedge clock_12uS) begin
		if(i_rst) begin
			cycle_stage <= 1;
		end else begin
			cycle_stage <= cycle_stage + 1;
		end
	end

	// Handle button output
	always @(posedge clock_12uS) begin
		if(i_rst) begin
			data <= 1;
		end else begin
			if(latch_phase) begin
				data <= 0;
			end else if(data_phase) begin 
				data <= {i_serial_data, data[7:1]};
			end else if(write_phase) begin
				o_button_state <= data;
			end
		end
	end


	// Assign outputs
	assign o_data_latch = latch_phase;
	assign o_data_clock = clock_12uS;

	//
	// Formal verification
	//
	`ifdef	FORMAL
		always @(*) begin
			if(latch_phase) begin
				assert( (latch_phase != data_phase) );
				assert( (latch_phase != end_phase) );
			end
			if(data_phase) begin
				assert( (data_phase != latch_phase) );
				assert( (data_phase != end_phase) );
			end
			if(end_phase) begin
				assert( (end_phase != latch_phase) );
				assert( (end_phase != latch_phase) );
			end
		end

		always @(*)
			assert((latch_counter <= LATCH_12US_CYCLES) || (latch_counter == 32'hFFFF_FFFF));
		
		// always @(posedge i_clk) begin
		// 	if (i_rst) begin
		// 		assert(sample_count == 0);
		// 		assert(latch_counter == 0);
		// 	end
		// end

		always @(posedge sample_clock) begin
			if (i_rst) begin
				assert(data == 0);
				assert(cycle_stage == 1);
			end
		end
				

		reg	f_valid_state;
		always @(*) begin
			f_valid_state = 0;
			case(cycle_stage)
				10'h01: f_valid_state = 1'b1;
				10'h02: f_valid_state = 1'b1;
				10'h04: f_valid_state = 1'b1;
				10'h08: f_valid_state = 1'b1;
				10'h10: f_valid_state = 1'b1;
				10'h20: f_valid_state = 1'b1;
				10'h40: f_valid_state = 1'b1;
				10'h80: f_valid_state = 1'b1;
				10'h100: f_valid_state = 1'b1;
				10'h200: f_valid_state = 1'b1;
			endcase
			assert(f_valid_state);
		end

	`endif


endmodule