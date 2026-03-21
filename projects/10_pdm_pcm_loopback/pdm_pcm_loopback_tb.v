// Testbench for PDM PCM Loopback
//
// Tests: reset, PDM clock, CDC synchroniser, LED mute indicator,
// and modulator duty-cycle polarity after the CIC pipeline has settled.
//
// Timing reference:
//   System clock period : 40 ns  (25 MHz)
//   PDM clock period    : 320 ns (8 system clocks, 3.125 MHz)
//   CIC decimation rate : 64 PDM clocks = 20 480 ns per PCM sample
//   CIC settle time     : ~6 decimation periods (6 × 20 480 ns = 122 880 ns)
`timescale 1ns / 1ps

module pdm_pcm_loopback_tb;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg  clk_25m;
    reg  rst_n;
    wire led_r, led_g, led_b;

    wire mic_clk;
    reg  mic_dat;
    wire mic_sel;

    wire amp_clk;
    wire amp_dat;

    // Instantiate DUT with default GAIN_SHIFT = 4
    pdm_pcm_loopback #(
        .GAIN_SHIFT(4)
    ) dut (
        .clk_25m (clk_25m),
        .rst_n   (rst_n),
        .led_r   (led_r),
        .led_g   (led_g),
        .led_b   (led_b),
        .mic_clk (mic_clk),
        .mic_dat (mic_dat),
        .mic_sel (mic_sel),
        .amp_clk (amp_clk),
        .amp_dat (amp_dat)
    );

    // -------------------------------------------------------------------------
    // 25 MHz clock → 40 ns period
    // -------------------------------------------------------------------------
    initial clk_25m = 0;
    always #20 clk_25m = ~clk_25m;

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("build/pdm_pcm_loopback_tb.vcd");
        $dumpvars(0, pdm_pcm_loopback_tb);
    end

    integer errors;
    integer ones_count;
    integer i;
    reg     alt_bit;    // toggles each PDM clock for silence test

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("Starting PDM PCM loopback simulation...");
        errors  = 0;
        mic_dat = 0;
        alt_bit = 0;

        // ---------------------------------------------------------------
        // Reset
        // ---------------------------------------------------------------
        rst_n = 0;
        #200;

        // During reset: amp_dat should be 0 (modulator reset value)
        if (amp_dat !== 1'b0) begin
            $display("ERROR [reset]: amp_dat=%b, expected 0", amp_dat);
            errors = errors + 1;
        end

        // LEDs: red on (led_r=0), green off (led_g=1) — combinational from rst_n
        if (led_r !== 1'b0 || led_g !== 1'b1) begin
            $display("ERROR [reset leds]: led_r=%b led_g=%b, expected 0 1", led_r, led_g);
            errors = errors + 1;
        end else begin
            $display("OK [reset leds]: red on, green off while rst_n=0");
        end

        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // ---------------------------------------------------------------
        // Test 1 – LED polarity during normal operation
        // ---------------------------------------------------------------
        @(posedge clk_25m);
        if (led_r !== 1'b1 || led_g !== 1'b0 || led_b !== 1'b1) begin
            $display("ERROR [run leds]: led_r=%b led_g=%b led_b=%b, expected 1 0 1",
                     led_r, led_g, led_b);
            errors = errors + 1;
        end else begin
            $display("OK [run leds]: green on, red and blue off");
        end

        // ---------------------------------------------------------------
        // Test 2 – mic_sel tied low (left channel)
        // ---------------------------------------------------------------
        if (mic_sel !== 1'b0) begin
            $display("ERROR [mic_sel]: expected 0, got %b", mic_sel);
            errors = errors + 1;
        end else begin
            $display("OK [mic_sel]: 0 (left channel)");
        end

        // ---------------------------------------------------------------
        // Test 3 – PDM clock period = 8 × 40 ns = 320 ns
        // ---------------------------------------------------------------
        begin : period_check
            realtime t0, t1;
            @(posedge mic_clk);
            t0 = $realtime;
            @(posedge mic_clk);
            t1 = $realtime;
            if ((t1 - t0) < 300.0 || (t1 - t0) > 340.0) begin
                $display("ERROR [pdm_period]: measured %0t ns, expected 320 ns", t1 - t0);
                errors = errors + 1;
            end else begin
                $display("OK [pdm_period]: %0t ns", t1 - t0);
            end
        end

        // ---------------------------------------------------------------
        // Test 4 – amp_clk == mic_clk (same clock source)
        // ---------------------------------------------------------------
        begin : clk_check
            integer j;
            for (j = 0; j < 10; j = j + 1) begin
                @(posedge clk_25m);
                if (amp_clk !== mic_clk) begin
                    $display("ERROR [amp_clk]: amp_clk=%b != mic_clk=%b at %0t",
                             amp_clk, mic_clk, $time);
                    errors = errors + 1;
                end
            end
            $display("OK [amp_clk]: matches mic_clk over 10 samples");
        end

        // ---------------------------------------------------------------
        // Test 5 – Silence: alternating PDM (0→1→0→…) = zero mean.
        //   Settle for 6 decimation periods (384 PDM clocks), then measure
        //   duty cycle over 128 PDM clocks. Expect ~50 % (48–80 ones/128).
        // ---------------------------------------------------------------
        $display("[%0t] Silence test: feeding alternating PDM...", $time);

        // Settle: alternate mic_dat for 6 × 64 PDM clocks
        alt_bit = 0;
        for (i = 0; i < 6 * 64; i = i + 1) begin
            mic_dat = alt_bit;
            alt_bit = ~alt_bit;
            @(posedge mic_clk);
        end

        // Measure: continue alternating, count amp_dat=1 over 128 PDM clocks
        ones_count = 0;
        for (i = 0; i < 128; i = i + 1) begin
            mic_dat = alt_bit;
            alt_bit = ~alt_bit;
            @(posedge amp_clk);
            ones_count = ones_count + amp_dat;
        end

        if (ones_count < 48 || ones_count > 80) begin
            $display("ERROR [silence duty]: %0d/128 ones, expected ~64 (48-80)",
                     ones_count);
            errors = errors + 1;
        end else begin
            $display("OK [silence duty]: %0d/128 ones (~50%% duty)",
                     ones_count);
        end

        // ---------------------------------------------------------------
        // Test 6 – Positive input: all-1s PDM = full positive PCM.
        //   Settle for 6 decimation periods, then measure duty cycle over
        //   128 PDM clocks. Expect > 50 % (> 64 ones/128).
        // ---------------------------------------------------------------
        $display("[%0t] Positive test: feeding all-1s PDM...", $time);
        mic_dat = 1;
        repeat (6 * 64) @(posedge mic_clk);

        ones_count = 0;
        for (i = 0; i < 128; i = i + 1) begin
            @(posedge amp_clk);
            ones_count = ones_count + amp_dat;
        end

        if (ones_count <= 64) begin
            $display("ERROR [positive duty]: %0d/128 ones, expected > 64 for all-1s PDM",
                     ones_count);
            errors = errors + 1;
        end else begin
            $display("OK [positive duty]: %0d/128 ones — modulator tracking positive PCM",
                     ones_count);
        end

        // ---------------------------------------------------------------
        // Test 7 – Negative input: all-0s PDM = full negative PCM.
        //   Settle for 6 decimation periods, then measure duty cycle over
        //   128 PDM clocks. Expect < 50 % (< 64 ones/128).
        // ---------------------------------------------------------------
        $display("[%0t] Negative test: feeding all-0s PDM...", $time);
        mic_dat = 0;
        repeat (6 * 64) @(posedge mic_clk);

        ones_count = 0;
        for (i = 0; i < 128; i = i + 1) begin
            @(posedge amp_clk);
            ones_count = ones_count + amp_dat;
        end

        if (ones_count >= 64) begin
            $display("ERROR [negative duty]: %0d/128 ones, expected < 64 for all-0s PDM",
                     ones_count);
            errors = errors + 1;
        end else begin
            $display("OK [negative duty]: %0d/128 ones — modulator tracking negative PCM",
                     ones_count);
        end

        // ---------------------------------------------------------------
        // Test 8 – Mute: assert rst_n=0, verify LED and amp_dat go to
        //          their reset values immediately.
        // ---------------------------------------------------------------
        $display("[%0t] Mute test: asserting rst_n=0...", $time);
        rst_n = 0;
        @(posedge clk_25m);

        // LEDs: red on (led_r=0), green off (led_g=1)
        if (led_r !== 1'b0 || led_g !== 1'b1) begin
            $display("ERROR [mute leds]: led_r=%b led_g=%b, expected 0 1", led_r, led_g);
            errors = errors + 1;
        end else begin
            $display("OK [mute leds]: red on, green off while muted");
        end

        // amp_dat should be 0 (modulator and clock gen in reset)
        #200;
        if (amp_dat !== 1'b0) begin
            $display("ERROR [mute amp_dat]: amp_dat=%b, expected 0 during reset", amp_dat);
            errors = errors + 1;
        end else begin
            $display("OK [mute amp_dat]: amp_dat=0 while rst_n=0");
        end

        rst_n = 1;
        $display("[%0t] Mute released", $time);

        // Verify green LED returns immediately on release
        @(posedge clk_25m);
        if (led_g !== 1'b0 || led_r !== 1'b1) begin
            $display("ERROR [unmute leds]: led_r=%b led_g=%b, expected 1 0", led_r, led_g);
            errors = errors + 1;
        end else begin
            $display("OK [unmute leds]: green on, red off after release");
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("");
        if (errors == 0)
            $display("PASS: All checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

endmodule
