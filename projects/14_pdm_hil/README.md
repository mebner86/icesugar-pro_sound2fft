# 14 — PDM HIL (Hardware-in-the-Loop Transfer Function Characterizer)

Combines [project 09](../09_pdm_pcm_loopback/) (PDM mic→CIC→sigma-delta→PDM amp) and
[project 13](../13_i2s_record_to_uart/) (UART command + BRAM recording) to implement a
closed-loop acoustic HIL test system.  Upload a test signal, replay it through the
MAX98358 speaker while recording the MP34DT01-M microphone, then download the recording
to compute the speaker-to-microphone transfer function H(f) on the host.

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
                                                                                        │
MP34DT01-M mic ──► 2-stage sync ──► CIC sinc³ (R=64) ──► pcm_raw ──────────────────────┘
                                                              │
                                                              ▼ pcm_valid
                                                        record_ram [0:4095]
                                                              │
                                                         'D' command
                                                              ▼
                                                          UART TX ──► Host PC
                                                              │
                                               H(f) = FFT(recorded) / FFT(played)
```

## UART Protocol (115200 8N1)

| Byte | Command | Action | FPGA Response |
|------|---------|--------|---------------|
| `'U'` (0x55) | CMD_UPLOAD | Receive 4096×2 bytes (big-endian 16-bit) → `replay_ram` | Sends `'K'` (0x4B) ACK |
| `'P'` (0x50) | CMD_PLAY | Replay `replay_ram` through speaker; record mic → `record_ram` | Sends `'K'` ACK |
| `'R'` (0x52) | CMD_RECORD | Record mic only (no playback) → `record_ram` | Sends `'K'` ACK |
| `'D'` (0x44) | CMD_DUMP | Stream `record_ram` as 4096×2 bytes (big-endian 16-bit) | Streams bytes |

Commands received while not in IDLE are silently ignored.

## State Machine

```
         'U'                    all bytes received → 'K'
 IDLE ──────────► UPLOAD ──────────────────────────────────► IDLE
  │                                                           │
  │ 'R'                   all samples → 'K'                  │ 'P'
  │                                                           │
  ▼                                                           ▼
RECORD ────────────────────────────────────────► IDLE    PLAY_RECORD ──────────► IDLE
  (addr == NUM_SAMPLES-1)                                  (addr == NUM_SAMPLES-1 → 'K')
                                                               │
                              'D'                              │
                               ▼                               │
                              DUMP ──────────────► IDLE ◄──────┘
                              (all bytes sent)
```

## LED Indicators (active-low)

| State | Blue | Red | Green | Meaning |
|-------|:----:|:---:|:-----:|---------|
| IDLE | **on** | off | off | Ready for command |
| UPLOAD | off | **on** | off | Loading replay buffer |
| PLAY_RECORD | off | **on** | **on** | Playing + recording |
| RECORD | off | **on** | off | Recording mic only |
| DUMP | off | off | **on** | Sending record buffer |

## Recording Parameters

| Parameter | Value |
|-----------|-------|
| Microphone | MP34DT01-M (on-board PDM) |
| Amplifier | MAX98358 (PDM, Port4) |
| PDM clock | 3.125 MHz (25 MHz / 8) |
| CIC decimation | 64 (sinc³) |
| Sample rate | 48,828 Hz |
| Sample width | 16-bit signed |
| Buffer depth | 4096 samples |
| Record duration | ~84 ms |
| Frequency resolution | ~11.9 Hz (Δf = Fs/N) |
| UART baud rate | 115200 8N1 |
| Upload/dump size | 8192 bytes |
| Upload/dump time | ~711 ms |

## Hardware Wiring

Same as project 09 (PDM mic + amp) plus the iCELink USB-CDC UART from project 13.

| Signal | FPGA Site | Connector | Direction |
|--------|-----------|-----------|-----------|
| `clk_25m` | P6 | Oscillator | input |
| `rst_n` | L14 | User button | input |
| `mic_clk` | H3 | On-board | output |
| `mic_dat` | K3 | On-board | input |
| `mic_sel` | K4 | On-board | output (low) |
| `amp_clk` | J4 | Port4.4 | output |
| `amp_dat` | J3 | Port4.6 | output |
| `uart_tx` | B9 | iCELink | output |
| `uart_rx` | A9 | iCELink | input |

## Architecture

### BRAM Buffers

Two on-chip EBR block-RAM buffers, each 4096 × 16-bit (~65 kbits, ~4 EBR blocks):

- **`replay_ram`** — written by UPLOAD (UART RX), read by PLAY_RECORD (PDM modulator)
- **`record_ram`** — written by PLAY_RECORD or RECORD (CIC output), read by DUMP (UART TX)

Total BRAM usage: ~8 EBR blocks out of 56 available on the ECP5-25F.

Both are inferred as EBR via the standard synchronous-write / synchronous-read (1-cycle latency) pattern.

### CIC Filter and Modulator

Identical to project 09:
- `rtl/pdm_cic.v` — CIC_ORDER=3, DEC_RATIO=64, OUT_BITS=16
- `rtl/pdm_modulator.v` — 1st-order sigma-delta, runs at 3.125 MHz PDM rate

During PLAY_RECORD the zero-order hold (`pcm_held`) is loaded from `replay_ram` on each
`pcm_valid` strobe.  In all other states `pcm_held` is zeroed so the speaker outputs silence.

## Build

```bash
cd projects/14_pdm_hil
make          # synthesise, place & route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open GTKWave (requires make sim first)
make lint     # Verilator static analysis
make program  # flash to board via icesprog
make clean    # remove build artefacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog · verilator

