// zf: Feed INES data to Game_Loader
module GameData (
    input clk, 
    input reset, 
    output reg downloading,
    output reg [7:0] odata, 
    output reg odata_clk
);

// 24KB+ buffer for ROM
localparam INES_SIZE = 28688; // 28KB + 16
initial $readmemh("roms/nes15.hex", INES);
// localparam INES_SIZE = 24592; // 24KB + 16
// initial $readmemh("roms/helloworld.hex", INES);

reg [7:0] INES[INES_SIZE:0];
reg [1:0] state = 0;
reg [$clog2(INES_SIZE)-1:0] addr = 0;
reg out_clk = 0;

reg [1:0] cnt;

always @(posedge clk) begin
    if (reset) begin
        state <= 0;
        addr <= 0;  // odata gets INES[0]
        odata_clk <= 0;
    end else if (state == 0) begin
        // start loading
        state <= 1;
        downloading <= 1;
        cnt <= 0;
    end else if (state==1) begin
        cnt <= cnt + 1;
        odata_clk <= 0;
        case (cnt)
        2'd0: begin
            // Output one byte to Game_Loader
            odata <= INES[addr];
            odata_clk <= 1;
        end
        2'd3: begin
            if (addr == INES_SIZE-1) begin        // done
                state <= 2;
                downloading <= 0;
            end
            addr <= addr + 1;
        end
        default: ;
        endcase
    end
end

endmodule
