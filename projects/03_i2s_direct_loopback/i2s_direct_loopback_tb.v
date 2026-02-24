// Testbench for I2S direct loopback (wire-through path)
`timescale 1ns / 1ps

module i2s_direct_loopback_tb;

    reg clk_25m;
    reg rst_n;
    wire led_r, led_g, led_b;

    wire mic_bclk, mic_lrclk, mic_sel;
    reg  mic_data;
    wire amp_bclk, amp_lrclk, amp_din, amp_sd;
    wire amp_gain;

    // Instantiate the DUT
    i2s_direct_loopback dut (
        .clk_25m  (clk_25m),
        .rst_n    (rst_n),
        .led_r    (led_r),
        .led_g    (led_g),
        .led_b    (led_b),
        .mic_bclk (mic_bclk),
        .mic_lrclk(mic_lrclk),
        .mic_data (mic_data),
        .mic_sel  (mic_sel),
        .amp_bclk (amp_bclk),
        .amp_lrclk(amp_lrclk),
        .amp_din  (amp_din),
        .amp_sd   (amp_sd),
        .amp_gain (amp_gain)
    );

    // 25 MHz clock = 40 ns period
    initial clk_25m = 0;
    always #20 clk_25m = ~clk_25m;

    // VCD dump
    initial begin
        $dumpfile("build/i2s_direct_loopback_tb.vcd");
        $dumpvars(0, i2s_direct_loopback_tb);
    end

    // -------------------------------------------------------------------------
    // Main simulation
    // -------------------------------------------------------------------------
    integer errors;
    integer bit_idx;

    initial begin
        $display("Starting I2S direct loopback simulation...");
        errors   = 0;
        mic_data = 0;

        // Apply reset
        rst_n = 0;
        #200;
        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // Wait for the first BCLK falling edge
        @(negedge mic_bclk);

        // Drive mic_data through two complete I2S frames (128 BCLKs).
        // On every rising BCLK edge, verify that amp_din mirrors mic_data.
        for (bit_idx = 0; bit_idx < 128; bit_idx = bit_idx + 1) begin
            mic_data = bit_idx[0] ^ bit_idx[2];   // Alternating bit pattern
            @(posedge mic_bclk);                  // Data stable; sample point
            if (amp_din !== mic_data) begin
                $display("ERROR [bit %0d]: amp_din=%b, mic_data=%b",
                         bit_idx, amp_din, mic_data);
                errors = errors + 1;
            end
            @(negedge mic_bclk);
        end

        // Verify clock forwarding
        $display("[%0t] Clock forwarding check...", $time);
        if (amp_bclk !== mic_bclk) begin
            $display("ERROR: amp_bclk != mic_bclk");
            errors = errors + 1;
        end
        if (amp_lrclk !== mic_lrclk) begin
            $display("ERROR: amp_lrclk != mic_lrclk");
            errors = errors + 1;
        end

        // Let a few more BCLK cycles pass
        repeat (64) @(negedge mic_bclk);

        if (errors == 0)
            $display("PASS: All checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

endmodule
