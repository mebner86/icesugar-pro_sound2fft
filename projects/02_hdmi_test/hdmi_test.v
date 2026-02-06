// HDMI Test Pattern Generator for iCESugar-Pro
// Generates a test image output via HDMI

module hdmi_test (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire clk_25m,
    input  wire rst_n,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire led_r,
    output wire led_g,
    output wire led_b
    // TODO: Add HDMI TMDS outputs
    // output wire [3:0] hdmi_p,  // TMDS positive (clk + 3 data)
    // output wire [3:0] hdmi_n   // TMDS negative (clk + 3 data)
);

    // Directly drive LEDs off (active low) for now
    assign led_r = 1'b1;
    assign led_g = 1'b1;
    assign led_b = 1'b1;

    // TODO: Implement HDMI test pattern generator
    // Components needed:
    // 1. PLL to generate pixel clock (e.g., 25.175 MHz for 640x480)
    // 2. Video timing generator (h/v sync, blanking)
    // 3. Test pattern generator (color bars, gradients, etc.)
    // 4. TMDS encoder (8b/10b encoding)
    // 5. Serializer (parallel to serial conversion)

endmodule
