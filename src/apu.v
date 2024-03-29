// Rewritten 6/4/2020 by Kitrinx
// This code is GPLv3.

module LenCounterUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       len_clk,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic [7:0] load_value,
    input  logic       halt_in,
    input  logic       addr,
    input  logic       is_triangle,
    input  logic       write,
    input  logic       enabled,
    output logic       lc_on
);

    always_ff @(posedge clk) begin : lenunit
        logic [7:0] len_counter_int;
        logic halt, halt_next;
        logic [7:0] len_counter_next;
        logic lc_on_1;
        logic clear_next;

        if (aclk1_d)
            if (~enabled)
                lc_on <= 0;

        if (aclk1) begin
            lc_on_1 <= lc_on;
            len_counter_next <= halt || ~|len_counter_int ? len_counter_int : len_counter_int - 1'd1;
            clear_next <= ~halt && ~|len_counter_int;
        end

        if (write) begin
            if (~addr) begin
                halt <= halt_in;
            end else begin
                lc_on <= 1;
                len_counter_int <= load_value;
            end
        end

        // This deliberately can overwrite being loaded from writes
        if (len_clk && lc_on_1) begin
            len_counter_int <= halt ? len_counter_int : len_counter_next;
            if (clear_next)
                lc_on <= 0;
        end

        if (reset) begin
            if (~is_triangle || cold_reset) begin
                halt <= 0;
            end
            lc_on <= 0;
            len_counter_int <= 0;
            len_counter_next <= 0;
        end
    end

endmodule

module EnvelopeUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       env_clk,
    input  logic [5:0] din,
    input  logic       addr,
    input  logic       write,
    output logic [3:0] envelope
);

    logic [3:0] env_count, env_vol;
    logic env_disabled;

    assign envelope = env_disabled ? env_vol : env_count;

    always_ff @(posedge clk) begin : envunit
        logic [3:0] env_div;
        logic env_reload;
        logic env_loop;
        logic env_reset;

        if (env_clk) begin
            if (~env_reload) begin
                env_div <= env_div - 1'd1;
                if (~|env_div) begin
                    env_div <= env_vol;
                    if (|env_count || env_loop)
                        env_count <= env_count - 1'd1;
                end
            end else begin
                env_div <= env_vol;
                env_count <= 4'hF;
                env_reload <= 1'b0;
            end
        end

        if (write) begin
            if (~addr) {env_loop, env_disabled, env_vol} <= din;
            if (addr) env_reload <= 1;
        end

        if (reset) begin
            env_loop <= 0;
            env_div <= 0;
            env_vol <= 0;
            env_count <= 0;
            env_reload <= 0;
        end
    end

endmodule

