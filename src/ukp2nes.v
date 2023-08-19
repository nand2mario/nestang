// Original author: hi631@github
// https://github.com/hi631/tang-nano-9K

module ukp2nes (
    input   usbclk,		// 12MHz
    input   usbrst_n,	// reset
	inout	usb_dm, usb_dp,
	output reg [7:0] btn_nes,
	output reg btn_x, btn_y,				// for auto-fire
	output reg [63:0] dbg_hid_report,		// last HID report
	output reg [15:0] dbg_vid,
	output reg [15:0] dbg_pid,
	output [3:0] dbg_dev,
    output conerr
);

wire dtrdy, dtstb;		// data ready and strobe
wire [7:0] ukpdat;		// actual data
wire vidpid;			    // last vid/pid was valid
//wire conerr;			// connection error
ukp ukp(
	.usbrst_n(usbrst_n), .usbclk(usbclk),
	.usb_dp(usb_dp), .usb_dm(usb_dm), .usb_oe(),
	.ukprdy(dtrdy), .ukpstb(dtstb), .ukpdat(ukpdat), .vidpid(vidpid),
	.conerr(conerr) );

reg  [3:0] rcvct;		// counter for recv data
reg  dtstbd, dtrdyd;	// delayed dtstb and dtrdy
reg [15:0] tmp_vid, tmp_pid;		// temporary VID and PID

// Device types, see vidpid_recognition below
localparam D_GENERIC = 0;
localparam D_GAMEPAD = 1;			
localparam D_DS2_ADAPTER = 2;

reg [3:0] dev = D_GENERIC;			// device type recognized through VID/PID
assign dbg_dev = dev;
reg valid = 0;					    // whether current scancode is valid

reg  btn_a, btn_b, btn_sel, btn_sta;
reg  btn_al, btn_ar, btn_ad, btn_au;	// left, right, down, up

