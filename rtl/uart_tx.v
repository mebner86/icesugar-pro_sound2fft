// uart_tx.v
// Parameterised UART transmitter.
// Accepts one byte at a time via an AXI-stream-style handshake (valid/ready),
// serialises it as 8N1 (8 data bits, no parity, 1 stop bit), LSB first.
//
// `ready` is asserted in IDLE.  A byte is accepted on the clock edge where
// both `valid` and `ready` are high.  The caller must hold `data` and `valid`
// stable until `ready` re-asserts (i.e. do not change `data` mid-transfer).

module uart_tx #(
    parameter CLK_FREQ  = 25_000_000,  // Input clock frequency in Hz
    parameter BAUD_RATE = 115_200      // Desired baud rate
) (
    input  wire       clk,
    input  wire       rst_n,

    // Data input (AXI-stream handshake)
    input  wire [7:0] data,   // Byte to transmit
    input  wire       valid,  // Caller asserts when data is ready
    output wire       ready,  // Module asserts when it can accept a byte

    // UART serial output (idles high)
    output reg        tx
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // e.g. 217 at 25 MHz / 115200
    localparam CNT_WIDTH    = $clog2(CLKS_PER_BIT);
    // Sized BIT_MAX keeps comparisons width-matched (see i2s_clkgen.v for the same pattern)
    /* verilator lint_off WIDTHTRUNC */
    localparam [CNT_WIDTH-1:0] BIT_MAX = CLKS_PER_BIT - 1;
    /* verilator lint_on WIDTHTRUNC */

    // State encoding
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]            state;
    reg [CNT_WIDTH-1:0]  baud_cnt;
    reg [7:0]                     shift;    // Data shift register
    reg [2:0]                     bit_idx;  // Which data bit we're sending (0-7)

    assign ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            baud_cnt <= 0;
            shift    <= 8'h00;
            bit_idx  <= 0;
            tx       <= 1'b1;  // UART line idles high
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (valid) begin
                        shift    <= data;
                        baud_cnt <= 0;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;  // Start bit
                    if (baud_cnt == BIT_MAX) begin
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        state    <= S_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx <= shift[0];  // LSB first
                    if (baud_cnt == BIT_MAX) begin
                        baud_cnt <= 0;
                        shift    <= {1'b0, shift[7:1]};  // Shift right
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
                    tx <= 1'b1;  // Stop bit
                    if (baud_cnt == BIT_MAX) begin
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
