// Simple clock divider module
// https://learn.digilentinc.com/Documents/262
// fjpolo, 11.2023

module ClockDivider_27Mto60Hz(
                        input i_clk,
                        input i_rst,
                        output reg o_clk    
                    );
     
    // Unit Parameters //
	parameter Hz  = 1;
	parameter KHz = 1000*Hz;
	parameter MHz = 1000*KHz;
    
    // Context-sensitive Parameters //
	parameter MASTER_CLOCK_FREQUENCY = 27*MHz; // USER VARIABLE
	parameter OUTPUT_UPDATE_FREQUENCY = 120*Hz; // USER VARIABLE
	parameter DIVIDER = MASTER_CLOCK_FREQUENCY / OUTPUT_UPDATE_FREQUENCY;

    // Regs
    reg [17:0] count;

    always @ (posedge(i_clk), posedge(i_rst))
    begin
        if (i_rst == 1'b1)
            count <= 18'b0;
        else if (count == DIVIDER - 1)
            count <= 18'b0;
        else
            count <= count + 1;
    end

    always @ (posedge(i_clk), posedge(i_rst))
    begin
        if (i_rst == 1'b1)
            o_clk <= 1'b0;
        else if (count == DIVIDER - 1)
            o_clk <= ~o_clk;
        else
            o_clk <= o_clk;
    end

endmodule