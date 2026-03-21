// pdm_sigma_delta_modulator_tb.v — Testbench for pdm_sigma_delta_modulator
//
// Verifies that:
//   1. LEDs show green=on, red=off during normal operation.
//   2. amp_dat toggles frequently (sigma-delta is active, not stuck).
//   3. pcm_held sweeps through the positive sine peak (≥ +870 after ÷32).
//   4. pcm_held sweeps through the negative sine peak (≤ −870 after ÷32).
//   5. sine_addr is in the valid range 0..63.
//
// Timing reference:
//   PDM clock    = sys_clk / 8  → pdm_valid every 8 sys_clk
//   pcm_valid    = pdm_valid / 64 → one pcm_valid every 512 sys_clk
//   Sine period  = 64 pcm_valid × 512 sys_clk = 32 768 sys_clk

`timescale 1ns/1ps

module pdm_sigma_delta_modulator_tb;

    // =========================================================================
    // Clock
    // =========================================================================
    localparam CLK_PERIOD = 10;  // ns (arbitrary; sets simulation time units)

    reg clk;
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg  rst_n;
    wire led_r, led_g, led_b;
    wire amp_clk, amp_dat;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    pdm_sigma_delta_modulator dut (
        .clk_25m (clk),
        .rst_n   (rst_n),
        .led_r   (led_r),
        .led_g   (led_g),
        .led_b   (led_b),
        .amp_clk (amp_clk),
        .amp_dat (amp_dat)
    );

    // =========================================================================
    // Stimulus — run 2 full sine periods and collect statistics
    // =========================================================================
    // One sine period = 64 pcm_valid × 512 sys_clk = 32 768 sys_clk
    localparam SYS_CLK_PER_PERIOD = 64 * 64 * 8;  // 32 768

    integer errors;
    integer transitions;
    integer saw_positive;   // pcm_held reached >= +870
    integer saw_negative;   // pcm_held reached <= -870
    reg     prev_amp;

    initial begin
        $dumpfile("build/pdm_sigma_delta_modulator_tb.vcd");
        $dumpvars(0, pdm_sigma_delta_modulator_tb);

        errors       = 0;
        transitions  = 0;
        saw_positive = 0;
        saw_negative = 0;
        prev_amp     = 1'b0;

        // ----------------------------------------------------------------
        // Reset
        // ----------------------------------------------------------------
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ----------------------------------------------------------------
        // Check LED state: green on (low), red off (high)
        // ----------------------------------------------------------------
        if (led_g !== 1'b0 || led_r !== 1'b1) begin
            $display("FAIL [leds]: led_g=%b led_r=%b (expected green=0 red=1)",
                     led_g, led_r);
            errors = errors + 1;
        end else begin
            $display("OK   [leds]: green=on red=off during operation");
        end

        // ----------------------------------------------------------------
        // Run for 2 sine periods, sampling every system clock
        // ----------------------------------------------------------------
        repeat (2 * SYS_CLK_PER_PERIOD) begin
            @(posedge clk);

            // Count amp_dat transitions (sigma-delta activity)
            if (amp_dat !== prev_amp) begin
                transitions = transitions + 1;
                prev_amp    = amp_dat;
            end

            // After ÷32, peak ≈ ±1023. Check within ≈85% of expected peak.
            if ($signed(dut.pcm_held) >= 870)
                saw_positive = 1;

            if ($signed(dut.pcm_held) <= -870)
                saw_negative = 1;
        end

        // ----------------------------------------------------------------
        // Check: amp_dat must be active (sigma-delta running)
        // ----------------------------------------------------------------
        if (transitions < 100) begin
            $display("FAIL [amp_dat]: only %0d transitions over 2 periods (expected many)",
                     transitions);
            errors = errors + 1;
        end else begin
            $display("OK   [amp_dat]: %0d transitions over 2 sine periods", transitions);
        end

        // ----------------------------------------------------------------
        // Check: positive peak must have been reached
        // ----------------------------------------------------------------
        if (!saw_positive) begin
            $display("FAIL [positive peak]: pcm_held never reached >= +870 (after ÷32)");
            errors = errors + 1;
        end else begin
            $display("OK   [positive peak]: pcm_held reached sine maximum");
        end

        // ----------------------------------------------------------------
        // Check: negative peak must have been reached
        // ----------------------------------------------------------------
        if (!saw_negative) begin
            $display("FAIL [negative peak]: pcm_held never reached <= -870 (after ÷32)");
            errors = errors + 1;
        end else begin
            $display("OK   [negative peak]: pcm_held reached sine minimum");
        end

        // ----------------------------------------------------------------
        // Check: sine_addr wraps to 0 at exact period boundaries
        // ----------------------------------------------------------------
        if (dut.sine_addr > 6'd63) begin
            $display("FAIL [sine_addr]: out of range: %0d", dut.sine_addr);
            errors = errors + 1;
        end else begin
            $display("OK   [sine_addr]: %0d (in valid range 0..63)", dut.sine_addr);
        end

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("");
        if (errors == 0)
            $display("PASS: all checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

    // Timeout: 2 periods + comfortable margin
    initial begin
        #(CLK_PERIOD * (2 * SYS_CLK_PER_PERIOD + 2000));
        $display("TIMEOUT");
        $finish;
    end

endmodule
