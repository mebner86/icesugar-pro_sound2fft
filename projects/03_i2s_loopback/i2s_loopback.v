// I2S Loopback for iCESugar-Pro (ECP5-25F)
// Reads audio from SPH0645 microphone, deserializes into parallel samples,
// then re-serializes and sends to MAX98357A amplifier.
// Validates the reusable i2s_clkgen, i2s_rx, and i2s_tx modules.

module i2s_loopback (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // SPH0645 microphone
    output wire mic_bclk,   // Bit clock (BCLK)
    output wire mic_lrclk,  // Word select (LRCL)
    input  wire mic_data,   // Serial data from mic (DOUT)
    output wire mic_sel,    // Channel select (SEL)

    // MAX98357A amplifier
    output wire amp_bclk,   // Bit clock (BCLK)
    output wire amp_lrclk,  // Word select (LRC)
    output wire amp_din,    // Serial data to amp (DIN)
    output wire amp_sd,     // Shutdown control (SD)
    inout  wire amp_gain    // Gain setting (GAIN), active-Z for floating
);

    // -------------------------------------------------------------------------
    // I2S clock generation: 25 MHz / 8 = 3.125 MHz BCLK, ~48.8 kHz sample rate
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // I2S receiver: deserialize mic data into parallel samples
    // -------------------------------------------------------------------------
    wire [23:0] rx_left_data;
    wire        rx_left_valid;
    wire [23:0] rx_right_data;
    wire        rx_right_valid;

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
        .right_data   (rx_right_data),
        .right_valid  (rx_right_valid)
    );

    // -------------------------------------------------------------------------
    // Sample registers: hold latest samples for the transmitter
    // -------------------------------------------------------------------------
    reg [23:0] left_sample;
    reg [23:0] right_sample;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            left_sample  <= 24'd0;
            right_sample <= 24'd0;
        end else begin
            if (rx_left_valid)
                left_sample <= rx_left_data;
            if (rx_right_valid)
                right_sample <= rx_right_data;
        end
    end

    // -------------------------------------------------------------------------
    // I2S transmitter: re-serialize parallel samples to amp
    // -------------------------------------------------------------------------
    wire tx_sdata;

    i2s_tx #(
        .DATA_BITS(24)
    ) tx (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .bclk_falling (bclk_falling),
        .lrclk        (lrclk),
        .left_data    (left_sample),
        .right_data   (24'd0),       // Mic is left-only; zero right to avoid noise
        .sdata        (tx_sdata)
    );

    assign amp_din = tx_sdata;

    // -------------------------------------------------------------------------
    // I2S clock outputs (same clocks to both mic and amp)
    // -------------------------------------------------------------------------
    assign mic_bclk  = bclk;
    assign amp_bclk  = bclk;
    assign mic_lrclk = lrclk;
    assign amp_lrclk = lrclk;

    // -------------------------------------------------------------------------
    // Control pins
    // -------------------------------------------------------------------------
    assign mic_sel  = 1'b0;    // Left channel (data on low LRCLK half)
    assign amp_sd   = 1'b1;    // Enable amplifier
    assign amp_gain = 1'bz;    // Floating: 9 dB default gain

    // -------------------------------------------------------------------------
    // Status LEDs (active low)
    // -------------------------------------------------------------------------
    assign led_r = 1'b1;       // Off
    assign led_g = 1'b0;       // On: running
    assign led_b = 1'b1;       // Off

endmodule
