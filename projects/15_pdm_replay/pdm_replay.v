// pdm_replay.v — PDM Sine Tone Replayer for iCESugar-Pro (ECP5-25F)
//
// Continuously replays a 64-sample 16-bit signed sine wave stored in ROM
// through the MAX98358 PDM amplifier, producing a ~763 Hz tone.
//
// Signal flow:
//   ROM (64 × 16-bit sine, init with `initial`) → zero-order hold
//                                               → 1st-order sigma-delta modulator
//                                               → 1-bit PDM @ 3.125 MHz
//                                               → MAX98358 PDM amp
//
// Timing:
//   PDM clock = 25 MHz / 8 = 3.125 MHz
//   PCM rate  = 3.125 MHz / 64 = ~48.828 kHz  (advances sine address)
//   Tone freq = 48828 Hz / 64 samples ≈ 763 Hz
//
// Reset button (rst_n = 0): sigma-delta accumulator cleared, pcm_held = 0
//   → amp outputs silence (≈50 % PDM duty cycle). Red LED on.
// Running (rst_n = 1): green LED on, sine replay active.

`default_nettype none

module pdm_replay (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset / hold-to-mute button

    // Status LEDs (active low)
    output wire led_r,      // Red:   on while held in reset (muted)
    output wire led_g,      // Green: on during normal replay
    output wire led_b,      // Blue:  unused (off)

    // MAX98358 PDM amplifier
    output wire amp_clk,    // PDM clock (3.125 MHz)
    output wire amp_dat     // Sigma-delta PDM output
);

    // =========================================================================
    // PDM clock generation: 25 MHz / 8 = 3.125 MHz
    // Toggle every 4 system clocks (period = 8 × 40 ns = 320 ns).
    // =========================================================================
    reg [2:0] clk_cnt;
    reg       pdm_clk_r;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt   <= 3'd0;
            pdm_clk_r <= 1'b0;
        end else begin
            if (clk_cnt == 3'd3) begin
                clk_cnt   <= 3'd0;
                pdm_clk_r <= ~pdm_clk_r;
            end else begin
                clk_cnt <= clk_cnt + 3'd1;
            end
        end
    end

    // Rising-edge strobe: one cycle at the start of each PDM clock high phase.
    reg pdm_clk_prev;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) pdm_clk_prev <= 1'b0;
        else        pdm_clk_prev <= pdm_clk_r;
    end

    wire pdm_valid = pdm_clk_r && !pdm_clk_prev;  // 3.125 MHz strobe

    // =========================================================================
    // PCM-rate divider: fire pcm_valid every 64 PDM clocks
    // → PCM rate = 3.125 MHz / 64 ≈ 48.828 kHz
    // → Sine tone = 48828 Hz / 64 samples ≈ 763 Hz
    // =========================================================================
    localparam DEC_RATIO = 6'd63;  // Count 0..63, fire at 63

    reg [5:0] dec_cnt;
    reg       pcm_valid;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            dec_cnt   <= 6'd0;
            pcm_valid <= 1'b0;
        end else begin
            pcm_valid <= 1'b0;
            if (pdm_valid) begin
                if (dec_cnt == DEC_RATIO) begin
                    dec_cnt   <= 6'd0;
                    pcm_valid <= 1'b1;
                end else begin
                    dec_cnt <= dec_cnt + 6'd1;
                end
            end
        end
    end

    // =========================================================================
    // Sine address counter: 6-bit, wraps mod 64 automatically
    // =========================================================================
    reg [5:0] sine_addr;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) sine_addr <= 6'd0;
        else if (pcm_valid) sine_addr <= sine_addr + 6'd1;
    end

    // =========================================================================
    // Sine ROM: 64 × 16-bit, initialized as 16-bit signed sine wave
    //   v[k] = round(32767 × sin(2π × k / 64))  for k = 0..63
    // Synthesized as LUT-based ROM by Yosys (no write port → read-only).
    // =========================================================================
    /* verilator lint_off LITENDIAN */
    reg signed [15:0] sine_rom [0:63];
    /* verilator lint_on LITENDIAN */

    initial begin
        //  k  decimal   hex
        sine_rom[ 0] = 16'h0000;  //       0
        sine_rom[ 1] = 16'h0C8C;  //    3212
        sine_rom[ 2] = 16'h18F9;  //    6393
        sine_rom[ 3] = 16'h2528;  //    9512
        sine_rom[ 4] = 16'h30FC;  //   12540
        sine_rom[ 5] = 16'h3C57;  //   15447
        sine_rom[ 6] = 16'h471D;  //   18205
        sine_rom[ 7] = 16'h5134;  //   20788
        sine_rom[ 8] = 16'h5A82;  //   23170
        sine_rom[ 9] = 16'h62F2;  //   25330
        sine_rom[10] = 16'h6A6D;  //   27245
        sine_rom[11] = 16'h70E2;  //   28898
        sine_rom[12] = 16'h7641;  //   30273
        sine_rom[13] = 16'h7A7D;  //   31357
        sine_rom[14] = 16'h7D8A;  //   32138
        sine_rom[15] = 16'h7F62;  //   32610
        sine_rom[16] = 16'h7FFF;  //   32767  ← positive peak
        sine_rom[17] = 16'h7F62;  //   32610
        sine_rom[18] = 16'h7D8A;  //   32138
        sine_rom[19] = 16'h7A7D;  //   31357
        sine_rom[20] = 16'h7641;  //   30273
        sine_rom[21] = 16'h70E2;  //   28898
        sine_rom[22] = 16'h6A6D;  //   27245
        sine_rom[23] = 16'h62F2;  //   25330
        sine_rom[24] = 16'h5A82;  //   23170
        sine_rom[25] = 16'h5134;  //   20788
        sine_rom[26] = 16'h471D;  //   18205
        sine_rom[27] = 16'h3C57;  //   15447
        sine_rom[28] = 16'h30FC;  //   12540
        sine_rom[29] = 16'h2528;  //    9512
        sine_rom[30] = 16'h18F9;  //    6393
        sine_rom[31] = 16'h0C8C;  //    3212
        sine_rom[32] = 16'h0000;  //       0  ← midpoint (second zero crossing)
        sine_rom[33] = 16'hF374;  //   -3212
        sine_rom[34] = 16'hE707;  //   -6393
        sine_rom[35] = 16'hDAD8;  //   -9512
        sine_rom[36] = 16'hCF04;  //  -12540
        sine_rom[37] = 16'hC3A9;  //  -15447
        sine_rom[38] = 16'hB8E3;  //  -18205
        sine_rom[39] = 16'hAECC;  //  -20788
        sine_rom[40] = 16'hA57E;  //  -23170
        sine_rom[41] = 16'h9D0E;  //  -25330
        sine_rom[42] = 16'h9593;  //  -27245
        sine_rom[43] = 16'h8F1E;  //  -28898
        sine_rom[44] = 16'h89BF;  //  -30273
        sine_rom[45] = 16'h8583;  //  -31357
        sine_rom[46] = 16'h8276;  //  -32138
        sine_rom[47] = 16'h809E;  //  -32610
        sine_rom[48] = 16'h8001;  //  -32767  ← negative peak
        sine_rom[49] = 16'h809E;  //  -32610
        sine_rom[50] = 16'h8276;  //  -32138
        sine_rom[51] = 16'h8583;  //  -31357
        sine_rom[52] = 16'h89BF;  //  -30273
        sine_rom[53] = 16'h8F1E;  //  -28898
        sine_rom[54] = 16'h9593;  //  -27245
        sine_rom[55] = 16'h9D0E;  //  -25330
        sine_rom[56] = 16'hA57E;  //  -23170
        sine_rom[57] = 16'hAECC;  //  -20788
        sine_rom[58] = 16'hB8E3;  //  -18205
        sine_rom[59] = 16'hC3A9;  //  -15447
        sine_rom[60] = 16'hCF04;  //  -12540
        sine_rom[61] = 16'hDAD8;  //   -9512
        sine_rom[62] = 16'hE707;  //   -6393
        sine_rom[63] = 16'hF374;  //   -3212
    end

    // =========================================================================
    // Zero-order hold: latch the current sine sample on each pcm_valid strobe.
    // Both pcm_held and sine_addr update on the same posedge, so pcm_held
    // receives sine_rom[sine_addr] before the address increments — correct ZOH.
    // =========================================================================
    reg signed [15:0] pcm_held;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)       pcm_held <= 16'sd0;
        else if (pcm_valid) pcm_held <= sine_rom[sine_addr] >>> 5;  // ÷32 attenuation
    end

    // =========================================================================
    // 1st-order sigma-delta modulator: PCM → PDM
    // Runs at PDM rate (pdm_valid strobe, 3.125 MHz).
    // =========================================================================
    wire amp_dat_w;

    pdm_modulator mod (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pcm_in    (pcm_held),
        .pdm_valid (pdm_valid),
        .pdm_out   (amp_dat_w)
    );

    // =========================================================================
    // Outputs
    // =========================================================================
    assign amp_clk = pdm_clk_r;
    assign amp_dat = amp_dat_w;

    // LEDs (active low): green on while running, red on while muted
    assign led_r = rst_n;    // Off when running (rst_n=1)
    assign led_g = ~rst_n;   // On when running
    assign led_b = 1'b1;     // Always off

endmodule

`default_nettype wire
