// pdm_hil.v — PDM Hardware-in-the-Loop Transfer Function Characterizer
// iCESugar-Pro (ECP5-25F)
//
// Builds on project 10 (PDM mic → CIC → PCM → sigma-delta → PDM amp) and
// project 14 (UART command + BRAM recording) to enable closed-loop acoustic
// transfer function measurement:
//
//   1. Upload a test signal (chirp, impulse, noise) via UART into replay_ram.
//   2. Replay the signal through the MAX98358 speaker while simultaneously
//      recording the MP34DT01-M microphone into record_ram.
//   3. Dump record_ram back to the host via UART.
//   4. Host computes H(f) = FFT(recorded) / FFT(played).
//
// UART protocol (115200 8N1):
//   Every command byte is followed by a big-endian 16-bit sample count N
//   (bytes N_HI then N_LO).  Valid range: 1..NUM_SAMPLES.  A count of 0 or
//   greater than NUM_SAMPLES is clamped to NUM_SAMPLES.
//
//   'U' (0x55) N_HI N_LO  CMD_UPLOAD  — receive N×2 bytes (big-endian 16-bit)
//                                        into replay_ram; send 'K' (0x4B) ACK.
//   'P' (0x50) N_HI N_LO  CMD_PLAY    — replay N samples from replay_ram while
//                                        recording N mic samples into record_ram;
//                                        send 'K' ACK when done.
//   'R' (0x52) N_HI N_LO  CMD_RECORD  — record N mic samples (no playback) into
//                                        record_ram; send 'K' ACK when done.
//   'D' (0x44) N_HI N_LO  CMD_DUMP    — stream N samples from record_ram as N×2
//                                        bytes (big-endian 16-bit); no trailing ACK.
//
// Commands arriving while not in IDLE are silently ignored.
//
// LED feedback (active-low):
//   led_b — on in IDLE (ready)
//   led_r — on in UPLOAD or RECORD
//   led_g — on in PLAY_RECORD or DUMP
//   (PLAY_RECORD lights both red and green)

