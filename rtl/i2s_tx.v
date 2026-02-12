// I2S Transmitter
// Serializes parallel left/right channel samples into I2S format.
// Outputs MSB-first with 1-BCLK delay after LRCLK transition,
// DATA_BITS of data followed by padding zeros in a 32-bit slot.

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

    reg [4:0]           bit_counter;
    reg [DATA_BITS-1:0] shift_reg;
    reg                 lrclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_counter <= 5'd0;
            shift_reg   <= 0;
            lrclk_prev  <= 1'b0;
        end else if (bclk_falling) begin
            lrclk_prev <= lrclk;

            if (lrclk != lrclk_prev) begin
                // LRCLK just transitioned — load new channel data
                // lrclk gives the NEW channel: low = left, high = right
                shift_reg   <= lrclk ? right_data : left_data;
                bit_counter <= 5'd0;
            end else if (bit_counter == 5'd0) begin
                // Bit 0 of the slot is the 1-cycle I2S delay — skip it
                bit_counter <= 5'd1;
            end else if (bit_counter <= DATA_BITS) begin
                // Shift out data bits MSB-first (bits 1..DATA_BITS of the slot)
                shift_reg   <= {shift_reg[DATA_BITS-2:0], 1'b0};
                bit_counter <= bit_counter + 5'd1;
            end else begin
                // Padding bits — just count
                bit_counter <= bit_counter + 5'd1;
            end
        end
    end

    // Output: MSB of shift register during data phase (counters 1..DATA_BITS),
    // zero during delay slot (counter 0) and padding (counter > DATA_BITS).
    assign sdata = (bit_counter >= 1 && bit_counter <= DATA_BITS) ? shift_reg[DATA_BITS-1] : 1'b0;

endmodule
