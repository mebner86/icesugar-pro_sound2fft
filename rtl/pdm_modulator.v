// 1st-order sigma-delta PDM modulator (PCM → PDM)
//
// Converts a signed 16-bit PCM sample into a 1-bit PDM bitstream running at
// the PDM clock rate. The caller holds the PCM sample in a register between
// updates (zero-order hold); this module updates its output on every
// pdm_valid strobe.
//
// Algorithm (1st-order error-feedback sigma-delta):
//   Each PDM clock cycle:
//     new_acc = accum + pcm_in         (17-bit signed intermediate)
//     pdm_out = (new_acc >= 0) ? 1 : 0
//     accum   = new_acc − (pdm_out ? +32768 : −32768)
//
// Accumulator bound proof:
//   pcm_in ∈ [−32768, +32767], accum ∈ [−32768, +32767] (induction):
//   Case pdm_out=1 (new_acc ≥ 0):  accum' = new_acc − 32768 ∈ [−32768, +32766] ✓
//   Case pdm_out=0 (new_acc < 0):  accum' = new_acc + 32768 ∈ [−32768, +32767] ✓
//   ∴ accum always fits in 16-bit signed; no overflow possible.
//
// Average value of pdm_out tracks (pcm_in + 32768) / 65536:
//   pcm_in = 0       → ~50 % duty cycle (silence)
//   pcm_in = +32767  → ~100 % duty cycle (full positive)
//   pcm_in = −32768  → ~0 %  duty cycle (full negative)

module pdm_modulator (
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

    // -------------------------------------------------------------------------
    // Integration accumulator (16-bit signed, bounded by proof above)
    // -------------------------------------------------------------------------
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

endmodule
