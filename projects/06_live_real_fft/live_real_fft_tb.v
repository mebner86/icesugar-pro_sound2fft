// Testbench for Live Real FFT Spectrum Display
`timescale 1ns / 1ps

module live_real_fft_tb;

    // Clock and reset
    reg clk_25m;
    reg rst_n;

    // Mic data (simulated I2S serial input)
    wire mic_bclk;
    wire mic_lrclk;
    reg  mic_data;

    // LED outputs
    wire led_r;
    wire led_g;
    wire led_b;

    // Instantiate the design under test
    live_real_fft dut (
        .clk_25m(clk_25m),
        .rst_n(rst_n),
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b),
        .mic_bclk(mic_bclk),
        .mic_lrclk(mic_lrclk),
        .mic_data(mic_data)
    );

    // Generate 25 MHz clock (40ns period)
    initial begin
        clk_25m = 0;
        forever #20 clk_25m = ~clk_25m;
    end

    // Simple I2S data generator: outputs a constant sample value
    // In real hardware, the mic provides this; here we simulate it
    reg [23:0] test_sample;
    reg [4:0]  bit_cnt;
    reg        lrclk_prev;

    initial begin
        mic_data = 0;
        test_sample = 24'h100000;  // Moderate positive value
        bit_cnt = 0;
        lrclk_prev = 0;
    end

    // Drive mic_data synchronized to mic_bclk rising edge
    always @(posedge mic_bclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 0;
            lrclk_prev <= 0;
        end else begin
            lrclk_prev <= mic_lrclk;
            if (mic_lrclk != lrclk_prev) begin
                // LRCLK transition: reset bit counter, 1-bit delay
                bit_cnt <= 0;
            end else if (bit_cnt == 0) begin
                // I2S 1-bit delay slot
                bit_cnt  <= 1;
                mic_data <= 0;
            end else if (bit_cnt <= 24) begin
                // Shift out MSB-first
                mic_data <= test_sample[24 - bit_cnt];
                bit_cnt  <= bit_cnt + 1;
            end else begin
                mic_data <= 0;  // Padding
                bit_cnt  <= bit_cnt + 1;
            end
        end
    end

    // Test sequence
    initial begin
        $dumpfile("build/live_real_fft_tb.vcd");
        $dumpvars(0, live_real_fft_tb);

        // Initialize
        rst_n = 0;

        // Release reset after a few cycles
        #200;
        rst_n = 1;

        // Run long enough to collect 512 samples and compute FFT
        // At ~48.8 kHz sample rate, 512 samples takes ~10.4 ms
        // Plus FFT computation time (~150 us) and unscramble (~30 us)
        // Total: ~11 ms = 11,000,000 ns
        #12000000;

        $display("Simulation complete");
        $finish;
    end

endmodule