module SquareChan (
    input  logic       MMC5,
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic       sq2,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       odd_or_even,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);

    // Register 1
    logic [1:0] Duty;

    // Register 2
    logic SweepEnable, SweepNegate, SweepReset;
    logic [2:0] SweepPeriod, SweepDivider, SweepShift;

    logic [10:0] Period;
    logic [11:0] TimerCtr;
    logic [2:0] SeqPos;
    logic [10:0] ShiftedPeriod;
    logic [10:0] PeriodRhs;
    logic [11:0] NewSweepPeriod;

    logic ValidFreq;
    logic subunit_write;
    logic [3:0] Envelope;
    logic lc;
    logic DutyEnabledUsed;
    logic DutyEnabled;

    assign DutyEnabledUsed = MMC5 ^ DutyEnabled;
    assign ShiftedPeriod = (Period >> SweepShift);
    assign PeriodRhs = (SweepNegate ? (~ShiftedPeriod + {10'b0, sq2}) : ShiftedPeriod);
    assign NewSweepPeriod = Period + PeriodRhs;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;
    assign IsNonZero = lc;

    assign ValidFreq = (MMC5 && allow_us) || ((|Period[10:3]) && (SweepNegate || ~NewSweepPeriod[11]));
    assign Sample = (~lc | ~ValidFreq | ~DutyEnabledUsed) ? 4'd0 : Envelope;

    LenCounterUnit LenSq (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (MMC5 ? Env_Clock : LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvSq (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    always_comb begin
        // The wave forms nad barrel shifter are abstracted simply here
        case (Duty)
            0: DutyEnabled = (SeqPos == 7);
            1: DutyEnabled = (SeqPos >= 6);
            2: DutyEnabled = (SeqPos >= 4);
            3: DutyEnabled = (SeqPos < 6);
        endcase
    end

    always_ff @(posedge clk) begin : sqblock
        // Unusual to APU design, the square timers are clocked overlapping two phi2. This
        // means that writes can impact this operation as they happen, however because of the way
        // the results are presented, we can simply delay it rather than adding complexity for
        // the same results.

        if (aclk1_d) begin
            if (TimerCtr == 0) begin
                TimerCtr <= {1'b0, Period};
                SeqPos <= SeqPos - 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        // Sweep Unit
        if (LenCtr_Clock) begin
            if (SweepDivider == 0) begin
                SweepDivider <= SweepPeriod;
                if (SweepEnable && SweepShift != 0 && ValidFreq)
                    Period <= NewSweepPeriod[10:0];
            end else begin
                SweepDivider <= SweepDivider - 1'd1;
            end
            if (SweepReset)
                SweepDivider <= SweepPeriod;
            SweepReset <= 0;
        end

        if (write) begin
            case (Addr)
                0: Duty <= DIN[7:6];
                1: if (~MMC5) begin
                    {SweepEnable, SweepPeriod, SweepNegate, SweepShift} <= DIN;
                    SweepReset <= 1;
                end
                2: Period[7:0] <= DIN;
                3: begin
                    Period[10:8] <= DIN[2:0];
                    SeqPos <= 0;
                end
            endcase
        end

        if (reset) begin
            Duty <= 0;
            SweepEnable <= 0;
            SweepNegate <= 0;
            SweepReset <= 0;
            SweepPeriod <= 0;
            SweepDivider <= 0;
            SweepShift <= 0;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
        end
    end

endmodule

module TriangleChan (
    input  logic       clk,
    input  logic       phi1,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       LinCtr_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);
    logic [10:0] Period, applied_period, TimerCtr;
    logic [4:0] SeqPos;
    logic [6:0] LinCtrPeriod, LinCtrPeriod_1, LinCtr;
    logic LinCtrl, line_reload;
    logic LinCtrZero;
    logic lc;

    logic LenCtrZero;
    logic subunit_write;
    logic [3:0] sample_latch;

    assign LinCtrZero = ~|LinCtr;
    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    assign Sample = (applied_period > 1 || allow_us) ? (SeqPos[3:0] ^ {4{~SeqPos[4]}}) : sample_latch;

    LenCounterUnit LenTri (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[7]),
        .addr           (Addr[0]),
        .is_triangle    (1'b1),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    always_ff @(posedge clk) begin
        if (phi1) begin
            if (TimerCtr == 0) begin
                TimerCtr <= Period;
                applied_period <= Period;
                if (IsNonZero & ~LinCtrZero)
                    SeqPos <= SeqPos + 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        if (aclk1) begin
            LinCtrPeriod_1 <= LinCtrPeriod;
        end

        if (LinCtr_Clock) begin
            if (line_reload)
                LinCtr <= LinCtrPeriod_1;
            else if (!LinCtrZero)
                LinCtr <= LinCtr - 1'd1;

            if (!LinCtrl)
                line_reload <= 0;
        end

        if (write) begin
            case (Addr)
                0: begin
                    LinCtrl <= DIN[7];
                    LinCtrPeriod <= DIN[6:0];
                end
                2: begin
                    Period[7:0] <= DIN;
                end
                3: begin
                    Period[10:8] <= DIN[2:0];
                    line_reload <= 1;
                end
            endcase
        end

        if (reset) begin
            sample_latch <= 4'hF;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
            LinCtrPeriod <= 0;
            LinCtr <= 0;
            LinCtrl <= 0;
            line_reload <= 0;
        end

        if (applied_period > 1) sample_latch <= Sample;
    end

endmodule

module NoiseChan (
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       PAL,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);
    logic ShortMode;
    logic [14:0] Shift;
    logic [3:0] Period;
    logic [11:0] NoisePeriod, TimerCtr;
    logic [3:0] Envelope;
    logic subunit_write;
    logic lc;

    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    // Produce the output signal
    assign Sample = (~lc || Shift[14]) ? 4'd0 : Envelope;

    LenCounterUnit LenNoi (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvNoi (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    logic [10:0] noise_pal_lut[16];
    assign noise_pal_lut = '{
        11'h200, 11'h280, 11'h550, 11'h5D5,
        11'h393, 11'h74F, 11'h61B, 11'h41F,
        11'h661, 11'h1C5, 11'h6AE, 11'h093,
        11'h4FE, 11'h12D, 11'h679, 11'h392
    };

    // Values read directly from the netlist
    logic [10:0] noise_ntsc_lut[16];
    assign noise_ntsc_lut = '{
        11'h200, 11'h280, 11'h2A8, 11'h6EA,
        11'h4E4, 11'h674, 11'h630, 11'h730,
        11'h4AC, 11'h304, 11'h722, 11'h230,
        11'h213, 11'h782, 11'h006, 11'h014
    };

    logic [10:0] noise_timer;
    logic noise_clock;
    always_ff @(posedge clk) begin
        if (aclk1_d) begin
            noise_timer <= {noise_timer[9:0], (noise_timer[10] ^ noise_timer[8]) | ~|noise_timer};

            if (noise_clock) begin
                noise_clock <= 0;
                noise_timer <= PAL ? noise_pal_lut[Period] : noise_ntsc_lut[Period];
                Shift <= {Shift[13:0], ((Shift[14] ^ (ShortMode ? Shift[8] : Shift[13])) | ~|Shift)};
            end
        end

        if (aclk1) begin
            if (noise_timer == 'h400)
                noise_clock <= 1;
        end

        if (write && Addr == 2) begin
            ShortMode <= DIN[7];
            Period <= DIN[3:0];
        end

        if (reset) begin
            if (|noise_timer) noise_timer <= (PAL ? noise_pal_lut[0] : noise_ntsc_lut[0]);
            ShortMode <= 0;
            Shift <= 0;
            Period <= 0;
        end

        if (cold_reset)
            noise_timer <= 0;
    end
endmodule

module DmcChan (
    input  logic        MMC5,
    input  logic        clk,
    input  logic        aclk1,
    input  logic        aclk1_d,
    input  logic        reset,
    input  logic        cold_reset,
    input  logic  [2:0] ain,
    input  logic  [7:0] DIN,
    input  logic        write,
    input  logic        dma_ack,      // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
    input  logic  [7:0] dma_data,     // Input data to DMC from memory.
    input  logic        PAL,
    output logic [15:0] dma_address,     // Address DMC wants to read
    output logic        irq,
    output logic  [6:0] Sample,
    output logic        dma_req,      // 1 when DMC wants DMA
    output logic        enable
);
    logic irq_enable;
    logic loop;                 // Looping enabled
    logic [3:0] frequency;           // Current value of frequency register
    logic [7:0] sample_address;  // Base address of sample
    logic [7:0] sample_length;      // Length of sample
    logic [11:0] bytes_remaining;      // 12 bits bytes left counter 0 - 4081.
    logic [7:0] sample_buffer;    // Next value to be loaded into shift reg

    logic [8:0] dmc_lsfr;
    logic [7:0] dmc_volume, dmc_volume_next;
    logic dmc_silence;
    logic have_buffer;
    logic [7:0] sample_shift;
    logic [2:0] dmc_bits; // Simply an 8 cycle counter.
    logic enable_1, enable_2, enable_3;

    logic [8:0] pal_pitch_lut[16];
    assign pal_pitch_lut = '{
        9'h1D7, 9'h067, 9'h0D9, 9'h143,
        9'h1E1, 9'h07B, 9'h05C, 9'h132,
        9'h04A, 9'h1A3, 9'h1CF, 9'h1CD,
        9'h02A, 9'h11C, 9'h11B, 9'h157
    };

    logic [8:0] ntsc_pitch_lut[16];
    assign ntsc_pitch_lut = '{
        9'h19D, 9'h0A2, 9'h185, 9'h1B6,
        9'h0EF, 9'h1F8, 9'h17C, 9'h117,
        9'h120, 9'h076, 9'h11E, 9'h13E,
        9'h162, 9'h123, 9'h0E3, 9'h0D5
    };

    assign Sample = dmc_volume_next[6:0];
    assign dma_req = ~have_buffer & enable & enable_3;
    logic dmc_clock;


    logic reload_next;
    always_ff @(posedge clk) begin
        dma_address[15] <= 1;
        if (write) begin
            case (ain)
                0: begin  // $4010
                        irq_enable <= DIN[7];
                        loop <= DIN[6];
                        frequency <= DIN[3:0];
                        if (~DIN[7]) irq <= 0;
                    end
                1: begin  // $4011 Applies immediately, can be overwritten before aclk1
                        dmc_volume <= {MMC5 & DIN[7], DIN[6:0]};
                    end
                2: begin  // $4012
                        sample_address <= MMC5 ? 8'h00 : DIN[7:0];
                    end
                3: begin  // $4013
                        sample_length <= MMC5 ? 8'h00 : DIN[7:0];
                    end
                5: begin // $4015
                        irq <= 0;
                        enable <= DIN[4];

                        if (DIN[4] && ~enable) begin
                            dma_address[14:0] <= {1'b1, sample_address[7:0], 6'h00};
                            bytes_remaining <= {sample_length, 4'h0};
                        end
                    end
            endcase
        end

        if (aclk1_d) begin
            enable_1 <= enable;
            enable_2 <= enable_1;
            dmc_lsfr <= {dmc_lsfr[7:0], (dmc_lsfr[8] ^ dmc_lsfr[4]) | ~|dmc_lsfr};

            if (dmc_clock) begin
                dmc_clock <= 0;
                dmc_lsfr <= PAL ? pal_pitch_lut[frequency] : ntsc_pitch_lut[frequency];
                sample_shift <= {1'b0, sample_shift[7:1]};
                dmc_bits <= dmc_bits + 1'd1;

                if (&dmc_bits) begin
                    dmc_silence <= ~have_buffer;
                    sample_shift <= sample_buffer;
                    have_buffer <= 0;
                end

                if (~dmc_silence) begin
                    if (~sample_shift[0]) begin
                        if (|dmc_volume_next[6:1])
                            dmc_volume[6:1] <= dmc_volume_next[6:1] - 1'd1;
                    end else begin
                        if(~&dmc_volume_next[6:1])
                            dmc_volume[6:1] <= dmc_volume_next[6:1] + 1'd1;
                    end
                end
            end

            // The data is technically clocked at phi2, but because of our implementation, to
            // ensure the right data is latched, we do it on the falling edge of phi2.
            if (dma_ack) begin
                dma_address[14:0] <= dma_address[14:0] + 1'd1;
                have_buffer <= 1;
                sample_buffer <= dma_data;

                if (|bytes_remaining)
                    bytes_remaining <= bytes_remaining - 1'd1;
                else begin
                    dma_address[14:0] <= {1'b1, sample_address[7:0], 6'h0};
                    bytes_remaining <= {sample_length, 4'h0};
                    enable <= loop;
                    if (~loop & irq_enable)
                        irq <= 1;
                end
            end
        end

        // Volume adjustment is done on aclk1. Technically, the value written to 4011 is immediately
        // applied, but won't "stick" if it conflicts with a lsfr clocked do-adjust.
        if (aclk1) begin
            enable_1 <= enable;
            enable_3 <= enable_2;

            dmc_volume_next <= dmc_volume;

            if (dmc_lsfr == 9'h100) begin
                dmc_clock <= 1;
            end
        end

        if (reset) begin
            irq <= 0;
            dmc_volume <= {7'h0, dmc_volume[0]};
            dmc_volume_next <= {7'h0, dmc_volume[0]};
            sample_shift <= 8'h0;
            if (|dmc_lsfr) dmc_lsfr <= (PAL ? pal_pitch_lut[0] : ntsc_pitch_lut[0]);
            bytes_remaining <= 0;
            dmc_bits <= 0;
            sample_buffer <= 0;
            have_buffer <= 0;
            enable <= 0;
            enable_1 <= 0;
            enable_2 <= 0;
            enable_3 <= 0;
            dma_address[14:0] <= 15'h0000;
        end

        if (cold_reset) begin
            dmc_lsfr <= 0;
            loop <= 0;
            frequency <= 0;
            irq_enable <= 0;
            dmc_volume <= 0;
            dmc_volume_next <= 0;
            sample_address <= 0;
            sample_length <= 0;
        end

    end

endmodule

module FrameCtr (
    input  logic clk,
    input  logic aclk1,
    input  logic aclk2,
    input  logic reset,
    input  logic cold_reset,
    input  logic write,
    input  logic read,
    input  logic write_ce,
    input  logic [7:0] din,
    input  logic [1:0] addr,
    input  logic PAL,
    input  logic MMC5,
    output logic irq,
    output logic irq_flag,
    output logic frame_half,
    output logic frame_quarter
);

    // NTSC -- Confirmed
    // Binary Frame Value         Decimal  Cycle
    // 15'b001_0000_0110_0001,    04193    03713 -- Quarter
    // 15'b011_0110_0000_0011,    13827    07441 -- Half
    // 15'b010_1100_1101_0011,    11475    11170 -- 3 quarter
    // 15'b000_1010_0001_1111,    02591    14899 -- Reset w/o Seq/Interrupt
    // 15'b111_0001_1000_0101     29061    18625 -- Reset w/ seq

    // PAL -- Speculative
    // Binary Frame Value         Decimal  Cycle
    // 15'b001_1111_1010_0100     08100    04156
    // 15'b100_0100_0011_0000     17456    08313
    // 15'b101_1000_0001_0101     22549    12469
    // 15'b000_1011_1110_1000     03048    16625
    // 15'b000_0100_1111_1010     01274    20782

    logic frame_reset;
    logic frame_interrupt_buffer;
    logic frame_int_disabled;
    logic FrameInterrupt;
    logic frame_irq, set_irq;
    logic FrameSeqMode_2;
    logic frame_reset_2;
    logic w4017_1, w4017_2;
    logic [14:0] frame;

    // Register 4017
    logic DisableFrameInterrupt;
    logic FrameSeqMode;

    assign frame_int_disabled = DisableFrameInterrupt; // | (write && addr == 5'h17 && din[6]);
    assign irq = FrameInterrupt && ~DisableFrameInterrupt;
    assign irq_flag = frame_interrupt_buffer;

    // This is implemented from the original LSFR frame counter logic taken from the 2A03 netlists. The
    // PAL LFSR numbers are educated guesses based on existing observed cycle numbers, but they may not
    // be perfectly correct.

    logic seq_mode;
    assign seq_mode = aclk1 ? FrameSeqMode : FrameSeqMode_2;

    logic frm_a, frm_b, frm_c, frm_d, frm_e;
    assign frm_a = (PAL ? 15'b001_1111_1010_0100 : 15'b001_0000_0110_0001) == frame;
    assign frm_b = (PAL ? 15'b100_0100_0011_0000 : 15'b011_0110_0000_0011) == frame;
    assign frm_c = (PAL ? 15'b101_1000_0001_0101 : 15'b010_1100_1101_0011) == frame;
    assign frm_d = (PAL ? 15'b000_1011_1110_1000 : 15'b000_1010_0001_1111) == frame && ~seq_mode;
    assign frm_e = (PAL ? 15'b000_0100_1111_1010 : 15'b111_0001_1000_0101) == frame;

    assign set_irq = frm_d & ~FrameSeqMode;
    assign frame_reset = frm_d | frm_e | w4017_2;
    assign frame_half = (frm_b | frm_d | frm_e | (w4017_2 & seq_mode));
    assign frame_quarter = (frm_a | frm_b | frm_c | frm_d | frm_e | (w4017_2 & seq_mode));

    always_ff @(posedge clk) begin : apu_block

        if (aclk1) begin
            frame <= frame_reset_2 ? 15'h7FFF : {frame[13:0], ((frame[14] ^ frame[13]) | ~|frame)};
            w4017_2 <= w4017_1;
            w4017_1 <= 0;
            FrameSeqMode_2 <= FrameSeqMode;
            frame_reset_2 <= 0;
        end

        if (aclk2 & frame_reset)
            frame_reset_2 <= 1;

        // Continously update the Frame IRQ state and read buffer
        if (set_irq & ~frame_int_disabled) begin
            FrameInterrupt <= 1;
            frame_interrupt_buffer <= 1;
        end else if (addr == 2'h1 && read)
            FrameInterrupt <= 0;
        else
            frame_interrupt_buffer <= FrameInterrupt;

        if (frame_int_disabled)
            FrameInterrupt <= 0;

        if (write_ce && addr == 3 && ~MMC5) begin  // Register $4017
            FrameSeqMode <= din[7];
            DisableFrameInterrupt <= din[6];
            w4017_1 <= 1;
        end

        if (reset) begin
            FrameInterrupt <= 0;
            frame_interrupt_buffer <= 0;
            w4017_1 <= 0;
            w4017_2 <= 0;
            DisableFrameInterrupt <= 0;
            if (cold_reset) FrameSeqMode <= 0; // Don't reset this on warm reset
            frame <= 15'h7FFF;
        end
    end

endmodule

module APU (
    input  logic        MMC5,
    input  logic        clk,
    input  logic        PHI2,
    input  logic        ce,
    input  logic        reset,
    input  logic        cold_reset,
    input  logic        allow_us,       // Set to 1 to allow ultrasonic frequencies
    input  logic        PAL,
    input  logic  [4:0] ADDR,           // APU Address Line
    input  logic  [7:0] DIN,            // Data to APU
    input  logic        RW,
    input  logic        CS,
    input  logic  [4:0] audio_channels, // Enabled audio channels
    input  logic  [7:0] DmaData,        // Input data to DMC from memory.
    input  logic        odd_or_even,
    input  logic        DmaAck,         // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
    output logic  [7:0] DOUT,           // Data from APU
    output logic [15:0] Sample,
    output logic        DmaReq,         // 1 when DMC wants DMA
    output logic [15:0] DmaAddr,        // Address DMC wants to read
    output logic        IRQ             // IRQ asserted high == asserted
);

    logic [7:0] len_counter_lut[32];
    assign len_counter_lut = '{
        8'h09, 8'hFD, 8'h13, 8'h01,
        8'h27, 8'h03, 8'h4F, 8'h05,
        8'h9F, 8'h07, 8'h3B, 8'h09,
        8'h0D, 8'h0B, 8'h19, 8'h0D,
        8'h0B, 8'h0F, 8'h17, 8'h11,
        8'h2F, 8'h13, 8'h5F, 8'h15,
        8'hBF, 8'h17, 8'h47, 8'h19,
        8'h0F, 8'h1B, 8'h1F, 8'h1D
    };

    logic [7:0] lc_load;
    assign lc_load = len_counter_lut[DIN[7:3]];

    // APU reads and writes happen at Phi2 of the 6502 core. Note: Not M2.
    logic read, read_old;
    logic write, write_ce, write_old;
    logic phi2_old, phi2_ce;

    assign read = RW & CS;
    assign write = ~RW & CS;
    assign phi2_ce = PHI2 & ~phi2_old;
    assign write_ce = write & phi2_ce;

    // The APU has four primary clocking events that take place:
    // aclk1    -- Aligned with CPU phi1, but every other cpu tick. This drives the majority of the APU
    // aclk1_d  -- Aclk1, except delayed by 1 cpu cycle exactly. Drives he half/quarter signals and len counter
    // aclk2    -- Aligned with CPU phi2, also every other frame
    // write    -- Happens on CPU phi2 (Not M2!). Most of these are latched by one of the above clocks.
    logic aclk1, aclk2, aclk1_delayed, phi1;
    assign aclk1 = ce & odd_or_even;          // Defined as the cpu tick when the frame counter increases
    assign aclk2 = phi2_ce & ~odd_or_even;                   // Tick on odd cycles, not 50% duty cycle so it covers 2 cpu cycles
    assign aclk1_delayed = ce & ~odd_or_even; // Ticks 1 cpu cycle after frame counter
    assign phi1 = ce;

    logic [4:0] Enabled;
    logic [3:0] Sq1Sample,Sq2Sample,TriSample,NoiSample;
    logic [6:0] DmcSample;
    logic DmcIrq;
    logic IsDmcActive;

    logic irq_flag;
    logic frame_irq;

    // Generate internal memory write signals
    logic ApuMW0, ApuMW1, ApuMW2, ApuMW3, ApuMW4, ApuMW5;
    assign ApuMW0 = ADDR[4:2]==0; // SQ1
    assign ApuMW1 = ADDR[4:2]==1; // SQ2
    assign ApuMW2 = ADDR[4:2]==2; // TRI
    assign ApuMW3 = ADDR[4:2]==3; // NOI
    assign ApuMW4 = ADDR[4:2]>=4; // DMC
    assign ApuMW5 = ADDR[4:2]==5; // Control registers

    logic Sq1NonZero, Sq2NonZero, TriNonZero, NoiNonZero;
    logic ClkE, ClkL;

    logic [4:0] enabled_buffer, enabled_buffer_1;
    assign Enabled = aclk1 ? enabled_buffer : enabled_buffer_1;

    always_ff @(posedge clk) begin
        phi2_old <= PHI2;

        if (aclk1) begin
            enabled_buffer_1 <= enabled_buffer;
        end

        if (ApuMW5 && write && ADDR[1:0] == 1) begin
            enabled_buffer <= DIN[4:0]; // Register $4015
        end

        if (reset) begin
            enabled_buffer <= 0;
            enabled_buffer_1 <= 0;
        end
    end

    logic frame_quarter, frame_half;
    assign ClkE = (frame_quarter & aclk1_delayed);
    assign ClkL = (frame_half & aclk1_delayed);

    // Generate bus output
    assign DOUT = {DmcIrq, irq_flag, 1'b0, IsDmcActive, NoiNonZero, TriNonZero,
        Sq2NonZero, Sq1NonZero};

    assign IRQ = frame_irq || DmcIrq;

    // Generate each channel
    SquareChan Squ1 (
        .MMC5         (MMC5),
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),
        .sq2          (1'b0),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW0 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .odd_or_even  (odd_or_even),
        .Enabled      (Enabled[0]),
        .Sample       (Sq1Sample),
        .IsNonZero    (Sq1NonZero)
    );

    SquareChan Squ2 (
        .MMC5         (MMC5),
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),       // nand2mario
        .sq2          (1'b1),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW1 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .odd_or_even  (odd_or_even),
        .Enabled      (Enabled[1]),
        .Sample       (Sq2Sample),
        .IsNonZero    (Sq2NonZero)
    );

    TriangleChan Tri (
        .clk          (clk),
        .phi1         (phi1),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW2 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .LinCtr_Clock (ClkE),
        .Enabled      (Enabled[2]),
        .Sample       (TriSample),
        .IsNonZero    (TriNonZero)
    );

    NoiseChan Noi (
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .PAL          (PAL),
        .write        (ApuMW3 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .Enabled      (Enabled[3]),
        .Sample       (NoiSample),
        .IsNonZero    (NoiNonZero)
    );

    DmcChan Dmc (
        .MMC5        (MMC5),
        .clk         (clk),
        .aclk1       (aclk1),
        .aclk1_d     (aclk1_delayed),
        .reset       (reset),
        .cold_reset  (cold_reset),
        .ain         (ADDR[2:0]),
        .DIN         (DIN),
        .write       (write & ApuMW4),
        .dma_ack     (DmaAck),
        .dma_data    (DmaData),
        .PAL         (PAL),
        .dma_address (DmaAddr),
        .irq         (DmcIrq),
        .Sample      (DmcSample),
        .dma_req     (DmaReq),
        .enable      (IsDmcActive)
    );

    APUMixer mixer (
        .square1      (Sq1Sample),
        .square2      (Sq2Sample),
        .noise        (NoiSample),
        .triangle     (TriSample),
        .dmc          (DmcSample),
        .sample       (Sample)
    );

    FrameCtr frame_counter (
        .clk          (clk),
        .aclk1        (aclk1),
        .aclk2        (aclk2),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .write        (ApuMW5 & write),
        .read         (ApuMW5 & read),
        .write_ce     (ApuMW5 & write_ce),
        .addr         (ADDR[1:0]),
        .din          (DIN),
        .PAL          (PAL),
        .MMC5         (MMC5),
        .irq          (frame_irq),
        .irq_flag     (irq_flag),
        .frame_half   (frame_half),
        .frame_quarter(frame_quarter)
    );

endmodule

// http://wiki.nesdev.com/w/index.php/APU_Mixer
// I generated three LUT's for each mix channel entry and one lut for the squares, then a
// 284 entry lut for the mix channel. It's more accurate than the original LUT system listed on
// the NesDev page. In addition I boosted the square channel 10% and lowered the mix channel 10%
// to more closely match real systems.

module APUMixer (
    input  logic  [3:0] square1,
    input  logic  [3:0] square2,
    input  logic  [3:0] triangle,
    input  logic  [3:0] noise,
    input  logic  [6:0] dmc,
    output logic [15:0] sample
);

logic [15:0] pulse_lut[32];
assign pulse_lut = '{
    16'h0000, 16'h0331, 16'h064F, 16'h0959, 16'h0C52, 16'h0F38, 16'h120E, 16'h14D3,
    16'h1788, 16'h1A2E, 16'h1CC6, 16'h1F4E, 16'h21C9, 16'h2437, 16'h2697, 16'h28EB,
    16'h2B32, 16'h2D6E, 16'h2F9E, 16'h31C3, 16'h33DD, 16'h35EC, 16'h37F2, 16'h39ED,
    16'h3BDF, 16'h3DC7, 16'h3FA6, 16'h417D, 16'h434B, 16'h4510, 16'h46CD, 16'h0000
};

logic [5:0] tri_lut[16];
assign tri_lut = '{
    6'h00, 6'h04, 6'h08, 6'h0C, 6'h10, 6'h14, 6'h18, 6'h1C,
    6'h20, 6'h24, 6'h28, 6'h2C, 6'h30, 6'h34, 6'h38, 6'h3C
};

logic [5:0] noise_lut[16];
assign noise_lut = '{
    6'h00, 6'h03, 6'h05, 6'h08, 6'h0B, 6'h0D, 6'h10, 6'h13,
    6'h15, 6'h18, 6'h1B, 6'h1D, 6'h20, 6'h23, 6'h25, 6'h28
};

logic [7:0] dmc_lut[128];
assign dmc_lut = '{
    8'h00, 8'h01, 8'h03, 8'h04, 8'h06, 8'h07, 8'h09, 8'h0A,
    8'h0C, 8'h0D, 8'h0E, 8'h10, 8'h11, 8'h13, 8'h14, 8'h16,
    8'h17, 8'h19, 8'h1A, 8'h1C, 8'h1D, 8'h1E, 8'h20, 8'h21,
    8'h23, 8'h24, 8'h26, 8'h27, 8'h29, 8'h2A, 8'h2B, 8'h2D,
    8'h2E, 8'h30, 8'h31, 8'h33, 8'h34, 8'h36, 8'h37, 8'h38,
    8'h3A, 8'h3B, 8'h3D, 8'h3E, 8'h40, 8'h41, 8'h43, 8'h44,
    8'h45, 8'h47, 8'h48, 8'h4A, 8'h4B, 8'h4D, 8'h4E, 8'h50,
    8'h51, 8'h53, 8'h54, 8'h55, 8'h57, 8'h58, 8'h5A, 8'h5B,
    8'h5D, 8'h5E, 8'h60, 8'h61, 8'h62, 8'h64, 8'h65, 8'h67,
    8'h68, 8'h6A, 8'h6B, 8'h6D, 8'h6E, 8'h6F, 8'h71, 8'h72,
    8'h74, 8'h75, 8'h77, 8'h78, 8'h7A, 8'h7B, 8'h7C, 8'h7E,
    8'h7F, 8'h81, 8'h82, 8'h84, 8'h85, 8'h87, 8'h88, 8'h8A,
    8'h8B, 8'h8C, 8'h8E, 8'h8F, 8'h91, 8'h92, 8'h94, 8'h95,
    8'h97, 8'h98, 8'h99, 8'h9B, 8'h9C, 8'h9E, 8'h9F, 8'hA1,
    8'hA2, 8'hA4, 8'hA5, 8'hA6, 8'hA8, 8'hA9, 8'hAB, 8'hAC,
    8'hAE, 8'hAF, 8'hB1, 8'hB2, 8'hB3, 8'hB5, 8'hB6, 8'hB8
};

logic [15:0] mix_lut[512];
assign mix_lut = '{
    16'h0000, 16'h0128, 16'h024F, 16'h0374, 16'h0497, 16'h05B8, 16'h06D7, 16'h07F5,
    16'h0911, 16'h0A2B, 16'h0B44, 16'h0C5B, 16'h0D71, 16'h0E84, 16'h0F96, 16'h10A7,
    16'h11B6, 16'h12C3, 16'h13CF, 16'h14DA, 16'h15E2, 16'h16EA, 16'h17EF, 16'h18F4,
    16'h19F6, 16'h1AF8, 16'h1BF7, 16'h1CF6, 16'h1DF3, 16'h1EEE, 16'h1FE9, 16'h20E1,
    16'h21D9, 16'h22CF, 16'h23C3, 16'h24B7, 16'h25A9, 16'h2699, 16'h2788, 16'h2876,
    16'h2963, 16'h2A4F, 16'h2B39, 16'h2C22, 16'h2D09, 16'h2DF0, 16'h2ED5, 16'h2FB9,
    16'h309B, 16'h317D, 16'h325D, 16'h333C, 16'h341A, 16'h34F7, 16'h35D3, 16'h36AD,
    16'h3787, 16'h385F, 16'h3936, 16'h3A0C, 16'h3AE1, 16'h3BB5, 16'h3C87, 16'h3D59,
    16'h3E29, 16'h3EF9, 16'h3FC7, 16'h4095, 16'h4161, 16'h422C, 16'h42F7, 16'h43C0,
    16'h4488, 16'h4550, 16'h4616, 16'h46DB, 16'h47A0, 16'h4863, 16'h4925, 16'h49E7,
    16'h4AA7, 16'h4B67, 16'h4C25, 16'h4CE3, 16'h4DA0, 16'h4E5C, 16'h4F17, 16'h4FD1,
    16'h508A, 16'h5142, 16'h51F9, 16'h52B0, 16'h5365, 16'h541A, 16'h54CE, 16'h5581,
    16'h5633, 16'h56E5, 16'h5795, 16'h5845, 16'h58F4, 16'h59A2, 16'h5A4F, 16'h5AFC,
    16'h5BA7, 16'h5C52, 16'h5CFC, 16'h5DA5, 16'h5E4E, 16'h5EF6, 16'h5F9D, 16'h6043,
    16'h60E8, 16'h618D, 16'h6231, 16'h62D4, 16'h6377, 16'h6418, 16'h64B9, 16'h655A,
    16'h65F9, 16'h6698, 16'h6736, 16'h67D4, 16'h6871, 16'h690D, 16'h69A8, 16'h6A43,
    16'h6ADD, 16'h6B76, 16'h6C0F, 16'h6CA7, 16'h6D3E, 16'h6DD5, 16'h6E6B, 16'h6F00,
    16'h6F95, 16'h7029, 16'h70BD, 16'h7150, 16'h71E2, 16'h7273, 16'h7304, 16'h7395,
    16'h7424, 16'h74B4, 16'h7542, 16'h75D0, 16'h765D, 16'h76EA, 16'h7776, 16'h7802,
    16'h788D, 16'h7917, 16'h79A1, 16'h7A2A, 16'h7AB3, 16'h7B3B, 16'h7BC3, 16'h7C4A,
    16'h7CD0, 16'h7D56, 16'h7DDB, 16'h7E60, 16'h7EE4, 16'h7F68, 16'h7FEB, 16'h806E,
    16'h80F0, 16'h8172, 16'h81F3, 16'h8274, 16'h82F4, 16'h8373, 16'h83F2, 16'h8471,
    16'h84EF, 16'h856C, 16'h85E9, 16'h8666, 16'h86E2, 16'h875E, 16'h87D9, 16'h8853,
    16'h88CD, 16'h8947, 16'h89C0, 16'h8A39, 16'h8AB1, 16'h8B29, 16'h8BA0, 16'h8C17,
    16'h8C8E, 16'h8D03, 16'h8D79, 16'h8DEE, 16'h8E63, 16'h8ED7, 16'h8F4A, 16'h8FBE,
    16'h9030, 16'h90A3, 16'h9115, 16'h9186, 16'h91F7, 16'h9268, 16'h92D8, 16'h9348,
    16'h93B8, 16'h9427, 16'h9495, 16'h9503, 16'h9571, 16'h95DF, 16'h964C, 16'h96B8,
    16'h9724, 16'h9790, 16'h97FB, 16'h9866, 16'h98D1, 16'h993B, 16'h99A5, 16'h9A0E,
    16'h9A77, 16'h9AE0, 16'h9B48, 16'h9BB0, 16'h9C18, 16'h9C7F, 16'h9CE6, 16'h9D4C,
    16'h9DB2, 16'h9E18, 16'h9E7D, 16'h9EE2, 16'h9F47, 16'h9FAB, 16'hA00F, 16'hA073,
    16'hA0D6, 16'hA139, 16'hA19B, 16'hA1FD, 16'hA25F, 16'hA2C1, 16'hA322, 16'hA383,
    16'hA3E3, 16'hA443, 16'hA4A3, 16'hA502, 16'hA562, 16'hA5C0, 16'hA61F, 16'hA67D,
    16'hA6DB, 16'hA738, 16'hA796, 16'hA7F2, 16'hA84F, 16'hA8AB, 16'hA907, 16'hA963,
    16'hA9BE, 16'hAA19, 16'hAA74, 16'hAACE, 16'hAB28, 16'hAB82, 16'hABDB, 16'hAC35,
    16'hAC8E, 16'hACE6, 16'hAD3E, 16'hAD96, 16'hADEE, 16'hAE46, 16'hAE9D, 16'hAEF4,
    16'hAF4A, 16'hAFA0, 16'hAFF6, 16'hB04C, 16'hB0A2, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
    16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000
};

wire [4:0] squares = square1 + square2;
wire [15:0] ch1 = pulse_lut[squares];
wire [8:0] mix = 9'(tri_lut[triangle]) + 9'(noise_lut[noise]) + 9'(dmc_lut[dmc]);
wire [15:0] ch2 = mix_lut[mix];

assign sample = ch1 + ch2;

endmodule
