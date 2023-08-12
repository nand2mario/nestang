module ukp2nes (
    input   usbclk,		// 12MHz
    input   usbrst_n,	// reset
	inout	usb_dm, usb_dp,
	output reg [7:0] btn_nes,
    output conerr
);

	wire dtrdy, dtstb;
	wire [7:0] ukpdat;
	wire conerr;
	ukp ukp(
		.usbrst_n(usbrst_n), .usbclk(usbclk),
		.usb_dp(usb_dp), .usb_dm(usb_dm), .usb_oe(),
		.ukprdy(dtrdy), .ukpstb(dtstb), .ukpdat(ukpdat),
		.conerr(conerr) );

reg  [2:0] rcvct;
reg  dtstbd, dtrdyd;
reg  btn_a, btn_b, btn_sel, btn_sta;
reg  btn_al, btn_ar, btn_ad, btn_au;
always @(posedge usbclk) begin
	dtrdyd <= dtrdy; dtstbd <= dtstb;
	if(~dtrdy) rcvct <= 0;
	else begin
		if(dtstb && ~dtstbd) begin
			case(rcvct)
				3: begin
					if     (ukpdat[7:6]==2'b00) btn_ad <= 1;
					else if(ukpdat[7:6]==2'b11) btn_au <= 1;
					else begin btn_ad <= 0; btn_au <= 0; end
				end
				4: begin
					if     (ukpdat[7:6]==2'b00) btn_al <= 1;
					else if(ukpdat[7:6]==2'b11) btn_ar <= 1;
					else begin btn_al <=0; btn_ar <= 0; end
				end
				5: begin
					//if(ukpdat[4]) btn_x <= 1; else btn_x <= 0;
					if(ukpdat[5]) btn_a <= 1; else btn_a <= 0;
					if(ukpdat[6]) btn_b <= 1; else btn_b <= 0;
					//if(ukpdat[7]) btn_y <= 1; else btn_y <= 0;
				end
				6: begin 
					//if(ukpdat[0]) btn_l <= 1; else btn_l <= 0;
					//if(ukpdat[1]) btn_r <= 1; else btn_r <= 0;
					if(ukpdat[4]) btn_sel <= 1; else btn_sel <= 0;
					if(ukpdat[5]) btn_sta <= 1; else btn_sta <= 0;
				end
			endcase
			rcvct <= rcvct + 1;
		end
	end
		if(~dtrdy && dtrdyd) btn_nes <= {btn_au,btn_ad,btn_ar,btn_al,btn_sta,btn_sel,btn_b,btn_a};
end
endmodule

module ukp(
	input usbrst_n,
	input usbclk,			// 12MHz
	inout usb_dp, usb_dm,
	output usb_oe,
	output reg ukprdy, 
	output ukpstb,
	output reg [7:0] ukpdat,
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

	wire [3:0] inst;
	reg  [3:0] insth;
	wire sample;
	reg connected = 0, inst_ready = 0, up = 0, um = 0, cond = 0, nak = 0, dmis = 0;
	reg ug, ugw, nrzon;
	reg bank = 0, record1 = 0;
	reg [1:0] mbit = 0;
	reg [3:0] state = 0, stated;
	reg [7:0] wk = 0;
	reg [7:0] sb = 0;
	reg [3:0] sadr;
	reg [13:0] pc = 0, wpc;
	reg [2:0] timing = 0;
	reg [3:0] lb4 = 0, lb4w;
	reg [13:0] interval = 0;
	reg [6:0] bitadr = 0;
	reg [7:0] data = 0;
	reg [2:0] nrztxct, nrzrxct;
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
			if (inst_ready) begin
				// 命令をデコード
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
						if(inst==12) connected <= ~connected;				// op=toggle
						if(inst==15) begin state <= S_B2; cond <= 1; end	// op=jmp
					end
					// アドレス付き命令を実行
					// ldiの処理
					S_LDI0: begin	wk[3:0] <= inst; state <= S_LDI1;	end
					S_LDI1: begin	wk[7:4] <= inst; state <= S_OPCODE; end
					// branch/jmpの準備
					S_B2: begin lb4w <= inst; state <= S_B0; end
					S_B0: begin lb4  <= inst; state <= S_B1; end
					S_B1: state <= S_OPCODE;
					// outの準備
					S_S0: begin sb[3:0] <= inst; state <= S_S1; end
					S_S1: begin sb[7:4] <= inst; state <= S_S2; mbit <= 1; end
				endcase
				// pcの制御
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
			// bit送信(out4/outb)の処理
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
			// start命令の処理
			dmid <= dmi;
			if (inst_ready & state == S_OPCODE & inst == 4'b0010) begin // op=start 
				bitadr <= 0; nak <= 1; nrzrxct <= 0;
			end else 
				if(ug==0 && dmi!=dmid) timing <= 1;
				else                   timing <= timing + 1;
			// IN命令時の処理
			if (sample) begin
				if (bitadr == 8) nak <= dmi;
				if(nrzrxct!=6) begin
					data[6:0] <= data[7:1]; data[7] <= dmis ~^ dmi;
					bitadr <= bitadr + 1; nrzon <= 0;
				end else nrzon <= 1;
				dmis <= dmi;
				if(dmis ~^ dmi) nrzrxct <= nrzrxct + 1;
				else           nrzrxct <= 0;
			end
			if(ug==0) begin
				if(bitadr==24) ukprdy <= 1;
				if(bitadr==88) ukprdy <= 0;
			end
			if((bitadr>11 & bitadr[2:0] == 3'b000) & (timing == 2)) ukpdat <= data;
			// タイミング
			interval <= interval_cy ? 0 : interval + 1;
			record1 <= record;
			if (~record & record1) bank <= ~bank;
			// 接続確認 & WDT
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

