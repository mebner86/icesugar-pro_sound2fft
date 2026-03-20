// I2S Receiver
// Deserializes I2S serial data into parallel left/right channel samples.
// Uses separate shift registers per channel, steered by the delayed LRCLK.
// The 1-BCLK I2S delay is handled naturally by lrclk_prev lagging lrclk
// by one BCLK cycle through the register pipeline from i2s_clkgen.

module i2s_rx #(
    parameter DATA_BITS = 24
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  bclk_falling,  // Single-cycle pulse from i2s_clkgen
    input  wire                  lrclk,
    input  wire                  sdata,

    output reg  [DATA_BITS-1:0]  left_data,
    output reg                   left_valid,
    output reg  [DATA_BITS-1:0]  right_data,
    output reg                   right_valid
);

    /* verilator lint_off UNUSEDSIGNAL */
    reg [31:0] left_shift;
    reg [31:0] right_shift;
    /* verilator lint_on UNUSEDSIGNAL */
    reg        lrclk_prev;

    // Include current sdata to form the complete 32-bit shifted value,
    // since the non-blocking shift hasn't taken effect at latch time.
    wire [31:0] left_captured  = {left_shift[30:0], sdata};
    wire [31:0] right_captured = {right_shift[30:0], sdata};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_shift  <= 0;
            right_shift <= 0;
            lrclk_prev  <= 1'b0;
            left_data   <= 0;
            left_valid  <= 1'b0;
            right_data  <= 0;
            right_valid <= 1'b0;
        end else begin
            left_valid  <= 1'b0;
            right_valid <= 1'b0;

            if (bclk_falling) begin
                lrclk_prev <= lrclk;

                // Shift sdata into the active channel. lrclk_prev lags
                // lrclk by one BCLK, providing the standard I2S delay.
                if (lrclk_prev)
                    right_shift <= right_captured;
                else
                    left_shift <= left_captured;

                // LRCLK transition: latch the completed channel
                if (lrclk != lrclk_prev) begin
                    if (!lrclk_prev) begin
                        // Was left (LRCLK low), now right — left complete
                        left_data  <= left_captured[31:32-DATA_BITS];
                        left_valid <= 1'b1;
                    end else begin
                        // Was right (LRCLK high), now left — right complete
                        right_data  <= right_captured[31:32-DATA_BITS];
                        right_valid <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
