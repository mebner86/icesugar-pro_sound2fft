// pdm_hil_tb.v — Testbench for the PDM HIL project
//
// Uses scaled parameters for fast simulation:
//   CLK_FREQ=100, BAUD_RATE=10 → CLKS_PER_BIT=10
//   NUM_SAMPLES=4
//
// PDM clock and CIC run at real ratios (DEC_RATIO=64); pcm_valid fires every
// 512 system clocks.  UART transactions are fast (10 clocks/bit).
//
// Test sequence:
//   1. Reset
//   2. Send 'U' + 2-byte count + 4 known samples into the replay buffer
//   3. Receive and verify the 'K' ACK
//   4. Drive mic_dat = 1 (all-ones PDM → maximum positive PCM) and send 'P' + count
//   5. Wait for and verify the 'K' ACK (PLAY_RECORD runs 4 pcm_valid pulses)
//   6. Send 'D' + count, receive 8 bytes, verify all samples are non-zero
//      (CIC output from all-ones PDM is positive after settling)
//   7. Report PASS / FAIL

`timescale 1ns/1ps

module pdm_hil_tb;

    // =========================================================================
    // Simulation parameters
    // =========================================================================
    localparam CLK_FREQ    = 100;
    localparam BAUD_RATE   = 10;
    localparam NUM_SAMPLES = 4;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 10

    localparam CLK_PERIOD = 10;  // ns (arbitrary, sets simulation time units)

    // =========================================================================
    // Clock
    // =========================================================================
    reg clk;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg  rst_n;
    wire led_r, led_g, led_b;

    wire mic_clk_w;
    reg  mic_dat_r;
    wire mic_sel_w;

    wire amp_clk_w;
    wire amp_dat_w;

    wire uart_tx_line;
    reg  uart_rx_line;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    pdm_hil #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .NUM_SAMPLES (NUM_SAMPLES)
    ) dut (
        .clk_25m  (clk),
        .rst_n    (rst_n),
        .led_r    (led_r),
        .led_g    (led_g),
        .led_b    (led_b),
        .mic_clk  (mic_clk_w),
        .mic_dat  (mic_dat_r),
        .mic_sel  (mic_sel_w),
        .amp_clk  (amp_clk_w),
        .amp_dat  (amp_dat_w),
        .uart_tx  (uart_tx_line),
        .uart_rx  (uart_rx_line)
    );

    // =========================================================================
    // Task: send one byte over uart_rx (8N1, LSB first)
    // =========================================================================
    task send_byte;
        input [7:0] b;
        integer i;
        begin
            // Start bit
            uart_rx_line = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            // 8 data bits, LSB first
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_line = b[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            // Stop bit
            uart_rx_line = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Task: receive one byte from uart_tx (8N1, LSB first)
    // =========================================================================
    task recv_byte;
        output [7:0] b;
        integer i;
        reg [7:0] tmp;
        begin
            tmp = 8'h00;
            // Wait for start bit (falling edge)
            @(negedge uart_tx_line);
            // Sample at mid-point of start bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx_line !== 1'b0) begin
                $display("ERROR: expected start bit low");
                $finish;
            end
            // Sample 8 data bits at mid-point of each baud period
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                tmp[i] = uart_tx_line;
            end
            // Verify stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (uart_tx_line !== 1'b1) begin
                $display("ERROR: expected stop bit high");
                $finish;
            end
            b = tmp;
        end
    endtask

    // =========================================================================
    // Known test samples to upload (16-bit, big-endian)
    // =========================================================================
    localparam [15:0] SAMPLE0 = 16'h1000;
    localparam [15:0] SAMPLE1 = 16'h2000;
    localparam [15:0] SAMPLE2 = 16'h7FFF;
    localparam [15:0] SAMPLE3 = 16'h8000;

    // =========================================================================
    // Stimulus
    // =========================================================================
    reg [7:0]  rx_byte;
    reg [15:0] rx_word;
    integer    errors;
    integer    k;

    initial begin
        $dumpfile("build/pdm_hil_tb.vcd");
        $dumpvars(0, pdm_hil_tb);

        mic_dat_r    = 1'b0;
        uart_rx_line = 1'b1;  // UART idles high
        rst_n        = 1'b0;
        errors       = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ------------------------------------------------------------------
        // Check IDLE LED (blue on, others off)
        // ------------------------------------------------------------------
        if (led_b !== 1'b0 || led_r !== 1'b1 || led_g !== 1'b1) begin
            $display("FAIL [idle leds]: led_b=%b led_r=%b led_g=%b, expected 0 1 1",
                     led_b, led_r, led_g);
            errors = errors + 1;
        end else begin
            $display("OK   [idle leds]: blue on, red/green off");
        end

        // ==================================================================
        // Step 1: Upload 4 samples via 'U' + 2-byte count command
        // ==================================================================
        $display("[%0t] Sending CMD_UPLOAD ('U') + %0d samples", $time, NUM_SAMPLES);
        send_byte(8'h55);              // 'U'
        send_byte(NUM_SAMPLES[15:8]);  // count HI
        send_byte(NUM_SAMPLES[7:0]);   // count LO

        // Sample 0: 0x1000
        send_byte(SAMPLE0[15:8]);
        send_byte(SAMPLE0[7:0]);
        // Sample 1: 0x2000
        send_byte(SAMPLE1[15:8]);
        send_byte(SAMPLE1[7:0]);
        // Sample 2: 0x7FFF
        send_byte(SAMPLE2[15:8]);
        send_byte(SAMPLE2[7:0]);
        // Sample 3: 0x8000
        send_byte(SAMPLE3[15:8]);
        send_byte(SAMPLE3[7:0]);

        // ------------------------------------------------------------------
        // Expect 'K' ACK after upload
        // ------------------------------------------------------------------
        recv_byte(rx_byte);
        if (rx_byte !== 8'h4B) begin
            $display("FAIL [upload ack]: expected 'K' (0x4B), got 0x%02X", rx_byte);
            errors = errors + 1;
        end else begin
            $display("OK   [upload ack]: received 'K'");
        end

        // Check back in IDLE
        @(posedge clk);
        if (led_b !== 1'b0) begin
            $display("FAIL [post-upload idle]: led_b not lit");
            errors = errors + 1;
        end else begin
            $display("OK   [post-upload idle]: blue LED on");
        end

        // ==================================================================
        // Step 2: CMD_PLAY — replay while recording all-ones PDM input
        // Drive mic_dat=1 for maximum positive CIC output.
        // ==================================================================
        $display("[%0t] Sending CMD_PLAY ('P'), driving mic_dat=1", $time);
        mic_dat_r = 1'b1;  // All-ones PDM: will produce maximum positive PCM

        send_byte(8'h50);              // 'P'
        send_byte(NUM_SAMPLES[15:8]);  // count HI
        send_byte(NUM_SAMPLES[7:0]);   // count LO

        // Expect 'K' ACK after PLAY_RECORD finishes
        // (4 pcm_valid pulses @ 512 clocks each = 2048 clocks minimum;
        //  plus UART overhead of recv_byte which waits for the falling edge)
        recv_byte(rx_byte);
        if (rx_byte !== 8'h4B) begin
            $display("FAIL [play ack]: expected 'K' (0x4B), got 0x%02X", rx_byte);
            errors = errors + 1;
        end else begin
            $display("OK   [play ack]: received 'K'");
        end

        mic_dat_r = 1'b0;  // Restore mic to idle

        // ==================================================================
        // Step 3: CMD_DUMP — stream back 4 recorded samples
        // Verify that all samples are non-zero (CIC response to all-ones PDM)
        // ==================================================================
        $display("[%0t] Sending CMD_DUMP ('D')", $time);
        fork
            begin
                send_byte(8'h44);              // 'D'
                send_byte(NUM_SAMPLES[15:8]);  // count HI
                send_byte(NUM_SAMPLES[7:0]);   // count LO
            end

            begin : dump_recv
                for (k = 0; k < NUM_SAMPLES; k = k + 1) begin
                    recv_byte(rx_byte);
                    rx_word[15:8] = rx_byte;
                    recv_byte(rx_byte);
                    rx_word[7:0] = rx_byte;

                    if (rx_word === 16'h0000) begin
                        $display("FAIL sample %0d: got zero (expected non-zero for all-ones PDM)",
                                 k);
                        errors = errors + 1;
                    end else begin
                        $display("OK   sample %0d: 0x%04X (non-zero CIC output)", k, rx_word);
                    end
                end
            end
        join

        // ==================================================================
        // Step 4: CMD_RECORD — verify mic-only recording gives 'K' ACK
        // ==================================================================
        $display("[%0t] Sending CMD_RECORD ('R') with mic_dat=1", $time);
        mic_dat_r = 1'b1;
        send_byte(8'h52);              // 'R'
        send_byte(NUM_SAMPLES[15:8]);  // count HI
        send_byte(NUM_SAMPLES[7:0]);   // count LO

        recv_byte(rx_byte);
        if (rx_byte !== 8'h4B) begin
            $display("FAIL [record ack]: expected 'K' (0x4B), got 0x%02X", rx_byte);
            errors = errors + 1;
        end else begin
            $display("OK   [record ack]: received 'K'");
        end
        mic_dat_r = 1'b0;

        // Check final IDLE state
        @(posedge clk);
        if (led_b !== 1'b0) begin
            $display("FAIL [final idle]: led_b not lit");
            errors = errors + 1;
        end else begin
            $display("OK   [final idle]: blue LED on");
        end

        // ==================================================================
        // Summary
        // ==================================================================
        $display("");
        if (errors == 0)
            $display("PASS: all checks passed.");
        else
            $display("FAIL: %0d error(s).", errors);

        $finish;
    end

    // Timeout watchdog: generous limit for 4 pcm_valid pulses + UART traffic
    initial begin
        #(CLK_PERIOD * 50000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
