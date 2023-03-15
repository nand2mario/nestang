
// zf: Feed INES data to Game_Loader
module GameData (input clk, input reset, input start,
    output reg [7:0] odata, output reg odata_clk
    );

    // 24KB+ buffer for ROM
    reg [7:0] INES[131088:0];
    reg [21:0] INES_SIZE = 131088;
    initial $readmemh("game.nes.hex", INES);

    reg [1:0] state = 0;
    reg [21:0] addr = 0;
    reg out_clk = 0;

    always @(posedge clk) begin
        if (reset) begin
            state <= 0;
            addr <= 0;  // odata gets INES[0]
            odata_clk <= 0;
        end else if (start && state == 0) begin
            // start loading
            state <= 1;
        end else if (state==1) begin
            if (addr == INES_SIZE) begin
                // we've just sent the last byte
                state <= 2;     // end of data
                odata_clk <= 0;
            end else begin
                // pump data to Game_Loader
/* verilator lint_off WIDTH */
                odata <= INES[addr];
/* verilator lint_on WIDTH */
                odata_clk <= 1;
                addr <= addr + 1;
            end
        end
    end
endmodule
