// 69 - Sunsoft FME-7
module Mapper69(
	input        clk,         // System clock
	input        ce,          // M2 ~cpu_clk
	input        enable,      // Mapper enabled
	input [31:0] flags,       // Cart flags
	input [15:0] prg_ain,     // prg address
	inout [21:0] prg_aout_b,  // prg address out
	input        prg_read,    // prg read
	input        prg_write,   // prg write
	input  [7:0] prg_din,     // prg data in
	inout  [7:0] prg_dout_b,  // prg data out
	inout        prg_allow_b, // Enable access to memory for the specified operation.
	input [13:0] chr_ain,     // chr address in
	inout [21:0] chr_aout_b,  // chr address out
	input        chr_read,    // chr ram read
	inout        chr_allow_b, // chr allow write
	inout        vram_a10_b,  // Value for A10 address line
	inout        vram_ce_b,   // True if the address should be routed to the internal 2kB VRAM.
	inout        irq_b,       // IRQ
	input [15:0] audio_in,    // Inverted audio from APU
	inout [15:0] audio_b,     // Mixed audio output
	inout [15:0] flags_out_b, // flags {0, 0, 0, 0, has_savestate, prg_conflict, prg_bus_write, has_chr_dout}
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? 8'hFF : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? audio : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
reg vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = {12'h0, 1'b1, 3'b0};
wire [15:0] audio;

reg [7:0] chr_bank[0:7];
reg [4:0] prg_bank[0:3];
reg [1:0] mirroring;
reg irq_countdown, irq_trigger;
reg [15:0] irq_counter;
reg [3:0] addr;
reg ram_enable, ram_select;
wire [16:0] new_irq_counter = irq_counter - {15'b0, irq_countdown};

always @(posedge clk)
if (~enable) begin
	chr_bank[0] <= 0;
	chr_bank[1] <= 0;
	chr_bank[2] <= 0;
	chr_bank[3] <= 0;
	chr_bank[4] <= 0;
	chr_bank[5] <= 0;
	chr_bank[6] <= 0;
	chr_bank[7] <= 0;
	prg_bank[0] <= 0;
	prg_bank[1] <= 0;
	prg_bank[2] <= 0;
	prg_bank[3] <= 0;
	mirroring <= 0;
	irq_countdown <= 0;
	irq_trigger <= 0;
	irq_counter <= 0;
	addr <= 0;
	ram_enable <= 0;
	ram_select <= 0;
	irq <= 0;
end else if (SaveStateBus_load) begin
	chr_bank[0]   <= SS_MAP1[ 7: 0];
	chr_bank[1]   <= SS_MAP1[15: 8];
	chr_bank[2]   <= SS_MAP1[23:16];
	chr_bank[3]   <= SS_MAP1[31:24];
	chr_bank[4]   <= SS_MAP1[39:32];
	chr_bank[5]   <= SS_MAP1[47:40];
	chr_bank[6]   <= SS_MAP1[55:48];
	chr_bank[7]   <= SS_MAP1[63:56];
	prg_bank[0]   <= SS_MAP2[ 4: 0];
	prg_bank[1]   <= SS_MAP2[ 9: 5];
	prg_bank[2]   <= SS_MAP2[14:10];
	prg_bank[3]   <= SS_MAP2[19:15];
	mirroring     <= SS_MAP2[21:20];
	irq_countdown <= SS_MAP2[   22];
	irq_trigger   <= SS_MAP2[   23];
	irq_counter   <= SS_MAP2[39:24];
	addr          <= SS_MAP2[43:40];
	ram_enable    <= SS_MAP2[   44];
	ram_select    <= SS_MAP2[   45];
	irq           <= SS_MAP2[   46];
end else if (ce) begin
	irq_counter <= new_irq_counter[15:0];
	if (irq_trigger && new_irq_counter[16]) irq <= 1;
	if (!irq_trigger) irq <= 0;

	if (prg_ain[15] & prg_write) begin
		case (prg_ain[14:13])
			0: addr <= prg_din[3:0];
			1: begin
				case(addr)
					0,1,2,3,4,5,6,7: chr_bank[addr[2:0]] <= prg_din;
					8,9,10,11:       prg_bank[addr[1:0]] <= prg_din[4:0];
					12:              mirroring <= prg_din[1:0];
					13:              {irq_countdown, irq_trigger} <= {prg_din[7], prg_din[0]};
					14:              irq_counter[7:0] <= prg_din;
					15:              irq_counter[15:8] <= prg_din;
				endcase

				if (addr == 8) {ram_enable, ram_select} <= prg_din[7:6];
			end
		endcase
	end
end

assign SS_MAP1_BACK[ 7: 0] = chr_bank[0];
assign SS_MAP1_BACK[15: 8] = chr_bank[1];
assign SS_MAP1_BACK[23:16] = chr_bank[2];
assign SS_MAP1_BACK[31:24] = chr_bank[3];
assign SS_MAP1_BACK[39:32] = chr_bank[4];
assign SS_MAP1_BACK[47:40] = chr_bank[5];
assign SS_MAP1_BACK[55:48] = chr_bank[6];
assign SS_MAP1_BACK[63:56] = chr_bank[7];
assign SS_MAP2_BACK[ 4: 0] = prg_bank[0];
assign SS_MAP2_BACK[ 9: 5] = prg_bank[1];
assign SS_MAP2_BACK[14:10] = prg_bank[2];
assign SS_MAP2_BACK[19:15] = prg_bank[3];
assign SS_MAP2_BACK[21:20] = mirroring;
assign SS_MAP2_BACK[   22] = irq_countdown;
assign SS_MAP2_BACK[   23] = irq_trigger;
assign SS_MAP2_BACK[39:24] = irq_counter;
assign SS_MAP2_BACK[43:40] = addr;
assign SS_MAP2_BACK[   44] = ram_enable;
assign SS_MAP2_BACK[   45] = ram_select;
assign SS_MAP2_BACK[   46] = irq;
assign SS_MAP2_BACK[63:47] = 17'b0; // free to be used

always begin
	casez(mirroring[1:0])
		2'b00: vram_a10 = {chr_ain[10]};    // vertical
		2'b01: vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?: vram_a10 = {mirroring[0]};   // 1 screen lower
	endcase
end

reg [4:0] prgout;
reg [7:0] chrout;

always begin
	casez(prg_ain[15:13])
		3'b011: prgout = prg_bank[0];
		3'b100: prgout = prg_bank[1];
		3'b101: prgout = prg_bank[2];
		3'b110: prgout = prg_bank[3];
		3'b111: prgout = 5'b11111;
		default: prgout = 5'bxxxxx;
	endcase

	chrout = chr_bank[chr_ain[12:10]];
end

wire ram_cs = (prg_ain[15:13] == 3'b011 && ram_select);
assign prg_aout = {ram_cs ? 4'b1111 : 4'b0000, prgout[4:0], prg_ain[12:0]};
assign prg_allow = (prg_ain >= 16'h6000) && (ram_cs ? ram_enable : !prg_write);
assign chr_allow = flags[15];
assign chr_aout = {4'b10_00, chrout, chr_ain[9:0]};
assign vram_ce = chr_ain[13];

assign audio = audio_in;

// savestate
localparam SAVESTATE_MODULES    = 2;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];
wire [63:0] SS_MAP1, SS_MAP2;
wire [63:0] SS_MAP1_BACK, SS_MAP2_BACK;	
wire [63:0] SaveStateBus_Dout_active = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1];
	
eReg_SavestateV #(SSREG_INDEX_MAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[0], SS_MAP1_BACK, SS_MAP1);  
eReg_SavestateV #(SSREG_INDEX_MAP2, 64'h0000000000000000) iREG_SAVESTATE_MAP2 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[1], SS_MAP2_BACK, SS_MAP2);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule


module SS5b_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	input  [15:0] audio_in,    // Inverted audio from APU
	output [15:0] audio_out,
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

SS5b_audio snd_5b (
	.clk(clk),
	.ce(ce),
	.enable(enable),
	.wren(wren),
	.addr_in(addr_in),
	.data_in(data_in),
	.audio_out(exp_out),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load),
	.SaveStateBus_Dout (SaveStateBus_Dout)
);

// Sunsoft 5B audio amplifies each channel logarithmicly before mixing. It's then mixed
// with APU audio (reverse polarity) and then reverses the polarity of the audio again.
// The expansion audio is much louder than APU audio, so we reduce it to 68% prior to
// mixing.

wire [15:0] exp_out;
wire [15:0] exp_adj = (|exp_out[15:14] ? 16'hFFFF : {exp_out[13:0], exp_out[1:0]});
wire [16:0] audio_mix = audio_in + (exp_adj + exp_adj[15:1]);

assign audio_out = 16'hFFFF - audio_mix[16:1];

endmodule

// Sunsoft 5B audio by Kitrinx
module SS5b_audio (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	output [15:0] audio_out,
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

reg [3:0] reg_select;

// Register bank
reg [7:0] internal[0:15];

// Register abstraction to readable wires

// Periods
wire [11:0] period_a     = {internal[1][3:0], internal[0]};
wire [11:0] period_b     = {internal[3][3:0], internal[2]};
wire [11:0] period_c     = {internal[5][3:0], internal[4]};
wire [4:0]  period_n     = internal[6][4:0];

// Enables
wire        tone_dis_a   = internal[7][0];
wire        tone_dis_b   = internal[7][1];
wire        tone_dis_c   = internal[7][2];
wire        noise_dis_a  = internal[7][3];
wire        noise_dis_b  = internal[7][4];
wire        noise_dis_c  = internal[7][5];

// Envelope
// wire        env_enable_a = internal[8][4];
 wire  [3:0] env_vol_a    = internal[8][3:0];
// wire        env_enable_b = internal[9][4];
 wire  [3:0] env_vol_b    = internal[9][3:0];
// wire        env_enable_c = internal[10][4];
 wire  [3:0] env_vol_c    = internal[10][3:0];
// wire [15:0] env_period   = {internal[12], internal[11]};
// wire        env_continue = internal[13][3];
// wire        env_attack   = internal[13][2];
// wire        env_alt      = internal[13][1];
// wire        env_hold     = internal[13][0];

reg [4:0] cycles;
reg [11:0] tone_a_cnt, tone_b_cnt, tone_c_cnt, noise_cnt;

reg [4:0] tone_a, tone_b, tone_c;

wire [12:0] tone_a_next = tone_a_cnt + 1'b1;
wire [12:0] tone_b_next = tone_b_cnt + 1'b1;
wire [12:0] tone_c_next = tone_c_cnt + 1'b1;
wire [12:0] noise_next = noise_cnt + 1'b1;

reg [16:0] noise_lfsr = 17'h1;
reg [5:0] envelope_a, envelope_b, envelope_c;

always_ff @(posedge clk)
if (~enable) begin
	internal <= '{
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0};

	{tone_a, tone_b, tone_c, envelope_a, envelope_b, envelope_c, cycles, noise_lfsr} <= 0;
	{tone_a_cnt, tone_b_cnt, tone_c_cnt, noise_cnt} <= 0;
end else if (SaveStateBus_load) begin
	internal[0 ] <= SS_MAP1[ 7: 0]; 
	internal[1 ] <= SS_MAP1[15: 8]; 
	internal[2 ] <= SS_MAP1[23:16]; 
	internal[3 ] <= SS_MAP1[31:24]; 
	internal[4 ] <= SS_MAP1[39:32]; 
	internal[5 ] <= SS_MAP1[47:40]; 
	internal[6 ] <= SS_MAP1[55:48]; 
	internal[7 ] <= SS_MAP1[63:56]; 
	internal[8 ] <= SS_MAP2[ 7: 0]; 
	internal[9 ] <= SS_MAP2[15: 8]; 
	internal[10] <= SS_MAP2[23:16]; 
	internal[11] <= SS_MAP2[31:24]; 
	internal[12] <= SS_MAP2[39:32]; 
	internal[13] <= SS_MAP2[47:40]; 
	internal[14] <= SS_MAP2[55:48]; 
	internal[15] <= SS_MAP2[63:56];
	reg_select   <= SS_MAP3[ 3: 0];
	cycles       <= SS_MAP3[ 8: 4];
	tone_a_cnt   <= SS_MAP3[20: 9];
	tone_b_cnt   <= SS_MAP3[32:21];
	tone_c_cnt   <= SS_MAP3[44:33];
	noise_cnt    <= SS_MAP3[56:45];
	tone_a       <= SS_MAP3[61:57];
	tone_b       <= SS_MAP4[ 4: 0];
	tone_c       <= SS_MAP4[ 9: 5];
	noise_lfsr   <= SS_MAP4[26:10];
	envelope_a   <= SS_MAP4[32:27];
	envelope_b   <= SS_MAP4[38:33];
	envelope_c   <= SS_MAP4[44:39];
end else if (ce) begin
	cycles <= cycles + 1'b1;

	// Write registers
	if (wren) begin
		if (addr_in[15:13] == 3'b110)  // C000
			reg_select <= data_in[3:0];
		if (addr_in[15:13] == 3'b111)  // E000
			internal[reg_select] <= data_in;
	end

	tone_a_cnt <= tone_a_next[11:0];
	tone_b_cnt <= tone_b_next[11:0];
	tone_c_cnt <= tone_c_next[11:0];

	if (tone_a_next >= period_a) begin
		tone_a_cnt <= 12'd0;
		tone_a <= tone_a + 1'b1;
	end

	if (tone_b_next >= period_b) begin
		tone_b_cnt<= 12'd0;
		tone_b <= tone_b + 1'b1;
	end

	if (tone_c_next >= period_c) begin
		tone_c_cnt <= 12'd0;
		tone_c <= tone_c + 1'b1;
	end

	// XXX: Implement modulation envelope if needed (not used in any games)
	envelope_a <= {env_vol_a, 1'b1};
	envelope_b <= {env_vol_b, 1'b1};
	envelope_c <= {env_vol_c, 1'b1};

	if (&cycles) begin
		// Advance noise LFSR every 32 cycles
		noise_cnt <= noise_next[11:0];

		if (noise_next >= period_n) begin
			noise_lfsr <= {noise_lfsr[15:0], noise_lfsr[16] ^ noise_lfsr[13]};
			noise_cnt <= 12'd0;
		end
	end

end

wire output_a, output_b, output_c;

always_comb begin
	case ({tone_dis_a, noise_dis_a})
		2'b00: output_a = noise_lfsr[0] & tone_a[4];
		2'b01: output_a = tone_a[4];
		2'b10: output_a = noise_lfsr[0];
		2'b11: output_a = 1'b0;
	endcase

	case ({tone_dis_b, noise_dis_b})
		2'b00: output_b = noise_lfsr[0] & tone_b[4];
		2'b01: output_b = tone_b[4];
		2'b10: output_b = noise_lfsr[0];
		2'b11: output_b = 1'b0;
	endcase

	case ({tone_dis_c, noise_dis_c})
		2'b00: output_c = noise_lfsr[0] & tone_c[4];
		2'b01: output_c = tone_c[4];
		2'b10: output_c = noise_lfsr[0];
		2'b11: output_c = 1'b0;
	endcase
end

assign audio_out =
	{output_a ? ss5b_amp_lut[envelope_a] : 8'h0, 5'b0} +
	{output_b ? ss5b_amp_lut[envelope_b] : 8'h0, 5'b0} +
	{output_c ? ss5b_amp_lut[envelope_c] : 8'h0, 5'b0} ;

// Logarithmic amplification table in 1.5db steps
wire [7:0] ss5b_amp_lut[0:31] = '{
	8'd0,  8'd0,  8'd1,  8'd1,  8'd1,   8'd1,   8'd2,   8'd2,
	8'd3,  8'd3,  8'd4,  8'd5,  8'd6,   8'd7,   8'd9,   8'd11,
	8'd13, 8'd15, 8'd18, 8'd22, 8'd26,  8'd31,  8'd37,  8'd44,
	8'd53, 8'd63, 8'd74, 8'd89, 8'd105, 8'd125, 8'd149, 8'd177
};

// savestate
assign SS_MAP1_BACK[ 7: 0] = internal[0 ]; 
assign SS_MAP1_BACK[15: 8] = internal[1 ]; 
assign SS_MAP1_BACK[23:16] = internal[2 ]; 
assign SS_MAP1_BACK[31:24] = internal[3 ]; 
assign SS_MAP1_BACK[39:32] = internal[4 ]; 
assign SS_MAP1_BACK[47:40] = internal[5 ]; 
assign SS_MAP1_BACK[55:48] = internal[6 ]; 
assign SS_MAP1_BACK[63:56] = internal[7 ]; 
assign SS_MAP2_BACK[ 7: 0] = internal[8 ]; 
assign SS_MAP2_BACK[15: 8] = internal[9 ]; 
assign SS_MAP2_BACK[23:16] = internal[10]; 
assign SS_MAP2_BACK[31:24] = internal[11]; 
assign SS_MAP2_BACK[39:32] = internal[12]; 
assign SS_MAP2_BACK[47:40] = internal[13]; 
assign SS_MAP2_BACK[55:48] = internal[14]; 
assign SS_MAP2_BACK[63:56] = internal[15];

assign SS_MAP3_BACK[ 3: 0] = reg_select;
assign SS_MAP3_BACK[ 8: 4] = cycles;
assign SS_MAP3_BACK[20: 9] = tone_a_cnt;
assign SS_MAP3_BACK[32:21] = tone_b_cnt;
assign SS_MAP3_BACK[44:33] = tone_c_cnt;
assign SS_MAP3_BACK[56:45] = noise_cnt;
assign SS_MAP3_BACK[61:57] = tone_a;
assign SS_MAP3_BACK[63:62] = 2'b0; // free to be used

assign SS_MAP4_BACK[ 4: 0] = tone_b;
assign SS_MAP4_BACK[ 9: 5] = tone_c;
assign SS_MAP4_BACK[26:10] = noise_lfsr;
assign SS_MAP4_BACK[32:27] = envelope_a;
assign SS_MAP4_BACK[38:33] = envelope_b;
assign SS_MAP4_BACK[44:39] = envelope_c;
assign SS_MAP4_BACK[63:45] = 19'b0; // free to be used

localparam SAVESTATE_MODULES    = 4;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];
wire [63:0] SS_MAP1, SS_MAP2, SS_MAP3, SS_MAP4;
wire [63:0] SS_MAP1_BACK, SS_MAP2_BACK, SS_MAP3_BACK, SS_MAP4_BACK;	
wire [63:0] SaveStateBus_Dout_active = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1] | SaveStateBus_wired_or[2] | SaveStateBus_wired_or[3];
	
eReg_SavestateV #(SSREG_INDEX_SNDMAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[0], SS_MAP1_BACK, SS_MAP1);  
eReg_SavestateV #(SSREG_INDEX_SNDMAP2, 64'h0000000000000000) iREG_SAVESTATE_MAP2 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[1], SS_MAP2_BACK, SS_MAP2);  
eReg_SavestateV #(SSREG_INDEX_SNDMAP3, 64'h0000000000000000) iREG_SAVESTATE_MAP3 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[2], SS_MAP3_BACK, SS_MAP3);  
eReg_SavestateV #(SSREG_INDEX_SNDMAP4, 64'h0000000000000000) iREG_SAVESTATE_MAP4 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[3], SS_MAP4_BACK, SS_MAP4);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule

// Mapper 190, Magic Kid GooGoo
// Mapper 67, Sunsoft-3
module Mapper67 (
	input        clk,         // System clock
	input        ce,          // M2 ~cpu_clk
	input        enable,      // Mapper enabled
	input [31:0] flags,       // Cart flags
	input [15:0] prg_ain,     // prg address
	inout [21:0] prg_aout_b,  // prg address out
	input        prg_read,    // prg read
	input        prg_write,   // prg write
	input  [7:0] prg_din,     // prg data in
	inout  [7:0] prg_dout_b,  // prg data out
	inout        prg_allow_b, // Enable access to memory for the specified operation.
	input [13:0] chr_ain,     // chr address in
	inout [21:0] chr_aout_b,  // chr address out
	input        chr_read,    // chr ram read
	inout        chr_allow_b, // chr allow write
	inout        vram_a10_b,  // Value for A10 address line
	inout        vram_ce_b,   // True if the address should be routed to the internal 2kB VRAM.
	inout        irq_b,       // IRQ
	input [15:0] audio_in,    // Inverted audio from APU
	inout [15:0] audio_b,     // Mixed audio output
	inout [15:0] flags_out_b, // flags {0, 0, 0, 0, has_savestate, prg_conflict, prg_bus_write, has_chr_dout}
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? 8'hFF : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = {12'h0, 1'b1, 3'b0};

reg [7:0] prg_bank_0;
reg [7:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3;
reg [1:0] mirroring;
reg irq_ack;
reg irq_enable;
reg irq_low;
reg [15:0] irq_counter;
wire mapper190 = (flags[7:0] == 190);

always @(posedge clk)
if (~enable) begin
	prg_bank_0 <= 0;
	chr_bank_0 <= 0;
	chr_bank_1 <= 0;
	chr_bank_2 <= 0;
	chr_bank_3 <= 0;
	mirroring <= 2'b00; //vertical for mapper190
	irq_counter <= 0;
	irq_enable <= 0;
	irq_low <= 0;
end else if (SaveStateBus_load) begin
	prg_bank_0 <= SS_MAP1[ 7: 0];
	chr_bank_0 <= SS_MAP1[15: 8];
	chr_bank_1 <= SS_MAP1[23:16];
	chr_bank_2 <= SS_MAP1[31:24];
	chr_bank_3 <= SS_MAP1[39:32];
	irq_counter<= SS_MAP1[55:40];
	mirroring  <= SS_MAP1[57:56];
	irq_ack    <= SS_MAP1[   58];
	irq_enable <= SS_MAP1[   59];
	irq_low    <= SS_MAP1[   60];
	irq        <= SS_MAP1[   61];
end else if (ce) begin
	irq_ack <= 1'b0;
	if ((prg_write) && (prg_ain[15])) begin// Cover all from $8000 to $FFFF to maximize compatibility
		if (!mapper190)
			casez({prg_ain[14:11],irq_low})
				5'b000_1_?: chr_bank_0 <= prg_din;
				5'b001_1_?: chr_bank_1 <= prg_din;
				5'b010_1_?: chr_bank_2 <= prg_din;
				5'b011_1_?: chr_bank_3 <= prg_din;
				5'b110_1_?: mirroring <= prg_din[1:0];
				5'b111_1_?: prg_bank_0 <= prg_din;
				5'b100_1_0: {irq_low, irq_counter[15:8]} <= {1'b1,prg_din};
				5'b100_1_1: {irq_low, irq_counter[7:0]} <= {1'b0,prg_din};
				5'b101_1_?: {irq_low, irq_ack, irq_enable} <= {2'b01, prg_din[4]};
			endcase
		else
			casez({prg_ain[13],prg_ain[1:0]})
				3'b0_??: prg_bank_0[3:0] <= {prg_ain[14],prg_din[2:0]};
				3'b1_00: chr_bank_0 <= prg_din;
				3'b1_01: chr_bank_1 <= prg_din;
				3'b1_10: chr_bank_2 <= prg_din;
				3'b1_11: chr_bank_3 <= prg_din;
			endcase
	end
	if (irq_enable) begin
		irq_counter <= irq_counter - 16'd1;
		if (irq_counter == 16'h0) begin
			irq <= 1'b1; // IRQ
			irq_enable <= 0;
		end
	end

	if (irq_ack)
		irq <= 1'b0; // IRQ ACK
end

assign SS_MAP1_BACK[ 7: 0] = prg_bank_0;
assign SS_MAP1_BACK[15: 8] = chr_bank_0;
assign SS_MAP1_BACK[23:16] = chr_bank_1;
assign SS_MAP1_BACK[31:24] = chr_bank_2;
assign SS_MAP1_BACK[39:32] = chr_bank_3;
assign SS_MAP1_BACK[55:40] = irq_counter;
assign SS_MAP1_BACK[57:56] = mirroring;
assign SS_MAP1_BACK[   58] = irq_ack;
assign SS_MAP1_BACK[   59] = irq_enable;
assign SS_MAP1_BACK[   60] = irq_low;
assign SS_MAP1_BACK[   61] = irq;
assign SS_MAP1_BACK[63:62] = 2'b0; // free to be used

always begin
	casez({mirroring})
		2'b00   :   vram_a10 = {chr_ain[10]};    // vertical
		2'b01   :   vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?   :   vram_a10 = {mirroring[0]};   // 1 screen lower:upper
	endcase
end

reg [7:0] prgsel;
always begin
	case(prg_ain[14])
	1'b0: prgsel = prg_bank_0;                // $8000 is swapable
	1'b1: prgsel = mapper190 ? 8'h00 : 8'hFF; // $C000 is hardwired to first/last bank
	endcase
end

reg [7:0] chrsel;
always begin
	casez(chr_ain[12:11])
		0: chrsel = chr_bank_0;
		1: chrsel = chr_bank_1;
		2: chrsel = chr_bank_2;
		3: chrsel = chr_bank_3;
	endcase
end

assign chr_aout = {3'b10_0, chrsel, chr_ain[10:0]};             //  2kB banks

wire [21:0] prg_aout_tmp = {2'b00, prgsel[5:0], prg_ain[13:0]}; // 16kB banks
wire prg_is_ram = (prg_ain >= 'h6000) && (prg_ain < 'h8000);
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};

assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;

assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;
assign chr_allow = flags[15];
assign vram_ce = chr_ain[13];

// savestate
wire [63:0] SS_MAP1;
wire [63:0] SS_MAP1_BACK;	
wire [63:0] SaveStateBus_Dout_active;	
eReg_SavestateV #(SSREG_INDEX_MAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_Dout_active, SS_MAP1_BACK, SS_MAP1);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule


// #68 - Sunsoft-4 - Game After Burner, and some japanese games. MAX: 128kB PRG, 256kB CHR
module Mapper68(
	input        clk,         // System clock
	input        ce,          // M2 ~cpu_clk
	input        enable,      // Mapper enabled
	input [31:0] flags,       // Cart flags
	input [15:0] prg_ain,     // prg address
	inout [21:0] prg_aout_b,  // prg address out
	input        prg_read,    // prg read
	input        prg_write,   // prg write
	input  [7:0] prg_din,     // prg data in
	inout  [7:0] prg_dout_b,  // prg data out
	inout        prg_allow_b, // Enable access to memory for the specified operation.
	input [13:0] chr_ain,     // chr address in
	inout [21:0] chr_aout_b,  // chr address out
	input        chr_read,    // chr ram read
	inout        chr_allow_b, // chr allow write
	inout        vram_a10_b,  // Value for A10 address line
	inout        vram_ce_b,   // True if the address should be routed to the internal 2kB VRAM.
	inout        irq_b,       // IRQ
	input [15:0] audio_in,    // Inverted audio from APU
	inout [15:0] audio_b,     // Mixed audio output
	inout [15:0] flags_out_b, // flags {0, 0, 0, 0, has_savestate, prg_conflict, prg_bus_write, has_chr_dout}
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? 8'hFF : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? 1'b0 : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire ram_enable;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg [15:0] flags_out = {12'h0, 1'b1, 3'b0};

reg [6:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3;
reg [6:0] nametable_0, nametable_1;
reg [3:0] prg_bank;
reg use_chr_rom;
reg [1:0] mirroring;

always @(posedge clk)
if (~enable) begin
	chr_bank_0 <= 0;
	chr_bank_1 <= 0;
	chr_bank_2 <= 0;
	chr_bank_3 <= 0;
	nametable_0 <= 0;
	nametable_1 <= 0;
	prg_bank <= 0;
	ram_enable <= 0;
	use_chr_rom <= 0;
	mirroring <= 0;
end else if (SaveStateBus_load) begin
	chr_bank_0 <= SS_MAP1[ 6: 0];
	chr_bank_1 <= SS_MAP1[13: 7];
	chr_bank_2 <= SS_MAP1[20:14];
	chr_bank_3 <= SS_MAP1[27:21];
	nametable_0<= SS_MAP1[34:28];
	nametable_1<= SS_MAP1[41:35];
	prg_bank   <= SS_MAP1[45:42];
	use_chr_rom<= SS_MAP1[   46];
	mirroring  <= SS_MAP1[48:47];
end else if (ce) begin
	if (prg_ain[15] && prg_write) begin
		case(prg_ain[14:12])
			0: chr_bank_0  <= prg_din[6:0]; // $8000-$8FFF: 2kB CHR bank at $0000
			1: chr_bank_1  <= prg_din[6:0]; // $9000-$9FFF: 2kB CHR bank at $0800
			2: chr_bank_2  <= prg_din[6:0]; // $A000-$AFFF: 2kB CHR bank at $1000
			3: chr_bank_3  <= prg_din[6:0]; // $B000-$BFFF: 2kB CHR bank at $1800
			4: nametable_0 <= prg_din[6:0]; // $C000-$CFFF: 1kB Nametable register 0 at $2000
			5: nametable_1 <= prg_din[6:0]; // $D000-$DFFF: 1kB Nametable register 1 at $2400
			6: {use_chr_rom, mirroring} <= {prg_din[4], prg_din[1:0]}; // $E000-$EFFF: Nametable control
			7: {ram_enable, prg_bank} <= prg_din[4:0]; // $F000-$FFFF: 16kB PRG banks at $8000-$BFFF and WRAM enable
		endcase
	end
end

assign SS_MAP1_BACK[ 6: 0] = chr_bank_0;
assign SS_MAP1_BACK[13: 7] = chr_bank_1;
assign SS_MAP1_BACK[20:14] = chr_bank_2;
assign SS_MAP1_BACK[27:21] = chr_bank_3;
assign SS_MAP1_BACK[34:28] = nametable_0;
assign SS_MAP1_BACK[41:35] = nametable_1;
assign SS_MAP1_BACK[45:42] = prg_bank;
assign SS_MAP1_BACK[   46] = use_chr_rom;
assign SS_MAP1_BACK[48:47] = mirroring;
assign SS_MAP1_BACK[63:49] = 15'b0; // free to be used

// $C000-$FFFF wired to last PRG bank
wire [3:0] prgout = ((prg_ain[15:14] == 2'b11) ? 4'b1111 : prg_bank);
wire prg_is_ram = (prg_ain[15:13] == 3'b011);
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
assign prg_aout = prg_is_ram ? prg_ram : {4'b00_00, prgout, prg_ain[13:0]};
assign prg_allow = (prg_ain[15] && !prg_write) || (prg_is_ram && ram_enable);

reg [6:0] chrout;
always begin
	casez(chr_ain[12:11])
		0: chrout = chr_bank_0;
		1: chrout = chr_bank_1;
		2: chrout = chr_bank_2;
		3: chrout = chr_bank_3;
	endcase
end

always begin
	casez(mirroring[1:0])
		2'b00: vram_a10 = {chr_ain[10]};    // vertical
		2'b01: vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?: vram_a10 = {mirroring[0]};   // 1 screen lower
	endcase
end

wire [6:0] nameout = (vram_a10 == 0) ? nametable_0 : nametable_1;

assign chr_allow = flags[15];
assign chr_aout = (chr_ain[13] == 0) ? {4'b10_00, chrout, chr_ain[10:0]} : {5'b10_001, nameout, chr_ain[9:0]};
assign vram_ce = chr_ain[13] && !use_chr_rom;

// savestate
wire [63:0] SS_MAP1;
wire [63:0] SS_MAP1_BACK;	
wire [63:0] SaveStateBus_Dout_active;	
eReg_SavestateV #(SSREG_INDEX_MAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_Dout_active, SS_MAP1_BACK, SS_MAP1);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule