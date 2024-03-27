// MMC5 Mapper aka "WTF were they thinking?!"

module MMC5(
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
	// Special ports
	input  [7:0] audio_dout,
	input [13:0] chr_ain_o,
	input        chr_ex,      // Extra sprites fetch active
	input  [7:0] chr_din,     // CHR Data in
	input        chr_write,   // CHR Write
	inout  [7:0] chr_dout_b,  // chr data (non standard)
	input        paused,
	// savestates              
	input       [63:0]  SaveStateBus_Din,
	input       [ 9:0]  SaveStateBus_Adr,
	input               SaveStateBus_wren,
	input               SaveStateBus_rst,
	input               SaveStateBus_load,
	output      [63:0]  SaveStateBus_Dout,
	
	input         Savestate_MAPRAMactive, 
	input  [9:0]  Savestate_MAPRAMAddr,     
	input         Savestate_MAPRAMRdEn,    
	input         Savestate_MAPRAMWrEn,    
	input  [7:0]  Savestate_MAPRAMWriteData,
	output [7:0]  Savestate_MAPRAMReadData
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_dout_b   = enable ? chr_dout : 8'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? audio : 16'hZ;

wire [21:0] prg_aout;
reg [21:0] chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
reg [7:0] chr_dout, prg_dout;
wire vram_ce;
wire [15:0] flags_out = {12'h0, 1'b1, 1'b0, prg_bus_write, has_chr_dout};
wire irq;
wire prg_bus_write, has_chr_dout;
wire [15:0] audio = audio_in;

reg [1:0] prg_mode, chr_mode;
reg prg_protect_1, prg_protect_2;
reg [1:0] extended_ram_mode;
reg [7:0] mirroring;
reg [7:0] fill_tile;
reg [1:0] fill_attr;
reg [2:0] prg_ram_bank;
reg [7:0] prg_bank_0, prg_bank_1, prg_bank_2;
reg [6:0] prg_bank_3;
reg [9:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3,
	chr_bank_4, chr_bank_5, chr_bank_6, chr_bank_7,
	chr_bank_8, chr_bank_9, chr_bank_a, chr_bank_b;
reg [1:0] upper_chr_bank_bits;
reg chr_last; // Which CHR set was written to last?

reg [4:0] vsplit_startstop;
reg vsplit_enable, vsplit_side;
reg [7:0] vsplit_scroll, vsplit_bank;

reg [7:0] irq_scanline;
reg irq_enable;
reg irq_pending, irq_pending_clear;

reg [7:0] multiplier_1;
reg [7:0] multiplier_2;
wire [15:0] multiply_result = multiplier_1 * multiplier_2;

reg [7:0] last_read_exattr;
reg [7:0] last_read_vram;
reg last_chr_read;

reg [7:0] vscroll;      // Current y scroll for the split region
reg in_split_area;

reg rendering_en;
reg ppu_sprite16_r;
wire sprite8x16_mode = ppu_sprite16_r & rendering_en;

reg ppu_in_frame, last_ppu_in_frame;
reg [7:0] ppu_scanline;

reg [11:0] ppu_last_nt_addr;
reg [1:0] ppu_nt_read_cnt, ppu_no_rd_read_cnt;
reg [5:0] ppu_tile_cnt;

reg last_chr_a13;
reg is_sprite_fetch;
// is_sprite_fetch goes high during the unused NT fetches of the first sprite.
// That is too late for the first extra sprite so also use chr_ex here.
wire is_bg_fetch = ~(is_sprite_fetch | chr_ex);

// On an original NES these PPU addresses should be latched because the lower 8 bits
// are overwritten with the read data on the 2nd cycle when PPU_/RD goes low.
// In the core the address is not changed so latching is not needed.
wire ppu_is_tile_addr = (~chr_ain[13]);
wire ppu_is_at_addr = (chr_ain[13:12] == 2'b10) & (&chr_ain[9:6]);
wire ppu_is_nt_addr = (chr_ain[13:12] == 2'b10) & (~&chr_ain[9:6]);

// Block RAM, otherwise we need to time multiplex..
reg [9:0] ram_addrA;
reg       ram_wrenA;
reg [7:0] ram_dataA;

wire [9:0] ram_addrB = Savestate_MAPRAMactive ? Savestate_MAPRAMAddr      : exram_read_addr;
wire       ram_wrenB = Savestate_MAPRAMactive ? Savestate_MAPRAMWrEn      : 1'b0;
wire [7:0] ram_dataB = Savestate_MAPRAMactive ? Savestate_MAPRAMWriteData : 8'b0;
wire [7:0] last_read_ram;


dpram #(.widthad_a(10)) expansion_ram
(
	.clock_a   (clk),
	.address_a (ram_addrA),
	.wren_a    (ram_wrenA),
	.byteena_a (1),
	.data_a    (ram_dataA),

	.clock_b   (clk),
	.address_b (ram_addrB),
	.wren_b    (ram_wrenB),
	.byteena_b (1),
	.data_b    (ram_dataB),
	.q_b       (last_read_ram)
);


// Handle IO register writes
always @(posedge clk) begin
	ram_wrenA <= 1'b0;
	if (ce) begin
	if (prg_write && prg_ain[15:10] == 6'b010100) begin // $5000-$53FF
		//if (prg_ain <= 16'h5113) $write("%X <= %X (%d)\n", prg_ain, prg_din, ppu_scanline);
		casez(prg_ain[9:0])
			10'h100: prg_mode <= prg_din[1:0];
			10'h101: chr_mode <= prg_din[1:0];
			10'h102: prg_protect_1 <= (prg_din[1:0] == 2'b10);
			10'h103: prg_protect_2 <= (prg_din[1:0] == 2'b01);
			10'h104: extended_ram_mode <= prg_din[1:0];
			10'h105: mirroring <= prg_din;
			10'h106: fill_tile <= prg_din;
			10'h107: fill_attr <= prg_din[1:0];
			10'h113: prg_ram_bank <= prg_din[2:0];
			10'h114: prg_bank_0 <= prg_din;
			10'h115: prg_bank_1 <= prg_din;
			10'h116: prg_bank_2 <= prg_din;
			10'h117: prg_bank_3 <= prg_din[6:0];
			10'h120: chr_bank_0 <= {upper_chr_bank_bits, prg_din};
			10'h121: chr_bank_1 <= {upper_chr_bank_bits, prg_din};
			10'h122: chr_bank_2 <= {upper_chr_bank_bits, prg_din};
			10'h123: chr_bank_3 <= {upper_chr_bank_bits, prg_din};
			10'h124: chr_bank_4 <= {upper_chr_bank_bits, prg_din};
			10'h125: chr_bank_5 <= {upper_chr_bank_bits, prg_din};
			10'h126: chr_bank_6 <= {upper_chr_bank_bits, prg_din};
			10'h127: chr_bank_7 <= {upper_chr_bank_bits, prg_din};
			10'h128: chr_bank_8  <= {upper_chr_bank_bits, prg_din};
			10'h129: chr_bank_9  <= {upper_chr_bank_bits, prg_din};
			10'h12a: chr_bank_a  <= {upper_chr_bank_bits, prg_din};
			10'h12b: chr_bank_b  <= {upper_chr_bank_bits, prg_din};
			10'h130: upper_chr_bank_bits <= prg_din[1:0];
			10'h200: {vsplit_enable, vsplit_side, vsplit_startstop} <= {prg_din[7:6], prg_din[4:0]};
			10'h201: vsplit_scroll <= prg_din;
			10'h202: vsplit_bank <= prg_din;
			10'h203: irq_scanline <= prg_din;
			10'h204: irq_enable <= prg_din[7];
			10'h205: multiplier_1 <= prg_din;
			10'h206: multiplier_2 <= prg_din;
			default: begin end
		endcase

		// Remember which set of CHR was written to last.
		// chr_last is set to 0 when changing bank with sprites set to 8x8
		if (prg_ain[9:4] == 6'b010010) //(prg_ain[9:0] >= 10'h120 && prg_ain[9:0] < 10'h130)
			chr_last <= prg_ain[3] & ppu_sprite16_r;

	end

		if (prg_write && prg_ain == 16'h2000) begin // $2000
			ppu_sprite16_r <= prg_din[5];
			if (~prg_din[5]) // chr_last is set to 0 when changing sprite size to 8x8
				chr_last <= 0;
		end
		if (prg_write && prg_ain == 16'h2001) begin // $2001
			rendering_en <= |prg_din[4:3];
		end

	end

	// Mode 0/1 - Not readable (returns open bus), can only be written while the PPU is rendering (otherwise, 0 is written)
	// Mode 2 - Readable and writable
	// Mode 3 - Read-only
	if (extended_ram_mode != 3) begin
		if (~paused && !ppu_in_frame && !extended_ram_mode[1] && chr_write && (mirrbits == 2) && chr_ain[13]) begin
			ram_addrA <= chr_ain[9:0];
			ram_dataA <= chr_din;
			ram_wrenA <= 1'b1;
		end else if (ce && prg_write && prg_ain[15:10] == 6'b010111) begin // $5C00-$5FFF
			ram_addrA <= prg_ain[9:0];
			ram_dataA <= (extended_ram_mode[1] || ppu_in_frame) ? prg_din : 8'd0;
			ram_wrenA <= 1'b1;
		end
	end

	if (~enable) begin
		prg_bank_3 <= 7'h7F;
		prg_mode <= 3;
	end
	
	if (SaveStateBus_load) begin
		prg_mode            <= SS_MAP1[ 1: 0];
		chr_mode            <= SS_MAP1[ 3: 2];
		prg_protect_1       <= SS_MAP1[    4];
		prg_protect_2       <= SS_MAP1[    5];
		extended_ram_mode   <= SS_MAP1[ 7: 6];
		mirroring           <= SS_MAP1[15: 8];
		fill_tile           <= SS_MAP1[23:16];
		fill_attr           <= SS_MAP1[25:24];
		prg_ram_bank        <= SS_MAP1[28:26];
		prg_bank_0          <= SS_MAP1[36:29];
		prg_bank_1          <= SS_MAP1[44:37];
		prg_bank_2          <= SS_MAP1[52:45];
		prg_bank_3          <= SS_MAP1[59:53];
		chr_bank_0          <= SS_MAP2[ 9: 0];
		chr_bank_1          <= SS_MAP2[19:10];
		chr_bank_2          <= SS_MAP2[29:20];
		chr_bank_3          <= SS_MAP2[39:30];
		chr_bank_4          <= SS_MAP2[49:40];
		chr_bank_5          <= SS_MAP2[59:50];
		chr_bank_6          <= SS_MAP3[ 9: 0];
		chr_bank_7          <= SS_MAP3[19:10];
		chr_bank_8          <= SS_MAP3[29:20];
		chr_bank_9          <= SS_MAP3[39:30];
		chr_bank_a          <= SS_MAP3[49:40];
		chr_bank_b          <= SS_MAP3[59:50];
		upper_chr_bank_bits <= SS_MAP4[ 1: 0];
		vsplit_enable       <= SS_MAP4[    2];
		vsplit_side         <= SS_MAP4[    3];
		vsplit_startstop    <= SS_MAP4[ 8: 4];
		vsplit_scroll       <= SS_MAP4[16: 9];
		vsplit_bank         <= SS_MAP4[24:17];
		irq_scanline        <= SS_MAP4[32:25];
		irq_enable          <= SS_MAP4[   33];
		multiplier_1        <= SS_MAP4[41:34];
		multiplier_2        <= SS_MAP4[49:42];
		chr_last            <= SS_MAP4[   50];
		ppu_sprite16_r      <= SS_MAP4[   51];
	end
end

assign SS_MAP1_BACK[ 1: 0] = prg_mode;
assign SS_MAP1_BACK[ 3: 2] = chr_mode;
assign SS_MAP1_BACK[    4] = prg_protect_1;
assign SS_MAP1_BACK[    5] = prg_protect_2;
assign SS_MAP1_BACK[ 7: 6] = extended_ram_mode;
assign SS_MAP1_BACK[15: 8] = mirroring;
assign SS_MAP1_BACK[23:16] = fill_tile;
assign SS_MAP1_BACK[25:24] = fill_attr;
assign SS_MAP1_BACK[28:26] = prg_ram_bank;
assign SS_MAP1_BACK[36:29] = prg_bank_0;
assign SS_MAP1_BACK[44:37] = prg_bank_1;
assign SS_MAP1_BACK[52:45] = prg_bank_2;
assign SS_MAP1_BACK[59:53] = prg_bank_3;
assign SS_MAP1_BACK[63:60] = 4'b0; // free to be used

assign SS_MAP2_BACK[ 9: 0] = chr_bank_0;
assign SS_MAP2_BACK[19:10] = chr_bank_1;
assign SS_MAP2_BACK[29:20] = chr_bank_2;
assign SS_MAP2_BACK[39:30] = chr_bank_3;
assign SS_MAP2_BACK[49:40] = chr_bank_4;
assign SS_MAP2_BACK[59:50] = chr_bank_5;
assign SS_MAP2_BACK[63:60] = 4'b0; // free to be used
				  
assign SS_MAP3_BACK[ 9: 0] = chr_bank_6;
assign SS_MAP3_BACK[19:10] = chr_bank_7;
assign SS_MAP3_BACK[29:20] = chr_bank_8;
assign SS_MAP3_BACK[39:30] = chr_bank_9;
assign SS_MAP3_BACK[49:40] = chr_bank_a;
assign SS_MAP3_BACK[59:50] = chr_bank_b;
assign SS_MAP3_BACK[63:60] = 4'b0; // free to be used
				  
assign SS_MAP4_BACK[ 1: 0] = upper_chr_bank_bits;
assign SS_MAP4_BACK[    2] = vsplit_enable;
assign SS_MAP4_BACK[    3] = vsplit_side;
assign SS_MAP4_BACK[ 8: 4] = vsplit_startstop;
assign SS_MAP4_BACK[16: 9] = vsplit_scroll;
assign SS_MAP4_BACK[24:17] = vsplit_bank;
assign SS_MAP4_BACK[32:25] = irq_scanline;
assign SS_MAP4_BACK[   33] = irq_enable;
assign SS_MAP4_BACK[41:34] = multiplier_1;
assign SS_MAP4_BACK[49:42] = multiplier_2;
assign SS_MAP4_BACK[   50] = chr_last;
assign SS_MAP4_BACK[   51] = ppu_sprite16_r;
assign SS_MAP4_BACK[63:52] = 12'b0; // free to be used


// Read from MMC5
always @* begin
	prg_bus_write = 1'b1;
	if (prg_ain[15:10] == 6'b010111 && extended_ram_mode[1]) begin
		prg_dout = last_read_ram;
	end else if (prg_ain == 16'h5204) begin
		prg_dout = {irq_pending, ppu_in_frame, 6'b111111};
	end else if (prg_ain == 16'h5205) begin
		prg_dout = multiply_result[7:0];
	end else if (prg_ain == 16'h5206) begin
		prg_dout = multiply_result[15:8];
	end else if (prg_ain == 16'h5015) begin
		prg_dout = {6'h00, audio_dout[1:0]};
	// TODO: 5010
	end else begin
		prg_dout = 8'hFF; // By default open bus.
		prg_bus_write = 0;
	end
end

// Scanline detection
always @(posedge clk) begin
	if (SaveStateBus_load) begin
		ppu_in_frame       <= SS_MAP5[    0];
		irq_pending        <= SS_MAP5[    1];
		in_split_area      <= SS_MAP5[    2];
		ppu_tile_cnt       <= SS_MAP5[ 8: 3];
		vscroll            <= SS_MAP5[16: 9];
		last_ppu_in_frame  <= SS_MAP5[   34];
		ppu_scanline       <= SS_MAP5[42:35];
		ppu_nt_read_cnt    <= SS_MAP5[44:43];
		ppu_no_rd_read_cnt <= SS_MAP5[46:45];
		ppu_last_nt_addr   <= SS_MAP5[58:47];
		irq_pending_clear  <= SS_MAP5[   59];
		is_sprite_fetch    <= SS_MAP5[   60];
		last_chr_a13       <= SS_MAP5[   61];
	end else begin

		if (~paused & ~last_chr_read & chr_read) begin
			ppu_last_nt_addr <= chr_ain_o[11:0];

			// Detect 3 PPU NT reads ($2xxx) from the same address
			// In_frame and IRQ will be asserted at the 4th read (address does not matter)
			// If the 4th and following reads are from the same NT address then
			// every read will increment the scanline counter.
			if (~&ppu_nt_read_cnt)
				ppu_nt_read_cnt <= ppu_nt_read_cnt + 1'b1;
			else begin
				if (~ppu_in_frame) begin
					ppu_in_frame <= 1;
					ppu_scanline <= 0;
					ppu_tile_cnt <= 6'd2;
					vscroll <= vsplit_scroll;
				end else begin
					// Testing shows the MMC5 goes out of frame when scanline 240 is detected.
					// Normally this should not happen because the PPU is idle on that line
					// but it could happen if the scanline counter is incremented more than
					// once per line which is what the MMC5 scanline glitch test does.
					if (ppu_scanline == 8'd239) begin
						ppu_in_frame <= 0;
					end else begin
						ppu_scanline <= ppu_scanline + 1'b1;
						if (ppu_scanline + 1'b1 == irq_scanline) begin
							irq_pending <= 1;
						end
					end

				end
			end

			if (chr_ain_o[13:12] != 2'b10 || (|ppu_nt_read_cnt && ppu_last_nt_addr != chr_ain_o[11:0])) begin
				ppu_nt_read_cnt <= 0;
			end

			last_chr_a13 <= chr_ain_o[13];
			if (ppu_in_frame) begin
				if (last_chr_a13 & ~chr_ain_o[13]) begin
					if (ppu_tile_cnt == 41) begin // Last sprite tile fetch
						ppu_tile_cnt <= 0; // First 2 background fetches for the next scanline
						vscroll <= (vscroll == 239) ? 8'd0 : (vscroll + 1'b1);
					end else begin
						ppu_tile_cnt <= ppu_tile_cnt + 1'b1;
					end
				end

				if (~last_chr_a13 & chr_ain_o[13]) begin
					if (ppu_tile_cnt == 34)
						is_sprite_fetch <= 1;

					if (ppu_tile_cnt == 0)
						is_sprite_fetch <= 0;

					if (ppu_tile_cnt == 0)
						in_split_area <= !vsplit_side;
					else if (ppu_tile_cnt == {1'b0, vsplit_startstop})
						in_split_area <= vsplit_side;
					else if (ppu_tile_cnt == 34)
						in_split_area <= 0;

				end
			end
		end

		// The "in-frame" flag is cleared when 3 CPU cycles pass without a PPU read having occurred
		if (~paused) begin
			if (chr_read) begin
				ppu_no_rd_read_cnt <= 0;
			end else if (ce & ppu_in_frame) begin
				ppu_no_rd_read_cnt <= ppu_no_rd_read_cnt + 1'b1;
				if (ppu_no_rd_read_cnt == 2'd2) begin
					ppu_in_frame <= 0;
				end
			end
		end

		if (ce) begin
			if (prg_read) begin
				if ({prg_ain[15:1], 1'b0} == 16'hFFFA) begin // $FFFA/FFFB
					ppu_in_frame <= 0;
				end
				if (prg_ain == 16'h5204) begin
					// MMC5 scanline glitch test expects irq_pending to be cleared after the read.
					irq_pending_clear <= 1;
				end
			end

			if (irq_pending_clear) begin
				if (irq_pending) irq_pending <= 0;
				irq_pending_clear <= 0;
			end
		end

		if (~paused) begin
			last_ppu_in_frame <= ppu_in_frame;
			if (last_ppu_in_frame & ~ppu_in_frame) begin
				ppu_nt_read_cnt <= 0;
				ppu_no_rd_read_cnt <= 0;
				irq_pending <= 0;
				in_split_area <= 0;
				is_sprite_fetch <= 0;
			end
		end

	end
end

assign irq = irq_pending && irq_enable;

// Mirroring bits
// %00 = NES internal NTA
// %01 = NES internal NTB
// %10 = use ExRAM as NT
// %11 = Fill Mode
wire [1:0] mirrbits = (chr_ain[11:10] == 0) ? mirroring[1:0] :
						(chr_ain[11:10] == 1) ? mirroring[3:2] :
						(chr_ain[11:10] == 2) ? mirroring[5:4] :
												mirroring[7:6];

// Compute the new overriden nametable/attr address the split will read from instead
// when the VSplit is active.
// Cycle 0, 1 = nametable
// Cycle 2, 3 = attribute
// Named it loopy so I can copypaste from PPU code :)
wire [9:0] loopy = {vscroll[7:3], ppu_tile_cnt[4:0]};

wire [9:0] split_addr = (ppu_is_nt_addr) ? loopy :                             // name table
											{4'b1111, loopy[9:7], loopy[4:2]}; // attribute table
// Selects 2 out of the attr bits read from exram.
wire [1:0] split_attr = (!loopy[1] && !loopy[6]) ? last_read_ram[1:0] :
						( loopy[1] && !loopy[6]) ? last_read_ram[3:2] :
						(!loopy[1] &&  loopy[6]) ? last_read_ram[5:4] :
													last_read_ram[7:6];
// If splitting is active or not
wire insplit = in_split_area && vsplit_enable && ~chr_ex;

// Currently reading the attribute byte?
wire exattr_read = (extended_ram_mode == 1) && ppu_is_at_addr && ppu_in_frame;

// If the current chr read should be redirected from |chr_dout| instead.
assign has_chr_dout = chr_ain[13] && (mirrbits[1] || insplit || exattr_read);
wire [1:0] override_attr = insplit ? split_attr : (extended_ram_mode == 1) ? last_read_exattr[7:6] : fill_attr;
always @* begin
	if (ppu_in_frame) begin
		if (ppu_is_nt_addr) begin
			// Name table fetch
			if (insplit || mirrbits[0] == 0)
				chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
			else begin
				// Inserting Filltile
				chr_dout = fill_tile;
			end
		end else begin
			// Attribute table fetch
			if (!insplit && !exattr_read && mirrbits[0] == 0)
				chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
			else
				chr_dout = {override_attr, override_attr, override_attr, override_attr};
		end
	end else begin
		chr_dout = last_read_vram;
	end
end

// Handle reading from the expansion ram.
// 0 - Use as extra nametable (possibly for split mode)
// 1 - Use as extended attribute data OR an extra nametable
// 2 - Use as ordinary RAM
// 3 - Use as ordinary RAM, write protected
wire [9:0] exram_read_addr = extended_ram_mode[1] ? prg_ain[9:0] : insplit ? split_addr : chr_ain[9:0];

always @(posedge clk) begin
	if (SaveStateBus_load) begin
		last_read_exattr <= SS_MAP5[24:17];
		last_read_vram   <= SS_MAP5[32:25];
		last_chr_read    <= SS_MAP5[   33];
	end else if (~paused) begin

		last_chr_read <= chr_read;

		if (~last_chr_read & chr_read) begin
			last_read_vram <= extended_ram_mode[1] ? 8'b0 : last_read_ram;

			if (ppu_is_nt_addr & ppu_in_frame) begin
				last_read_exattr <= last_read_ram;
			end
		end
	end
end

assign SS_MAP5_BACK[    0] = ppu_in_frame;
assign SS_MAP5_BACK[    1] = irq_pending;
assign SS_MAP5_BACK[    2] = in_split_area;
assign SS_MAP5_BACK[ 8: 3] = ppu_tile_cnt;
assign SS_MAP5_BACK[16: 9] = vscroll;
assign SS_MAP5_BACK[24:17] = last_read_exattr;
assign SS_MAP5_BACK[32:25] = last_read_vram;
assign SS_MAP5_BACK[   33] = last_chr_read;
assign SS_MAP5_BACK[   34] = last_ppu_in_frame;
assign SS_MAP5_BACK[42:35] = ppu_scanline;
assign SS_MAP5_BACK[44:43] = ppu_nt_read_cnt;
assign SS_MAP5_BACK[46:45] = ppu_no_rd_read_cnt;
assign SS_MAP5_BACK[58:47] = ppu_last_nt_addr;
assign SS_MAP5_BACK[   59] = irq_pending_clear;
assign SS_MAP5_BACK[   60] = is_sprite_fetch;
assign SS_MAP5_BACK[   61] = last_chr_a13;
assign SS_MAP5_BACK[63:62] = 0; // free to be used

// Compute PRG address to read from.
reg [7:0] prgsel;
always @* begin
	casez({prg_mode, prg_ain[15:13]})
		5'b??_0??: prgsel = {5'b0xxxx, prg_ram_bank};                // $6000-$7FFF all modes
		5'b00_1??: prgsel = {1'b1, prg_bank_3[6:2], prg_ain[14:13]}; // $8000-$FFFF mode 0, 32kB (prg_bank_3, skip 2 bits)

		5'b01_10?: prgsel = {      prg_bank_1[7:1], prg_ain[13]};    // $8000-$BFFF mode 1, 16kB (prg_bank_1, skip 1 bit)
		5'b01_11?: prgsel = {1'b1, prg_bank_3[6:1], prg_ain[13]};    // $C000-$FFFF mode 1, 16kB (prg_bank_3, skip 1 bit)

		5'b10_10?: prgsel = {      prg_bank_1[7:1], prg_ain[13]};    // $8000-$BFFF mode 2, 16kB (prg_bank_1, skip 1 bit)
		5'b10_110: prgsel = {      prg_bank_2};                      // $C000-$DFFF mode 2, 8kB  (prg_bank_2)
		5'b10_111: prgsel = {1'b1, prg_bank_3};                      // $E000-$FFFF mode 2, 8kB  (prg_bank_3)

		5'b11_100: prgsel = {      prg_bank_0};                      // $8000-$9FFF mode 3, 8kB (prg_bank_0)
		5'b11_101: prgsel = {      prg_bank_1};                      // $A000-$BFFF mode 3, 8kB (prg_bank_1)
		5'b11_110: prgsel = {      prg_bank_2};                      // $C000-$DFFF mode 3, 8kB (prg_bank_2)
		5'b11_111: prgsel = {1'b1, prg_bank_3};                      // $E000-$FFFF mode 3, 8kB (prg_bank_3)
	endcase
	//Original
	//prgsel[7] = !prgsel[7]; // 0 means RAM, doh.

	//Done below
	//if (prgsel[7])
	//  prgsel[7] = 0;  //ROM
	//else
	//  // Limit to 64k RAM.
	//  prgsel[7:3] = 5'b1_1100;  //RAM location for saves
end

assign prg_aout = {prgsel[7] ? {2'b00, prgsel[6:0]} : {6'b11_1100, prgsel[2:0]}, prg_ain[12:0]};    // 8kB banks

// Registers $5120-$5127 apply to sprite graphics and $5128-$512B for background graphics, but ONLY when 8x16 sprites are enabled.
// Otherwise, the last set of registers written to (either $5120-$5127 or $5128-$512B) will be used for all graphics.
// 0 if using $5120-$5127, 1 if using $5128-$512F

wire chrset = (~sprite8x16_mode) ? 1'd0 : (ppu_in_frame) ? is_bg_fetch : chr_last;
reg [9:0] chrsel;

always @* begin
	casez({chr_mode, chr_ain[12:10], chrset})
		6'b00_???_0: chrsel = {chr_bank_7[6:0], chr_ain[12:10]}; // $0000-$1FFF mode 0, 8 kB
		6'b00_???_1: chrsel = {chr_bank_b[6:0], chr_ain[12:10]}; // $0000-$1FFF mode 0, 8 kB

		6'b01_0??_0: chrsel = {chr_bank_3[7:0], chr_ain[11:10]}; // $0000-$0FFF mode 1, 4 kB
		6'b01_1??_0: chrsel = {chr_bank_7[7:0], chr_ain[11:10]}; // $1000-$1FFF mode 1, 4 kB
		6'b01_???_1: chrsel = {chr_bank_b[7:0], chr_ain[11:10]}; // $0000-$0FFF mode 1, 4 kB

		6'b10_00?_0: chrsel = {chr_bank_1[8:0], chr_ain[10]};    // $0000-$07FF mode 2, 2 kB
		6'b10_01?_0: chrsel = {chr_bank_3[8:0], chr_ain[10]};    // $0800-$0FFF mode 2, 2 kB
		6'b10_10?_0: chrsel = {chr_bank_5[8:0], chr_ain[10]};    // $1000-$17FF mode 2, 2 kB
		6'b10_11?_0: chrsel = {chr_bank_7[8:0], chr_ain[10]};    // $1800-$1FFF mode 2, 2 kB
		6'b10_?0?_1: chrsel = {chr_bank_9[8:0], chr_ain[10]};    // $0000-$07FF mode 2, 2 kB
		6'b10_?1?_1: chrsel = {chr_bank_b[8:0], chr_ain[10]};    // $0800-$0FFF mode 2, 2 kB

		6'b11_000_0: chrsel = chr_bank_0;                        // $0000-$03FF mode 3, 1 kB
		6'b11_001_0: chrsel = chr_bank_1;                        // $0400-$07FF mode 3, 1 kB
		6'b11_010_0: chrsel = chr_bank_2;                        // $0800-$0BFF mode 3, 1 kB
		6'b11_011_0: chrsel = chr_bank_3;                        // $0C00-$0FFF mode 3, 1 kB
		6'b11_100_0: chrsel = chr_bank_4;                        // $1000-$13FF mode 3, 1 kB
		6'b11_101_0: chrsel = chr_bank_5;                        // $1400-$17FF mode 3, 1 kB
		6'b11_110_0: chrsel = chr_bank_6;                        // $1800-$1BFF mode 3, 1 kB
		6'b11_111_0: chrsel = chr_bank_7;                        // $1C00-$1FFF mode 3, 1 kB
		6'b11_?00_1: chrsel = chr_bank_8;                        // $0000-$03FF mode 3, 1 kB
		6'b11_?01_1: chrsel = chr_bank_9;                        // $0400-$07FF mode 3, 1 kB
		6'b11_?10_1: chrsel = chr_bank_a;                        // $0800-$0BFF mode 3, 1 kB
		6'b11_?11_1: chrsel = chr_bank_b;                        // $0C00-$0FFF mode 3, 1 kB
	endcase

	chr_aout = {2'b10, chrsel, chr_ain[9:0]};    // 1kB banks

	// Override |chr_aout| if we're in a vertical split.
	if (ppu_in_frame && insplit) begin
		//$write("In vertical split!\n");
//		chr_aout = {2'b10, vsplit_bank, chr_ain[11:3], vscroll[2:0]}; // SL
		chr_aout = {2'b10, vsplit_bank, chr_ain[11:3], chr_ain[2:0]}; // CL
	end else if (ppu_in_frame && extended_ram_mode == 1 && is_bg_fetch && ppu_is_tile_addr) begin
		//$write("In exram thingy!\n");
		// Extended attribute mode. Replace the page with the page from exram.
		chr_aout = {2'b10, upper_chr_bank_bits, last_read_exattr[5:0], chr_ain[11:0]};
	end

end

// The a10 VRAM address line. (Used for mirroring)
assign vram_a10 = mirrbits[0];
assign vram_ce = chr_ain[13] && !mirrbits[1];

// Writing to RAM is enabled only when the protect bits say so.
wire prg_ram_we = prg_protect_1 && prg_protect_2;
assign prg_allow = (prg_ain >= 16'h6000) && (!prg_write || ((!prgsel[7]) && prg_ram_we));

// MMC5 boards typically have no CHR RAM.
assign chr_allow = flags[15];

// savestate
always@(posedge clk) begin
	if (enable) begin
		if (Savestate_MAPRAMRdEn) begin
			Savestate_MAPRAMReadData <= last_read_ram;
		end
	end else begin
		Savestate_MAPRAMReadData <= 8'd0;
	end
end

localparam SAVESTATE_MODULES    = 5;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];
wire [63:0] SS_MAP1, SS_MAP2, SS_MAP3, SS_MAP4, SS_MAP5;
wire [63:0] SS_MAP1_BACK, SS_MAP2_BACK, SS_MAP3_BACK, SS_MAP4_BACK, SS_MAP5_BACK;	
wire [63:0] SaveStateBus_Dout_active = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1] | SaveStateBus_wired_or[2] | SaveStateBus_wired_or[3] | SaveStateBus_wired_or[4];
	
eReg_SavestateV #(SSREG_INDEX_MAP1, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[0], SS_MAP1_BACK, SS_MAP1);  
eReg_SavestateV #(SSREG_INDEX_MAP2, 64'h0000000000000000) iREG_SAVESTATE_MAP2 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[1], SS_MAP2_BACK, SS_MAP2);  
eReg_SavestateV #(SSREG_INDEX_MAP3, 64'h0000000000000000) iREG_SAVESTATE_MAP3 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[2], SS_MAP3_BACK, SS_MAP3);  
eReg_SavestateV #(SSREG_INDEX_MAP4, 64'h0000000000000000) iREG_SAVESTATE_MAP4 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[3], SS_MAP4_BACK, SS_MAP4);  
eReg_SavestateV #(SSREG_INDEX_MAP5, 64'h0000000000000000) iREG_SAVESTATE_MAP5 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[4], SS_MAP5_BACK, SS_MAP5);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule

module mmc5_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input         rden,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	output  [7:0] data_out,
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

// NOTE: The apu volume is 100% of MMC5 and the polarity is reversed.
wire [16:0] audio_o = audio + audio_in;
wire [15:0] audio;
assign audio_out = audio_o[16:1];

wire apu_cs = (addr_in[15:5]==11'b0101_0000_000) && (addr_in[3]==0);
wire DmaReq;          // 1 when DMC wants DMA
wire [15:0] DmaAddr;  // Address DMC wants to read
reg odd_or_even;
wire apu_irq;         // TODO: IRQ asserted

reg phi2;
always @(posedge clk) begin
	phi2 <= ce;
	if (~enable)
		odd_or_even <= 0;
	else if (ce)
		odd_or_even <= ~odd_or_even;
		
	if (SaveStateBus_load) begin
		odd_or_even <= SS_MAP1[0];
	end
end

assign SS_MAP1_BACK[    0] = odd_or_even;
assign SS_MAP1_BACK[63: 1] = 63'b0; // free to be used

APU mmc5apu(
	.MMC5           (1),
	.clk            (clk),
	.ce             (ce),
	.PHI2           (phi2),
	.CS             (apu_cs),
	.reset          (~enable | SaveStateBus_load),
	.ADDR           (addr_in[4:0]),
	.DIN            (data_in),
	.DOUT           (data_out),
	.RW             (~wren),
	.audio_channels (5'b10011),
	.Sample         (audio),
	.DmaReq         (DmaReq),
	.DmaAck         (1),
	.DmaAddr        (DmaAddr),
	.DmaData        (0),
	.odd_or_even    (odd_or_even),
	.IRQ            (apu_irq),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ), 
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (SaveStateBus_load ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[1])
);
defparam mmc5apu.SSREG_INDEX_TOP  = SSREG_INDEX_SNDMAP1;
defparam mmc5apu.SSREG_INDEX_DMC1 = SSREG_INDEX_SNDMAP2;
defparam mmc5apu.SSREG_INDEX_DMC2 = SSREG_INDEX_SNDMAP3;
defparam mmc5apu.SSREG_INDEX_FCT  = SSREG_INDEX_SNDMAP4;

// savestates
localparam SAVESTATE_MODULES    = 2;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];
wire [63:0] SS_MAP1;
wire [63:0] SS_MAP1_BACK;	
wire [63:0] SaveStateBus_Dout_active = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1];
	
eReg_SavestateV #(SSREG_INDEX_SNDMAP5, 64'h0000000000000000) iREG_SAVESTATE_MAP1 (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[0], SS_MAP1_BACK, SS_MAP1);  

assign SaveStateBus_Dout = enable ? SaveStateBus_Dout_active : 64'h0000000000000000;

endmodule
