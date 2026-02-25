// uart_rx.v
// Parameterised UART receiver.
// Detects a start bit on the incoming serial line, samples each of the 8 data
// bits at the mid-point of each baud period, then asserts `valid` for exactly
// one clock cycle when a complete byte has been received.
//
// The `rx` input is synchronised through a two-flop chain to prevent
// metastability.  Framing is 8N1 (8 data bits, no parity, 1 stop bit), LSB first.

module uart_rx #(
    parameter CLK_FREQ  = 25_000_000,  // Input clock frequency in Hz
    parameter BAUD_RATE = 115_200      // Expected baud rate
) (
    input  wire       clk,
    input  wire       rst_n,

    // UART serial input
    input  wire       rx,

    // Received byte output — `valid` pulses high for one clock when a byte arrives
    output reg  [7:0] data,
    output reg        valid
);

    localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;       // e.g. 217
    localparam HALF_BIT      = CLKS_PER_BIT / 2;           // mid-point sample offset
    localparam CNT_WIDTH     = $clog2(CLKS_PER_BIT);
    // Sized localparams keep comparisons width-matched (see i2s_clkgen.v for the same pattern)
    /* verilator lint_off WIDTHTRUNC */
    localparam [CNT_WIDTH-1:0] BIT_MAX  = CLKS_PER_BIT - 1;
    localparam [CNT_WIDTH-1:0] HALF_MAX = HALF_BIT;
    /* verilator lint_on WIDTHTRUNC */

    // State encoding
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    // Two-FF synchroniser for rx input
    reg rx_s0, rx_s1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s0 <= 1'b1;
            rx_s1 <= 1'b1;
        end else begin
            rx_s0 <= rx;
            rx_s1 <= rx_s0;
        end
    end
    wire rx_sync = rx_s1;

    reg [1:0]            state;
    reg [CNT_WIDTH-1:0]  baud_cnt;
    reg [7:0]                     shift;
    reg [2:0]                     bit_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            baud_cnt <= 0;
            shift    <= 8'h00;
            bit_idx  <= 0;
            data     <= 8'h00;
            valid    <= 1'b0;
        end else begin
            valid <= 1'b0;  // Default: de-assert each cycle

            case (state)
                S_IDLE: begin
                    if (!rx_sync) begin
                        // Falling edge — potential start bit; wait half a baud to confirm
                        baud_cnt <= 1;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    if (baud_cnt == HALF_MAX) begin
                        if (!rx_sync) begin
                            // Still low at mid-point: valid start bit
                            baud_cnt <= 0;
                            bit_idx  <= 0;
                            state    <= S_DATA;
                        end else begin
                            // Glitch — abort
                            state <= S_IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                S_DATA: begin
                    if (baud_cnt == BIT_MAX) begin
                        // Sample at mid-point of next bit (we reset counter here,
                        // so the next period's mid-point is at HALF_BIT)
                        baud_cnt        <= 0;
                        shift           <= {rx_sync, shift[7:1]};  // LSB arrives first
                        if (bit_idx == 7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                S_STOP: begin
                    if (baud_cnt == BIT_MAX) begin
                        if (rx_sync) begin
                            // Valid stop bit
                            data  <= shift;
                            valid <= 1'b1;
                        end
                        // Return to idle regardless (bad framing is silently dropped)
                        baud_cnt <= 0;
                        state    <= S_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
