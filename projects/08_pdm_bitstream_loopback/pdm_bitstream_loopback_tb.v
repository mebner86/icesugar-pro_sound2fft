// Testbench for PDM bitstream loopback
// Verifies: reset, PDM clock division, channel-select pin, and
// the 2-stage synchronizer data path.
`timescale 1ns / 1ps

module pdm_bitstream_loopback_tb;

    reg  clk_25m;
    reg  rst_n;
    wire led_r, led_g, led_b;

    wire mic_clk;
    reg  mic_dat;
    wire mic_sel;

    wire amp_clk;
    wire amp_dat;

    // Instantiate DUT
    pdm_bitstream_loopback dut (
        .clk_25m(clk_25m),
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

    // 25 MHz clock → 40 ns period
    initial clk_25m = 0;
    always #20 clk_25m = ~clk_25m;

    // VCD dump
    initial begin
        $dumpfile("build/pdm_bitstream_loopback_tb.vcd");
        $dumpvars(0, pdm_bitstream_loopback_tb);
    end

    integer errors;

    initial begin
        $display("Starting PDM bitstream loopback simulation...");
        errors  = 0;
        mic_dat = 0;

        // ---------------------------------------------------------------
        // Apply reset and verify outputs are deasserted cleanly
        // ---------------------------------------------------------------
        rst_n = 0;
        #100;

        // Check: amp_dat should be 0 during reset
        if (amp_dat !== 1'b0) begin
            $display("ERROR [reset]: amp_dat=%b, expected 0", amp_dat);
            errors = errors + 1;
        end

        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // ---------------------------------------------------------------
        // Test 1 – mic_sel is tied low (left-channel select)
        // ---------------------------------------------------------------
        #40;  // one clock cycle
        if (mic_sel !== 1'b0) begin
            $display("ERROR [mic_sel]: expected 0, got %b", mic_sel);
            errors = errors + 1;
        end else begin
            $display("OK [mic_sel]: 0 (left channel)");
        end

        // ---------------------------------------------------------------
        // Test 2 – amp_clk == mic_clk (shared clock)
        // Sample ten rising edges and confirm equality.
        // ---------------------------------------------------------------
        begin : clk_check
            integer i;
            for (i = 0; i < 10; i = i + 1) begin
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
        // Test 3 – PDM clock period = 8 × 40 ns = 320 ns
        // Measure two consecutive rising edges.
        // ---------------------------------------------------------------
        begin : period_check
            realtime t0, t1;
            @(posedge mic_clk);
            t0 = $realtime;
            @(posedge mic_clk);
            t1 = $realtime;
            if ((t1 - t0) < 300.0 || (t1 - t0) > 340.0) begin
                $display("ERROR [pdm_period]: measured %0t ns, expected 320 ns",
                         t1 - t0);
                errors = errors + 1;
            end else begin
                $display("OK [pdm_period]: %0t ns", t1 - t0);
            end
        end

        // ---------------------------------------------------------------
        // Test 4 – 2-stage synchronizer: mic_dat=1 propagates in 2 clocks
        // ---------------------------------------------------------------
        @(posedge clk_25m);
        mic_dat = 1;
        // Cycle 1: pdm_sync1 captures 1, pdm_sync2 still 0
        @(posedge clk_25m);
        if (amp_dat !== 1'b0) begin
            $display("ERROR [sync latency]: amp_dat should still be 0 after 1 cycle");
            errors = errors + 1;
        end
        // Cycle 2: pdm_sync2 (= amp_dat) captures 1
        @(posedge clk_25m);
        if (amp_dat !== 1'b1) begin
            $display("ERROR [sync]: amp_dat=%b after 2 cycles, expected 1", amp_dat);
            errors = errors + 1;
        end else begin
            $display("OK [sync]: mic_dat=1 appears at amp_dat after 2 clock cycles");
        end

        // ---------------------------------------------------------------
        // Test 5 – mic_dat=0 also propagates in 2 clocks
        // ---------------------------------------------------------------
        @(posedge clk_25m);
        mic_dat = 0;
        @(posedge clk_25m);
        if (amp_dat !== 1'b1) begin
            $display("ERROR [sync latency]: amp_dat should still be 1 after 1 cycle");
            errors = errors + 1;
        end
        @(posedge clk_25m);
        if (amp_dat !== 1'b0) begin
            $display("ERROR [sync]: amp_dat=%b after 2 cycles, expected 0", amp_dat);
            errors = errors + 1;
        end else begin
            $display("OK [sync]: mic_dat=0 appears at amp_dat after 2 clock cycles");
        end

        // ---------------------------------------------------------------
        // Test 6 – green LED on, red and blue off (active-low)
        // ---------------------------------------------------------------
        if (led_g !== 1'b0 || led_r !== 1'b1 || led_b !== 1'b1) begin
            $display("ERROR [leds]: R=%b G=%b B=%b, expected R=1 G=0 B=1",
                     led_r, led_g, led_b);
            errors = errors + 1;
        end else begin
            $display("OK [leds]: green on, red and blue off");
        end

        // Let the simulation run a few more PDM clocks
        repeat (16) @(posedge mic_clk);

        $display("");
        if (errors == 0)
            $display("PASS: All checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

endmodule
