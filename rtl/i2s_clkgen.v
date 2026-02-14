// I2S Clock Generator
// Generates BCLK and LRCLK from a system clock for I2S communication.
// BCLK = clk / (2 * CLK_DIV), LRCLK toggles every 32 BCLKs (64 per frame).

module i2s_clkgen #(
    parameter CLK_DIV = 4   // BCLK half-period in system clocks (default: 25 MHz / 8 = 3.125 MHz)
) (
    input  wire clk,
    input  wire rst_n,

    output wire bclk,
    output wire lrclk,
    output wire bclk_falling   // Single-cycle pulse on BCLK falling edge
);

    localparam DIV_WIDTH = $clog2(CLK_DIV);

    // -------------------------------------------------------------------------
    // BCLK generation: clk / (2 * CLK_DIV)
    // -------------------------------------------------------------------------
    reg [DIV_WIDTH-1:0] bclk_counter;
    reg                 bclk_reg;

    wire bclk_toggle = (bclk_counter == DIV_WIDTH'(CLK_DIV - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_counter <= 0;
            bclk_reg     <= 1'b0;
        end else if (bclk_toggle) begin
            bclk_counter <= 0;
            bclk_reg     <= ~bclk_reg;
        end else begin
            bclk_counter <= bclk_counter + 1;
        end
    end

    // Falling edge detect: counter about to wrap AND bclk is currently high
    assign bclk_falling = bclk_toggle && bclk_reg;

    // -------------------------------------------------------------------------
    // LRCLK generation: toggles every 32 BCLKs
    // -------------------------------------------------------------------------
    reg [4:0] bit_counter;
    reg       lrclk_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_counter <= 5'd0;
            lrclk_reg   <= 1'b0;
        end else if (bclk_falling) begin
            if (bit_counter == 5'd31) begin
                bit_counter <= 5'd0;
                lrclk_reg   <= ~lrclk_reg;
            end else begin
                bit_counter <= bit_counter + 5'd1;
            end
        end
    end

    assign bclk  = bclk_reg;
    assign lrclk = lrclk_reg;

endmodule