## Usage

Connect the MAX98358 amplifier module to Port4 (same wiring as project 09) and attach the
iCELink USB-CDC port to the host.  Open a terminal at **115200 baud, 8N1**.

### Full HIL measurement with `hil_test.py`

```bash
pip install pyserial numpy matplotlib scipy

# Log chirp (default): 200 Hz → 20 kHz sweep
python3 hil_test.py /dev/ttyACM0

# Impulse response only
python3 hil_test.py /dev/ttyACM0 --signal impulse

# White noise excitation, save PCM and H(f) CSV
python3 hil_test.py /dev/ttyACM0 --signal noise --save

# Background noise capture (no speaker output)
python3 hil_test.py /dev/ttyACM0 --record-only
```

The script uploads the test signal, triggers play+record, downloads the result and
displays a six-panel plot: input waveform, mic waveform, |H(f)| (dB), ∠H(f) (deg),
impulse response h(t), and a spectrogram of the recorded signal.

### Minimal Python snippet

```python
import serial, struct, time

SAMPLE_RATE = 48_828
NUM_SAMPLES = 4096

with serial.Serial('/dev/ttyACM0', 115_200, timeout=5) as s:
    # Upload a 1 kHz sine wave
    import numpy as np
    t = np.arange(NUM_SAMPLES) / SAMPLE_RATE
    sig = (np.sin(2 * np.pi * 1000 * t) * 0.9 * 32767).astype(np.int16)
    payload = struct.pack(f'>{NUM_SAMPLES}h', *sig)

    s.write(b'U')
    s.write(payload)
    assert s.read(1) == b'K', "Upload ACK missing"

    s.write(b'P')
    assert s.read(1) == b'K', "Play ACK missing"

    s.write(b'D')
    raw = s.read(NUM_SAMPLES * 2)   # 8192 bytes

recorded = struct.unpack(f'>{NUM_SAMPLES}h', raw)
```

### Command-line (Linux)

```bash
PORT=/dev/ttyACM0

# Upload silence (8192 zero bytes), then record background noise
printf '\x55' > $PORT; dd if=/dev/zero bs=8192 count=1 > $PORT; sleep 0.1
printf '\x52' > $PORT; sleep 0.1   # CMD_RECORD
printf '\x44' > $PORT; dd if=$PORT bs=8192 count=1 of=noise.pcm

# Convert to WAV
sox -r 48828 -e signed -b 16 -c 1 noise.pcm noise.wav
```

## Simulation

The testbench (`pdm_hil_tb.v`) uses scaled parameters (CLK_FREQ=100, BAUD_RATE=10,
NUM_SAMPLES=4) for fast simulation while preserving the real PDM/CIC ratios.

Expected output:
```
OK   [idle leds]: blue on, red/green off
[...] Sending CMD_UPLOAD ('U') + 4 samples
OK   [upload ack]: received 'K'
OK   [post-upload idle]: blue LED on
[...] Sending CMD_PLAY ('P'), driving mic_dat=1
OK   [play ack]: received 'K'
[...] Sending CMD_DUMP ('D')
OK   sample 0: 0xXXXX (non-zero CIC output)
OK   sample 1: 0xXXXX (non-zero CIC output)
OK   sample 2: 0xXXXX (non-zero CIC output)
OK   sample 3: 0xXXXX (non-zero CIC output)
[...] Sending CMD_RECORD ('R') with mic_dat=1
OK   [record ack]: received 'K'
OK   [final idle]: blue LED on
PASS: all checks passed.
```
