// i2s_record_to_uart_tb.v
// Testbench for the I2S record-to-UART project.
//
// Uses scaled-down CLK_FREQ/BAUD_RATE (CLK_FREQ=100, BAUD_RATE=10,
// CLKS_PER_BIT=10) and NUM_SAMPLES=4 for fast simulation.
//
// Test sequence:
//   1. Reset
//   2. Wait for first LRCLK falling edge
//   3. Send 'R' command via UART; simultaneously drive 4 known I2S frames
//   4. Wait for recording to complete (state returns to IDLE, blue LED on)
//   5. Send 'D' command via UART
//   6. Receive 12 bytes (4 samples × 3 bytes) and verify each triplet

`timescale 1ns/1ps

module i2s_record_to_uart_tb;

    // =========================================================================
    // Simulation parameters — CLKS_PER_BIT=10, NUM_SAMPLES=4, CLK_DIV=2
    // =========================================================================
    localparam CLK_FREQ   = 100;
    localparam BAUD_RATE  = 10;
    localparam CLK_DIV    = 2;   // Fast I2S for simulation
    localparam NUM_SAMPLES = 4;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 10

    localparam CLK_PERIOD = 10;  // ns (100 MHz sim clock, arbitrary)

    // Clock
    reg clk;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT signals
    reg  rst_n;
    wire led_r, led_g, led_b;
    wire mic_bclk, mic_lrclk, mic_sel;
    reg  mic_data;
    wire uart_tx_line;
    reg  uart_rx_line;

    // Instantiate DUT
    i2s_record_to_uart #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .CLK_DIV     (CLK_DIV),
        .NUM_SAMPLES (NUM_SAMPLES)
    ) dut (
        .clk_25m   (clk),
        .rst_n     (rst_n),
        .led_r     (led_r),
        .led_g     (led_g),
        .led_b     (led_b),
        .mic_bclk  (mic_bclk),
        .mic_lrclk (mic_lrclk),
        .mic_data  (mic_data),
        .mic_sel   (mic_sel),
        .uart_tx   (uart_tx_line),
        .uart_rx   (uart_rx_line)
    );

    // =========================================================================
    // Task: send one UART byte on uart_rx (8N1, LSB first)
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
    // Task: receive one UART byte from uart_tx (8N1, LSB first)
    // =========================================================================
    task recv_byte;
        output [7:0] b;
        integer i;
        reg [7:0] tmp;
        begin
            tmp = 8'h00;
            // Wait for start bit (falling edge)
            @(negedge uart_tx_line);
            // Wait to mid-point of start bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx_line !== 1'b0) begin
                $display("ERROR: expected start bit low, got %b", uart_tx_line);
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
                $display("ERROR: expected stop bit high, got %b", uart_tx_line);
                $finish;
            end
            b = tmp;
        end
    endtask

    // =========================================================================
    // Task: send one 24-bit I2S left-channel word (right channel = zero)
    // Matches i2s_rx DATA_BITS=24, 32-bit slot: 1 delay + 24 data + 7 pad.
    // Must be called after a LRCLK falling edge (start of left slot).
    // =========================================================================
    task send_i2s_left_word;
        input [23:0] word;
        integer i;
        begin
            // Bit 0 of slot: 1-BCLK I2S delay
            @(negedge mic_bclk);
            mic_data = 1'b0;
            // Bits 1..24: data MSB first
            for (i = 23; i >= 0; i = i - 1) begin
                @(negedge mic_bclk);
                mic_data = word[i];
            end
            // Bits 25..31: padding zeros (7 bits)
            for (i = 0; i < 7; i = i + 1) begin
                @(negedge mic_bclk);
                mic_data = 1'b0;
            end
        end
    endtask

    // =========================================================================
    // Task: send right-channel slot (all zeros, just consume the 32 BCLKs)
    // =========================================================================
    task send_i2s_right_dummy;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) begin
                @(negedge mic_bclk);
                mic_data = 1'b0;
            end
        end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    // Known test words (full 24-bit I2S)
    localparam [23:0] WORD0 = 24'hABCDEF;
    localparam [23:0] WORD1 = 24'h123456;
    localparam [23:0] WORD2 = 24'hDEAD00;
    localparam [23:0] WORD3 = 24'hBEEF42;

    reg [7:0]  rx_byte;
    reg [23:0] rx_word;
    integer    errors;
    integer    k;

    initial begin
        $dumpfile("build/i2s_record_to_uart_tb.vcd");
        $dumpvars(0, i2s_record_to_uart_tb);

        mic_data     = 1'b0;
        uart_rx_line = 1'b1;  // UART idle high
        rst_n        = 1'b0;
        errors       = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ------------------------------------------------------------------
        // Step 1: Wait for first LRCLK falling edge (start of left channel)
        // ------------------------------------------------------------------
        @(negedge mic_lrclk);
        $display("[%0t] First LRCLK falling edge — sending 'R' and 4 I2S frames", $time);

        // ------------------------------------------------------------------
        // Step 2: Send 'R' command and simultaneously drive 4 I2S frames.
        // The UART byte arrives before the first rx_left_valid pulse, so the
        // state machine is already in RECORD when samples start flowing.
        // ------------------------------------------------------------------
        fork
            // UART side: send 'R'
            send_byte(8'h52);

            // I2S side: drive 4 left-channel frames (each frame = left + right slot)
            begin
                // Frame 1
                send_i2s_left_word(WORD0);
                send_i2s_right_dummy;
                // Frame 2
                send_i2s_left_word(WORD1);
                send_i2s_right_dummy;
                // Frame 3
                send_i2s_left_word(WORD2);
                send_i2s_right_dummy;
                // Frame 4
                send_i2s_left_word(WORD3);
                send_i2s_right_dummy;
            end
        join

        $display("[%0t] 4 I2S frames sent; waiting for IDLE (blue LED)", $time);

        // ------------------------------------------------------------------
        // Step 3: Wait until recording is complete (state returns to IDLE,
        // led_b goes low = lit = active-low).
        // ------------------------------------------------------------------
        @(negedge led_b);
        $display("[%0t] Back in IDLE — sending 'D'", $time);

        // ------------------------------------------------------------------
        // Step 4: Send 'D' and receive 12 bytes (4 × 24-bit big-endian)
        // ------------------------------------------------------------------
        fork
            send_byte(8'h44);  // 'D'

            begin
                for (k = 0; k < NUM_SAMPLES; k = k + 1) begin
                    recv_byte(rx_byte);
                    rx_word[23:16] = rx_byte;
                    recv_byte(rx_byte);
                    rx_word[15:8] = rx_byte;
                    recv_byte(rx_byte);
                    rx_word[7:0] = rx_byte;

                    case (k)
                        0: begin
                            if (rx_word !== WORD0) begin
                                $display("FAIL sample %0d: expected 0x%06X, got 0x%06X", k, WORD0, rx_word);
                                errors = errors + 1;
                            end else
                                $display("OK   sample %0d: 0x%06X", k, rx_word);
                        end
                        1: begin
                            if (rx_word !== WORD1) begin
                                $display("FAIL sample %0d: expected 0x%06X, got 0x%06X", k, WORD1, rx_word);
                                errors = errors + 1;
                            end else
                                $display("OK   sample %0d: 0x%06X", k, rx_word);
                        end
                        2: begin
                            if (rx_word !== WORD2) begin
                                $display("FAIL sample %0d: expected 0x%06X, got 0x%06X", k, WORD2, rx_word);
                                errors = errors + 1;
                            end else
                                $display("OK   sample %0d: 0x%06X", k, rx_word);
                        end
                        3: begin
                            if (rx_word !== WORD3) begin
                                $display("FAIL sample %0d: expected 0x%06X, got 0x%06X", k, WORD3, rx_word);
                                errors = errors + 1;
                            end else
                                $display("OK   sample %0d: 0x%06X", k, rx_word);
                        end
                    endcase
                end
            end
        join

        if (errors == 0)
            $display("PASS: all %0d samples correct", NUM_SAMPLES);
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 200000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
