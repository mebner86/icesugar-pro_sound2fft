// uart_serializer.v
// Captures one complete FFT frame (256 bins × 9-bit magnitude) into a buffer
// and streams it over UART using the COBS convention:
//
//   [bin_0] [bin_1] ... [bin_255] [0x00]   — 257 bytes per frame
//
// 0x00 is the exclusive frame delimiter.  Bin values are clamped to 0x01–0xFF
// so 0x00 never appears in the payload.  Clamping 0x00 → 0x01 loses one
// log₂ step (~0.03 dB) which is imperceptible on a spectrum display.
//
// Frame coherence: the capture buffer is written ONLY during every FRAME_DIV-th
// FFT frame.  UART transmission starts only after that frame's last bin has been
// written, so every transmitted frame contains 256 bins from one FFT snapshot.
//
// Timing at 115200 baud and FRAME_DIV=9:
//   UART frame:    257 bytes × 10 bits / 115200 ≈ 22.3 ms
//   FFT frame:     512 samples / 48828 Hz       ≈ 10.5 ms
//   Display rate:  1 / (9 × 10.5 ms)            ≈ 10.6 Hz
//   Idle gap:      9 × 10.5 ms − 22.3 ms        ≈ 72 ms
//
// The idle gap guarantees the buffer is never read and written at the same time.

module uart_serializer #(
    parameter CLK_FREQ  = 25_000_000,
    parameter BAUD_RATE = 115_200,
    parameter FRAME_DIV = 9   // Transmit one in every FRAME_DIV FFT frames
) (
    input  wire       clk,
    input  wire       rst_n,

    // FFT magnitude input (from fft_real512)
    input  wire [7:0] mag_addr,   // Bin index 0–255
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [8:0] mag_data,   // 9-bit log2 magnitude (4.4 fixed-point)
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire       mag_valid,  // One pulse per bin, sequential

    // UART serial output
    output wire       uart_tx,

    // High while a frame is being transmitted
    output wire       tx_active
);

    // =========================================================================
    // Frame divider
    // frame_cnt counts down from FRAME_MAX to 0.  When it hits 0 the current
    // FFT frame is the designated capture frame; the counter then reloads.
    // Reset to 0 so the very first FFT frame is captured immediately.
    // =========================================================================
    localparam SKIP_BITS = $clog2(FRAME_DIV);
    /* verilator lint_off WIDTHTRUNC */
    localparam [SKIP_BITS-1:0] FRAME_MAX  = FRAME_DIV - 1;
    localparam [SKIP_BITS-1:0] FRAME_ZERO = 0;
    /* verilator lint_on WIDTHTRUNC */

    reg [SKIP_BITS-1:0] frame_cnt;   // counts down FRAME_MAX → 0

    // =========================================================================
    // Capture buffer: 256 × 8 bits.
    // Written ONLY during the capture frame (frame_cnt == 0).
    // Read by the TX FSM using combinatorial (distributed RAM) reads.
    // =========================================================================
    (* ram_style = "distributed" *) reg [7:0] cap_buf [0:255];

    // Clamp: take the top 8 bits of 9-bit mag_data; replace 0x00 with 0x01
    wire [7:0] clamped = (mag_data[8:1] == 8'h00) ? 8'h01 : mag_data[8:1];

    always @(posedge clk) begin
        if (mag_valid && (frame_cnt == FRAME_ZERO))
            cap_buf[mag_addr] <= clamped;
    end

    // =========================================================================
    // Frame counter and capture-done flag
    // =========================================================================
    reg  frame_ready;
    wire tx_start;  // combinatorial: IDLE && frame_ready

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt   <= FRAME_ZERO;  // capture first FFT frame immediately
            frame_ready <= 1'b0;
        end else begin
            if (tx_start)
                frame_ready <= 1'b0;

            if (mag_valid && mag_addr == 8'hFF) begin
                if (frame_cnt == FRAME_ZERO) begin
                    frame_ready <= 1'b1;    // capture frame fully written
                    frame_cnt   <= FRAME_MAX;
                end else begin
                    frame_cnt <= frame_cnt - 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // TX FSM
    // =========================================================================
    localparam [1:0] S_IDLE = 2'd0,
                     S_SEND = 2'd1,   // Streaming 256 bin bytes
                     S_TERM = 2'd2;   // Sending 0x00 terminator

    reg [1:0] state;
    reg [7:0] tx_idx;      // Current bin index being transmitted (0–255)
    reg [7:0] tx_data_r;
    reg       tx_valid_r;
    wire      tx_ready;

    assign tx_start  = (state == S_IDLE) && frame_ready;
    assign tx_active = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            tx_idx     <= 8'h00;
            tx_data_r  <= 8'h00;
            tx_valid_r <= 1'b0;
        end else begin
            // De-assert valid once the UART has accepted the byte.
            // The case branches below may override this back to 1 in the same
            // clock cycle (last NBA wins), keeping the pipeline full.
            if (tx_valid_r && tx_ready)
                tx_valid_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (frame_ready) begin
                        tx_idx     <= 8'h00;
                        tx_data_r  <= cap_buf[8'h00]; // combinatorial read
                        tx_valid_r <= 1'b1;
                        state      <= S_SEND;
                    end
                end

                S_SEND: begin
                    if (tx_valid_r && tx_ready) begin
                        if (tx_idx == 8'hFF) begin
                            // All 256 bins sent — queue COBS terminator
                            tx_data_r  <= 8'h00;
                            tx_valid_r <= 1'b1;
                            state      <= S_TERM;
                        end else begin
                            // Pre-fetch next bin (combinatorial read — 0 latency)
                            tx_idx     <= tx_idx + 8'h01;
                            tx_data_r  <= cap_buf[tx_idx + 8'h01];
                            tx_valid_r <= 1'b1;
                        end
                    end
                end

                S_TERM: begin
                    // 0x00 accepted → frame complete
                    if (tx_valid_r && tx_ready)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // UART TX
    // =========================================================================
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) tx_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (tx_data_r),
        .valid (tx_valid_r),
        .ready (tx_ready),
        .tx    (uart_tx)
    );

endmodule
