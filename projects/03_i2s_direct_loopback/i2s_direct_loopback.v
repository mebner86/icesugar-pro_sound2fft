// I2S Direct Loopback for iCESugar-Pro (ECP5-25F)
// Forwards I2S audio from SPH0645 microphone directly to MAX98357A amplifier.
// The FPGA acts as I2S clock master; mic DOUT is wired straight to amp DIN.
// No deserialization or reserialization — pure bit-stream pass-through.

module i2s_direct_loopback (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // SPH0645 microphone
    output wire mic_bclk,   // Bit clock (BCLK)
    output wire mic_lrclk,  // Word select (LRCLK)
    input  wire mic_data,   // Serial data from mic (DOUT)
    output wire mic_sel,    // Channel select (SEL)

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

    /* verilator lint_off PINCONNECTEMPTY */
    i2s_clkgen #(
        .CLK_DIV(4)
    ) clkgen (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .bclk         (bclk),
        .lrclk        (lrclk),
        .bclk_falling ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // -------------------------------------------------------------------------
    // I2S clock outputs (same clocks to both mic and amp)
    // -------------------------------------------------------------------------
    assign mic_bclk  = bclk;
    assign mic_lrclk = lrclk;
    assign amp_bclk  = bclk;
    assign amp_lrclk = lrclk;

    // -------------------------------------------------------------------------
    // Direct data pass-through: mic DOUT → amp DIN
    // -------------------------------------------------------------------------
    assign amp_din = mic_data;

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
    assign mic_sel  = 1'b0;        // Left channel (data on low LRCLK half)
    assign amp_sd   = amp_enabled; // High=on, low=shutdown
    assign amp_gain = 1'bz;        // Floating: 9 dB default gain

    // -------------------------------------------------------------------------
    // Status LEDs (active low)
    // -------------------------------------------------------------------------
    assign led_r = 1'b1;       // Off
    assign led_g = 1'b0;       // On: running
    assign led_b = 1'b1;       // Off

endmodule
