// Sigma-delta PDM modulator (PCM → PDM)
//
// Converts a signed 16-bit PCM sample into a 1-bit PDM bitstream running at
// the PDM clock rate. The caller holds the PCM sample in a register between
// updates (zero-order hold); this module updates its output on every
// pdm_valid strobe.
//
// ORDER=1 (default): 1st-order error-feedback.
//   Noise shaping: 20 dB/decade (NTF = 1 − z⁻¹).
//   Accumulator stays bounded to 16-bit signed (proven below).
//
// ORDER=2: 2nd-order cascaded-integrators-feedback (CIFB).
//   Noise shaping: 40 dB/decade (NTF = (1 − z⁻¹)²).
//   Two integrators, each receiving DAC feedback after quantisation.
//   Integrators are clamped to ±2²³ to guarantee stability at full-scale
//   inputs (a pure 2nd-order single-bit loop is conditionally stable;
//   clamping prevents integrator runaway with minimal distortion).
//
// 1st-order algorithm:
//   new_acc = accum + pcm_in         (17-bit signed intermediate)
//   pdm_out = (new_acc >= 0) ? 1 : 0
//   accum   = new_acc − (pdm_out ? +32768 : −32768)
//
// 1st-order accumulator bound proof:
//   pcm_in ∈ [−32768, +32767], accum ∈ [−32768, +32767] (induction):
//   Case pdm_out=1 (new_acc ≥ 0):  accum' = new_acc − 32768 ∈ [−32768, +32766] ✓
//   Case pdm_out=0 (new_acc < 0):  accum' = new_acc + 32768 ∈ [−32768, +32767] ✓
//   ∴ accum always fits in 16-bit signed; no overflow possible.
//
// 2nd-order algorithm:
//   sum1    = acc1 + pcm_in          (first integrator)
//   sum2    = acc2 + sum1            (second integrator)
//   pdm_out = (sum2 >= 0) ? 1 : 0
//   fb      = pdm_out ? +32768 : −32768
//   acc1    = clamp(sum1 − fb)
//   acc2    = clamp(sum2 − fb)
//
// Average value of pdm_out tracks (pcm_in + 32768) / 65536:
//   pcm_in = 0       → ~50 % duty cycle (silence)
//   pcm_in = +32767  → ~100 % duty cycle (full positive)
//   pcm_in = −32768  → ~0 %  duty cycle (full negative)

module pdm_modulator #(
    parameter ORDER = 1   // 1 = first-order, 2 = second-order
) (
    input  wire              clk,
    input  wire              rst_n,

    // PCM input: signed 16-bit, held by caller between pcm_valid updates.
    // 0 = silence (50 % PDM duty cycle).
    input  wire signed [15:0] pcm_in,

    // Single-cycle strobe at the PDM clock rate (one pulse per PDM period).
    input  wire              pdm_valid,

    // 1-bit PDM output, registered, updated on every pdm_valid.
    output reg               pdm_out
);

generate
if (ORDER == 1) begin : gen_order1

    // -----------------------------------------------------------------
    // 1st-order error-feedback sigma-delta
    // -----------------------------------------------------------------
    reg signed [15:0] accum;

    // Sign-extend both operands to 17 bits for overflow-safe addition.
    wire signed [16:0] new_acc = {accum[15], accum} + {pcm_in[15], pcm_in};

    // Quantiser: 1 when new_acc ≥ 0 (MSB = 0), 0 when new_acc < 0 (MSB = 1).
    wire out_bit = ~new_acc[16];

    // Feedback: subtract midscale (+32768 when output=1, −32768 when output=0).
    // Result is bounded to [−32768, +32767] (see proof above) — safe to keep
    // the lower 16 bits; bit [16] of next_accum is intentionally discarded.
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [16:0] next_accum = out_bit ? (new_acc - 17'sd32768)
                                            : (new_acc + 17'sd32768);
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum   <= 16'sd0;
            pdm_out <= 1'b0;
        end else if (pdm_valid) begin
            pdm_out <= out_bit;
            accum   <= next_accum[15:0];
        end
    end

end else begin : gen_order2

    // -----------------------------------------------------------------
    // 2nd-order CIFB sigma-delta  (NTF = (1 − z⁻¹)²)
    //
    // Two cascaded integrators, each receiving DAC feedback:
    //   acc1 integrates (pcm_in − fb)   → tracks input signal error
    //   acc2 integrates (acc1   − fb)   → second-order noise shaping
    //
    // Transfer function derivation (linear model, quantiser = unity + E):
    //   A1(z)(1−z⁻¹) = U(z) − V(z)·z⁻¹
    //   A2(z)(1−z⁻¹) = A1(z) − V(z)·z⁻¹
    //   V(z) = A2(z) + E(z)
    //   ⟹ V(z) = U(z) + E(z)·(1−z⁻¹)²
    //   STF = 1,  NTF = (1−z⁻¹)²
    // -----------------------------------------------------------------

    // Accumulator width: 32-bit signed gives ample headroom for the
    // clamped 24-bit range (±2²³) plus 16-bit PCM additions.
    reg signed [31:0] acc1, acc2;

    // Sign-extend PCM to 32 bits
    wire signed [31:0] pcm_ext = {{16{pcm_in[15]}}, pcm_in};

    // --- Integrator outputs (pre-feedback) ---
    wire signed [31:0] sum1 = acc1 + pcm_ext;
    wire signed [31:0] sum2 = acc2 + sum1;

    // --- Quantiser ---
    wire out_bit = ~sum2[31];   // 1 when sum2 ≥ 0

    // --- DAC feedback: ±32768 (same scale as 1st-order) ---
    wire signed [31:0] fb = out_bit ? 32'sd32768 : -32'sd32768;

    // --- Post-feedback accumulator values ---
    wire signed [31:0] next1 = sum1 - fb;
    wire signed [31:0] next2 = sum2 - fb;

    // --- Integrator clamping ---
    // Clamp to ±2²³ (256× the PCM range).  This prevents integrator
    // runaway for sustained full-scale inputs where the 2nd-order loop
    // would otherwise be conditionally unstable.  The clamp range is
    // large enough that it never activates during normal audio signals.
    localparam signed [31:0] CLAMP_HI =  32'sd8388607;   //  2²³ − 1
    localparam signed [31:0] CLAMP_LO = -32'sd8388608;   // −2²³

    /* verilator lint_off UNUSEDSIGNAL */
    wire clamp1 = (next1 > CLAMP_HI) || (next1 < CLAMP_LO);
    wire clamp2 = (next2 > CLAMP_HI) || (next2 < CLAMP_LO);
    /* verilator lint_on UNUSEDSIGNAL */

    wire signed [31:0] clamped1 = (next1 > CLAMP_HI) ? CLAMP_HI :
                                  (next1 < CLAMP_LO) ? CLAMP_LO : next1;
    wire signed [31:0] clamped2 = (next2 > CLAMP_HI) ? CLAMP_HI :
                                  (next2 < CLAMP_LO) ? CLAMP_LO : next2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc1    <= 32'sd0;
            acc2    <= 32'sd0;
            pdm_out <= 1'b0;
        end else if (pdm_valid) begin
            pdm_out <= out_bit;
            acc1    <= clamped1;
            acc2    <= clamped2;
        end
    end

end
endgenerate

endmodule