always @(posedge usbclk) begin : process_in_data
	dtrdyd <= dtrdy; dtstbd <= dtstb;
	if(~dtrdy) rcvct <= 0;
	else begin
		if(dtstb && ~dtstbd) begin
			case(rcvct)
				0: begin
					tmp_vid[7:0] <= ukpdat;		// collect VID/PID from the device descriptor
					dbg_hid_report[7:0] <= ukpdat;
				end
				1: begin
					tmp_vid[15:8] <= ukpdat;
					dbg_hid_report[15:8] <= ukpdat;
				end
				2: begin
					tmp_pid[7:0] <= ukpdat;
					dbg_hid_report[23:16] <= ukpdat;
				end
				3: begin
					tmp_pid[15:8] <= ukpdat;
					dbg_hid_report[31:24] <= ukpdat;
				end
				4: dbg_hid_report[39:32] <= ukpdat;
				5: dbg_hid_report[47:40] <= ukpdat;
				6: dbg_hid_report[55:48] <= ukpdat;
				7: dbg_hid_report[63:56] <= ukpdat;
			endcase
			// Generic gamepad handling. 
			// A typical scheme:
			// - d[3] is X axis (0: left, 255: right)
			// - d[4] is Y axis
			// - d[5][7:4] is buttons YBAX
			// - d[6][5:4] is buttons START,SELECT
			// Variations:
			// - Some gamepads uses d[0] and d[1] for X and Y axis.
			// - Some transmits a different set when d[0][1:0] is 2 (a dualshock adapater)
			case (rcvct)
			0: begin
				if (ukpdat[1:0] != 2'b10) begin
					// for DualShock2 adapter, 2'b10 marks an irrelevant record
					valid <= 1;
					btn_al <= 0; btn_ar <= 0; btn_au <= 0; btn_ad <= 0;
				end else
					valid <= 0;
				if (ukpdat==8'h00) {btn_al, btn_ar} <= 2'b10;
				if (ukpdat==8'hff) {btn_al, btn_ar} <= 2'b01;
			end
			1: begin
				if (ukpdat==8'h00) {btn_au, btn_ad} <= 2'b10;
				if (ukpdat==8'hff) {btn_au, btn_ad} <= 2'b01;
			end
			3: if (valid) begin 
				if (ukpdat[7:6]==2'b00) {btn_al, btn_ar} <= 2'b10;
				if (ukpdat[7:6]==2'b11) {btn_al, btn_ar} <= 2'b01;
			end
			4: if (valid) begin 
				if (ukpdat[7:6]==2'b00) {btn_au, btn_ad} <= 2'b10;
				if (ukpdat[7:6]==2'b11) {btn_au, btn_ad} <= 2'b01;
			end
			5: if (valid) begin
				btn_x <= ukpdat[4];
				btn_a <= ukpdat[5];
				btn_b <= ukpdat[6];
				btn_y <= ukpdat[7];
			end
			6: if (valid) begin
				btn_sel <= ukpdat[4];
				btn_sta <= ukpdat[5];
			end
			endcase
			// TODO: add any special handling if needed 
			// (using the detected controller type in 'dev')

			rcvct <= rcvct + 1;
		end
	end
		if(~dtrdy && dtrdyd) btn_nes <= {btn_ar,btn_al,btn_ad,btn_au,btn_sta,btn_sel,btn_b,btn_a};
end

always @(posedge usbclk) begin : vidpid_recognition
	if (vidpid) begin
		dbg_vid <= tmp_vid;
		dbg_pid <= tmp_pid;
		case({tmp_vid, tmp_pid})
		32'h081F_E401:		// "Gamepad" - snes-style gamepad
			dev <= D_GAMEPAD;
		32'h0810_0001:		// "Twin USB Joystick" - DS2 USB adapter
			dev <= D_DS2_ADAPTER;
		default:
			dev <= D_GENERIC;
		endcase
	end
end

endmodule

module ukp(
	input usbrst_n,
	input usbclk,				// 12MHz clock
	inout usb_dp, usb_dm,		// D+, D-
	output usb_oe,
	output reg ukprdy, 			// data frame is outputing
	output ukpstb,				// strobe for a byte within the frame
	output reg [7:0] ukpdat,	// output data when ukpstb=1
	output reg vidpid,			// VID/PID in last response is valid
	output conerr
);

	parameter S_OPCODE = 0;
	parameter S_LDI0 = 1;
	parameter S_LDI1 = 2;
	parameter S_B0 = 3;
	parameter S_B1 = 4;
	parameter S_B2 = 5;
	parameter S_S0 = 6;
	parameter S_S1 = 7;
	parameter S_S2 = 8;
	parameter S_TOGGLE0 = 9;

	wire [3:0] inst;
	reg  [3:0] insth;
	wire sample;						// 1: an IN sample is available
	reg connected = 0, inst_ready = 0, up = 0, um = 0, cond = 0, nak = 0, dmis = 0;
	reg ug, ugw, nrzon;					// ug=1: output enabled, 0: hi-Z
	reg bank = 0, record1 = 0;
	reg [1:0] mbit = 0;					// 1: out4/outb is transmitting
	reg [3:0] state = 0, stated;
	reg [7:0] wk = 0;					// W register
	reg [7:0] sb = 0;					// out value
	reg [3:0] sadr;						// out4/outb write ptr
	reg [13:0] pc = 0, wpc;				// program counter, wpc = next pc
	reg [2:0] timing = 0;				// T register (0~7)
	reg [3:0] lb4 = 0, lb4w;
	reg [13:0] interval = 0;
	reg [6:0] bitadr = 0;				// 0~127
	reg [7:0] data = 0;					// received data
	reg [2:0] nrztxct, nrzrxct;			// NRZI trans/recv count for bit stuffing
	wire interval_cy = interval == 12001;
	wire next = ~(state == S_OPCODE & (
		inst ==2 & dmi |								// start
		(inst==4 || inst==5) & timing != 0 |			// out0/hiz
		inst ==13 & (~sample | (dpi | dmi) & wk != 1) |	// in 
		inst ==14 & ~interval_cy						// wait
	));
	wire branch = state == S_B1 & cond;
	wire retpc  = state == S_OPCODE && inst==7  ? 1 : 0;
	wire jmppc  = state == S_OPCODE && inst==15 ? 1 : 0;
	wire dbit   = sb[7-sadr[2:0]];
	wire record;
	reg  dmid;
	reg [23:0] conct;
	wire conerr = conct[23] || ~usbrst_n;;

	ukprom ukprom(.clk(usbclk), .adr(pc), .data(inst));

	always @(posedge usbclk) begin
		if(~usbrst_n) begin 
			pc <= 0; connected <= 0; cond <= 0; inst_ready <= 0; state <= S_OPCODE; timing <= 0; 
			mbit <= 0; bitadr <= 0; nak <= 1; ug <= 0;
		end else begin
			dpi <= usb_dp; dmi <= usb_dm;
			vidpid <= 0;		// ensure pulse
			if (inst_ready) begin
				// Instruction decoding
				case(state)
					S_OPCODE: begin
						insth <= inst;
						if(inst==1) state <= S_LDI0;						// op=ldi
						if(inst==3) begin sadr <= 3; state <= S_S0; end		// op=out4
						if(inst==4) begin ug <= 9; up <= 0; um <= 0; end
						if(inst==5) begin ug <= 0; end
						if(inst==6) begin sadr <= 7; state <= S_S0; end		// op=outb
						if (inst[3:2]==2'b10) begin							// op=10xx(BZ,BC,BNAK,DJNZ)
							state <= S_B0;
							case (inst[1:0])
								2'b00: cond <= ~dmi;
								2'b01: cond <= connected;
								2'b10: cond <= nak;
								2'b11: cond <= wk != 1;
							endcase
						end
						if(inst==11 | inst==13 & sample) wk <= wk - 8'd1;	// op=DJNZ,IN
						if(inst==15) begin state <= S_B2; cond <= 1; end	// op=jmp
						if(inst==12) state <= S_TOGGLE0;
					end
					// Instructions with operands
					// ldi
					S_LDI0: begin	wk[3:0] <= inst; state <= S_LDI1;	end
					S_LDI1: begin	wk[7:4] <= inst; state <= S_OPCODE; end
					// branch/jmp
					S_B2: begin lb4w <= inst; state <= S_B0; end
					S_B0: begin lb4  <= inst; state <= S_B1; end
					S_B1: state <= S_OPCODE;
					// out
					S_S0: begin sb[3:0] <= inst; state <= S_S1; end
					S_S1: begin sb[7:4] <= inst; state <= S_S2; mbit <= 1; end
					// toggle and vidpid
					S_TOGGLE0: begin 
						if (inst == 1) connected <= ~connected;			// toggle
						else vidpid <= 1;                               // vidpid
						state <= S_OPCODE;
  					end
				endcase
				// pc control
				if (mbit==0) begin 
					if(jmppc) wpc <= pc + 4;
					if (next | branch | retpc) begin
						if(retpc) pc <= wpc;					// ret
						else if(branch)
							if(insth==15)						// jmp
								pc <= { inst, lb4, lb4w, 2'b00 };
							else								// branch
								pc <= { 4'b0000, inst, lb4, 2'b00 };
						else	pc <= pc + 1;					// next
						inst_ready <= 0;
					end
				end
			end
			else inst_ready <= 1;
			// bit transmission (out4/outb)
			if (mbit==1 && timing == 0) begin
				if(ug==0) nrztxct <= 0;
				else
					if(dbit) nrztxct <= nrztxct + 1;
					else     nrztxct <= 0;
				if(insth == 4'd6) begin
					if(nrztxct!=6) begin up <= dbit ?  up : ~up; um <= dbit ? ~up :  up; end
					else           begin up <= ~up; um <= up; nrztxct <= 0; end
				end else begin
					up <=  sb[{1'b1,sadr[1:0]}]; um <= sb[sadr[2:0]];
				end
				ug <= 1'b1; 
				if(nrztxct!=6) sadr <= sadr - 4'd1;
				if(sadr==0) begin mbit <= 0; state <= S_OPCODE; end
			end
			// start instruction
			dmid <= dmi;
			if (inst_ready & state == S_OPCODE & inst == 4'b0010) begin // op=start 
				bitadr <= 0; nak <= 1; nrzrxct <= 0;
			end else 
				if(ug==0 && dmi!=dmid) timing <= 1;
				else                   timing <= timing + 1;
			// IN instruction
			if (sample) begin
				if (bitadr == 8) nak <= dmi;
				if(nrzrxct!=6) begin
					data[6:0] <= data[7:1]; 
					data[7] <= dmis ~^ dmi;		// ~^/^~ is XNOR, basically testing bit equality
					bitadr <= bitadr + 1; nrzon <= 0;
				end else nrzon <= 1;
				dmis <= dmi;
				if(dmis ~^ dmi) nrzrxct <= nrzrxct + 1;
				else           nrzrxct <= 0;
			end
			if(ug==0) begin
				if(bitadr==24) ukprdy <= 1;			// ignore first 3 bytes
				if(bitadr==88) ukprdy <= 0;			// output next 8 bytes
			end
			if((bitadr>11 & bitadr[2:0] == 3'b000) & (timing == 2)) ukpdat <= data;
			// Timing
			interval <= interval_cy ? 0 : interval + 1;
			record1 <= record;
			if (~record & record1) bank <= ~bank;
			// Connection status & WDT
			ukprdyd <= ukprdy;
			if(ukprdy && ~ukprdyd) conct <= 0; 
			else begin 
				if(conct[23:22]!=2'b11) conct <= conct + 1;
				else begin pc <= 0; conct <= 0; end		// !! WDT ON
			end 
		end
	end

	assign usb_dp = ug ? up : 1'bZ;
	assign usb_dm = ug ? um : 1'bZ;
	assign usb_oe = ug;
	assign sample = inst_ready & state == S_OPCODE & inst == 4'b1101 & timing == 4; // IN
	assign record = connected & ~nak;
	assign ukpstb = ~nrzon & ukprdy & (bitadr[2:0] == 3'b100) & (timing == 2);
	reg       dpi, dmi; 
	reg       ukprdyd;
endmodule

