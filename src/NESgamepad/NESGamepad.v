// NES classic gamepad based on https://github.com/michael-swan/NES-Controller-SIPO
// fjpolo, 11.2023
parameter NUMBER_OF_STATES = 10;

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
	// Unit Parameters //
	parameter Hz  = 1;
	parameter KHz = 1000*Hz;
	parameter MHz = 1000*KHz;
	
	// Context-sensitive Parameters //
	parameter MASTER_CLOCK_FREQUENCY = 27*MHz; // USER VARIABLE
	parameter OUTPUT_UPDATE_FREQUENCY = 120*Hz; // USER VARIABLE
    parameter LATCH_CYCLES = (12 / 1000000) * (1 / MASTER_CLOCK_FREQUENCY);
	
	// Clock divider register size
	// parameter DIVIDER_EXPONENT = log2( (MASTER_CLOCK_FREQUENCY / OUTPUT_UPDATE_FREQUENCY) / 10 ) - 2;
	parameter DIVIDER_EXPONENT = 13;

	// Keep track of the stage of the cycle
	reg [(NUMBER_OF_STATES-1):0] cycle_stage;
    reg [31:0] latch_counter;
	reg [7:0] data;

    initial cycle_stage = 1;
	initial latch_counter = 0;

	// Generate control signals for the three phases
	// wire latch_phase = cycle_stage[0];
	wire latch_phase = cycle_stage[0];
	wire data_phase = (!cycle_stage[0] & !cycle_stage[NUMBER_OF_STATES-1]) ? 1 : 0;
	wire end_phase = (cycle_stage[NUMBER_OF_STATES-1]);
	assign o_data_available = (cycle_stage[NUMBER_OF_STATES-1]);

	// Generate a clock for generating the data clock and sampling the controller's output
	reg [DIVIDER_EXPONENT:0] sample_count;
	wire sample_clock = sample_count[DIVIDER_EXPONENT];
	always @(posedge i_clk) begin
		if (i_rst) begin
            sample_count <= 0;
            latch_counter <= 0;
        end else begin               
            if (latch_phase) begin
				o_button_state <= 0;
                latch_counter <= latch_counter + 1;
            end else if (cycle_stage > 1) begin
                latch_counter <= 32'h0000_0000;
            end else begin
                latch_counter <= 32'hFFFF_FFFF;
            end
			// o_button_state
			if (end_phase) begin
				o_button_state[7:0] <= data;
			end else begin
				o_button_state[7:0] <= o_button_state[7:0];
			end
            sample_count <= sample_count + 1;
        end
    end
	
	// Handle inputs from the controller
	always @(posedge sample_clock) begin
        if (i_rst) begin
            data <= 0;
            cycle_stage <= 1;
        end else begin
            if(latch_phase) begin
                data <= 8'h0;
            end else if(data_phase) begin
                data <= {data[6:0], i_serial_data};
            end
            // Count cycles
			if(cycle_stage == (1<<(NUMBER_OF_STATES-1)))
				cycle_stage <= 1;
			else
				cycle_stage <= cycle_stage << 1;
        end
	end

	// Generate output signals
	assign o_data_latch = latch_phase & (latch_counter <= 324);
	assign o_data_clock = data_phase & sample_clock;
endmodule