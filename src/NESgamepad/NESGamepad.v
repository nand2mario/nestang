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
	parameter NUMBER_OF_STATES = 10;
	
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
	parameter DIVIDER_EXPONENT = 13;

	// Keep track of the stage of the cycle
	reg [(NUMBER_OF_STATES-1):0] cycle_stage;
    reg [31:0] latch_counter;
	reg [7:0] data;

	// Generate control signals for the three phases
	// wire latch_phase = cycle_stage[0];
	wire latch_phase = cycle_stage[0];
	wire data_phase = (!cycle_stage[0] & !cycle_stage[NUMBER_OF_STATES-1]) ? 1 : 0;
	wire end_phase = (cycle_stage[NUMBER_OF_STATES-1]);
	assign o_data_available = (cycle_stage[NUMBER_OF_STATES-1]);

	// Generate a clock for generating the data clock and sampling the controller's output
	reg [DIVIDER_EXPONENT:0] sample_count;
	wire sample_clock = sample_count[DIVIDER_EXPONENT];

    initial cycle_stage = 1;
	initial latch_counter = 0;
	initial data = 8'h00;
	initial sample_count = 0;

	// Handle latch counter -> 0...324 * i_clk = ~12uS
	always @(posedge i_clk) begin
		if (i_rst) begin
            latch_counter <= 0;
        end else begin               
            if (latch_phase) begin
				if (latch_counter > (LATCH_12US_CYCLES - 1))
					latch_counter <= 32'h0000_0000;
                else
					latch_counter <= latch_counter + 1;
            end else if (cycle_stage > 1) begin
                latch_counter <= 32'h0000_0000;
            end else begin
                latch_counter <= 32'hFFFF_FFFF;
            end
        end
    end
	
	// Handle sample count
	always @(posedge i_clk)
		if (i_rst)
            sample_count <= 0;
		else
			sample_count <= sample_count + 1;

	// Handle button output
	always @(posedge i_clk) begin          
		// o_button_state
		if (latch_phase) begin
				o_button_state <= 0;
		end if (end_phase) begin
			o_button_state[7:0] <= data;
		end else begin
			o_button_state[7:0] <= o_button_state[7:0];
		end
	end
	
	// Handle inputs from the controller
	always @(posedge sample_clock) begin
        if (i_rst) begin
            data <= 0;
        end else begin
            if(latch_phase) begin
                data <= 8'h0;
            end else if(data_phase) begin
                // data <= {data[6:0], i_serial_data};	        // [    A       B       Select  Start   Up      Down    Left    Right   ]
                data <= {i_serial_data, data[7:1]};		        // [    Right   Left    Down    Up      Start   Select  B       A       ]
            end
        end
	end

	// Handle cycle stage
	always @(posedge sample_clock) begin
		if (i_rst) begin
            cycle_stage <= 1;
        end else begin
			// Count cycles
			if(cycle_stage == (1<<(NUMBER_OF_STATES - 1)))
				cycle_stage <= 1;
			else
				cycle_stage <= cycle_stage << 1;
		end
	end

	// Generate output signals
	assign o_data_latch = latch_phase & (latch_counter <= LATCH_12US_CYCLES);
	assign o_data_clock = data_phase & sample_clock;

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