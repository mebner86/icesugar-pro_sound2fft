// Testbench for I2S loopback
`timescale 1ns / 1ps

module i2s_loopback_tb;

    reg clk_25m;
    reg rst_n;
    wire led_r, led_g, led_b;

    wire mic_bclk, mic_lrclk, mic_sel;
    reg  mic_data;
    wire amp_bclk, amp_lrclk, amp_din, amp_sd;
    wire amp_gain;

    // Instantiate the DUT
    i2s_loopback dut (
        .clk_25m(clk_25m),
        .rst_n(rst_n),
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b),
        .mic_bclk(mic_bclk),
        .mic_lrclk(mic_lrclk),
        .mic_data(mic_data),
        .mic_sel(mic_sel),
        .amp_bclk(amp_bclk),
        .amp_lrclk(amp_lrclk),
        .amp_din(amp_din),
        .amp_sd(amp_sd),
        .amp_gain(amp_gain)
    );

    // 25 MHz clock = 40ns period
    initial clk_25m = 0;
    always #20 clk_25m = ~clk_25m;

    // VCD dump
    initial begin
        $dumpfile("build/i2s_loopback_tb.vcd");
        $dumpvars(0, i2s_loopback_tb);
    end

    // Simulate SPH0645 mic: output data on falling edge of BCLK
    // Send a 24-bit test word (0xABCDEF) in the left channel slot
    reg [23:0] test_word;
    integer    bit_idx;

    task send_word;
        input [23:0] word;
        integer i;
        begin
            // I2S: one BCLK delay after LRCLK transition, then 24 data bits
            @(negedge mic_bclk);  // Slot bit 0: one-cycle delay
            mic_data = 1'b0;
            for (i = 23; i >= 0; i = i - 1) begin
                @(negedge mic_bclk);
                mic_data = word[i];
            end
            // Remaining slot bits: pad with zeros
            for (i = 0; i < 7; i = i + 1) begin
                @(negedge mic_bclk);
                mic_data = 1'b0;
            end
        end
    endtask

    // Run simulation
    initial begin
        $display("Starting I2S loopback simulation...");

        mic_data = 0;

        // Apply reset
        rst_n = 0;
        #200;
        rst_n = 1;
        $display("Reset released at %0t", $time);

        // Wait for first LRCLK falling edge (start of left channel)
        @(negedge mic_lrclk);

        // Send test words over two full frames
        send_word(24'hABCDEF);  // Left channel, frame 1
        send_word(24'h000000);  // Right channel, frame 1
        send_word(24'h123456);  // Left channel, frame 2
        send_word(24'h000000);  // Right channel, frame 2

        // Let a few more BCLK cycles pass
        repeat (64) @(negedge mic_bclk);

        $display("Simulation complete.");
        $finish;
    end

endmodule
