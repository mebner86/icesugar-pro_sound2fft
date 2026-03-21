// fft_uart.v
// FFT spectrum analyzer with UART output for iCESugar-Pro (ECP5-25F).
//
// Reads audio from SPH0645 I2S microphone, computes a 512-point real FFT
// (via 256-point complex FFT), and streams the 256-bin magnitude spectrum
// over UART using COBS framing (0x00 frame delimiter).
//
// Protocol: 256 data bytes (magnitude 0x01–0xFF, 4.4 fixed-point log2)
//           followed by 0x00 terminator.  One frame = 257 bytes at ~10.6 Hz.
//
// No PLL required — FFT and UART both run on the 25 MHz system clock.

module fft_uart #(
    parameter CLK_FREQ  = 25_000_000,
    parameter BAUD_RATE = 115_200,
    parameter FRAME_DIV = 9   // Display rate = FFT rate / FRAME_DIV ≈ 10.6 Hz
) (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active-low)
    output wire led_r,   // On while FFT is computing
    output wire led_g,   // On while UART is transmitting
    output wire led_b,   // Off

    // SPH0645 microphone (I2S)
    output wire mic_bclk,
    output wire mic_lrclk,
    input  wire mic_data,
    output wire mic_sel,   // Low = left channel

    // UART via iCELink USB-CDC
    output wire uart_tx
);

    // =========================================================================
    // I2S Clock Generation
    // 25 MHz / (2 × CLK_DIV) = 3.125 MHz BCLK → 48828 Hz sample rate
    // =========================================================================
    wire bclk, lrclk, bclk_falling;

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
    assign mic_sel   = 1'b0;

    // =========================================================================
    // I2S Receiver — 24-bit left-channel samples
    // =========================================================================
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

    // Truncate to 16-bit for FFT (keep upper bits, discard low-order noise)
    wire signed [15:0] fft_sample = $signed(rx_left_data[23:8]);

    // =========================================================================
    // FFT Engine — 512-point real FFT via 256-point complex FFT
    // Outputs 256 bins sequentially: mag_addr 0→255, one per 3 clocks
    // =========================================================================
    wire [7:0] mag_addr;
    wire [8:0] mag_data;   // log2 magnitude, 4.4 fixed-point, 9-bit
    wire       mag_valid;
    wire       fft_busy;

    fft_real512 fft_inst (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .sample_in    (fft_sample),
        .sample_valid (rx_left_valid),
        .mag_addr     (mag_addr),
        .mag_data     (mag_data),
        .mag_valid    (mag_valid),
        .busy         (fft_busy)
    );

    // =========================================================================
    // UART Serializer — captures FFT frame and streams over UART
    // =========================================================================
    wire tx_active;

    uart_serializer #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .FRAME_DIV (FRAME_DIV)
    ) serializer (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .mag_addr  (mag_addr),
        .mag_data  (mag_data),
        .mag_valid (mag_valid),
        .uart_tx   (uart_tx),
        .tx_active (tx_active)
    );

    // =========================================================================
    // Status LEDs (active-low)
    // =========================================================================
    assign led_r = ~fft_busy;   // Red:   on while FFT is computing
    assign led_g = ~tx_active;  // Green: on while UART is transmitting
    assign led_b = 1'b1;        // Blue:  off

endmodule
