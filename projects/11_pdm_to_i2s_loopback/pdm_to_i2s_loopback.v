// PDM-to-I2S Loopback for iCESugar-Pro (ECP5-25F)
// Reads audio from MP34DT01-M PDM microphone, converts to parallel samples,
// then re-serializes and sends to MAX98357A I2S amplifier.

module pdm_to_i2s_loopback (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // MP34DT01-M PDM microphone
    output wire pdm_clk,    // PDM clock
    input  wire pdm_dat,    // PDM data
    output wire pdm_sel,    // L/R channel select (low=left)

    // MAX98357A amplifier
    output wire amp_bclk,   // Bit clock (BCLK)
    output wire amp_lrclk,  // Word select (LRC)
    output wire amp_din,    // Serial data to amp (DIN)
    output wire amp_sd,     // Shutdown control (SD): low=off, high=on
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
    // PDM microphone: clock and control
    // -------------------------------------------------------------------------
    assign pdm_clk = bclk;  // 3.125 MHz PDM clock (within MP34DT01-M 1-3.25 MHz range)
    assign pdm_sel = 1'b0;  // Left channel (data driven on CLK falling edge)

    // -------------------------------------------------------------------------
    // PDM input synchronizer (2-stage for metastability)
    // -------------------------------------------------------------------------
    reg pdm_sync1, pdm_sync2;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pdm_sync1 <= 1'b0;
            pdm_sync2 <= 1'b0;
        end else begin
            pdm_sync1 <= pdm_dat;
            pdm_sync2 <= pdm_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // BCLK rising edge detect (for PDM sampling)
    // MP34DT01-M drives data on CLK falling edge; sample on rising edge.
    // -------------------------------------------------------------------------
    reg bclk_prev;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            bclk_prev <= 1'b0;
        else
            bclk_prev <= bclk;
    end

    wire bclk_rising = bclk && !bclk_prev;

    // -------------------------------------------------------------------------
    // CIC decimation filter: PDM 1-bit → 16-bit PCM at 48.8 kHz
    // 3rd-order sinc³, R=64 decimation (3.125 MHz / 64 = 48.828 kHz)
    // -------------------------------------------------------------------------
    wire signed [15:0] pcm_sample;
    wire               pcm_valid;

    pdm_cic #(
        .CIC_ORDER (3),
        .DEC_RATIO (64),
        .OUT_BITS  (16)
    ) cic (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pdm_bit   (pdm_sync2),
        .pdm_valid (bclk_rising),
        .pcm_out   (pcm_sample),
        .pcm_valid (pcm_valid)
    );

    // -------------------------------------------------------------------------
    // Latch CIC output into I2S sample register
    // VOLUME_SHIFT attenuates by ~6 dB per step to prevent feedback.
    // -------------------------------------------------------------------------
    localparam VOLUME_SHIFT = 4;  // Right-shift by 4 → ~24 dB attenuation

    wire signed [15:0] attenuated = pcm_sample >>> VOLUME_SHIFT;
    reg [23:0] left_sample;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            left_sample <= 24'd0;
        else if (pcm_valid)
            left_sample <= {attenuated, 8'd0};
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
    // I2S clock outputs to amplifier
    // -------------------------------------------------------------------------
    assign amp_bclk  = bclk;
    assign amp_lrclk = lrclk;

    // -------------------------------------------------------------------------
    // Amp startup delay: hold amp in shutdown for ~1s to let system settle
    // -------------------------------------------------------------------------
    reg [24:0] amp_delay_cnt;
    reg        amp_enabled;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            amp_delay_cnt <= 25'd0;
            amp_enabled   <= 1'b0;
        end else if (!amp_enabled) begin
            if (amp_delay_cnt == 25'd24_999_999)   // 1 s at 25 MHz
                amp_enabled <= 1'b1;
            else
                amp_delay_cnt <= amp_delay_cnt + 25'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Control pins
    // -------------------------------------------------------------------------
    assign amp_sd   = amp_enabled;                  // High=on, low=shutdown
    assign amp_gain = 1'bz;    // Floating: 9 dB default gain

    // -------------------------------------------------------------------------
    // Status LEDs (active low)
    // -------------------------------------------------------------------------
    assign led_r = 1'b1;       // Off
    assign led_g = 1'b0;       // On: running
    assign led_b = 1'b1;       // Off

endmodule
