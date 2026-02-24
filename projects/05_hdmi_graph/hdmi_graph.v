// HDMI Graph Display for iCESugar-Pro
// Uses portrait 480x800 timing (same as the display's native mode) and
// rotates coordinates so the graph appears correct in landscape orientation.
// Static test data from ROM; designed for later live FFT connection.

module hdmi_graph (
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
    // Video Timing (480x800 portrait - display's native mode)
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
    // Coordinate rotation: portrait (480x800) → landscape (800x480)
    // The display is physically rotated 90° CCW for landscape viewing.
    // If the image appears mirrored, use CW rotation instead:
    //   wire [9:0] land_x = 10'd799 - pixel_y;
    //   wire [9:0] land_y = pixel_x;
    // ==========================================================================
    wire [9:0] land_x = pixel_y;
    wire [9:0] land_y = 10'd479 - pixel_x;

    // ==========================================================================
    // Graph Data ROM (static test spectrum)
    // ==========================================================================
    wire [7:0] graph_addr;
    wire [8:0] graph_data;

    graph_data_rom rom_inst (
        .clk(clk_pixel),
        .addr(graph_addr),
        .data(graph_data)
    );

    // ==========================================================================
    // Graph Renderer
    // ==========================================================================
    wire [7:0] red, green, blue;

    graph_renderer renderer_inst (
        .clk_pixel(clk_pixel),
        .rst_n(rst_sync_n),
        .pixel_x(land_x),
        .pixel_y(land_y),
        .active(active),
        .data_addr(graph_addr),
        .data_value(graph_data),
        .red(red),
        .green(green),
        .blue(blue)
    );

    // ==========================================================================
    // Pipeline alignment: delay sync signals by 1 clock to match
    // the graph renderer's 1-cycle ROM read latency
    // ==========================================================================
    reg hsync_d1, vsync_d1, active_d1;

    always @(posedge clk_pixel or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            hsync_d1  <= 1'b1;
            vsync_d1  <= 1'b1;
            active_d1 <= 1'b0;
        end else begin
            hsync_d1  <= hsync;
            vsync_d1  <= vsync;
            active_d1 <= active;
        end
    end

    // ==========================================================================
    // TMDS Encoding (using delayed sync/active for pipeline alignment)
    // ==========================================================================
    wire [9:0] tmds_red, tmds_green, tmds_blue;

    // Blue channel carries hsync/vsync during blanking
    tmds_encoder enc_blue (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(blue),
        .ctrl({vsync_d1, hsync_d1}),
        .data_en(active_d1),
        .tmds_out(tmds_blue)
    );

    // Green and red channels have no control data
    tmds_encoder enc_green (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(green),
        .ctrl(2'b00),
        .data_en(active_d1),
        .tmds_out(tmds_green)
    );

    tmds_encoder enc_red (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(red),
        .ctrl(2'b00),
        .data_en(active_d1),
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
