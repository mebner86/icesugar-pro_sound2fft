// fft_uart_tb.v
// Testbench for uart_serializer.
//
// Drives a synthetic FFT frame into the serializer and verifies that the
// UART output matches the expected COBS-framed byte sequence:
//   [bin_0] [bin_1] ... [bin_255] [0x00]
//
// Stimulus: mag_data = {i[7:0], 1'b0} for bin i, so mag_data[8:1] = i.
//   bin 0  → 0x00 → clamped to 0x01
//   bin 1  → 0x01 (no clamp)
//   bin 5  → injected as 9'h000 → clamped to 0x01  (explicit clamp test)
//   bin 255 → 0xFF (no clamp, valid data byte)
//
// Decodes every UART byte by sampling uart_tx at mid-bit, LSB-first.
// Verifies all 257 received bytes and reports PASS / FAIL.

`timescale 1ns/1ps

module fft_uart_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_FREQ       = 25_000_000;
    localparam BAUD_RATE      = 115_200;
    localparam CLK_PERIOD_NS  = 40;                       // 25 MHz
    localparam CLKS_PER_BIT   = CLK_FREQ / BAUD_RATE;    // 217

    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg clk   = 0;
    reg rst_n = 0;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        repeat(5) @(posedge clk);
        rst_n = 1;
    end

    // =========================================================================
    // DUT
    // =========================================================================
    reg  [7:0] mag_addr  = 0;
    reg  [8:0] mag_data  = 0;
    reg        mag_valid = 0;
    wire       uart_tx_out;
    wire       tx_active;

    uart_serializer #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .mag_addr  (mag_addr),
        .mag_data  (mag_data),
        .mag_valid (mag_valid),
        .uart_tx   (uart_tx_out),
        .tx_active (tx_active)
    );

    // =========================================================================
    // Stimulus: send one synthetic FFT frame
    // mag_data = {i[7:0], 1'b0}  →  mag_data[8:1] = i[7:0]
    // Bin 5 overridden to 9'h000 to explicitly test clamping.
    // =========================================================================
    task send_frame;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                @(posedge clk);
                mag_addr  <= i[7:0];
                mag_data  <= (i == 5) ? 9'h000 : {i[7:0], 1'b0};
                mag_valid <= 1'b1;
                @(posedge clk);
                mag_valid <= 1'b0;
                repeat(2) @(posedge clk);
            end
        end
    endtask

    // =========================================================================
    // UART receiver: sample uart_tx_out and decode one byte (8N1, LSB first)
    // =========================================================================
    task recv_byte;
        output [7:0] byte_out;
        integer i;
        reg [7:0] val;
        begin
            @(negedge uart_tx_out);                              // start bit begins
            #(CLK_PERIOD_NS * CLKS_PER_BIT / 2);                // centre of start bit
            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                #(CLK_PERIOD_NS * CLKS_PER_BIT);
                val[i] = uart_tx_out;                            // LSB first
            end
            #(CLK_PERIOD_NS * CLKS_PER_BIT);                    // skip stop bit
            byte_out = val;
        end
    endtask

    // =========================================================================
    // Main test
    // =========================================================================
    reg [7:0] rx_buf [0:256];   // 256 data bytes + 1 terminator
    integer   errors;
    integer   i;
    reg [7:0] expected;
    reg [7:0] byte_val;

    initial begin
        $dumpfile("build/fft_uart_tb.vcd");
        $dumpvars(0, fft_uart_tb);

        errors = 0;

        @(posedge rst_n);
        repeat(10) @(posedge clk);

        // ----------------------------------------------------------------
        // Inject one FFT frame
        // ----------------------------------------------------------------
        send_frame;

        // ----------------------------------------------------------------
        // Receive 257 bytes (256 data + 0x00 terminator)
        // ----------------------------------------------------------------
        for (i = 0; i <= 256; i = i + 1) begin
            recv_byte(byte_val);
            rx_buf[i] = byte_val;
        end

        // ----------------------------------------------------------------
        // Verify data bytes (bins 0–255)
        // ----------------------------------------------------------------
        for (i = 0; i < 256; i = i + 1) begin
            // Expected: mag_data[8:1] = i, clamped to 0x01 if zero
            // Bin 0: i=0 → 0x00 → clamped → 0x01
            // Bin 5: forced 9'h000 → clamped → 0x01
            // Others: i (non-zero, no clamp)
            if (i == 0 || i == 5)
                expected = 8'h01;
            else
                expected = i[7:0];

            if (rx_buf[i] !== expected) begin
                $display("FAIL bin %0d: expected 0x%02x, got 0x%02x",
                         i, expected, rx_buf[i]);
                errors = errors + 1;
            end
        end

        // ----------------------------------------------------------------
        // Verify COBS terminator
        // ----------------------------------------------------------------
        if (rx_buf[256] !== 8'h00) begin
            $display("FAIL: terminator expected 0x00, got 0x%02x", rx_buf[256]);
            errors = errors + 1;
        end

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        if (errors == 0)
            $display("PASS: all 257 bytes correct");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

endmodule
