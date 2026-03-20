// i2s_record_to_uart.v
// Records a block of I2S microphone samples to BRAM on command, then streams
// them back over UART on a second command.
//
// UART protocol (115200 8N1):
//   'R' (0x52) — CMD_RECORD: reset address counter and start capturing;
//                auto-stops when NUM_SAMPLES frames have been received.
//   'D' (0x44) — CMD_DUMP:   stream NUM_SAMPLES×3 bytes (big-endian 24-bit)
//                over UART.
// Commands received while not in IDLE are ignored.
//
// LED feedback (active-low):
//   led_b — IDLE (ready, waiting for command)
//   led_r — RECORD in progress
//   led_g — DUMP in progress

module i2s_record_to_uart #(
    parameter CLK_FREQ   = 25_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE  = 115_200,     // UART baud rate
    parameter CLK_DIV    = 4,           // I2S BCLK half-period (BCLK = clk / (2*CLK_DIV))
    parameter NUM_SAMPLES = 4096        // Number of 24-bit samples to record
) (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active-low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // I2S microphone interface
    output wire mic_bclk,
    output wire mic_lrclk,
    input  wire mic_data,
    output wire mic_sel,   // Low = left channel select

    // UART interface (to/from iCELink USB-CDC)
    output wire uart_tx,
    input  wire uart_rx
);

    // =========================================================================
    // I2S clock generator
    // =========================================================================
    wire bclk_falling;

    i2s_clkgen #(
        .CLK_DIV (CLK_DIV)
    ) clkgen_inst (
        .clk         (clk_25m),
        .rst_n       (rst_n),
        .bclk        (mic_bclk),
        .lrclk       (mic_lrclk),
        .bclk_falling(bclk_falling)
    );

    // mic_sel low = left channel (SPH0645 word-select pin)
    assign mic_sel = 1'b0;

    // =========================================================================
    // I2S receiver
    // =========================================================================
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] rx_left_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire        rx_left_valid;

    /* verilator lint_off PINCONNECTEMPTY */
    i2s_rx #(
        .DATA_BITS (24)
    ) rx_inst (
        .clk         (clk_25m),
        .rst_n       (rst_n),
        .bclk_falling(bclk_falling),
        .lrclk       (mic_lrclk),
        .sdata       (mic_data),
        .left_data   (rx_left_data),
        .left_valid  (rx_left_valid),
        .right_data  (),
        .right_valid ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // UART receiver (commands)
    // =========================================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) urx_inst (
        .clk   (clk_25m),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (rx_data),
        .valid (rx_valid)
    );

    // =========================================================================
    // UART transmitter (sample data)
    // =========================================================================
    reg  [7:0] tx_data_r;
    reg        tx_valid_r;
    wire       tx_ready;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) utx_inst (
        .clk   (clk_25m),
        .rst_n (rst_n),
        .data  (tx_data_r),
        .valid (tx_valid_r),
        .ready (tx_ready),
        .tx    (uart_tx)
    );

    // =========================================================================
    // Sample RAM (inferred ECP5 EBR — synchronous registered read output)
    // =========================================================================
    localparam ADDR_BITS = $clog2(NUM_SAMPLES);

    // =========================================================================
    // Control state machine — declarations
    // (must precede the BRAM always block so addr_cnt is visible)
    // =========================================================================
    localparam S_IDLE   = 2'd0;
    localparam S_RECORD = 2'd1;
    localparam S_DUMP   = 2'd2;

    localparam CMD_RECORD = 8'h52;  // 'R'
    localparam CMD_DUMP   = 8'h44;  // 'D'

    reg [1:0]          state;
    reg [ADDR_BITS:0]  addr_cnt;   // One extra bit to detect NUM_SAMPLES exactly
    reg [1:0]          dump_byte;  // 2 = high, 1 = mid, 0 = low byte pending
    reg                dump_init;  // 1 = waiting 1 cycle for BRAM registered output

    reg [23:0] sample_ram [0:NUM_SAMPLES-1];
    reg [23:0] dump_word;   // Registered output of sample_ram

    // Synchronous write: separate always block (no async reset) so Yosys infers EBR
    always @(posedge clk_25m)
        if (state == S_RECORD && rx_left_valid)
            sample_ram[addr_cnt[ADDR_BITS-1:0]] <= rx_left_data;

    // Synchronous read: 1-cycle latency
    always @(posedge clk_25m)
        dump_word <= sample_ram[addr_cnt[ADDR_BITS-1:0]];

    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            addr_cnt   <= 0;
            dump_byte  <= 2'd0;
            dump_init  <= 1'b0;
            tx_data_r  <= 8'h00;
            tx_valid_r <= 1'b0;
        end else begin
            // Default: de-assert tx_valid after it has been accepted
            if (tx_valid_r && tx_ready)
                tx_valid_r <= 1'b0;

            case (state)
                // -----------------------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        if (rx_data == CMD_RECORD) begin
                            addr_cnt <= 0;
                            state    <= S_RECORD;
                        end else if (rx_data == CMD_DUMP) begin
                            addr_cnt  <= 0;
                            dump_byte <= 2'd2;
                            dump_init <= 1'b1;  // Prefetch first word
                            state     <= S_DUMP;
                        end
                    end
                end

                // -----------------------------------------------------------------
                S_RECORD: begin
                    if (rx_left_valid) begin
                        if (addr_cnt == NUM_SAMPLES - 1) begin
                            addr_cnt <= 0;
                            state    <= S_IDLE;
                        end else begin
                            addr_cnt <= addr_cnt + 1;
                        end
                    end
                end

                // -----------------------------------------------------------------
                S_DUMP: begin
                    if (dump_init) begin
                        // Waiting 1 cycle for BRAM registered output to be valid
                        dump_init <= 1'b0;
                    end else if (!tx_valid_r) begin
                        // UART TX is free — send next byte (big-endian)
                        tx_valid_r <= 1'b1;
                        case (dump_byte)
                            2'd2: begin
                                tx_data_r <= dump_word[23:16];
                                dump_byte <= 2'd1;
                            end
                            2'd1: begin
                                tx_data_r <= dump_word[15:8];
                                dump_byte <= 2'd0;
                            end
                            default: begin
                                tx_data_r <= dump_word[7:0];
                                if (addr_cnt == NUM_SAMPLES - 1) begin
                                    addr_cnt <= 0;
                                    state    <= S_IDLE;
                                end else begin
                                    addr_cnt  <= addr_cnt + 1;
                                    dump_byte <= 2'd2;
                                    dump_init <= 1'b1;
                                end
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // LED indicators (active-low)
    // =========================================================================
    assign led_b = ~(state == S_IDLE);    // Blue  on in IDLE
    assign led_r = ~(state == S_RECORD);  // Red   on while recording
    assign led_g = ~(state == S_DUMP);    // Green on while dumping

endmodule
