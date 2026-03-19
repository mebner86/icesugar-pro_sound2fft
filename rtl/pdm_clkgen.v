// PDM Clock Generator
// Generates a PDM clock and a single-cycle rising-edge strobe from a system
// clock.  PDM_CLK = clk / (2 * CLK_DIV).
//
// Default: CLK_DIV = 4  →  25 MHz / 8 = 3.125 MHz
// Within MP34DT01-M spec (1–3.25 MHz) and MAX98358 spec.

module pdm_clkgen #(
    parameter CLK_DIV = 4   // PDM clock half-period in system clocks
) (
    input  wire clk,
    input  wire rst_n,

    output wire pdm_clk,      // Divided clock output
    output wire pdm_clk_rise  // Single-cycle strobe on rising edge of pdm_clk
);

    localparam DIV_WIDTH = $clog2(CLK_DIV);
    /* verilator lint_off WIDTHTRUNC */
    localparam [DIV_WIDTH-1:0] DIV_MAX = CLK_DIV - 1;
    /* verilator lint_on WIDTHTRUNC */

    reg [DIV_WIDTH-1:0] counter;
    reg                 clk_reg;

    wire toggle = (counter == DIV_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            clk_reg <= 1'b0;
        end else if (toggle) begin
            counter <= 0;
            clk_reg <= ~clk_reg;
        end else begin
            counter <= counter + 1;
        end
    end

    // Rising-edge detect: counter about to wrap AND clk_reg is currently low
    // (i.e. clk_reg is about to transition 0→1).
    assign pdm_clk      = clk_reg;
    assign pdm_clk_rise = toggle && !clk_reg;

endmodule
