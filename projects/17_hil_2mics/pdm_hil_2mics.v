// pdm_hil_2mics.v — Dual-Microphone PDM HIL Transfer Function Characterizer
// iCESugar-Pro (ECP5-25F)
//
// Extends project 15 (pdm_hil) with a second PDM microphone.  Both mics
// record simultaneously during PLAY_RECORD and RECORD states, enabling
// comparison of the two channels (e.g. for beamforming, noise cancellation,
// or differential transfer-function measurement).
//
// Mic 1: on-board MP34DT01-M (mic_sel=0, left channel)
// Mic 2: external MP34DT01-M on Port3 (mic2_sel=1, right channel)
//
// Both microphones share the same PDM clock (3.125 MHz).
//
// UART protocol (115200 8N1):
//   'U' (0x55) CMD_UPLOAD  — receive NUM_SAMPLES×2 bytes (big-endian 16-bit)
//                            into replay_ram; send 'K' (0x4B) ACK when done.
//   'P' (0x50) CMD_PLAY    — replay replay_ram through speaker while recording
//                            both mics into record_ram / record2_ram;
//                            send 'K' ACK when done.
//   'R' (0x52) CMD_RECORD  — record both mics (no playback) into
//                            record_ram / record2_ram; send 'K' ACK when done.
//   'D' (0x44) CMD_DUMP    — stream record_ram  (mic 1) as NUM_SAMPLES×2 bytes;
//                            no trailing ACK.
//   'E' (0x45) CMD_DUMP2   — stream record2_ram (mic 2) as NUM_SAMPLES×2 bytes;
//                            no trailing ACK.
//
// Commands arriving while not in IDLE are silently ignored.
//
// LED feedback (active-low):
//   led_b — on in IDLE (ready)
//   led_r — on in UPLOAD or RECORD
//   led_g — on in PLAY_RECORD or DUMP/DUMP2
//   (PLAY_RECORD lights both red and green)

