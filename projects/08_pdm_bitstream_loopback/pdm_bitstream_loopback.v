// PDM Bitstream Loopback for iCESugar-Pro (ECP5-25F)
// Reads the raw PDM bitstream from an MP34DT01-M microphone and forwards it
// directly to a MAX98358 PDM amplifier with no decimation or DSP.
//
// Signal flow:
//   FPGA generates 3.125 MHz PDM clock
//   → MP34DT01-M mic (mic_clk / mic_dat)
//   → 2-stage metastability synchronizer
//   → MAX98358 PDM amp (amp_clk / amp_dat)

module pdm_bitstream_loopback (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset button

    // Status LEDs (active low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // MP34DT01-M PDM microphone
    output wire mic_clk,    // PDM clock output to mic (3.125 MHz)
    input  wire mic_dat,    // PDM data input from mic
    output wire mic_sel,    // Channel select: 0 = left (mic drives data on CLK falling edge)

    // MAX98358 PDM amplifier
    output wire amp_clk,    // PDM clock output to amp (same source as mic_clk)
    output wire amp_dat     // PDM data output to amp (synchronized mic data)
);

    // -------------------------------------------------------------------------
    // PDM clock generation: 25 MHz / 8 = 3.125 MHz
    // Toggle every 4 system clocks: period = 8 × 40 ns = 320 ns
    // Within MP34DT01-M spec (1–3.25 MHz) and MAX98358 spec.
    // -------------------------------------------------------------------------
    reg [2:0] clk_cnt;
    reg       pdm_clk_r;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt   <= 3'd0;
            pdm_clk_r <= 1'b0;
        end else begin
            if (clk_cnt == 3'd3) begin
                clk_cnt   <= 3'd0;
                pdm_clk_r <= ~pdm_clk_r;
            end else begin
                clk_cnt <= clk_cnt + 3'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Microphone control
    // -------------------------------------------------------------------------
    assign mic_clk = pdm_clk_r;
    assign mic_sel = 1'b0;   // Left channel: mic drives data on CLK falling edge

    // -------------------------------------------------------------------------
    // 2-stage synchronizer: prevent metastability on the async PDM data input.
    // Adds 2 × 40 ns = 80 ns latency, well within the 160 ns PDM half-period.
    // -------------------------------------------------------------------------
    reg pdm_sync1, pdm_sync2;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pdm_sync1 <= 1'b0;
            pdm_sync2 <= 1'b0;
        end else begin
            pdm_sync1 <= mic_dat;
            pdm_sync2 <= pdm_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // Amplifier outputs
    // MAX98358 SD_MODE is pulled to 3.3 V via 2 kΩ on the module (always on).
    // -------------------------------------------------------------------------
    assign amp_clk = pdm_clk_r;   // Same clock as mic
    assign amp_dat = pdm_sync2;   // Synchronized mic bitstream

    // -------------------------------------------------------------------------
    // Status LEDs (active low)
    // -------------------------------------------------------------------------
    assign led_r = 1'b1;   // Off
    assign led_g = 1'b0;   // On: system running
    assign led_b = 1'b1;   // Off

endmodule
