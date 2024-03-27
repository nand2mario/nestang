// MMC3 style mappers. Some of these can probably be consolidated.

// iNES mapper 64 and 158 - Tengen's version of MMC3
module Rambo1(
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
	input [13:0] chr_ain_o,
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;


wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = {12'h0, 1'b1, 3'b0};

reg [3:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_K;                         // Mode for CHR banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg [1:0] irq_delay;
reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
reg [7:0] chr_bank_8, chr_bank_9;
reg [5:0] prg_bank_0, prg_bank_1, prg_bank_2;  // Selected PRG banks
reg irq_cycle_mode, next_irq_cycle_mode;
reg [1:0] cycle_counter;

// Mapper has vram_a10 wired to CHR A17
//wire mapper64 = (flags[7:0] == 64);//default
wire mapper158 = (flags[7:0] == 158);

// This code detects rising edges on a12.
reg old_a12_edge;
reg [4:0] a12_ctr;
wire a12_edge = (chr_ain_o[12] && a12_ctr == 0) || old_a12_edge;
reg reload_extra = 0;
always @(posedge clk) begin
	if (SaveStateBus_load) begin
		old_a12_edge       <= SS_MAP1[   33];
		a12_ctr            <= SS_MAP1[38:34];
	end else begin
		old_a12_edge <= a12_edge && !ce;
		if (ce) begin
			if (chr_ain_o[12]) begin
				a12_ctr <= 5'd16;
			end else if (a12_ctr > 0) begin
				a12_ctr <= a12_ctr - 1'd1;
			end
		end
	end
end

always @(posedge clk)
if (~enable) begin
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_K <= 0;
	chr_a12_invert <= 0;
	reload_extra <= 0;
	mirroring <= 0;
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	{chr_bank_0, chr_bank_1} <= 0;
	{chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
	{chr_bank_8, chr_bank_9} <= 0;
	{prg_bank_0, prg_bank_1, prg_bank_2} <= 6'b111111;
	irq_cycle_mode <= 0;
	next_irq_cycle_mode <= 0;
	cycle_counter <= 0;
	irq <= 0;
	irq_delay <= 0;
end else if (SaveStateBus_load) begin
	irq                <= SS_MAP1[    0];
	cycle_counter      <= SS_MAP1[ 2: 1];
	irq_cycle_mode     <= SS_MAP1[    3];
	next_irq_cycle_mode<= SS_MAP1[    4];
	reload_extra       <= SS_MAP1[    5];
	bank_select        <= SS_MAP1[ 9: 6];
	prg_rom_bank_mode  <= SS_MAP1[   10];
	chr_a12_invert     <= SS_MAP1[   11];
	mirroring          <= SS_MAP1[   12];
	irq_enable         <= SS_MAP1[   13];
	irq_reload         <= SS_MAP1[   14];
	irq_latch          <= SS_MAP1[22:15];
	counter            <= SS_MAP1[30:23];
	irq_delay          <= SS_MAP1[32:31];
//	old_a12_edge       <= SS_MAP1[   33];
//	a12_ctr            <= SS_MAP1[38:34];
	chr_bank_0         <= SS_MAP1[46:39];
	chr_bank_1         <= SS_MAP1[54:47];
	chr_bank_2         <= SS_MAP1[62:55];
	chr_K              <= SS_MAP1[   63];
	chr_bank_3         <= SS_MAP2[ 7: 0];
	chr_bank_4         <= SS_MAP2[15: 8];
	chr_bank_5         <= SS_MAP2[23:16];
	prg_bank_0         <= SS_MAP2[29:24];
	prg_bank_1         <= SS_MAP2[35:30];
	prg_bank_2         <= SS_MAP2[41:36];
	chr_bank_8         <= SS_MAP2[49:42];
	chr_bank_9         <= SS_MAP2[57:50];
end else if (ce) begin
	// Process these before writes so irq_reload and cycle_counter register writes take precedence.
	cycle_counter <= cycle_counter + 1'd1;
	irq_cycle_mode <= next_irq_cycle_mode;

	if (irq_cycle_mode ? (cycle_counter == 3) : a12_edge) begin
		if (counter == 8'h00) begin
			counter <= irq_latch + ((irq_reload && reload_extra) ? 1'd1 : 1'd0);
			if (~|({irq_latch, ((irq_reload && reload_extra) ? 1'd1 : 1'd0)}) && irq_reload && irq_enable) begin
				irq_delay <= 1;
			end
		end else begin
			counter <= counter - 1'd1;
			if (counter == 8'h01 && irq_enable) begin
				irq_delay <= 1;
			end
		end
		irq_reload <= 0;
	end

	if (irq_delay) begin
		irq <= 1;
		irq_delay <= 0;
	end

	if (prg_write && prg_ain[15]) begin
		case({prg_ain[14:13], prg_ain[0]})
			// Bank select ($8000-$9FFE, even)
			3'b00_0: {chr_a12_invert, prg_rom_bank_mode, chr_K, bank_select} <= {prg_din[7:5], prg_din[3:0]};
			// Bank data ($8001-$9FFF, odd)
			3'b00_1:
				case (bank_select)
					0: chr_bank_0 <= prg_din;       // Select 2 (K=0) or 1 (K=1) KB CHR bank at PPU $0000 (or $1000);
					1: chr_bank_1 <= prg_din;       // Select 2 (K=0) or 1 (K=1) KB CHR bank at PPU $0800 (or $1800);
					2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
					3: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
					4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
					5: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
					6: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
					7: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					8: chr_bank_8 <= prg_din;       // If K=1, Select 1 KB CHR bank at PPU $0400 (or $1400);
					9: chr_bank_9 <= prg_din;       // If K=1, Select 1 KB CHR bank at PPU $0C00 (or $1C00)
					15: prg_bank_2 <= prg_din[5:0]; // Select 8 KB PRG ROM bank at $C000-$DFFF (or $8000-$9FFF);
				endcase
			3'b01_0: mirroring <= prg_din[0];                   // Mirroring ($A000-$BFFE, even)
			3'b01_1: begin end
			3'b10_0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
			3'b10_1: begin
						reload_extra <= |a12_ctr ? 1'd0 : 1'd1;
						{irq_reload, next_irq_cycle_mode} <= {1'b1, prg_din[0]}; // IRQ reload ($C001-$DFFF, odd)
						cycle_counter <= 0;
						counter <= 0;
					end
			3'b11_0: {irq_enable, irq} <= 2'b00;                 // IRQ disable ($E000-$FFFE, even)
			3'b11_1: {irq_enable, irq} <= 2'b10;                 // IRQ enable ($E001-$FFFF, odd)
		endcase
	end
end

assign SS_MAP1_BACK[    0] = irq;
assign SS_MAP1_BACK[ 2: 1] = cycle_counter;
assign SS_MAP1_BACK[    3] = irq_cycle_mode;
assign SS_MAP1_BACK[    4] = next_irq_cycle_mode;
assign SS_MAP1_BACK[    5] = reload_extra;
assign SS_MAP1_BACK[ 9: 6] = bank_select;
assign SS_MAP1_BACK[   10] = prg_rom_bank_mode;
assign SS_MAP1_BACK[   11] = chr_a12_invert;
assign SS_MAP1_BACK[   12] = mirroring;
assign SS_MAP1_BACK[   13] = irq_enable;
assign SS_MAP1_BACK[   14] = irq_reload;
assign SS_MAP1_BACK[22:15] = irq_latch;
assign SS_MAP1_BACK[30:23] = counter;
assign SS_MAP1_BACK[32:31] = irq_delay;
assign SS_MAP1_BACK[   33] = old_a12_edge;
assign SS_MAP1_BACK[38:34] = a12_ctr;
assign SS_MAP1_BACK[46:39] = chr_bank_0;
assign SS_MAP1_BACK[54:47] = chr_bank_1;
assign SS_MAP1_BACK[62:55] = chr_bank_2;
assign SS_MAP1_BACK[   63] = chr_K;

assign SS_MAP2_BACK[ 7: 0] = chr_bank_3;
assign SS_MAP2_BACK[15: 8] = chr_bank_4;
assign SS_MAP2_BACK[23:16] = chr_bank_5;
assign SS_MAP2_BACK[29:24] = prg_bank_0;
assign SS_MAP2_BACK[35:30] = prg_bank_1;
assign SS_MAP2_BACK[41:36] = prg_bank_2;
assign SS_MAP2_BACK[49:42] = chr_bank_8;
assign SS_MAP2_BACK[57:50] = chr_bank_9;
assign SS_MAP2_BACK[63:58] = 6'b0; // free to be used

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [5:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode})
		3'b00_0: prgsel = prg_bank_0;  // $8000 is R:6
		3'b01_0: prgsel = prg_bank_1;  // $A000 is R:7
		3'b10_0: prgsel = prg_bank_2;  // $C000 is R:F
		3'b11_0: prgsel = 6'b111111;   // $E000 fixed to last bank
		3'b00_1: prgsel = prg_bank_2;  // $8000 is R:F
		3'b01_1: prgsel = prg_bank_0;  // $A000 is R:6
		3'b10_1: prgsel = prg_bank_1;  // $C000 is R:7
		3'b11_1: prgsel = 6'b111111;   // $E000 fixed to last bank
	endcase
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [7:0] chrsel;

always @* begin
	casez({chr_ain[12] ^ chr_a12_invert, chr_ain[11], chr_ain[10], chr_K})
		4'b00?_0: chrsel = {chr_bank_0[7:1], chr_ain[10]};
		4'b01?_0: chrsel = {chr_bank_1[7:1], chr_ain[10]};
		4'b000_1: chrsel = chr_bank_0;
		4'b001_1: chrsel = chr_bank_8;
		4'b010_1: chrsel = chr_bank_1;
		4'b011_1: chrsel = chr_bank_9;
		4'b100_?: chrsel = chr_bank_2;
		4'b101_?: chrsel = chr_bank_3;
		4'b110_?: chrsel = chr_bank_4;
		4'b111_?: chrsel = chr_bank_5;
	endcase
end

assign prg_aout = {3'b00_0,  prgsel, prg_ain[12:0]};
assign {chr_allow, chr_aout} = {flags[15], 4'b10_00, chrsel, chr_ain[9:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign vram_a10 = mapper158 ? chrsel[7] :  // Mapper 158 controls mirroring by switching the top bits of the CHR address
		mirroring ? chr_ain[11] : chr_ain[10];
assign vram_ce = chr_ain[13];

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

// This mapper also handles mapper 33,47,48,74,76,80,82,88,95,118,119,154,191,192,194,195,206 and 207.
module MMC3 (
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
	input [13:0] chr_ain_o,
	input        m2_inv,
	input        paused,
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire irq;
reg [15:0] flags_out = {12'h0, 1'b1, 3'b0};

reg [2:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg [3:0] ram_enable, ram_protect;       // RAM protection bits
reg ram6_enabled, ram6_enable, ram6_protect; //extra bits for mmc6
reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg chr_bank_0_0, chr_bank_1_0;    // Keep extra bit
reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
reg [7:0] prg_bank_0, prg_bank_1, prg_bank_2;  // Selected PRG banks
reg last_a12;
wire prg_is_ram;
reg [6:0] irq_reg;
assign irq = mapper48 ? irq_reg[3] & irq_enable : irq_reg[0];
reg [7:0] m268_reg [5:0];

// The alternative behavior has slightly different IRQ counter semantics.
wire mmc3_alt_behavior = acclaim;

wire TQROM =     (flags[7:0] == 119); 	// TQROM maps 8kB CHR RAM
wire TxSROM =    (flags[7:0] == 118); 	// Connects CHR A17 to CIRAM A10
wire mapper47 =  (flags[7:0] == 47);		// Mapper 47 is a multicart that has 128k for each game. It has no RAM.
wire mapper37 =  (flags[7:0] == 37);    // European Triple Cart (Super Mario, Tetris, Nintendo World Cup)
wire DxROM =     (flags[7:0] == 206);
wire mapper112 = (flags[7:0] == 112);   // Ntdec
wire mapper48 =  (flags[7:0] == 48);    // Taito's TC0690
wire mapper33 =  (flags[7:0] == 33);    // Taito's TC0190 (TC0690-like. No IRQ. Different Mirroring bit)
wire mapper95 =  (flags[7:0] == 95);    // NAMCOT-3425
wire mapper88 =  (flags[7:0] == 88);    // NAMCOT-3433
wire mapper154 = (flags[7:0] == 154);   // NAMCOT-3453
wire mapper76 =  (flags[7:0] == 76);    // NAMCOT-3446
wire mapper80 =  (flags[7:0] == 80);    // Taito's X1-005
wire mapper82 =  (flags[7:0] == 82);    // Taito's X1-017
wire mapper207 = (flags[7:0] == 207);   // Taito's X1-017
wire mapper74 =  (flags[7:0] == 74);    // Has 2KB CHR RAM
wire mapper191 = (flags[7:0] == 191);   // Has 2KB CHR RAM
wire mapper192 = (flags[7:0] == 192);   // Has 4KB CHR RAM
wire mapper194 = (flags[7:0] == 194);   // Has 2KB CHR RAM
wire mapper195 = (flags[7:0] == 195);   // Has 4KB CHR RAM
wire mapper196 = (flags[7:0] == 196);   // PRG A0 line switcheroo
wire mapper189 = (flags[7:0] == 189);
wire MMC6 = ((flags[7:0] == 4) && (flags[24:21] == 1)); // mapper 4, submapper 1 = MMC6
wire acclaim = ((flags[7:0] == 4) && (flags[24:21] == 3)); // Acclaim mapper
wire mapper268 = ({flags[20:17],flags[7:0]} == 268); // Coolboy/Mindkids; Note: if mapper 268-256=12 was in this driver, it would need to check upper mapper bits
wire mapper268_5k = (flags[24:21] == 1);
wire oversized = mapper268;
wire gnrom;
wire lockout;
wire gnrom_lock;
wire mega_unrom;
wire weird_mode;

wire four_screen_mirroring = flags[16];// | DxROM; // not all DxROM are 4-screen
reg mapper47_multicart;
reg [2:0] mapper37_multicart;
reg [3:0] mapper189_prgsel;
wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1'd1;
reg [3:0] a12_ctr;
wire irq_support = !DxROM && !mapper33 && !mapper95 && !mapper88 && !mapper154 && !mapper76
	&& !mapper80 && !mapper82 && !mapper207 && !mapper112; //82,207 not needed
wire prg_invert_support = (irq_support && !mapper48);
wire chr_invert_support = (irq_support && !mapper48) || mapper82;
wire regs_7e = mapper80 || mapper82 || mapper207;
wire internal_128 = mapper80 || mapper207;
wire prg_reg_odd = (~mapper196) ? prg_ain[0] : ( |prg_ain[3:2] | (prg_ain[1] & ~prg_ain[14]) );

always @(posedge clk)
if (~enable) begin
	irq_reg <= 7'b0000000;
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_a12_invert <= 0;
	mirroring <= flags[14];
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	ram_enable <= {4{mapper112}};
	ram_protect <= 0;
	{chr_bank_0, chr_bank_1} <= 0;
	{chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
	{prg_bank_0, prg_bank_1} <= 0;
	prg_bank_2 <= 8'b11111110;
	a12_ctr <= 0;
	last_a12 <= 0;
	mapper37_multicart <= 3'b000;
	{m268_reg[0],m268_reg[1],m268_reg[2],m268_reg[3],m268_reg[4],m268_reg[5]} <= 0;
end else if (SaveStateBus_load) begin
	irq_reg            <= SS_MAP1[ 6: 0];
	bank_select        <= SS_MAP1[ 9: 7];
	prg_rom_bank_mode  <= SS_MAP1[   10];
	chr_a12_invert     <= SS_MAP1[   11];
	mirroring          <= SS_MAP1[   12];
	irq_enable         <= SS_MAP1[   13];
	irq_reload         <= SS_MAP1[   14];
	irq_latch          <= SS_MAP1[22:15];
	counter            <= SS_MAP1[30:23];
	ram_enable         <= SS_MAP1[34:31];
	ram_protect        <= SS_MAP1[38:35];
	chr_bank_0         <= SS_MAP1[46:39];
	chr_bank_1         <= SS_MAP1[54:47];
	chr_bank_2         <= SS_MAP1[62:55];
	chr_bank_3         <= SS_MAP2[ 7: 0];
	chr_bank_4         <= SS_MAP2[15: 8];
	chr_bank_5         <= SS_MAP2[23:16];
	prg_bank_0[5:0]    <= SS_MAP2[29:24];
	prg_bank_1[5:0]    <= SS_MAP2[35:30];
	prg_bank_2[5:0]    <= SS_MAP2[41:36];
	a12_ctr            <= SS_MAP2[45:42];
	last_a12           <= SS_MAP2[   46];
	mapper37_multicart <= SS_MAP2[49:47];
	mapper47_multicart <= SS_MAP2[   50];
	mapper189_prgsel   <= SS_MAP2[54:51];
	ram6_enabled       <= SS_MAP2[   55];
	ram6_enable        <= SS_MAP2[   56];
	ram6_protect       <= SS_MAP2[   57];
	prg_bank_0[7:6]    <= SS_MAP2[59:58];
	prg_bank_1[7:6]    <= SS_MAP2[61:60];
	prg_bank_2[7:6]    <= SS_MAP2[63:62];
	m268_reg[0]        <= SS_MAP3[ 7: 0];
	m268_reg[1]        <= SS_MAP3[15: 8];
	m268_reg[2]        <= SS_MAP3[23:16];
	m268_reg[3]        <= SS_MAP3[31:24];
	m268_reg[4]        <= SS_MAP3[39:32];
	m268_reg[5]        <= SS_MAP3[47:40];
	chr_bank_0_0       <= SS_MAP1[   48];
	chr_bank_1_0       <= SS_MAP1[   49];
end else begin
	if (ce) begin // M2
		if (!regs_7e && prg_write && prg_ain[15]) begin
			if (!mapper33 && !mapper48 && !mapper112) begin
				casez({prg_ain[14:13], prg_reg_odd})
					3'b00_0: {chr_a12_invert, prg_rom_bank_mode, ram6_enabled, bank_select} <= {prg_din[7:5], prg_din[2:0]}; // Bank select ($8000-$9FFE, even)
					3'b00_1: begin // Bank data ($8001-$9FFF, odd)
						case (bank_select)
							0: {chr_bank_0,chr_bank_0_0} <= {1'b0,prg_din};  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
							1: {chr_bank_1,chr_bank_1_0} <= {1'b0,prg_din};  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
							2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
							3: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
							4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
							5: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
							6: prg_bank_0 <= prg_din;       // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
							7: prg_bank_1 <= prg_din;       // Select 8 KB PRG ROM bank at $A000-$BFFF
						endcase
					end
					3'b01_0: mirroring <= !prg_din[0];                   // Mirroring ($A000-$BFFE, even)
					3'b01_1: {ram_enable, ram_protect, ram6_enable, ram6_protect} <= {{4{prg_din[7]}},{4{prg_din[6]}}, prg_din[5:4]}; // PRG RAM protect ($A001-$BFFF, odd)
					3'b10_0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
					3'b10_1: irq_reload <= 1;                           // IRQ reload ($C001-$DFFF, odd)
					3'b11_0: {irq_enable, irq_reg[0]} <= 2'b00;         // IRQ disable ($E000-$FFFE, even)
					3'b11_1: irq_enable <= 1;                           // IRQ enable ($E001-$FFFF, odd)
				endcase
			end else if (!mapper112) begin
				casez({prg_ain[14:13], prg_ain[1:0], mapper48})
					5'b00_00_0: {mirroring, prg_bank_0[5:0]} <= prg_din[6:0] ^ 7'h40; // Select 8 KB PRG ROM bank at $8000-$9FFF
					5'b00_00_1: prg_bank_0[5:0] <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF
					5'b00_01_?: prg_bank_1[5:0] <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					5'b00_10_?: chr_bank_0 <= prg_din;  // Select 2 KB CHR bank at PPU $0000-$07FF
					5'b00_11_?: chr_bank_1 <= prg_din;  // Select 2 KB CHR bank at PPU $0800-$0FFF
					5'b01_00_?: chr_bank_2 <= prg_din;  // Select 1 KB CHR bank at PPU $1000-$13FF
					5'b01_01_?: chr_bank_3 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
					5'b01_10_?: chr_bank_4 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
					5'b01_11_?: chr_bank_5 <= prg_din;  // Select 1 KB CHR bank at PPU $1C00-$1FFF
	
					5'b10_00_1: irq_latch <= prg_din ^ 8'hFF;              // IRQ latch ($C000-$DFFC)
					5'b10_01_1: {irq_reload, irq_reg} <= 8'b10000000;      // IRQ reload ($C001-$DFFD)
					5'b10_10_1: irq_enable <= 1;                           // IRQ enable ($C002-$DFFE)
					5'b10_11_1: irq_enable <= 0;                           // IRQ disable ($C003-$DFFF)
	
					5'b11_00_1: mirroring <= !prg_din[6];  // Mirroring
				endcase
			end else begin
				casez({prg_ain[14:13], prg_ain[0]})
					3'b00_0: {bank_select} <= {prg_din[2:0]}; // Bank select ($8000-$9FFE)
	
					3'b01_0: begin // Bank data ($A000-$BFFF)
						case (bank_select)
						0: prg_bank_0 <= prg_din;       // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
						1: prg_bank_1 <= prg_din;       // Select 8 KB PRG ROM bank at $A000-$BFFF
						2: chr_bank_0 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
						3: chr_bank_1 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
						4: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
						5: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
						6: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
						7: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
						endcase
					end
	
					3'b11_0: mirroring <= !prg_din[0];  // Mirroring ($E000-$FFFE)
				endcase
			end
	
			if (mapper154)
				mirroring <= !prg_din[6];
			if (DxROM || mapper76 || mapper88)
				mirroring <= flags[14]; // Hard-wired mirroring
		end
		else if (regs_7e && prg_write && prg_ain[15:4]==12'h7EF) begin
			casez({prg_ain[3:0], mapper82})
				5'b0000_?: chr_bank_0 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0000-$07FF
				5'b0001_?: chr_bank_1 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0800-$0FFF
				5'b0010_?: chr_bank_2 <= prg_din;  // Select 1 KB CHR bank at PPU $1000-$13FF
				5'b0011_?: chr_bank_3 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
				5'b0100_?: chr_bank_4 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
				5'b0101_?: chr_bank_5 <= prg_din;  // Select 1 KB CHR bank at PPU $1C00-$1FFF
				5'b011?_0: {mirroring} <= prg_din[0]; // Select Mirroing
				5'b100?_0: {ram_enable[3], ram_protect[3]} <= {(prg_din==8'hA3),!(prg_din==8'hA3)};  // Enable RAM at $7F00-$7FFF
				5'b0110_1: {chr_a12_invert,mirroring} <= prg_din[1:0]; // Select Mirroing
				5'b0111_1: {ram_enable[0], ram_protect[0]} <= {(prg_din==8'hCA),!(prg_din==8'hCA)};  // Enable RAM at $6000-$67FF
				5'b1000_1: {ram_enable[1], ram_protect[1]} <= {(prg_din==8'h69),!(prg_din==8'h69)};  // Enable RAM at $6F00-$6FFF
				5'b1001_1: {ram_enable[2], ram_protect[2]} <= {(prg_din==8'h84),!(prg_din==8'h84)};  // Enable RAM at $7000-$73FF  //Using 6K; Require 5K instead?
				5'b101?_0: prg_bank_0[5:0] <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF
				5'b110?_0: prg_bank_1[5:0] <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
				5'b111?_0: prg_bank_2[5:0] <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $C000-$DFFF
				5'b1010_1: prg_bank_0[5:0] <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $8000-$9FFF
				5'b1011_1: prg_bank_1[5:0] <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $A000-$BFFF
				5'b1100_1: prg_bank_2[5:0] <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $C000-$DFFF
			endcase
		end
	
		if (mapper268 && prg_write && ({mapper268_5k,prg_ain[15:12]}==5'h6 || {mapper268_5k,prg_ain[15:12]}==5'h15)) begin
			if (prg_ain[2:0]==3'h2) begin
				m268_reg[2][3:0] <= prg_din[3:0];
				if (!gnrom_lock)
					m268_reg[2][7:4] <= prg_din[7:4];
			end else if ((prg_ain[2:1]!=2'b11) && !lockout) begin
				m268_reg[prg_ain[2:0]] <= prg_din;
			end
		end
	
		// For Mapper 47
		// $6000-7FFF:  [.... ...B]  Block select
		if (prg_write && prg_is_ram)
			mapper47_multicart <= prg_din[0];
	
		// For Mapper 37
		// $6000-7FFF:  [.... .QBB]  Block select
		if (prg_write && prg_is_ram)
			mapper37_multicart <= prg_din[2:0];
	
		// Mapper 189
		// $4120-7FFF:  [AAAA BBBB] A,B:  PRG Reg
		if (prg_write && prg_ain[15:14] == 2'b01 && prg_ain[8])
			mapper189_prgsel <= (prg_din[7:4] | prg_din[3:0]); // Select 32 KB PRG ROM bank at $8000-$FFFF
	end

	if (m2_inv) begin // Inverted M2
		irq_reg[6:1] <= irq_reg[5:0]; // 4 cpu cycle delay for mapper 48

		if (!acclaim) begin // nintendo mapper 'cools down' for 3 inverted M2 cycles
			a12_ctr <= (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
		end
	end

	if (~paused) begin
		// Trigger IRQ counter on rising edge of chr_ain[12]
		// All MMC3A's and non-Sharp MMC3B's will generate only a single IRQ when $C000 is $00.
		// This is because this version of the MMC3 generates IRQs when the scanline counter is decremented to 0.
		// In addition, writing to $C001 with $C000 still at $00 will result in another single IRQ being generated.
		// In the community, this is known as the "alternate" or "old" behavior.
		// All MMC3C's and Sharp MMC3B's will generate an IRQ on each scanline while $C000 is $00.
		// This is because this version of the MMC3 generates IRQs when the scanline counter is equal to 0.
		// In the community, this is known as the "normal" or "new" behavior.

		last_a12 <= chr_ain_o[12];
		if ((acclaim && (!last_a12 && chr_ain_o[12]) && (a12_ctr == 6)) ||
			(~acclaim && (!last_a12 && chr_ain_o[12]) && (a12_ctr == 0))) begin
			counter <= new_counter;
	
			// MMC Scanline
			if ( (!mmc3_alt_behavior || counter != 0 || irq_reload) && new_counter == 0 && irq_enable && irq_support) begin
				irq_reg[0] <= 1;
			end
			irq_reload <= 0;
		end

		if (acclaim) begin
			if (!last_a12 && chr_ain_o[12]) // acclaim mapper counts down 8 pulses, or 16 edges total
				a12_ctr <= (a12_ctr != 0) ? a12_ctr - 4'b0001 : 4'b0111;
			if (prg_ain == 16'hC001 && prg_write) a12_ctr <= 4'b0111;
		end else if (chr_ain_o[12]) // Nintendo mapper cooldown resets on a12
			a12_ctr <= 4'b0011;
	end
end

assign SS_MAP1_BACK[ 6: 0] = irq_reg;
assign SS_MAP1_BACK[ 9: 7] = bank_select;
assign SS_MAP1_BACK[   10] = prg_rom_bank_mode;
assign SS_MAP1_BACK[   11] = chr_a12_invert;
assign SS_MAP1_BACK[   12] = mirroring;
assign SS_MAP1_BACK[   13] = irq_enable;
assign SS_MAP1_BACK[   14] = irq_reload;
assign SS_MAP1_BACK[22:15] = irq_latch;
assign SS_MAP1_BACK[30:23] = counter;
assign SS_MAP1_BACK[34:31] = ram_enable;
assign SS_MAP1_BACK[38:35] = ram_protect;
assign SS_MAP1_BACK[46:39] = chr_bank_0;
assign SS_MAP1_BACK[54:47] = chr_bank_1;
assign SS_MAP1_BACK[62:55] = chr_bank_2;
assign SS_MAP1_BACK[   63] = 1'b0; // free to be used

assign SS_MAP2_BACK[ 7: 0] = chr_bank_3;
assign SS_MAP2_BACK[15: 8] = chr_bank_4;
assign SS_MAP2_BACK[23:16] = chr_bank_5;
assign SS_MAP2_BACK[29:24] = prg_bank_0[5:0];
assign SS_MAP2_BACK[35:30] = prg_bank_1[5:0];
assign SS_MAP2_BACK[41:36] = prg_bank_2[5:0];
assign SS_MAP2_BACK[45:42] = a12_ctr;
assign SS_MAP2_BACK[   46] = last_a12;
assign SS_MAP2_BACK[49:47] = mapper37_multicart;
assign SS_MAP2_BACK[   50] = mapper47_multicart;
assign SS_MAP2_BACK[54:51] = mapper189_prgsel;
assign SS_MAP2_BACK[   55] = ram6_enabled;
assign SS_MAP2_BACK[   56] = ram6_enable;
assign SS_MAP2_BACK[   57] = ram6_protect;
assign SS_MAP2_BACK[59:58] = prg_bank_0[7:6];
assign SS_MAP2_BACK[61:60] = prg_bank_1[7:6];
assign SS_MAP2_BACK[63:62] = prg_bank_2[7:6];
//assign SS_MAP2_BACK[64:64] = 0'b0; // full

assign SS_MAP3_BACK[ 7: 0] = m268_reg[0];
assign SS_MAP3_BACK[15: 8] = m268_reg[1];
assign SS_MAP3_BACK[23:16] = m268_reg[2];
assign SS_MAP3_BACK[31:24] = m268_reg[3];
assign SS_MAP3_BACK[39:32] = m268_reg[4];
assign SS_MAP3_BACK[47:40] = m268_reg[5];
assign SS_MAP3_BACK[   48] = chr_bank_0_0;
assign SS_MAP3_BACK[   49] = chr_bank_1_0;
assign SS_MAP3_BACK[63:50] = 14'b0; // free to be used

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [7:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode && prg_invert_support})
		3'b00_0: prgsel = prg_bank_0;  // $8000 mode 0
		3'b00_1: prgsel = prg_bank_2;  // $8000 fixed to second last bank
		3'b01_?: prgsel = prg_bank_1;  // $A000 mode 0,1
		3'b10_0: prgsel = prg_bank_2;  // $C000 fixed to second last bank
		3'b10_1: prgsel = prg_bank_0;  // $C000 mode 1
		3'b11_?: prgsel = 8'b11111111; // $E000 fixed to last bank
	endcase

	// mapper47 is limited to 128k PRG, the top bits are controlled by mapper47_multicart instead.
	if (mapper47) prgsel[7:4] = {3'b000, mapper47_multicart};
	if (mapper37) begin
	prgsel[7:4] = {3'b000, mapper37_multicart[2]};
		if (mapper37_multicart[1:0] == 3'd3)
			prgsel[3] = 1'b1;
		else if (mapper37_multicart[2] == 1'b0)
			prgsel[3] = 1'b0;
	end

	if (mapper189) prgsel = {2'b00,mapper189_prgsel,prg_ain[14:13]};
	if (!oversized) prgsel[7:6] = 2'b00;
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [8:0] chrsel;
wire use_chr_ain_12 = chr_ain[12] ^ (chr_a12_invert && chr_invert_support);
always @* begin
	if (!mapper76) begin
		casez({use_chr_ain_12, chr_ain[11], chr_ain[10]})
			3'b00?: chrsel = {chr_bank_0, chr_ain[10]};
			3'b01?: chrsel = {chr_bank_1, chr_ain[10]};
			3'b100: chrsel = {1'b0, chr_bank_2};
			3'b101: chrsel = {1'b0, chr_bank_3};
			3'b110: chrsel = {1'b0, chr_bank_4};
			3'b111: chrsel = {1'b0, chr_bank_5};
		endcase
		// mapper47 is limited to 128k CHR, the top bit is controlled by mapper47_multicart instead.
		if (mapper47) chrsel[7] = mapper47_multicart;
		if (mapper37) chrsel[7] = mapper37_multicart[2];
		if ((mapper88) || (mapper154)) chrsel[6] = chr_ain[12];
	end else begin
		case(chr_ain[12:11])
			2'b00: chrsel = {chr_bank_2, chr_ain[10]};
			2'b01: chrsel = {chr_bank_3, chr_ain[10]};
			2'b10: chrsel = {chr_bank_4, chr_ain[10]};
			2'b11: chrsel = {chr_bank_5, chr_ain[10]};
		endcase
	end
end

assign gnrom = m268_reg[3][4];
assign lockout = m268_reg[3][7] && !gnrom;
assign gnrom_lock = m268_reg[2][7];
assign mega_unrom = m268_reg[5][4];
assign weird_mode = m268_reg[3][6];
wire [24:13] map268p; //only [20:13] used below => max size is 2MB
wire [17:10] map268c;
assign map268p[24:21] = {m268_reg[0][5:4],m268_reg[1][3:2]};
assign map268p[20] = m268_reg[1][5]?prgsel[7]:m268_reg[1][4];
assign map268p[19] = mega_unrom ? (prg_ain[14] | map268c[17]): m268_reg[1][6]?prgsel[6]:m268_reg[0][2];
assign map268p[18] = mega_unrom ? (prg_ain[14] | map268c[16]): !m268_reg[1][7]?prgsel[5]:m268_reg[0][1];
assign map268p[17] = !m268_reg[0][6]?prgsel[4]:m268_reg[0][0];
assign map268p[16:15] = gnrom ? m268_reg[3][3:2] : weird_mode && !prg_rom_bank_mode && prg_ain[14]?2'b00:prgsel[3:2];
assign map268p[14] = gnrom ? m268_reg[1][1]?prg_ain[14]:m268_reg[3][1] : weird_mode && !prg_rom_bank_mode && prg_ain[14]?1'b0:prgsel[1];
assign map268p[13] = gnrom ? prg_ain[13]: weird_mode && !prg_rom_bank_mode && prg_ain[14]?1'b0:prgsel[0];

assign map268c[17] = !m268_reg[0][7]?chrsel[7]:m268_reg[0][3];
assign map268c[16:13] = gnrom ? ({~m268_reg[2][6:4],1'b1} & m268_reg[2][3:0]): weird_mode && chr_ain[10] ? 4'h0 : chrsel[6:3];
assign map268c[12:11] = (weird_mode && chr_ain[10]) ? 2'h0 : chrsel[2:1];
assign map268c[10] = (weird_mode && chr_ain[10]) ? 1'b0 : (use_chr_ain_12 || !weird_mode) ? chrsel[0] : chr_ain[12] ? chr_bank_1_0 : chr_bank_0_0 ;

wire m268_chr_ram = {map268c[17:11],1'b1} == m268_reg[4];

wire [21:0] prg_aout_tmp = {1'b0, mapper268 ? map268p[20:13] : prgsel, prg_ain[12:0]};

wire ram_enable_a = !MMC6 ? (ram_enable[prg_ain[12:11]])
						:   (ram6_enabled && ram6_enable && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b0)
						 || (ram6_enabled && ram_enable[3] && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b1);

wire ram_protect_a = !MMC6 ? (ram_protect[prg_ain[12:11]])
						:   !(ram6_enabled && ram6_enable && ram6_protect && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b0)
						 && !(ram6_enabled && ram_enable[3] && ram_protect[3] && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b1);

wire chr_ram_cs =
		TQROM                 ? chrsel[6]               :
		mapper74              ? chrsel[7:1]==7'b0000100 :
		mapper191             ? chrsel[7]               :
		mapper192             ? chrsel[7:2]==6'b000010  :
		mapper194             ? chrsel[7:1]==7'b0000000 :
		mapper195             ? chrsel[7:2]==6'b000000  :
		four_screen_mirroring ? chr_ain[13]             :
		flags[15];

assign chr_allow = chr_ram_cs;
assign chr_aout =
		(TQROM & chr_ram_cs)                 ? {9'b11_1111_111,    chrsel[2:0], chr_ain[9:0]} :   // TQROM 8kb CHR-RAM
		(mapper74 & chr_ram_cs)              ? {11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
		(mapper191 & chr_ram_cs)             ? {11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
		(mapper192 & chr_ram_cs)             ? {10'b11_1111_1111,  chrsel[1:0], chr_ain[9:0]} :   // 4kb CHR-RAM
		(mapper194 & chr_ram_cs)             ? {11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
		(mapper195 & chr_ram_cs)             ? {10'b11_1111_1111,  chrsel[1:0], chr_ain[9:0]} :   // 4kb CHR-RAM
		(four_screen_mirroring & chr_ram_cs) ? {9'b11_1111_111,   chr_ain[13], chr_ain[11:0]} :   // DxROM 8kb CHR-RAM
		(m268_chr_ram)                       ? {11'b11_1111_1111_1,            chr_ain[10:0]} :   // 2kb CHR-RAM
		(mapper268)                          ? {4'b10_00,              map268c, chr_ain[9:0]} :   // Mapper 268 override
		                                       {3'b10_0,                chrsel, chr_ain[9:0]};    // Standard MMC3

wire ram_a13 = mapper268 && m268_reg[3][5] && (prg_ain[15:12] == 4'h5);
assign prg_is_ram = (ram_a13 || (prg_ain[15:13] == 3'b011) && ((prg_ain[12:8] == 5'b1_1111) | ~internal_128)) //(>= 'h6000 && < 'h8000) && (==7Fxx or external_ram)
					&& ram_enable_a && !(ram_protect_a && prg_write);
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram && !mapper47;
wire [21:0] prg_ram = {8'b11_1100_00, ram_a13, internal_128 ? 6'b000000 : MMC6 ? {3'b000, prg_ain[9:7]} : prg_ain[12:7], prg_ain[6:0]};
assign prg_aout = prg_is_ram  && !mapper47 && !DxROM && !mapper95 && !mapper88 ? prg_ram : prg_aout_tmp;
assign vram_a10 = TxSROM ? chrsel[7] :              // TxSROM do not support mirroring
					mapper95 ? chrsel[5] :          // mapper95 does not support mirroring
					mapper154 ? mirroring :         // mapper154 does not support mirroring
					mapper207 ? chrsel[7] :         // mapper207 does not support mirroring
					(mirroring ? chr_ain[10] : chr_ain[11]);
assign vram_ce = chr_ain[13] && !four_screen_mirroring;

// savestate
localparam SAVESTATE_MODULES    = 3;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];
wire [63:0] SS_MAP1, SS_MAP2, SS_MAP3;
wire [63:0] SS_MAP1_BACK, SS_MAP2_BACK, SS_MAP3_BACK;	
wire [63:0] SaveStateBus_Dout_active = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1] | SaveStateBus_wired_or[2];
	
eReg_SavestateV #(SSREG_INDEX_MAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[0], SS_MAP1_BACK, SS_MAP1);  
eReg_SavestateV #(SSREG_INDEX_MAP2, 64'h0000000000000000) iREG_SAVESTATE_MAP2 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[1], SS_MAP2_BACK, SS_MAP2);  
eReg_SavestateV #(SSREG_INDEX_MAP3, 64'h0000000000000000) iREG_SAVESTATE_MAP3 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[2], SS_MAP3_BACK, SS_MAP3);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule


// mapper 165
module Mapper165(
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
	input [13:0] chr_ain_o,
	input        m2_inv,
	input        paused
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = 0;

reg [2:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg ram_enable, ram_protect;       // RAM protection bits
reg [5:0] prg_bank_0, prg_bank_1;  // Selected PRG banks
wire prg_is_ram;

reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg [7:0] chr_bank_2, chr_bank_4;
reg latch_0, latch_1;

wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1'd1;
reg [3:0] a12_ctr;
reg last_a12 = 0;

always @(posedge clk)
if (~enable) begin
	irq <= 0;
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_a12_invert <= 0;
	mirroring <= flags[14];
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	{ram_enable, ram_protect} <= 0;
	{chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_4} <= 0;
	{prg_bank_0, prg_bank_1} <= 0;
	a12_ctr <= 0;
	last_a12 <= 0;
end else begin
	if (ce) begin
		if (prg_write && prg_ain[15]) begin
			case({prg_ain[14], prg_ain[13], prg_ain[0]})
				3'b00_0: {chr_a12_invert, prg_rom_bank_mode, bank_select} <= {prg_din[7], prg_din[6], prg_din[2:0]}; // Bank select ($8000-$9FFE, even)
				3'b00_1: begin // Bank data ($8001-$9FFF, odd)
					case (bank_select)
						0: chr_bank_0 <= {prg_din[7:1], 1'b0};  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
						1: chr_bank_1 <= {prg_din[7:1], 1'b0};  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
						2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
						3: ;                            // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
						4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
						5: ;                            // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
						6: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
						7: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					endcase
				end
				3'b01_0: mirroring <= prg_din[0];                   // Mirroring ($A000-$BFFE, even)
				3'b01_1: {ram_enable, ram_protect} <= prg_din[7:6]; // PRG RAM protect ($A001-$BFFF, odd)
				3'b10_0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
				3'b10_1: irq_reload <= 1;                           // IRQ reload ($C001-$DFFF, odd)
				3'b11_0: begin irq_enable <= 0; irq <= 0; end       // IRQ disable ($E000-$FFFE, even)
				3'b11_1: irq_enable <= 1;                           // IRQ enable ($E001-$FFFF, odd)
			endcase
		end
	end

	if (m2_inv) begin // Inverted M2
		// nintendo mapper 'cools down' for 3 inverted M2 cycles
		a12_ctr <= (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
	end

	if (~paused) begin
		// Trigger IRQ counter on rising edge of chr_ain[12]

		last_a12 <= chr_ain_o[12];
		if ((!last_a12 && chr_ain_o[12]) && (a12_ctr == 0)) begin
			counter <= new_counter;
	
			// MMC Scanline
			if ( (counter != 0 || irq_reload) && new_counter == 0 && irq_enable) begin
				irq <= 1;
			end
			irq_reload <= 0;
		end

		if (chr_ain_o[12]) // Nintendo mapper cooldown resets on a12
			a12_ctr <= 4'b0011;
	end
end

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [5:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode})
		3'b00_0: prgsel = prg_bank_0;  // $8000 mode 0
		3'b00_1: prgsel = 6'b111110;   // $8000 fixed to second last bank
		3'b01_?: prgsel = prg_bank_1;  // $A000 mode 0,1
		3'b10_0: prgsel = 6'b111110;   // $C000 fixed to second last bank
		3'b10_1: prgsel = prg_bank_0;  // $C000 mode 1
		3'b11_?: prgsel = 6'b111111;   // $E000 fixed to last bank
	endcase
end

wire [21:0] prg_aout_tmp = {3'b00_0,  prgsel, prg_ain[12:0]};

// PPU reads $0FD0: latch 0 is set to $FD for subsequent reads
// PPU reads $0FE0: latch 0 is set to $FE for subsequent reads
// PPU reads $1FD0 through $1FDF: latch 1 is set to $FD for subsequent reads
// PPU reads $1FE0 through $1FEF: latch 1 is set to $FE for subsequent reads
always @(posedge clk)
if (ce && chr_read) begin
	latch_0 <= (chr_ain_o       == 14'h0fd0) ? 1'd0 : (chr_ain_o       == 14'h0fe0) ? 1'd1 : latch_0;
	latch_1 <= (chr_ain_o[13:4] == 10'h1fd ) ? 1'd0 : (chr_ain_o[13:4] == 10'h1fe ) ? 1'd1 : latch_1;
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [7:0] chrsel;
always @* begin
	casez({chr_ain[12] ^ chr_a12_invert, latch_0, latch_1})
		3'b0_0?: chrsel = chr_bank_0;
		3'b0_1?: chrsel = chr_bank_1;
		3'b1_?0: chrsel = chr_bank_2;
		3'b1_?1: chrsel = chr_bank_4;
	endcase
end

assign chr_allow = !chrsel; // page 0 is CHR-RAM
assign chr_aout = !chrsel ? {10'b11_1111_1111, chr_ain[11:0]} :   // 4KB CHR-RAM
				{4'b10_00, chrsel[7:2], chr_ain[11:0]}; // CHR-ROM per 4KB page

assign prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000 && ram_enable && !(ram_protect && prg_write);
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram;
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;
assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
assign vram_ce = chr_ain[13];

endmodule

// mapper 413 based on Nintendulator NRS source
// mapper 413 uses MMC3 style interrupts
module Mapper413 (
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
	input [13:0] chr_ain_o,
	input        m2_inv,
	input        paused,
	output [2:0] prg_aoute    // Extended prg address out bits
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire irq;
reg [15:0] flags_out = 0;

reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg [4:0] irq_reg;
assign irq = irq_reg[0];

wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1'd1;
reg [3:0] a12_ctr;
reg last_a12 = 0;

reg misc_inc;
reg old_misc_inc;
reg misc_ctrl;
reg [22:0] prg_amisc;
wire prg_is_misc = (prg_ain[15:11] == 5'b0100_1) | (prg_ain[15:12] == 4'b1100); // $48xx or $Cxxx
assign prg_aoute = prg_is_misc ? {2'b10,prg_amisc[22]} : 3'd0;

reg [5:0] bank_reg[0:3];

always @(posedge clk)
if (~enable) begin
	irq_reg <= 5'b00000;
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	bank_reg[0] <= 0;
	bank_reg[1] <= 0;
	bank_reg[2] <= 0;
	bank_reg[3] <= 0;
	prg_amisc <= 0;
	misc_ctrl <= 0;
	misc_inc <= 0;
	old_misc_inc <= 0;
	a12_ctr <= 0;
	last_a12 <= 0;
end else begin
	if (ce) begin
		if (prg_write && prg_ain[15]) begin
			casez(prg_ain[14:12])
				3'b000: irq_latch <= prg_din;                      // IRQ latch $8000-8FFF (mmc3=$C000-$DFFE, even)
				3'b001: irq_reload <= 1;                           // IRQ reload $9000-9FFF (mmc3=$C001-$DFFF, odd)
				3'b010: begin irq_enable <= 0; irq_reg[0] <= 0; end// IRQ disable $A000-AFFF (mmc3=$E000-$FFFE, even)
				3'b011: irq_enable <= 1;                           // IRQ enable $B000-BFFF (mmc3=$E001-$FFFF, odd)
				3'b100: prg_amisc <= {prg_amisc[21:0], prg_din[7]};// Misc Address (shift left 1, insert MSB)
				3'b101: misc_ctrl <= prg_din[1];                   // Misc Control (& 0x2)
				3'b11?: bank_reg[prg_din[7:6]] <= prg_din[5:0];    // Bank select din[7:6] ($E000-$EFFE)
			endcase
		end
	
		misc_inc <= 0;
		old_misc_inc <= misc_inc;
		if (prg_read && prg_is_misc)
			misc_inc <= 1;
		if (old_misc_inc && !misc_inc && misc_ctrl)
			prg_amisc <= prg_amisc + 23'd1;
	end

	if (m2_inv) begin // Inverted M2
		// nintendo mapper 'cools down' for 3 inverted M2 cycles
		a12_ctr <= (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
		irq_reg[4:1] <= irq_reg[3:0]; // 1 cpu cycle delay ??? what is this for
	end

	if (~paused) begin
		// Trigger IRQ counter on rising edge of chr_ain[12]

		last_a12 <= chr_ain_o[12];
		if ((!last_a12 && chr_ain_o[12]) && (a12_ctr == 0)) begin
			counter <= new_counter;
	
			// MMC Scanline
			if ( (counter != 0 || irq_reload) && new_counter == 0 && irq_enable) begin
				irq_reg[0] <= 1;
			end
			irq_reload <= 0;
		end

		if (chr_ain_o[12]) // Nintendo mapper cooldown resets on a12
			a12_ctr <= 4'b0011;
	end
end

reg [5:0] prgsel;
always @* begin
	casez(prg_ain[15:11])
		5'b00??_?: prgsel = 6'b000000;   // $0000 CPU - not used
//		5'b0100_0: prgsel = 6'b000000;   // $4000 not used
//		5'b0100_1: prgsel = 6'b000000;   // $4800 misc - not used
		5'b010?_?: prgsel = 6'b000000;   // $5000 fixed to 0x1 (prg_ain[11]=1)
		5'b011?_?: prgsel = bank_reg[0]; // $6000 =$E000, $00
		5'b100?_?: prgsel = bank_reg[1]; // $8000 =$E000, $40
		5'b101?_?: prgsel = bank_reg[2]; // $A000 =$E000, $80
//		5'b1100_?: prgsel = 6'b000011;   // $C000 misc - not used 
		5'b110?_?: prgsel = 6'b000011;   // $D000 fixed to 0x7 ({prgsel[5:0],prg_ain[11]} = 7)
		5'b111?_?: prgsel = 6'b000100;   // $E000 fixed to 0x8-9
	endcase
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [5:0] chrsel;
always @* begin
	case(chr_ain[12])
		1'b0: chrsel = bank_reg[3]; // =$E000, $C0
		1'b1: chrsel = 6'b11_1101;  // 0x3D
	endcase
end

wire [21:0] prg_aout_tmp = {3'b00_0,  prgsel, prg_ain[12:0]};

assign chr_allow = flags[15];
assign chr_aout =  {4'b10_00, chrsel, chr_ain[11:0]};

assign prg_allow = (prg_ain[15] || (prg_ain[14] && (prg_ain[13:11] != 3'b000))) && !prg_write;
assign prg_aout = prg_is_misc ? prg_amisc[21:0] : prg_aout_tmp;
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
assign vram_ce = chr_ain[13];

endmodule

