// Live FFT Spectrum Display for iCESugar-Pro
// Reads audio from SPH0645 I2S microphone, computes 256-point FFT,
// and displays the frequency spectrum on an HDMI display (800x480).

module live_fft (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // SPH0645 microphone (I2S)
    output wire mic_bclk,
    output wire mic_lrclk,
    input  wire mic_data,
    output wire mic_sel,

    // HDMI TMDS outputs (differential pairs)
    output wire [3:0] gpdi_dp,
    output wire [3:0] gpdi_dn
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

    wire rst_sync_n = rst_n & pll_locked;

    // ==========================================================================
    // I2S Clock Generation: 25 MHz / 8 = 3.125 MHz BCLK, ~48.8 kHz sample rate
    // ==========================================================================
    wire bclk;
    wire lrclk;
    wire bclk_falling;

    i2s_clkgen #(
        .CLK_DIV(4)
    ) clkgen (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .bclk         (bclk),
        .lrclk        (lrclk),
        .bclk_falling (bclk_falling)
    );

    assign mic_bclk  = bclk;
    assign mic_lrclk = lrclk;
    assign mic_sel   = 1'b0;  // Left channel

    // ==========================================================================
    // I2S Receiver: deserialize mic data into 24-bit parallel samples
    // ==========================================================================
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] rx_left_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire        rx_left_valid;

    /* verilator lint_off PINCONNECTEMPTY */
    i2s_rx #(
        .DATA_BITS(24)
    ) rx (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .bclk_falling (bclk_falling),
        .lrclk        (lrclk),
        .sdata        (mic_data),
        .left_data    (rx_left_data),
        .left_valid   (rx_left_valid),
        .right_data   (),
        .right_valid  ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // Truncate 24-bit samples to 16-bit for FFT (keep upper bits)
    wire signed [15:0] fft_sample = $signed(rx_left_data[23:8]);

    // ==========================================================================
    // FFT Engine: 256-point radix-2 DIT
    // ==========================================================================
    wire [7:0] mag_addr;
    wire [8:0] mag_data;
    wire       mag_valid;
    wire       fft_busy;

    fft256 #(
        .MAG_SHIFT(3)
    ) fft_inst (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .sample_in    (fft_sample),
        .sample_valid (rx_left_valid),
        .mag_addr     (mag_addr),
        .mag_data     (mag_data),
        .mag_valid    (mag_valid),
        .busy         (fft_busy)
    );

    // ==========================================================================
    // Display RAM: bridges system clock and pixel clock domains
    // ==========================================================================
    wire [7:0] graph_addr;
    wire [8:0] graph_data;

    display_ram disp_ram (
        .wr_clk  (clk_25m),
        .wr_en   (mag_valid),
        .wr_addr (mag_addr),
        .wr_data (mag_data),
        .rd_clk  (clk_pixel),
        .rd_addr (graph_addr),
        .rd_data (graph_data)
    );

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
    // Coordinate rotation: portrait (480x800) -> landscape (800x480)
    // ==========================================================================
    wire [9:0] land_x = pixel_y;
    wire [9:0] land_y = 10'd479 - pixel_x;

    // ==========================================================================
    // Graph Renderer
    // ==========================================================================
    wire [7:0] red, green, blue;

    graph_renderer renderer_inst (
        .clk_pixel  (clk_pixel),
        .rst_n      (rst_sync_n),
        .pixel_x    (land_x),
        .pixel_y    (land_y),
        .active     (active),
        .data_addr  (graph_addr),
        .data_value (graph_data),
        .red        (red),
        .green      (green),
        .blue       (blue)
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

    tmds_encoder enc_blue (
        .clk(clk_pixel),
        .rst_n(rst_sync_n),
        .data_in(blue),
        .ctrl({vsync_d1, hsync_d1}),
        .data_en(active_d1),
        .tmds_out(tmds_blue)
    );

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
    tmds_serializer ser_blue (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_blue),
        .tmds_p(gpdi_dp[0]),
        .tmds_n(gpdi_dn[0])
    );

    tmds_serializer ser_green (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_green),
        .tmds_p(gpdi_dp[1]),
        .tmds_n(gpdi_dn[1])
    );

    tmds_serializer ser_red (
        .clk_pixel(clk_pixel),
        .clk_shift(clk_shift),
        .rst_n(rst_sync_n),
        .tmds_in(tmds_red),
        .tmds_p(gpdi_dp[2]),
        .tmds_n(gpdi_dn[2])
    );

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
    assign led_r = ~fft_busy;          // Red on while computing FFT
    assign led_g = ~pll_locked;        // Green on when PLL locked
    assign led_b = 1'b1;              // Off

endmodule
