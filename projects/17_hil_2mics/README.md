# 17 — Dual-Mic PDM HIL (Hardware-in-the-Loop Transfer Function Characterizer)

Extends [project 15](../15_pdm_hil/) with a second PDM microphone.  Both mics
record simultaneously during playback or record-only mode, measuring the
acoustic damping of a hearing protection device by comparing the outside and
inside signals.

- **Mic 1** (outside): on-board MP34DT01-M — placed outside the hearing protection
- **Mic 2** (inside): external MP34DT01-M on Port P5 — placed inside the hearing protection

## Signal Flow

```
Host PC
  │  'U' + 8192 bytes
  ▼
UART RX ──────────────────────────────────────► replay_ram [0:4095]
                                                      │
                                  'P' command         │ pcm_valid (48.828 kHz)
                                                      ▼
                                              pdm_modulator ──► amp_clk/dat ──► MAX98358 speaker
                                                                                        │
                                                                              (acoustic path)
                                                                               ┌────────┴────────┐
                                                                               │                  │
MP34DT01-M mic 1 ──► sync ──► CIC sinc³ ──► pcm_raw  ──► record_ram           │                  │
(on-board)                                                                     │                  │
                                                                               │                  │
MP34DT01-M mic 2 ──► sync ──► CIC sinc³ ──► pcm2_raw ──► record2_ram          │                  │
(Port P5)                                                                      │                  │
                                                                               └──────────────────┘
                         'D' dumps record_ram  (mic 1) ──► UART TX ──► Host
                         'E' dumps record2_ram (mic 2) ──► UART TX ──► Host
```

## UART Protocol (115200 8N1)

| Byte | Command | Action | FPGA Response |
|------|---------|--------|---------------|
| `'U'` (0x55) | CMD_UPLOAD | Receive 16384×2 bytes (big-endian 16-bit) → `replay_ram` | Sends `'K'` (0x4B) ACK |
| `'P'` (0x50) | CMD_PLAY | Replay through speaker; record both mics | Sends `'K'` ACK |
| `'R'` (0x52) | CMD_RECORD | Record both mics (no playback) | Sends `'K'` ACK |
| `'D'` (0x44) | CMD_DUMP | Stream `record_ram` (mic 1) as 16384×2 bytes | Streams bytes |
| `'E'` (0x45) | CMD_DUMP2 | Stream `record2_ram` (mic 2) as 16384×2 bytes | Streams bytes |

Commands received while not in IDLE are silently ignored.

## LED Indicators (active-low)

| State | Blue | Red | Green | Meaning |
|-------|:----:|:---:|:-----:|---------|
| IDLE | **on** | off | off | Ready for command |
| UPLOAD | off | **on** | off | Loading replay buffer |
| PLAY_RECORD | off | **on** | **on** | Playing + recording both mics |
| RECORD | off | **on** | off | Recording both mics only |
| DUMP / DUMP2 | off | off | **on** | Sending record buffer |

## Recording Parameters

| Parameter | Value |
|-----------|-------|
| Microphone 1 | MP34DT01-M (on-board PDM, left) |
| Microphone 2 | MP34DT01-M (external PDM, Port P5, right) |
| Amplifier | MAX98358 (PDM, Port4) |
| PDM clock | 3.125 MHz (25 MHz / 8, shared) |
| CIC decimation | 64 (sinc³) per mic |
| Sample rate | 48,828 Hz |
| Sample width | 16-bit signed |
| Buffer depth | 16384 samples per mic |
| Record duration | ~335 ms |
| UART baud rate | 115200 8N1 |
| Total BRAM | ~48 EBR blocks (3 buffers × 16 EBR) |

## Hardware Wiring

| Signal | FPGA Site | Connector | Direction |
|--------|-----------|-----------|-----------|
| `clk_25m` | P6 | Oscillator | input |
| `rst_n` | L14 | User button | input |
| `mic_clk` | H3 | On-board | output |
| `mic_dat` | K3 | On-board | input |
| `mic_sel` | K4 | On-board | output (low) |
| `mic2_clk` | C6 | Port P5 | output |
| `mic2_dat` | C7 | Port P5 | input |
| `mic2_sel` | C5 | Port P5 | output (high) |
| `amp_clk` | J4 | Port4 | output |
| `amp_dat` | J3 | Port4 | output |
| `uart_tx` | B9 | iCELink | output |
| `uart_rx` | A9 | iCELink | input |

## Build

```bash
cd projects/17_hil_2mics
make          # synthesise, place & route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open GTKWave (requires make sim first)
make lint     # Verilator static analysis
make program  # flash to board via icesprog
make clean    # remove build artefacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog · verilator

## Usage

### Recording data with `fpgactrl`

Use the Go CLI tool at `tools/fpgactrl/` for signal generation, upload, playback,
recording, and CSV export:

```bash
# Full workflow: generate chirp → upload → play+record → dump → save CSV
fpgactrl run --port /dev/ttyACM0 --signal chirp --save signals.csv

# Record-only (no playback)
fpgactrl run --port /dev/ttyACM0 --record-only --save quiet.csv

# Generate signal offline (no hardware)
fpgactrl gen --signal impulse --save impulse.csv
```

### Viewing and comparing signals with `hil_test.py`

```bash
pip install numpy matplotlib

# View a single recording
python3 hil_test.py signals.csv

# Compare multiple recordings — use checkboxes to select signals
python3 hil_test.py with_headphones.csv without_headphones.csv
```

The viewer shows time-domain waveforms and FFT magnitude plots with interactive
checkboxes to toggle individual signals (e.g. mic1 from file 1, mic2 from file 2).

## Simulation

The testbench (`pdm_hil_2mics_tb.v`) uses scaled parameters (CLK_FREQ=100,
BAUD_RATE=10, NUM_SAMPLES=4) for fast simulation.

It drives mic 1 with all-ones PDM and mic 2 with all-zeros PDM during
PLAY_RECORD, then verifies that mic 1 records non-zero CIC output while
mic 2 records a different value.  A second test drives both mics high during
RECORD-only mode and verifies both buffers contain non-zero data.

Expected output:
```
OK   [idle leds]: blue on, red/green off
OK   [mic_sel]: mic1=left (0)
OK   [mic2_sel]: mic2=right (1)
[...] Sending CMD_UPLOAD ('U') + 4 samples
OK   [upload ack]: received 'K'
[...] Sending CMD_PLAY ('P'), mic1=1, mic2=0
OK   [play ack]: received 'K'
[...] Sending CMD_DUMP ('D') — mic 1
OK   mic1 sample 0-3: non-zero
[...] Sending CMD_DUMP2 ('E') — mic 2
OK   mic2 sample 0-3: values received
[...] Sending CMD_RECORD ('R') with both mics=1
OK   [record ack]: received 'K'
[...] Verifying mic2 recorded non-zero after record-only
OK   mic2 record sample 0-3: non-zero
OK   [final idle]: blue LED on
PASS: all checks passed.
```
