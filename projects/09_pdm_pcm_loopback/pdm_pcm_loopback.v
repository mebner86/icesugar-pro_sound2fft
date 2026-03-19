// PDM PCM Loopback for iCESugar-Pro (ECP5-25F)
//
// Extends project 08 (raw PDM loopback) by converting the PDM bitstream to
// 16-bit PCM with a 3rd-order CIC filter, applying configurable gain, then
// re-modulating back to PDM via a 1st-order sigma-delta modulator before
// forwarding to the MAX98358 PDM amplifier.
//
// Signal flow:
//   MP34DT01-M mic  →  2-stage sync
//                   →  CIC sinc³ decimation (R=64)  →  16-bit PCM @ ~48.8 kHz
//                   →  gain (signed shift with saturation)
//                   →  zero-order hold (latch between PCM updates)
//                   →  1st-order sigma-delta modulator  →  1-bit PDM @ 3.125 MHz
//                   →  MAX98358 PDM amp
//
// Gain / mute:
//   GAIN_SHIFT is a signed integer (~6 dB per step):
//     > 0  →  amplify (left-shift with saturation clamp, e.g. +1 = +6 dB)
//     = 0  →  unity gain (default)
//     < 0  →  attenuate (right-shift, e.g. -4 = −24 dB)
//   Holding the reset button (rst_n = 0) puts the design in reset: the CIC
//   and modulator are zeroed, so amp_dat produces silence (50 % PDM duty
//   cycle once the modulator is released). The red LED lights immediately
//   when the button is held; the green LED lights when running normally.

module pdm_pcm_loopback #(
    parameter integer GAIN_SHIFT = 0    // Signed: >0 = amplify, 0 = unity, <0 = attenuate
) (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset / hold-to-mute button

    // Status LEDs (active low)
    output wire led_r,      // Red:   on while rst_n is held (muted)
    output wire led_g,      // Green: on during normal operation
    output wire led_b,      // Blue:  unused (off)

    // MP34DT01-M PDM microphone
    output wire mic_clk,    // PDM clock output (3.125 MHz)
    input  wire mic_dat,    // PDM data input
    output wire mic_sel,    // Channel select: 0 = left channel

    // MAX98358 PDM amplifier
    output wire amp_clk,    // PDM clock output (same source as mic_clk)
    output wire amp_dat     // Reconstructed PDM data
);

    // -------------------------------------------------------------------------
    // PDM clock generation: 25 MHz / 8 = 3.125 MHz
    // -------------------------------------------------------------------------
    wire pdm_clk_r;
    wire pdm_valid;

    pdm_clkgen pdm_clk_inst (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .pdm_clk      (pdm_clk_r),
        .pdm_clk_rise (pdm_valid)
    );

    // -------------------------------------------------------------------------
    // 2-stage synchronizer: prevent metastability on the async PDM data input.
    // Adds 2 × 40 ns = 80 ns latency, well within the 160 ns PDM half-period.
    // -------------------------------------------------------------------------
    reg pdm_sync1, pdm_sync2;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pdm_sync1 <= 1'b0;
            pdm_sync2 <= 1'b0;
        end else begin
            pdm_sync1 <= mic_dat;
            pdm_sync2 <= pdm_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // CIC sinc³ decimation filter: 3.125 MHz PDM → 16-bit PCM @ ~48.8 kHz
    // DEC_RATIO = 64 → sample rate = 3.125 MHz / 64 = 48.828 kHz
    // -------------------------------------------------------------------------
    wire signed [15:0] pcm_raw;
    wire               pcm_valid;

    pdm_cic #(
        .CIC_ORDER (3),
        .DEC_RATIO (64),
        .OUT_BITS  (16)
    ) cic (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pdm_bit   (pdm_sync2),
        .pdm_valid (pdm_valid),
        .pcm_out   (pcm_raw),
        .pcm_valid (pcm_valid)
    );

    // -------------------------------------------------------------------------
    // Gain: signed shift applied to PCM sample (~6 dB per step).
    //   GAIN_SHIFT > 0  →  left-shift (amplify), saturated to ±32767/±32768
    //   GAIN_SHIFT = 0  →  unity (pass-through)
    //   GAIN_SHIFT < 0  →  right-shift (attenuate, no saturation needed)
    // The intermediate is 32-bit to hold any shifted value before clamping.
    // -------------------------------------------------------------------------
    wire signed [31:0] pcm_ext = {{16{pcm_raw[15]}}, pcm_raw};

    wire signed [31:0] pcm_shifted;
    generate
        if (GAIN_SHIFT > 0) begin : g_amplify
            assign pcm_shifted = pcm_ext <<< GAIN_SHIFT;
        end else if (GAIN_SHIFT < 0) begin : g_attenuate
            assign pcm_shifted = pcm_ext >>> (-GAIN_SHIFT);
        end else begin : g_unity
            assign pcm_shifted = pcm_ext;
        end
    endgenerate

    // Saturate: no overflow for attenuation/unity (upper 17 bits always match
    // sign); for amplification, clamp to the 16-bit signed range.
    /* verilator lint_off WIDTHEXPAND */
    wire overflow = (pcm_shifted[31:15] != {17{pcm_shifted[15]}});
    /* verilator lint_on WIDTHEXPAND */
    wire signed [15:0] pcm_gained = overflow ? (pcm_shifted[31] ? 16'sh8000 : 16'sh7FFF)
                                             : pcm_shifted[15:0];

    // -------------------------------------------------------------------------
    // Zero-order hold: latch the gained PCM sample each time the CIC produces
    // a new output. The modulator reads pcm_held continuously and updates at
    // the PDM rate, interpolating between PCM updates via the sigma-delta loop.
    // -------------------------------------------------------------------------
    reg signed [15:0] pcm_held;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            pcm_held <= 16'sd0;
        else if (pcm_valid)
            pcm_held <= pcm_gained;
    end

    // -------------------------------------------------------------------------
    // 1st-order sigma-delta modulator: PCM → PDM
    // Runs at PDM rate (pdm_valid strobe, 3.125 MHz).
    // After reset, pcm_held = 0, so the modulator produces ~50 % duty cycle
    // (silence) — no click or pop when the button is pressed/released.
    // -------------------------------------------------------------------------
    wire amp_dat_w;

    pdm_modulator mod (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pcm_in    (pcm_held),
        .pdm_valid (pdm_valid),
        .pdm_out   (amp_dat_w)
    );

    // -------------------------------------------------------------------------
    // Microphone control
    // -------------------------------------------------------------------------
    assign mic_clk = pdm_clk_r;
    assign mic_sel = 1'b0;      // Left channel: mic drives data on CLK falling edge

    // -------------------------------------------------------------------------
    // Amplifier outputs
    // MAX98358 SD_MODE is pulled to 3.3 V via 2 kΩ on the module (always on).
    // -------------------------------------------------------------------------
    assign amp_clk = pdm_clk_r;
    assign amp_dat = amp_dat_w;

    // -------------------------------------------------------------------------
    // Status LEDs (active low, combinational from rst_n)
    // Driving directly from rst_n means the LED state changes immediately when
    // the button is pressed, before any registered reset propagates.
    //   rst_n = 0 (button held): led_r = 0 (red on),   led_g = 1 (green off)
    //   rst_n = 1 (running):     led_r = 1 (red off),  led_g = 0 (green on)
    // -------------------------------------------------------------------------
    assign led_r = rst_n;
    assign led_g = ~rst_n;
    assign led_b = 1'b1;    // Off

endmodule
