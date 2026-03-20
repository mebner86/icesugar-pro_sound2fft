# 13_i2s_record_to_uart

Record a fixed block of I2S microphone audio to BRAM on command, then stream
the samples back over UART.  Combines the I2S receiver from project 04 with
the UART infrastructure from project 11.

## Description

A single-character ASCII command triggers recording: the FPGA captures 4096
consecutive left-channel samples (full 24-bit I2S words) into on-chip BRAM.
A second command streams those samples back to the host as raw big-endian
24-bit PCM over the iCELink USB-CDC virtual COM port.

No PLL, no HDMI, no amplifier — just the microphone and UART.

## Recording Parameters

| Parameter | Value |
|-----------|-------|
| Sample rate | 48,828 Hz (CLK_DIV=4: 25 MHz / 8 / 32 LRCLK half-period) |
| Sample width | 24 bits (full I2S word) |
| Block size | 4096 samples |
| Record duration | ~84 ms |
| UART baud rate | 115200 8N1 |
| Dump size | 12288 bytes (4096 × 3) |
| Dump time | ~1067 ms |

## UART Protocol

Two single-byte ASCII commands (easy to test with `echo -n 'R' > /dev/ttyACM0`):

| Byte | Command | Action |
|------|---------|--------|
| `'R'` (0x52) | CMD_RECORD | Reset address, start capturing; auto-stops when full |
| `'D'` (0x44) | CMD_DUMP | Stream 4096 samples as 12288 bytes (big-endian 24-bit) |

Commands received while not in IDLE are silently ignored.

## Architecture

```
SPH0645 mic (I2S, left channel)
  │
i2s_clkgen (CLK_DIV=4) + i2s_rx (DATA_BITS=24)
  │  rx_left_data[23:0] + rx_left_valid
  ▼
sample_ram [0:4095] reg [23:0]   (inferred ECP5 EBR)
  ▲                   │
  │  CMD_RECORD       │  CMD_DUMP (big-endian, MSB first)
  │                   ▼
uart_rx (A9) ──► state machine ──► uart_tx (B9) ──► iCELink USB-CDC ──► Host
```

## State Machine

```
         'R'                    addr==NUM_SAMPLES-1
 IDLE ────────► RECORD ─────────────────────────► IDLE
   ▲                                               │
   │ done (all bytes sent)                         │ 'D'
   └─────────────── DUMP ◄────────────────────────┘
```

## Status LEDs

| LED | Colour | State |
|-----|--------|-------|
| `led_b` | Blue | Lit in IDLE (ready) |
| `led_r` | Red | Lit while recording |
| `led_g` | Green | Lit while dumping |

## Pin Connections

| Signal | FPGA Site | Connector | Direction |
|--------|-----------|-----------|-----------|
| `clk_25m` | P6 | Oscillator | Input |
| `rst_n` | L14 | User button | Input |
| `mic_bclk` | R7 | P4.5 | Output |
| `mic_lrclk` | D5 | P4.7 | Output |
| `mic_data` | D4 | P4.9 | Input |
| `mic_sel` | E4 | P4.11 | Output (low = left) |
| `uart_tx` | B9 | iCELink | Output |
| `uart_rx` | A9 | iCELink | Input |

## Build

From the repo root (inside Dev Container):

```bash
make build 13   # synthesise, place & route, generate bitstream
make sim   13   # run simulation
make lint  13   # Verilator lint check
```

Or from the project directory:

```bash
make          # build bitstream
make sim      # run simulation (Icarus Verilog)
make lint     # lint
make waves    # open GTKWave (after make sim)
make clean    # remove build artefacts
```

## Simulation

The testbench (`i2s_record_to_uart_tb.v`) uses scaled parameters
(CLK_FREQ=100, BAUD_RATE=10, NUM_SAMPLES=4) for fast simulation:

1. Sends `'R'` over UART while simultaneously driving 4 known I2S frames
2. Waits for recording to complete (blue LED asserts)
3. Sends `'D'` and receives 12 bytes
4. Verifies each sample matches the expected full 24-bit value

Expected output:
```
OK   sample 0: 0xABCDEF
OK   sample 1: 0x123456
OK   sample 2: 0xDEAD00
OK   sample 3: 0xBEEF42
PASS: all 4 samples correct
```

## Program

```bash
icesprog projects/13_i2s_record_to_uart/build/i2s_record_to_uart.bit
# or drag the .bit file to the USB drive that appears when the board is plugged in
```

## Usage

Connect the SPH0645 microphone to the P4 connector (same wiring as project 04).
Open a serial terminal at **115200 baud, 8N1**.

**Record, dump, and plot with the bundled Python script:**

```bash
# Linux / macOS
python3 record_and_plot.py /dev/ttyACM0

# Windows
python record_and_plot.py COM4

# Also save raw PCM (convert to WAV with sox)
python3 record_and_plot.py /dev/ttyACM0 --save capture.pcm
```

The script sends `R`, waits for recording to complete, sends `D`, receives the
12288-byte payload, removes the microphone DC offset, then shows a two-panel
plot: waveform (amplitude vs time) and one-sided FFT spectrum (dBFS vs kHz).

**Minimal Python snippet (no plot):**

```python
import serial, struct, time

with serial.Serial('/dev/ttyACM0', 115200, timeout=2) as s:
    s.write(b'R')
    time.sleep(0.1)           # wait ~84 ms for recording to complete
    s.write(b'D')
    raw = s.read(4096 * 3)    # 12288 bytes

# Decode big-endian signed 24-bit
samples = [int.from_bytes(raw[i:i+3], 'big', signed=True) for i in range(0, len(raw), 3)]
```

**Record and dump from the command line (Linux):**

```bash
# Trigger recording
echo -n 'R' > /dev/ttyACM0
sleep 0.1

# Dump and save raw PCM
echo -n 'D' > /dev/ttyACM0
dd if=/dev/ttyACM0 bs=12288 count=1 of=capture.pcm

# Convert to WAV (requires sox)
sox -r 48828 -e signed -b 24 -c 1 capture.pcm capture.wav
```

**Windows** — open PuTTY or a Python script; use the COM port shown in Device Manager.
