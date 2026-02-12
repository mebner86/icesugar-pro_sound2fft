// I2S Receiver
// Deserializes I2S serial data into parallel left/right channel samples.
// Assumes standard I2S format: MSB-first, 1-BCLK delay after LRCLK transition,
// DATA_BITS of data followed by padding zeros in a 32-bit slot.

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

    reg [4:0]           bit_counter;
    reg [DATA_BITS-1:0] shift_reg;
    reg                 lrclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_counter <= 5'd0;
            shift_reg   <= 0;
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

                if (lrclk != lrclk_prev) begin
                    // LRCLK just transitioned — latch completed channel, reset counter
                    // The channel that just ended is identified by lrclk_prev
                    if (!lrclk_prev) begin
                        // Was left channel (LRCLK low), now transitioning to right
                        left_data  <= shift_reg;
                        left_valid <= 1'b1;
                    end else begin
                        // Was right channel (LRCLK high), now transitioning to left
                        right_data  <= shift_reg;
                        right_valid <= 1'b1;
                    end
                    bit_counter <= 5'd0;
                end else if (bit_counter == 5'd0) begin
                    // Bit 0 of the slot is the 1-cycle I2S delay — skip it
                    bit_counter <= 5'd1;
                end else if (bit_counter <= DATA_BITS) begin
                    // Shift in data bits MSB-first (bits 1..DATA_BITS of the slot)
                    shift_reg   <= {shift_reg[DATA_BITS-2:0], sdata};
                    bit_counter <= bit_counter + 5'd1;
                end else begin
                    // Padding bits — just count
                    bit_counter <= bit_counter + 5'd1;
                end
            end
        end
    end

endmodule
