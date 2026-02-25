// uart_loopback_tb.v
// Testbench for the UART loopback project.
//
// Uses scaled-down CLK_FREQ/BAUD_RATE parameters so simulation runs in
// microseconds rather than real time.  The TB sends a sequence of bytes on
// uart_rx and checks that identical bytes come back on uart_tx.

`timescale 1ns/1ps

module uart_loopback_tb;

    // Simulation parameters — chosen so CLKS_PER_BIT = 10 for easy timing.
    localparam CLK_FREQ  = 100;
    localparam BAUD_RATE = 10;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 10

    // Clock
    localparam CLK_PERIOD = 10;  // ns (100 MHz sim clock, irrelevant for logic)
    reg clk;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT signals
    reg  rst_n;
    wire led_r, led_g, led_b;
    wire uart_tx;
    reg  uart_rx;

    // Instantiate DUT with fast baud rate
    uart_loopback #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk_25m (clk),
        .rst_n   (rst_n),
        .led_r   (led_r),
        .led_g   (led_g),
        .led_b   (led_b),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx)
    );

    // =========================================================================
    // Task: send one UART byte on uart_rx (8N1, LSB first)
    // =========================================================================
    task send_byte;
        input [7:0] b;
        integer i;
        begin
            // Start bit
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);

            // 8 data bits, LSB first
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = b[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end

            // Stop bit
            uart_rx = 1'b1;
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
            @(negedge uart_tx);

            // Wait half a baud to reach mid-point of start bit, then verify
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx !== 1'b0) begin
                $display("ERROR: expected start bit low, got %b", uart_tx);
                $finish;
            end

            // Sample 8 data bits at mid-point of each baud period
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                tmp[i] = uart_tx;
            end

            // Verify stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (uart_tx !== 1'b1) begin
                $display("ERROR: expected stop bit high, got %b", uart_tx);
                $finish;
            end

            b = tmp;
        end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    // Bytes to send (spell out "Hi!\r\n" as individual values)
    localparam N_BYTES = 5;
    reg [7:0] test_bytes [0:N_BYTES-1];
    integer   k;
    reg [7:0] received;
    integer   errors;

    initial begin
        $dumpfile("build/uart_loopback_tb.vcd");
        $dumpvars(0, uart_loopback_tb);

        // Initialise
        test_bytes[0] = 8'h48;  // 'H'
        test_bytes[1] = 8'h69;  // 'i'
        test_bytes[2] = 8'h21;  // '!'
        test_bytes[3] = 8'h0D;  // '\r'
        test_bytes[4] = 8'h0A;  // '\n'

        uart_rx = 1'b1;         // Idle high
        rst_n   = 1'b0;
        errors  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // Send each byte and check it comes back
        for (k = 0; k < N_BYTES; k = k + 1) begin
            fork
                send_byte(test_bytes[k]);
                recv_byte(received);
            join

            if (received !== test_bytes[k]) begin
                $display("FAIL byte %0d: sent 0x%02X, got 0x%02X", k, test_bytes[k], received);
                errors = errors + 1;
            end else begin
                $display("OK   byte %0d: 0x%02X ('%s')", k, received,
                         (received >= 8'h20 && received < 8'h7F) ? received : 8'h2E);
            end
        end

        if (errors == 0)
            $display("PASS: all %0d bytes looped back correctly", N_BYTES);
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * CLK_FREQ * 100);
        $display("TIMEOUT");
        $finish;
    end

endmodule
