module usb_hid_host_rom(clk, adr, data);
	input clk;
	input [13:0] adr;
	output [3:0] data;
	reg [3:0] data; 
	reg [3:0] mem [536];
	initial $readmemh("usb_hid_host_rom.hex", mem);
	always @(posedge clk) data <= mem[adr];
endmodule
