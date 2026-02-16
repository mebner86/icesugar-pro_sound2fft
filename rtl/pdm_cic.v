// PDM CIC Decimation Filter
// Nth-order (sinc^N) Cascaded Integrator-Comb filter for converting a 1-bit
// PDM bitstream into multi-bit PCM samples at a decimated rate.
// CIC_ORDER integrator stages run at the PDM rate; CIC_ORDER comb stages
// run at the decimated output rate (PDM rate / DEC_RATIO).

module pdm_cic #(
    parameter CIC_ORDER = 3,    // Filter order (stages are manually unrolled for N=3)
    parameter DEC_RATIO = 64,   // Decimation ratio
    parameter OUT_BITS  = 16    // Output PCM width (truncated from internal width)
) (
    input  wire                          clk,
    input  wire                          rst_n,

    // PDM input (must be synchronized to clk externally)
    input  wire                          pdm_bit,    // 1-bit PDM data
    input  wire                          pdm_valid,  // Single-cycle pulse: sample pdm_bit

    // Decimated PCM output
    output reg  signed [OUT_BITS-1:0]    pcm_out,
    output reg                           pcm_valid
);

    // -------------------------------------------------------------------------
    // Internal width: N * log2(R) + B_in bits for correct CIC wrapping arithmetic
    // For signed {-1,+1} input, B_in = 2 (sign + magnitude).
    // For N=3, R=64: 3 * 6 + 2 = 20 bits signed (range: ±262144)
    // -------------------------------------------------------------------------
    localparam LOG2_R    = $clog2(DEC_RATIO);
    localparam CIC_WIDTH = CIC_ORDER * LOG2_R + 2;

    // Decimation counter width and max value
    localparam DEC_BITS = $clog2(DEC_RATIO);
    /* verilator lint_off WIDTHTRUNC */
    localparam [DEC_BITS-1:0] DEC_MAX = DEC_RATIO - 1;
    /* verilator lint_on WIDTHTRUNC */

    // -------------------------------------------------------------------------
    // PDM input mapping: 1 -> +1, 0 -> -1 (signed, eliminates DC offset)
    // -------------------------------------------------------------------------
    wire signed [CIC_WIDTH-1:0] pdm_signed = pdm_bit ?
        {{(CIC_WIDTH-1){1'b0}}, 1'b1} :  // +1
        {CIC_WIDTH{1'b1}};               // -1 (two's complement)

    // -------------------------------------------------------------------------
    // Integrator stages (running at PDM rate, on every pdm_valid)
    // Each stage is a running accumulator: y[n] = y[n-1] + x[n]
    // Overflow (wrapping) is intentional — the comb stages cancel drift.
    // -------------------------------------------------------------------------
    reg signed [CIC_WIDTH-1:0] integ1, integ2, integ3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integ1 <= 0;
            integ2 <= 0;
            integ3 <= 0;
        end else if (pdm_valid) begin
            integ1 <= integ1 + pdm_signed;
            integ2 <= integ2 + integ1;
            integ3 <= integ3 + integ2;
        end
    end

    // -------------------------------------------------------------------------
    // Decimation counter: fires dec_tick every DEC_RATIO PDM samples
    // -------------------------------------------------------------------------
    reg [DEC_BITS-1:0] dec_count;
    wire dec_tick = pdm_valid && (dec_count == DEC_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dec_count <= 0;
        else if (pdm_valid)
            dec_count <= dec_tick ? {DEC_BITS{1'b0}} : dec_count + 1;
    end

    // -------------------------------------------------------------------------
    // Comb stages (running at decimated rate, on every dec_tick)
    // Each stage computes: y[n] = x[n] - x[n-1]
    // Combinational subtract chain with registered delay elements.
    // -------------------------------------------------------------------------
    reg signed [CIC_WIDTH-1:0] comb1_delay, comb2_delay, comb3_delay;

    wire signed [CIC_WIDTH-1:0] comb1_out = integ3 - comb1_delay;
    wire signed [CIC_WIDTH-1:0] comb2_out = comb1_out - comb2_delay;
    wire signed [CIC_WIDTH-1:0] comb3_out = comb2_out - comb3_delay;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comb1_delay <= 0;
            comb2_delay <= 0;
            comb3_delay <= 0;
        end else if (dec_tick) begin
            comb1_delay <= integ3;
            comb2_delay <= comb1_out;
            comb3_delay <= comb2_out;
        end
    end

    // -------------------------------------------------------------------------
    // Output: truncate CIC_WIDTH to OUT_BITS (take MSBs)
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [CIC_WIDTH-1:0] cic_result = comb3_out;
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcm_out   <= 0;
            pcm_valid <= 1'b0;
        end else begin
            pcm_valid <= dec_tick;
            if (dec_tick)
                pcm_out <= cic_result[CIC_WIDTH-1 -: OUT_BITS];
        end
    end

endmodule
