// HDMI Test Pattern Generator for iCESugar-Pro
// Outputs vertical color bars via HDMI at 480x800@60Hz

module hdmi_test (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // HDMI TMDS outputs (differential pairs)
    output wire [3:0] gpdi_dp,  // TMDS positive (blue, green, red, clock)
    output wire [3:0] gpdi_dn   // TMDS negative
);

    // ==========================================================================
    // Clock Generation
    // ==========================================================================
    wire clk_pixel;  // 30 MHz pixel clock
    wire clk_shift;  // 150 MHz shift clock (5x for DDR)
    wire pll_locked;

    pll pll_inst (
        .clk_25m(clk_25m),
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .locked(pll_locked)
    );

    // Reset synchronization
    wire rst_sync_n = rst_n & pll_locked;

    // ==========================================================================
    // Video Timing
    // ==========================================================================
    wire hsync, vsync, active;
    wire [9:0] pixel_x, pixel_y;

    video_timing timing_inst (
        .clk_pixel(clk_pixel),
        .rst_n(rst_sync_n),
        .hsync(hsync),
        .vsync(vsync),
        .active(active),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );

    // ==========================================================================
    // Test Pattern
    // ==========================================================================
    wire [7:0] red, green, blue;

    test_pattern pattern_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .active(active),
        .red(red),
        .green(green),
        .blue(blue)
    );

    // ==========================================================================
    // TMDS Encoding
    // ==========================================================================
    wire [9:0] tmds_red, tmds_green, tmds_blue;

    // Blue channel carries hsync/vsync during blanking
    tmds_encoder enc_blue (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(blue),
        .ctrl({vsync, hsync}),
        .data_en(active),
        .tmds_out(tmds_blue)
    );

    // Green and red channels have no control data
    tmds_encoder enc_green (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(green),
        .ctrl(2'b00),
        .data_en(active),
        .tmds_out(tmds_green)
    );

    tmds_encoder enc_red (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(red),
        .ctrl(2'b00),
        .data_en(active),
        .tmds_out(tmds_red)
    );

    // ==========================================================================
    // TMDS Serialization
    // ==========================================================================

    // Data channel 0: Blue
    tmds_serializer ser_blue (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_blue),
        .tmds_p(gpdi_dp[0]),
        .tmds_n(gpdi_dn[0])
    );

    // Data channel 1: Green
    tmds_serializer ser_green (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_green),
        .tmds_p(gpdi_dp[1]),
        .tmds_n(gpdi_dn[1])
    );

    // Data channel 2: Red
    tmds_serializer ser_red (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_red),
        .tmds_p(gpdi_dp[2]),
        .tmds_n(gpdi_dn[2])
    );

    // Clock channel: transmit pixel clock as 10'b0000011111 pattern
    tmds_serializer ser_clk (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(10'b0000011111),
        .tmds_p(gpdi_dp[3]),
        .tmds_n(gpdi_dn[3])
    );

    // ==========================================================================
    // Status LEDs
    // ==========================================================================
    // Green LED on when PLL locked, others off
    assign led_r = 1'b1;           // Off (active low)
    assign led_g = ~pll_locked;    // On when locked
    assign led_b = 1'b1;           // Off

endmodule
