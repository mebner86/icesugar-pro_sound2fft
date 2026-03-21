// uart_loopback.v
// UART loopback demo for iCESugar-Pro (ECP5-25F).
//
// Bytes received on uart_rx are echoed back on uart_tx using the iCELink
// USB-CDC virtual COM port (one USB-C cable, no extra hardware needed).
// Open a terminal at 115200 8N1, type characters, and watch them echo back.
//
// LED feedback (active-low):
//   led_g — lit while transmitting (uart_tx not idle)
//   led_b — pulses briefly each time a byte is received
//   led_r — always off

module uart_loopback #(
    parameter CLK_FREQ  = 25_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE = 115_200      // UART baud rate
) (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active-low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // UART interface (to/from iCELink USB-CDC)
    output wire uart_tx,
    input  wire uart_rx
);

    // =========================================================================
    // UART RX
    // =========================================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) rx_inst (
        .clk   (clk_25m),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (rx_data),
        .valid (rx_valid)
    );

    // =========================================================================
    // 1-byte FIFO between RX and TX
    // Needed because uart_tx takes ~10 baud periods to transmit; a second
    // incoming byte could arrive before the first is done.  One slot is
    // sufficient at 115200 baud (a full frame is ~87 µs; the inter-character
    // gap from a human or typical host is much longer).
    // =========================================================================
    reg [7:0] buf_data;
    reg       buf_full;

    wire tx_ready;
    reg  [7:0] tx_data_r;
    reg        tx_valid_r;

    // When RX fires: if TX is idle and buffer empty, feed directly; otherwise
    // store in the 1-byte buffer (overrun is silently ignored — acceptable for
    // a loopback demo at human typing speeds).
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            buf_data   <= 8'h00;
            buf_full   <= 1'b0;
            tx_data_r  <= 8'h00;
            tx_valid_r <= 1'b0;
        end else begin
            // Default: de-assert tx_valid after it has been accepted
            if (tx_valid_r && tx_ready)
                tx_valid_r <= 1'b0;

            // Drain buffer into TX when TX is ready
            if (buf_full && tx_ready && !tx_valid_r) begin
                tx_data_r  <= buf_data;
                tx_valid_r <= 1'b1;
                buf_full   <= 1'b0;
            end

            // New byte from RX
            if (rx_valid) begin
                if (tx_ready && !tx_valid_r) begin
                    // TX is idle — send immediately
                    tx_data_r  <= rx_data;
                    tx_valid_r <= 1'b1;
                end else begin
                    // TX busy — buffer (overwrites if already full)
                    buf_data <= rx_data;
                    buf_full <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // UART TX
    // =========================================================================
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) tx_inst (
        .clk   (clk_25m),
        .rst_n (rst_n),
        .data  (tx_data_r),
        .valid (tx_valid_r),
        .ready (tx_ready),
        .tx    (uart_tx)
    );

    // =========================================================================
    // LED indicators (active-low)
    // =========================================================================
    assign led_r = 1'b1;           // Always off
    assign led_g = tx_ready;       // Low (lit) while transmitting

    // led_b: pulse low for ~4 ms on each received byte
    localparam PULSE_LEN   = CLK_FREQ / 256;  // ~4 ms at 25 MHz
    localparam PULSE_WIDTH = $clog2(PULSE_LEN);
    /* verilator lint_off WIDTHTRUNC */
    localparam [PULSE_WIDTH-1:0] PULSE_MAX = PULSE_LEN - 1;
    /* verilator lint_on WIDTHTRUNC */
    reg [PULSE_WIDTH-1:0] pulse_cnt;
    reg                   pulse_active;

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt    <= 0;
            pulse_active <= 1'b0;
        end else begin
            if (rx_valid) begin
                pulse_cnt    <= 0;
                pulse_active <= 1'b1;
            end else if (pulse_active) begin
                if (pulse_cnt == PULSE_MAX) begin
                    pulse_active <= 1'b0;
                    pulse_cnt    <= 0;
                end else begin
                    pulse_cnt <= pulse_cnt + 1;
                end
            end
        end
    end

    assign led_b = ~pulse_active;  // Active-low

endmodule
