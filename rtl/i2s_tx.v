// I2S Transmitter
// Serializes parallel left/right channel samples into I2S format.
// Outputs MSB-first, DATA_BITS of data followed by zero padding in
// a 32-bit slot. The 1-BCLK I2S delay is provided by the register
// pipeline between i2s_clkgen and this module.

module i2s_tx #(
    parameter DATA_BITS = 24
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  bclk_falling,  // Single-cycle pulse from i2s_clkgen
    input  wire                  lrclk,
    input  wire [DATA_BITS-1:0]  left_data,
    input  wire [DATA_BITS-1:0]  right_data,

    output wire                  sdata
);

    reg [DATA_BITS-1:0] shift_reg;
    reg                 lrclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 0;
            lrclk_prev <= 1'b0;
        end else if (bclk_falling) begin
            lrclk_prev <= lrclk;

            if (lrclk != lrclk_prev)
                // LRCLK transition — load new channel data and output MSB
                // immediately. The pipeline delay from i2s_clkgen already
                // provides the 1-BCLK I2S delay.
                shift_reg <= lrclk ? right_data : left_data;
            else
                // Shift out MSB-first; zeros fill from right (natural padding)
                shift_reg <= {shift_reg[DATA_BITS-2:0], 1'b0};
        end
    end

    assign sdata = shift_reg[DATA_BITS-1];

endmodule
