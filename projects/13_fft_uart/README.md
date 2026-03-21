# 13_fft_uart

Real-time FFT spectrum analyzer that streams frequency data to a host PC over
UART instead of displaying it on an HDMI screen.  Builds on the FFT engine
from project 07 and the UART infrastructure from project 12.

## Description

The FPGA reads audio from an SPH0645 I2S microphone, computes a 512-point
real FFT, and continuously transmits the 256-bin magnitude spectrum over the
iCELink USB-CDC virtual COM port.  A Python script on the host receives the
frames and renders a live spectrum plot using matplotlib.

No PLL or HDMI hardware is required — everything runs on the 25 MHz system
clock.

## Architecture

```
SPH0645 mic (I2S)
  │
i2s_clkgen + i2s_rx
  │  24-bit samples @ 48.8 kHz
  │  truncate → 16-bit
  ▼
fft_real512
  │  256 bins × 9-bit log2 magnitude
  │  mag_addr[7:0], mag_data[8:0], mag_valid
  ▼
uart_serializer ──► uart_tx (B9) ──► iCELink USB-CDC ──► Host PC
  │
  │  COBS frame: [bin_0]...[bin_255][0x00]  (257 bytes, ~10.6 Hz)
  ▼
display_fft.py (matplotlib, runs on host)
```

## Wire Protocol (COBS convention)

Each frame is **257 bytes**:

```
[bin_0] [bin_1] ... [bin_255] [0x00]
```

| Field | Value | Notes |
|-------|-------|-------|
| Data bytes | 0x01–0xFF | log₂ magnitude, 4.4 fixed-point; clamped from 0x00→0x01 |
| Delimiter | 0x00 | Exclusive COBS frame boundary; never appears in data |

- **Baud rate**: 115200 8N1
- **FFT rate**: ~94 Hz (512 samples at 48.8 kHz)
- **Frame divider**: `FRAME_DIV=9` — one in every 9 FFT frames is transmitted
- **Display rate**: 94 / 9 ≈ **10.6 Hz**
- **UART frame time**: 257 × 10 bits / 115200 ≈ 22.3 ms
- **Idle gap**: 9 × 10.5 ms − 22.3 ms ≈ 72 ms (buffer is never read and written simultaneously)

**Frame coherence**: the capture buffer is written only during the designated
FFT frame.  All 256 bins in every transmitted frame come from the same FFT
computation — no mixing across frames.

### Magnitude encoding

Each byte encodes log₂ magnitude in **4.4 fixed-point** (1 LSB = 1/16 log₂ ≈ 0.43 dB):

| Byte | log₂ value | Approx. dB |
|------|-----------|------------|
| 0x01 | 0.0625 | ~0.4 dB |
| 0x10 | 1.0 | ~6 dB |
| 0x80 | 8.0 | ~48 dB |
| 0xFF | 15.9375 | ~96 dB |

### Python re-sync

```python
raw = ser.read_until(b'\x00')   # read until COBS delimiter
if len(raw) == 257:             # 256 data bytes + 0x00
    bins = list(raw[:256])      # discard wrong-length frames (startup glitch)
```

## Frequency Mapping

512-point real FFT at 48828 Hz sample rate → 256 unique bins:

| Bin | Frequency |
|-----|-----------|
| 0 | 0 Hz (DC) |
| 1 | 95.4 Hz |
| 128 | 12.2 kHz |
| 255 | 24.3 kHz |

Frequency resolution: Fs / N = 48828 / 512 ≈ **95.4 Hz/bin**

## Pin Connections

| Signal | FPGA Site | Connector | Direction |
|--------|-----------|-----------|-----------|
| `clk_25m` | P6 | Oscillator | Input |
| `rst_n` | L14 | User button | Input |
| `mic_bclk` | R7 | P4.5 | Output |
| `mic_lrclk` | D5 | P4.7 | Output |
| `mic_data` | D4 | P4.9 | Input |
| `mic_sel` | E4 | P4.11 | Output |
| `uart_tx` | B9 | iCELink | Output |

## Status LEDs

| LED | Colour | Meaning |
|-----|--------|---------|
| `led_r` | Red | On while FFT is computing (~0.7% duty cycle) |
| `led_g` | Green | On while UART is transmitting (~52% duty cycle) |
| `led_b` | Blue | Off |

## Build

From the repo root (inside Dev Container):

```bash
make build 13   # synthesise, place & route, generate bitstream
make sim   13   # run simulation (fast — serialiser only, no FFT/I2S)
make lint  13   # Verilator lint check
```

Or from the project directory:

```bash
make          # build bitstream
make sim      # run simulation
make lint     # lint
make waves    # open GTKWave (after make sim)
make clean    # remove build artefacts
```

## Simulation

The testbench (`fft_uart_tb.v`) exercises `uart_serializer` in isolation:

- Injects a synthetic 256-bin FFT frame
- Bin 0 and bin 5 carry zero magnitude → verifies clamping to 0x01
- Decodes every UART byte by sampling at mid-bit
- Checks all 257 bytes and prints PASS / FAIL

```
PASS: all 257 bytes correct
```

## Program

```bash
icesprog projects/13_fft_uart/build/fft_uart.bit
# or drag the .bit file to the USB drive that appears when the board is plugged in
```

## Python Display

### Setup (once, per environment)

See the [Python environment setup](#python-environment-setup) section in the
root README for full instructions.  Quick reference:

**Miniforge / conda (Windows):**
```bash
conda create -n sound2fft python=3.11
conda activate sound2fft
pip install -r requirements.txt          # from repo root
```

**pip venv (Linux / macOS / container):**
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt          # from repo root
```

### Run

```bash
# Windows (find COMx in Device Manager)
python projects/13_fft_uart/display_fft.py COM5

# Linux
python projects/13_fft_uart/display_fft.py /dev/ttyACM0

# macOS
python projects/13_fft_uart/display_fft.py /dev/tty.usbmodem...
```

Optional `--baud` argument (default 115200):
```bash
python projects/13_fft_uart/display_fft.py COM5 --baud 115200
```

### Display

The plot shows:
- **X-axis**: frequency in kHz (0–24.4 kHz)
- **Left Y-axis**: log₂ magnitude in 4.4 fixed-point units (0–16)
- **Right Y-axis**: approximate dB (0–96 dBFS)
- **Title bar**: running frame count, dropped-frame count (stale frames discarded to stay live), and bad-frame count (wrong-length frames from startup glitches)

Press **Ctrl-C** or close the window to exit.

### Development inside Dev Container

The display script can be edited and linted inside the container.  Install
the packages into a local venv for IDE IntelliSense:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt          # from repo root
```

Point VS Code's Python extension to `.venv/bin/python` (repo root venv).
The COM port won't be accessible inside the container, but all editing and
static analysis works normally.