`default_nettype none

module pdm_hil #(
    parameter integer CLK_FREQ    = 25_000_000,  // System clock frequency in Hz
    parameter integer BAUD_RATE   = 115_200,      // UART baud rate
    parameter integer NUM_SAMPLES = 4096          // Replay and record buffer depth
) (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active-low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // MP34DT01-M PDM microphone
    output wire mic_clk,
    input  wire mic_dat,
    output wire mic_sel,

    // MAX98358 PDM amplifier
    output wire amp_clk,
    output wire amp_dat,

    // UART (iCELink USB-CDC)
    output wire uart_tx,
    input  wire uart_rx
);

    // =========================================================================
    // PDM clock generation: 25 MHz / 8 = 3.125 MHz
    // =========================================================================
    wire pdm_clk_r;
    wire pdm_valid;

    pdm_clkgen pdm_clk_inst (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .pdm_clk      (pdm_clk_r),
        .pdm_clk_rise (pdm_valid)
    );

    // =========================================================================
    // 2-stage synchronizer for PDM data input
    // =========================================================================
    reg pdm_sync1, pdm_sync2;
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pdm_sync1 <= 1'b0;
            pdm_sync2 <= 1'b0;
        end else begin
            pdm_sync1 <= mic_dat;
            pdm_sync2 <= pdm_sync1;
        end
    end

    // =========================================================================
    // CIC sinc³ decimation: 3.125 MHz PDM → 16-bit PCM @ ~48.8 kHz
    // =========================================================================
    wire signed [15:0] pcm_raw;
    wire               pcm_valid;

    pdm_cic #(
        .CIC_ORDER (3),
        .DEC_RATIO (64),
        .OUT_BITS  (16)
    ) cic (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pdm_bit   (pdm_sync2),
        .pdm_valid (pdm_valid),
        .pcm_out   (pcm_raw),
        .pcm_valid (pcm_valid)
    );

    // =========================================================================
    // UART receiver (commands and upload data)
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
    // UART transmitter (dump data and ACK bytes)
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
    // BRAM buffers (inferred as ECP5 EBR via synchronous read/write)
    // =========================================================================
    localparam ADDR_BITS = $clog2(NUM_SAMPLES);
    /* verilator lint_off WIDTHTRUNC */
    localparam [ADDR_BITS:0] DEF_SAMPLE_LAST = NUM_SAMPLES - 1;
    /* verilator lint_on WIDTHTRUNC */

    // Replay buffer: written by UPLOAD, read by PLAY_RECORD
    reg [15:0] replay_ram [0:NUM_SAMPLES-1];
    reg [15:0] replay_word;  // Registered (1-cycle latency) read output

    // Record buffer: written by PLAY_RECORD or RECORD, read by DUMP
    reg [15:0] record_ram [0:NUM_SAMPLES-1];
    reg [15:0] dump_word;    // Registered (1-cycle latency) read output

    // =========================================================================
    // State machine — declarations
    // =========================================================================
    localparam S_IDLE        = 3'd0;
    localparam S_UPLOAD      = 3'd1;
    localparam S_PLAY_RECORD = 3'd2;
    localparam S_RECORD      = 3'd3;
    localparam S_DUMP        = 3'd4;
    localparam S_RECV_CNT_HI = 3'd5;  // Receiving high byte of sample count
    localparam S_RECV_CNT_LO = 3'd6;  // Receiving low byte of sample count

    localparam CMD_UPLOAD = 8'h55;  // 'U'
    localparam CMD_PLAY   = 8'h50;  // 'P'
    localparam CMD_RECORD = 8'h52;  // 'R'
    localparam CMD_DUMP   = 8'h44;  // 'D'
    localparam ACK_BYTE   = 8'h4B;  // 'K'

    reg [2:0]          state;
    reg [ADDR_BITS:0]  addr_cnt;     // Sample address counter

    // Runtime sample count: programmed via the 2-byte count prefix of each
    // command.  sample_last = effective_count - 1 (termination value for addr_cnt).
    reg [ADDR_BITS:0]  sample_last;
    reg [2:0]          next_state_r; // Target state after count bytes received
    reg [7:0]          count_hi_r;   // MSB of incoming sample count

    // Combinational assembly of the incoming 16-bit count.
    // Valid only while rx_valid is asserted in S_RECV_CNT_LO.
    wire [15:0]        rx_count_full = {count_hi_r, rx_data};
    /* verilator lint_off WIDTHTRUNC */
    wire [ADDR_BITS:0] rx_count_clamped =
        (rx_count_full == 16'h0000 || rx_count_full > NUM_SAMPLES)
        ? NUM_SAMPLES[ADDR_BITS:0]
        : rx_count_full[ADDR_BITS:0];
    /* verilator lint_on WIDTHTRUNC */

    // Upload byte assembly
    reg        upload_high;        // 1 = waiting for MSB, 0 = waiting for LSB
    reg [7:0]  upload_hi_byte;     // Latched MSB while waiting for LSB

    // Dump control
    reg        dump_high;          // 1 = MSB byte pending, 0 = LSB byte pending
    reg        dump_init;          // 1 = waiting one cycle for BRAM registered output

    // PCM hold register: drives the sigma-delta modulator
    reg signed [15:0] pcm_held;

    // =========================================================================
    // BRAM write: replay_ram (synchronous, no async reset → infers EBR)
    // =========================================================================
    always @(posedge clk_25m)
        if (state == S_UPLOAD && rx_valid && !upload_high)
            replay_ram[addr_cnt[ADDR_BITS-1:0]] <= {upload_hi_byte, rx_data};

    // BRAM read: replay_ram (1-cycle latency)
    always @(posedge clk_25m)
        replay_word <= replay_ram[addr_cnt[ADDR_BITS-1:0]];

    // =========================================================================
    // BRAM write: record_ram (synchronous, no async reset → infers EBR)
    // =========================================================================
    always @(posedge clk_25m)
        if ((state == S_PLAY_RECORD || state == S_RECORD) && pcm_valid)
            record_ram[addr_cnt[ADDR_BITS-1:0]] <= pcm_raw;

    // BRAM read: record_ram (1-cycle latency)
    always @(posedge clk_25m)
        dump_word <= record_ram[addr_cnt[ADDR_BITS-1:0]];

    // =========================================================================
    // PCM hold for playback: drives sigma-delta modulator
    // =========================================================================
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            pcm_held <= 16'sd0;
        else if (state == S_PLAY_RECORD && pcm_valid)
            pcm_held <= replay_word;   // ZOH: latch replay sample each PCM period
        else if (state != S_PLAY_RECORD)
            pcm_held <= 16'sd0;        // Silence when not playing
    end

    // =========================================================================
    // Sigma-delta modulator: PCM → PDM → MAX98358 amp
    // =========================================================================
    wire amp_dat_w;

    pdm_modulator mod (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pcm_in    (pcm_held),
        .pdm_valid (pdm_valid),
        .pdm_out   (amp_dat_w)
    );

    // =========================================================================
    // Control state machine
    // =========================================================================
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            addr_cnt       <= 0;
            sample_last    <= DEF_SAMPLE_LAST;
            next_state_r   <= S_IDLE;
            count_hi_r     <= 8'h00;
            upload_high    <= 1'b1;
            upload_hi_byte <= 8'h00;
            dump_high      <= 1'b0;
            dump_init      <= 1'b0;
            tx_data_r      <= 8'h00;
            tx_valid_r     <= 1'b0;
        end else begin
            // Default: de-assert tx_valid once the transmitter has accepted the byte
            if (tx_valid_r && tx_ready)
                tx_valid_r <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // Wait for command byte then go to S_RECV_CNT_HI to collect the
                // 2-byte sample count before dispatching to the target state.
                // -------------------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        case (rx_data)
                            CMD_UPLOAD: begin
                                next_state_r <= S_UPLOAD;
                                state        <= S_RECV_CNT_HI;
                            end
                            CMD_PLAY: begin
                                next_state_r <= S_PLAY_RECORD;
                                state        <= S_RECV_CNT_HI;
                            end
                            CMD_RECORD: begin
                                next_state_r <= S_RECORD;
                                state        <= S_RECV_CNT_HI;
                            end
                            CMD_DUMP: begin
                                next_state_r <= S_DUMP;
                                state        <= S_RECV_CNT_HI;
                            end
                            default: ;  // Ignore unknown commands
                        endcase
                    end
                end

                // -------------------------------------------------------------
                // Receive high byte of the 2-byte sample count.
                // -------------------------------------------------------------
                S_RECV_CNT_HI: begin
                    if (rx_valid) begin
                        count_hi_r <= rx_data;
                        state      <= S_RECV_CNT_LO;
                    end
                end

                // -------------------------------------------------------------
                // Receive low byte of the 2-byte sample count.  Assemble, clamp
                // to [1..NUM_SAMPLES], store sample_last, initialise per-state
                // bookkeeping, then transition to the target state.
                // -------------------------------------------------------------
                S_RECV_CNT_LO: begin
                    if (rx_valid) begin
                        sample_last <= rx_count_clamped - 1;
                        addr_cnt    <= 0;
                        case (next_state_r)
                            S_UPLOAD: upload_high <= 1'b1;
                            S_DUMP: begin
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;  // Prefetch first word
                            end
                            default: ;
                        endcase
                        state <= next_state_r;
                    end
                end

                // -------------------------------------------------------------
                // Receive N big-endian 16-bit words from UART.
                // Two bytes per sample: MSB first (upload_high=1), then LSB.
                // Write to replay_ram on LSB receipt.
                // ACK with 'K' when complete; return to IDLE.
                // -------------------------------------------------------------
                S_UPLOAD: begin
                    if (rx_valid) begin
                        if (upload_high) begin
                            // MSB received: latch and wait for LSB
                            upload_hi_byte <= rx_data;
                            upload_high    <= 1'b0;
                        end else begin
                            // LSB received: word is now {upload_hi_byte, rx_data}
                            // (BRAM write handled in separate always block above)
                            upload_high <= 1'b1;
                            if (addr_cnt == sample_last) begin
                                // Last sample written — send ACK and return to IDLE
                                tx_data_r  <= ACK_BYTE;
                                tx_valid_r <= 1'b1;
                                addr_cnt   <= 0;
                                state      <= S_IDLE;
                            end else begin
                                addr_cnt <= addr_cnt + 1;
                            end
                        end
                    end
                end

                // -------------------------------------------------------------
                // Replay replay_ram through PDM amp while recording CIC output
                // into record_ram.  Both counters advance on each pcm_valid.
                // BRAM read latency (1 cycle) is absorbed — pcm_valid fires
                // every 512 system clocks so replay_word is always settled.
                // ACK with 'K' when complete; return to IDLE.
                // -------------------------------------------------------------
                S_PLAY_RECORD: begin
                    if (pcm_valid) begin
                        // pcm_held is updated from replay_word in the separate
                        // always block; record_ram write handled above.
                        if (addr_cnt == sample_last) begin
                            tx_data_r  <= ACK_BYTE;
                            tx_valid_r <= 1'b1;
                            addr_cnt   <= 0;
                            state      <= S_IDLE;
                        end else begin
                            addr_cnt <= addr_cnt + 1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // Record mic only (no playback). pcm_held stays zero so amp
                // outputs silence.  record_ram write handled above.
                // ACK with 'K' when complete; return to IDLE.
                // -------------------------------------------------------------
                S_RECORD: begin
                    if (pcm_valid) begin
                        if (addr_cnt == sample_last) begin
                            tx_data_r  <= ACK_BYTE;
                            tx_valid_r <= 1'b1;
                            addr_cnt   <= 0;
                            state      <= S_IDLE;
                        end else begin
                            addr_cnt <= addr_cnt + 1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // Stream record_ram as big-endian 16-bit bytes over UART.
                // dump_init absorbs the 1-cycle BRAM registered-read latency.
                // No trailing ACK — host knows exactly how many bytes to expect.
                // -------------------------------------------------------------
                S_DUMP: begin
                    if (dump_init) begin
                        // Wait one cycle for BRAM registered output to settle
                        dump_init <= 1'b0;
                    end else if (!tx_valid_r) begin
                        if (dump_high) begin
                            tx_data_r  <= dump_word[15:8];  // MSB first
                            tx_valid_r <= 1'b1;
                            dump_high  <= 1'b0;
                        end else begin
                            tx_data_r  <= dump_word[7:0];   // LSB second
                            tx_valid_r <= 1'b1;
                            if (addr_cnt == sample_last) begin
                                addr_cnt <= 0;
                                state    <= S_IDLE;
                            end else begin
                                addr_cnt  <= addr_cnt + 1;
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;  // Prefetch next word
                            end
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Microphone and amplifier outputs
    // =========================================================================
    assign mic_clk = pdm_clk_r;
    assign mic_sel = 1'b0;      // Left channel

    assign amp_clk = pdm_clk_r;
    assign amp_dat = amp_dat_w;

    // =========================================================================
    // LED indicators (active-low)
    // =========================================================================
    assign led_b = ~(state == S_IDLE);
    assign led_r = ~(state == S_UPLOAD || state == S_PLAY_RECORD || state == S_RECORD);
    assign led_g = ~(state == S_PLAY_RECORD || state == S_DUMP);

endmodule

`default_nettype wire
