// I2S Loopback for iCESugar-Pro (ECP5-25F)
// Reads audio from SPH0645 microphone and sends it to MAX98357A amplifier

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
    // BCLK generation: 25 MHz / 8 = 3.125 MHz
    // -------------------------------------------------------------------------
    reg [2:0] bclk_counter;
    reg       bclk_reg;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            bclk_counter <= 3'd0;
            bclk_reg     <= 1'b0;
        end else if (bclk_counter == 3'd3) begin
            bclk_counter <= 3'd0;
            bclk_reg     <= ~bclk_reg;
        end else begin
            bclk_counter <= bclk_counter + 3'd1;
        end
    end

    // -------------------------------------------------------------------------
    // LRCLK generation: toggles every 32 BCLKs (64 per frame = ~48.8 kHz)
    // -------------------------------------------------------------------------
    reg [4:0] bit_counter;
    reg       lrclk_reg;

    wire bclk_falling = (bclk_counter == 3'd3) && bclk_reg;

    always @(posedge clk_25m or negedge rst_n) begin
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

    // -------------------------------------------------------------------------
    // I2S clock outputs (same signal to both devices via separate pins)
    // -------------------------------------------------------------------------
    assign mic_bclk  = bclk_reg;
    assign amp_bclk  = bclk_reg;
    assign mic_lrclk = lrclk_reg;
    assign amp_lrclk = lrclk_reg;

    // -------------------------------------------------------------------------
    // Data passthrough: mic DOUT → amp DIN
    // SPH0645 outputs on falling BCLK, MAX98357A latches on rising BCLK
    // -------------------------------------------------------------------------
    assign amp_din = mic_data;

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
    assign led_g = 1'b0;       // On: indicates running
    assign led_b = 1'b1;       // Off

endmodule