`default_nettype none

module pdm_hil_2mics #(
    parameter integer CLK_FREQ   = 25_000_000,  // System clock frequency in Hz
    parameter integer BAUD_RATE  = 115_200,      // UART baud rate
    parameter integer NUM_SAMPLES = 4096         // Replay and record buffer depth
) (
    input  wire clk_25m,
    input  wire rst_n,

    // Status LEDs (active-low)
    output wire led_r,
    output wire led_g,
    output wire led_b,

    // MP34DT01-M PDM microphone 1 (on-board)
    output wire mic_clk,
    input  wire mic_dat,
    output wire mic_sel,

    // MP34DT01-M PDM microphone 2 (external, Port3)
    output wire mic2_clk,
    input  wire mic2_dat,
    output wire mic2_sel,

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
    // 2-stage synchronizers for PDM data inputs
    // =========================================================================
    // Mic 1
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

    // Mic 2
    reg pdm2_sync1, pdm2_sync2;
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n) begin
            pdm2_sync1 <= 1'b0;
            pdm2_sync2 <= 1'b0;
        end else begin
            pdm2_sync1 <= mic2_dat;
            pdm2_sync2 <= pdm2_sync1;
        end
    end

    // =========================================================================
    // CIC sinc³ decimation: 3.125 MHz PDM → 16-bit PCM @ ~48.8 kHz
    // =========================================================================
    // Mic 1
    wire signed [15:0] pcm_raw;
    wire               pcm_valid;

    pdm_cic #(
        .CIC_ORDER (3),
        .DEC_RATIO (64),
        .OUT_BITS  (16)
    ) cic1 (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pdm_bit   (pdm_sync2),
        .pdm_valid (pdm_valid),
        .pcm_out   (pcm_raw),
        .pcm_valid (pcm_valid)
    );

    // Mic 2 (pcm_valid not connected — fires identically to cic1's)
    wire signed [15:0] pcm2_raw;

    /* verilator lint_off PINCONNECTEMPTY */
    pdm_cic #(
        .CIC_ORDER (3),
        .DEC_RATIO (64),
        .OUT_BITS  (16)
    ) cic2 (
        .clk       (clk_25m),
        .rst_n     (rst_n),
        .pdm_bit   (pdm2_sync2),
        .pdm_valid (pdm_valid),
        .pcm_out   (pcm2_raw),
        .pcm_valid ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

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
    localparam [ADDR_BITS:0] LAST_ADDR = NUM_SAMPLES - 1;
    /* verilator lint_on WIDTHTRUNC */

    // Replay buffer: written by UPLOAD, read by PLAY_RECORD
    reg [15:0] replay_ram [0:NUM_SAMPLES-1];
    reg [15:0] replay_word;

    // Record buffer (mic 1): written by PLAY_RECORD or RECORD, read by DUMP
    reg [15:0] record_ram [0:NUM_SAMPLES-1];
    reg [15:0] dump_word;

    // Record buffer (mic 2): written by PLAY_RECORD or RECORD, read by DUMP2
    reg [15:0] record2_ram [0:NUM_SAMPLES-1];
    reg [15:0] dump2_word;

    // =========================================================================
    // State machine — declarations
    // =========================================================================
    localparam S_IDLE        = 3'd0;
    localparam S_UPLOAD      = 3'd1;
    localparam S_PLAY_RECORD = 3'd2;
    localparam S_RECORD      = 3'd3;
    localparam S_DUMP        = 3'd4;
    localparam S_DUMP2       = 3'd5;

    localparam CMD_UPLOAD = 8'h55;  // 'U'
    localparam CMD_PLAY   = 8'h50;  // 'P'
    localparam CMD_RECORD = 8'h52;  // 'R'
    localparam CMD_DUMP   = 8'h44;  // 'D'
    localparam CMD_DUMP2  = 8'h45;  // 'E'
    localparam ACK_BYTE   = 8'h4B;  // 'K'

    reg [2:0]          state;
    reg [ADDR_BITS:0]  addr_cnt;

    // Upload byte assembly
    reg        upload_high;
    reg [7:0]  upload_hi_byte;

    // Dump control
    reg        dump_high;
    reg        dump_init;

    // PCM hold register: drives the sigma-delta modulator
    reg signed [15:0] pcm_held;

    // =========================================================================
    // BRAM write: replay_ram
    // =========================================================================
    always @(posedge clk_25m)
        if (state == S_UPLOAD && rx_valid && !upload_high)
            replay_ram[addr_cnt[ADDR_BITS-1:0]] <= {upload_hi_byte, rx_data};

    // BRAM read: replay_ram (1-cycle latency)
    always @(posedge clk_25m)
        replay_word <= replay_ram[addr_cnt[ADDR_BITS-1:0]];

    // =========================================================================
    // BRAM write: record_ram (mic 1)
    // =========================================================================
    always @(posedge clk_25m)
        if ((state == S_PLAY_RECORD || state == S_RECORD) && pcm_valid)
            record_ram[addr_cnt[ADDR_BITS-1:0]] <= pcm_raw;

    // BRAM read: record_ram (1-cycle latency)
    always @(posedge clk_25m)
        dump_word <= record_ram[addr_cnt[ADDR_BITS-1:0]];

    // =========================================================================
    // BRAM write: record2_ram (mic 2)
    // =========================================================================
    always @(posedge clk_25m)
        if ((state == S_PLAY_RECORD || state == S_RECORD) && pcm_valid)
            record2_ram[addr_cnt[ADDR_BITS-1:0]] <= pcm2_raw;

    // BRAM read: record2_ram (1-cycle latency)
    always @(posedge clk_25m)
        dump2_word <= record2_ram[addr_cnt[ADDR_BITS-1:0]];

    // =========================================================================
    // PCM hold for playback: drives sigma-delta modulator
    // =========================================================================
    always @(posedge clk_25m or negedge rst_n) begin
        if (!rst_n)
            pcm_held <= 16'sd0;
        else if (state == S_PLAY_RECORD && pcm_valid)
            pcm_held <= replay_word;
        else if (state != S_PLAY_RECORD)
            pcm_held <= 16'sd0;
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
            upload_high    <= 1'b1;
            upload_hi_byte <= 8'h00;
            dump_high      <= 1'b0;
            dump_init      <= 1'b0;
            tx_data_r      <= 8'h00;
            tx_valid_r     <= 1'b0;
        end else begin
            if (tx_valid_r && tx_ready)
                tx_valid_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (rx_valid) begin
                        case (rx_data)
                            CMD_UPLOAD: begin
                                addr_cnt    <= 0;
                                upload_high <= 1'b1;
                                state       <= S_UPLOAD;
                            end
                            CMD_PLAY: begin
                                addr_cnt <= 0;
                                state    <= S_PLAY_RECORD;
                            end
                            CMD_RECORD: begin
                                addr_cnt <= 0;
                                state    <= S_RECORD;
                            end
                            CMD_DUMP: begin
                                addr_cnt  <= 0;
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;
                                state     <= S_DUMP;
                            end
                            CMD_DUMP2: begin
                                addr_cnt  <= 0;
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;
                                state     <= S_DUMP2;
                            end
                            default: ;
                        endcase
                    end
                end

                S_UPLOAD: begin
                    if (rx_valid) begin
                        if (upload_high) begin
                            upload_hi_byte <= rx_data;
                            upload_high    <= 1'b0;
                        end else begin
                            upload_high <= 1'b1;
                            if (addr_cnt == LAST_ADDR) begin
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

                S_PLAY_RECORD: begin
                    if (pcm_valid) begin
                        if (addr_cnt == LAST_ADDR) begin
                            tx_data_r  <= ACK_BYTE;
                            tx_valid_r <= 1'b1;
                            addr_cnt   <= 0;
                            state      <= S_IDLE;
                        end else begin
                            addr_cnt <= addr_cnt + 1;
                        end
                    end
                end

                S_RECORD: begin
                    if (pcm_valid) begin
                        if (addr_cnt == LAST_ADDR) begin
                            tx_data_r  <= ACK_BYTE;
                            tx_valid_r <= 1'b1;
                            addr_cnt   <= 0;
                            state      <= S_IDLE;
                        end else begin
                            addr_cnt <= addr_cnt + 1;
                        end
                    end
                end

                S_DUMP: begin
                    if (dump_init) begin
                        dump_init <= 1'b0;
                    end else if (!tx_valid_r) begin
                        if (dump_high) begin
                            tx_data_r  <= dump_word[15:8];
                            tx_valid_r <= 1'b1;
                            dump_high  <= 1'b0;
                        end else begin
                            tx_data_r  <= dump_word[7:0];
                            tx_valid_r <= 1'b1;
                            if (addr_cnt == LAST_ADDR) begin
                                addr_cnt <= 0;
                                state    <= S_IDLE;
                            end else begin
                                addr_cnt  <= addr_cnt + 1;
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;
                            end
                        end
                    end
                end

                S_DUMP2: begin
                    if (dump_init) begin
                        dump_init <= 1'b0;
                    end else if (!tx_valid_r) begin
                        if (dump_high) begin
                            tx_data_r  <= dump2_word[15:8];
                            tx_valid_r <= 1'b1;
                            dump_high  <= 1'b0;
                        end else begin
                            tx_data_r  <= dump2_word[7:0];
                            tx_valid_r <= 1'b1;
                            if (addr_cnt == LAST_ADDR) begin
                                addr_cnt <= 0;
                                state    <= S_IDLE;
                            end else begin
                                addr_cnt  <= addr_cnt + 1;
                                dump_high <= 1'b1;
                                dump_init <= 1'b1;
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
    assign mic_clk  = pdm_clk_r;
    assign mic_sel  = 1'b0;       // Left channel

    assign mic2_clk = pdm_clk_r;  // Shared PDM clock
    assign mic2_sel = 1'b1;       // Right channel

    assign amp_clk  = pdm_clk_r;
    assign amp_dat  = amp_dat_w;

    // =========================================================================
    // LED indicators (active-low)
    // =========================================================================
    assign led_b = ~(state == S_IDLE);
    assign led_r = ~(state == S_UPLOAD || state == S_PLAY_RECORD || state == S_RECORD);
    assign led_g = ~(state == S_PLAY_RECORD || state == S_DUMP || state == S_DUMP2);

endmodule

`default_nettype wire
