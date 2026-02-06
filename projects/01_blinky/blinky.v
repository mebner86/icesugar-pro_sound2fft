// Blinky example for iCESugar-Pro (ECP5-25F)
// Blinks the onboard LED at ~1Hz

module blinky (
    input  wire clk_25m,    // 25 MHz oscillator
    input  wire rst_n,      // Active-low reset
    output wire led_r,      // Red LED (active low)
    output wire led_g,      // Green LED (active low)
    output wire led_b       // Blue LED (active low)
);

    // 25 MHz clock -> 1 Hz blink requires ~25M counts
    // Use 24-bit counter, bit 23 toggles at ~1.5 Hz
    reg [23:0] counter;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            counter <= 24'd0;
        else
            counter <= counter + 1'b1;
    end

    // LED accent: cycle through colors using upper counter bits
    assign led_r = ~counter[23];
    assign led_g = ~counter[22];
    assign led_b = ~counter[21];

endmodule
