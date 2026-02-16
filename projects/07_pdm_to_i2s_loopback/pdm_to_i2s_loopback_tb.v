// Testbench for PDM-to-I2S loopback (PDM CIC decimation → I2S TX)
`timescale 1ns / 1ps

module pdm_to_i2s_loopback_tb;

    reg clk_25m;
    reg rst_n;
    wire led_r, led_g, led_b;

    wire pdm_clk, pdm_sel;
    reg  pdm_dat;
    wire amp_bclk, amp_lrclk, amp_din, amp_sd;
    wire amp_gain;

    // Instantiate the DUT
    pdm_to_i2s_loopback dut (
        .clk_25m(clk_25m),
        .rst_n(rst_n),
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b),
        .pdm_clk(pdm_clk),
        .pdm_dat(pdm_dat),
        .pdm_sel(pdm_sel),
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
        $dumpfile("build/pdm_to_i2s_loopback_tb.vcd");
        $dumpvars(0, pdm_to_i2s_loopback_tb);
    end

    // -------------------------------------------------------------------------
    // Task: send a PDM frame (64 bits, one per BCLK cycle)
    // MP34DT01-M drives data on pdm_clk falling edge; we emulate that here.
    // -------------------------------------------------------------------------
    task send_pdm_frame;
        input [63:0] pattern;
        integer i;
        begin
            for (i = 63; i >= 0; i = i - 1) begin
                @(negedge pdm_clk);
                pdm_dat = pattern[i];
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor: display CIC output on each pcm_valid
    // -------------------------------------------------------------------------
    reg signed [15:0] last_pcm;
    integer pcm_count;

    always @(posedge clk_25m) begin
        if (dut.pcm_valid) begin
            last_pcm = dut.pcm_sample;
            pcm_count = pcm_count + 1;
            $display("[%0t] PCM #%0d: %0d (0x%04X)", $time, pcm_count,
                     $signed(dut.pcm_sample), dut.pcm_sample);
        end
    end

    // -------------------------------------------------------------------------
    // Main simulation
    // -------------------------------------------------------------------------
    integer errors;

    initial begin
        $display("Starting PDM-to-I2S loopback simulation...");
        errors = 0;
        pcm_count = 0;
        pdm_dat = 0;

        // Apply reset
        rst_n = 0;
        #200;
        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // Wait for first pdm_clk falling edge to sync
        @(negedge pdm_clk);

        // -----------------------------------------------------------------
        // Test 1: All-ones PDM (DC positive)
        // After several frames the CIC should ramp up to a positive value.
        // -----------------------------------------------------------------
        $display("\n--- Test 1: All-ones PDM (6 frames) ---");
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);
        send_pdm_frame(64'hFFFFFFFFFFFFFFFF);

        if (last_pcm <= 0) begin
            $display("ERROR: After all-ones, expected positive PCM, got %0d", last_pcm);
            errors = errors + 1;
        end else begin
            $display("OK: All-ones produced positive PCM: %0d", last_pcm);
        end

        // -----------------------------------------------------------------
        // Test 2: All-zeros PDM (DC negative)
        // After several frames the CIC should swing to a negative value.
        // -----------------------------------------------------------------
        $display("\n--- Test 2: All-zeros PDM (6 frames) ---");
        send_pdm_frame(64'h0000000000000000);
        send_pdm_frame(64'h0000000000000000);
        send_pdm_frame(64'h0000000000000000);
        send_pdm_frame(64'h0000000000000000);
        send_pdm_frame(64'h0000000000000000);
        send_pdm_frame(64'h0000000000000000);

        if (last_pcm >= 0) begin
            $display("ERROR: After all-zeros, expected negative PCM, got %0d", last_pcm);
            errors = errors + 1;
        end else begin
            $display("OK: All-zeros produced negative PCM: %0d", last_pcm);
        end

        // -----------------------------------------------------------------
        // Test 3: Alternating 1/0 (Nyquist frequency)
        // Sinc³ filter heavily attenuates this — output should be near zero.
        // -----------------------------------------------------------------
        $display("\n--- Test 3: Alternating 1/0 (6 frames) ---");
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);
        send_pdm_frame(64'hAAAAAAAAAAAAAAAA);

        if (last_pcm > 100 || last_pcm < -100) begin
            $display("ERROR: Alternating pattern should be near zero, got %0d", last_pcm);
            errors = errors + 1;
        end else begin
            $display("OK: Alternating pattern near zero: %0d", last_pcm);
        end

        // -----------------------------------------------------------------
        // Test 4: Verify pcm_valid count (~1 per frame, 18 frames total)
        // Allow ±1 due to alignment between test sync and decimation counter.
        // -----------------------------------------------------------------
        $display("\n--- Test 4: pcm_valid count ---");
        if (pcm_count < 17 || pcm_count > 19) begin
            $display("ERROR: Expected ~18 pcm_valid pulses, got %0d", pcm_count);
            errors = errors + 1;
        end else begin
            $display("OK: Got %0d pcm_valid pulses", pcm_count);
        end

        // Let a few more BCLK cycles pass
        repeat (64) @(negedge pdm_clk);

        $display("");
        if (errors == 0)
            $display("PASS: All checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

endmodule
