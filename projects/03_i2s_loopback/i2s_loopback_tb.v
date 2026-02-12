// Testbench for I2S loopback (deserialize → reserialize path)
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

    // -------------------------------------------------------------------------
    // Task: send a word to the mic serial input in I2S format
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Task: capture a word from the amp serial output
    // -------------------------------------------------------------------------
    reg [23:0] captured_word;

    task capture_word;
        integer i;
        begin
            @(negedge amp_bclk);  // Slot bit 0: one-cycle delay (should be zero)
            for (i = 23; i >= 0; i = i - 1) begin
                @(negedge amp_bclk);
                captured_word[i] = amp_din;
            end
            // Skip remaining slot bits
            for (i = 0; i < 7; i = i + 1) begin
                @(negedge amp_bclk);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor: display RX captured samples
    // -------------------------------------------------------------------------
    always @(posedge clk_25m) begin
        if (dut.rx_left_valid)
            $display("[%0t] RX left  sample: 0x%06X", $time, dut.rx_left_data);
        if (dut.rx_right_valid)
            $display("[%0t] RX right sample: 0x%06X", $time, dut.rx_right_data);
    end

    // -------------------------------------------------------------------------
    // Main simulation
    // -------------------------------------------------------------------------
    integer errors;

    initial begin
        $display("Starting I2S loopback simulation...");
        errors = 0;
        mic_data = 0;

        // Apply reset
        rst_n = 0;
        #200;
        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // Wait for first LRCLK falling edge (start of left channel)
        @(negedge mic_lrclk);

        // Frame 1: send test data to mic input
        $display("[%0t] Sending frame 1: L=0xABCDEF, R=0x000000", $time);
        send_word(24'hABCDEF);  // Left channel
        send_word(24'h000000);  // Right channel

        // Frame 2: send more test data; simultaneously the TX should be
        // outputting frame 1's data (one frame latency through RX→TX path)
        $display("[%0t] Sending frame 2: L=0x123456, R=0x654321", $time);
        send_word(24'h123456);  // Left channel
        send_word(24'h654321);  // Right channel

        // Frame 3: capture TX output — should contain frame 2's data
        // (frame 1 was loaded during frame 2, frame 2 loaded at start of frame 3)
        $display("[%0t] Capturing TX output for frame 3...", $time);
        capture_word();  // Left channel from TX
        $display("[%0t] TX left  output: 0x%06X", $time, captured_word);
        if (captured_word !== 24'h123456) begin
            $display("ERROR: Expected TX left = 0x123456, got 0x%06X", captured_word);
            errors = errors + 1;
        end
        capture_word();  // Right channel from TX
        $display("[%0t] TX right output: 0x%06X", $time, captured_word);
        if (captured_word !== 24'h654321) begin
            $display("ERROR: Expected TX right = 0x654321, got 0x%06X", captured_word);
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
