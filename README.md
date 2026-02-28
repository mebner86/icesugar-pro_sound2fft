# icesugar-pro_sound2fft

[![CI](https://github.com/mebner86/icesugar-pro_sound2fft/actions/workflows/ci.yml/badge.svg)](https://github.com/mebner86/icesugar-pro_sound2fft/actions/workflows/ci.yml)

Real-time audio spectrum analyzer on the iCESugar-Pro (ECP5) FPGA — I2S microphone to HDMI display.


https://github.com/user-attachments/assets/a4d3b1ac-cda3-45de-9872-42211985f9db


## Overview

This project demonstrates real-time FFT visualization on an HDMI display, using audio input from an I2S microphone. It targets the iCESugar-Pro FPGA board and uses a fully open source toolchain.

## Requirements

- [Docker](https://www.docker.com/get-started/)
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- iCESugar-Pro FPGA board ([ECP5-25F](https://github.com/wuxx/icesugar-pro))
- I2S MEMS microphone (e.g., [SPH0645](https://www.adafruit.com/product/3421))
- I2S amplifier (e.g., [MAX98357A](https://www.adafruit.com/product/3006))
- HDMI display (e.g., [Waveshare 3.2inch HDMI LCD (H)](https://www.waveshare.com/3.2inch-hdmi-lcd-h.htm))

## Quick Start

### 1. Open in Dev Container

Open the repository folder in VS Code, then either:
- Click **Reopen in Container** in the notification that appears, or
- Open the Command Palette (`Ctrl+Shift+P`) and run **Dev Containers: Reopen in Container**

VS Code builds the container (first time only) and reopens the workspace inside it. All FPGA tools (Yosys, nextpnr-ecp5, Project Trellis, Icarus Verilog, Verilator, cocotb) are available directly in the integrated terminal. Pre-commit hooks are installed automatically.

### 2. Build and Run Projects

The project is specified as a positional argument — either the full name or any unambiguous prefix (e.g. `01` for `01_blinky`).

```bash
# List available projects
make list

# Build all projects
make build

# Build a single project (full name or prefix)
make build 01_blinky
make build 01

# Run simulation
make sim 01

# Clean build artifacts
make clean 01    # Single project
make clean       # All projects
```

### Available Make Commands

| Command | Description |
|---------|-------------|
| `make help` | Show usage summary (default target) |
| `make list` | List available projects |
| `make build [<project>]` | Build bitstream (or all) |
| `make sim [<project>]` | Run simulation (or all) |
| `make clean [<project>]` | Clean build files (or all; also cleans test artifacts) |
| `make clean-tests` | Clean only test artifacts |
| `make test` | Run RTL unit tests (cocotb) |
| `make setup` | Install pre-commit hooks |
| `make lint` | Run linters on all files |

### Programming the FPGA

Flashing the bitstream to the board requires USB access, which is not available inside the dev container. Copy the built bitstream from `projects/<project>/build/<project>.bit` to your host machine and flash it using [icesprog](https://github.com/wuxx/icesugar) or by copying to the USB drive that appears when the board is plugged in.

**Remote development via Raspberry Pi Zero:** One convenient approach is to connect the FPGA to a Raspberry Pi Zero (running Raspberry Pi OS Lite). Install the USB library and drop in a pre-built `icesprog` binary:

```bash
sudo apt install libusb-1.0-0
sudo wget -O /usr/local/bin/icesprog https://github.com/wuxx/icesugar/raw/refs/heads/master/tools/icesprog.arm64
sudo chmod +x /usr/local/bin/icesprog
```

Then `scp` the built `.bit` file to the Pi and flash it from there:

```bash
scp projects/<project>/build/<project>.bit <username>@<pi-address>:~
ssh <username>@<pi-address> "sudo icesprog <project>.bit"
```

> **Tip:** SSH key-based authentication is handy here — it avoids repeated password prompts when running `scp` and `ssh` commands. Search online for `ssh-keygen` and `ssh-copy-id` to set it up.

## Python Environment Setup

Some projects (`12_fft_uart`, `13_i2s_record_to_uart`, `14_pdm_hil`) include a Python host
script that runs **outside** the Dev Container on your local machine.  All
Python dependencies are listed in `requirements.txt` at the repo root.

### Miniforge / conda (Windows — recommended)

```bash
conda create -n sound2fft python=3.11
conda activate sound2fft
pip install -r requirements.txt
```

### pip venv (Linux / macOS)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Dev Container (for IDE support only)

The scripts can be edited and linted inside the container.  Create a venv
there for IntelliSense — the COM port won't be accessible, but all static
analysis works normally:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Point VS Code's Python extension to `.venv/bin/python`.

## Development Setup

### Pre-commit Hooks

Pre-commit hooks are installed automatically when the dev container starts. On each commit they run:
- Trailing whitespace and EOF fixes
- YAML validation
- Verilog/SystemVerilog linting (Verilator)
- Python formatting (Ruff)

To reinstall manually: `make setup`

### Optional Host Tools

For viewing simulation waveforms, install [GTKWave](https://gtkwave.sourceforge.net/):

```bash
sudo apt install gtkwave   # Debian/Ubuntu
brew install gtkwave       # macOS
```

Example usage:

```bash
gtkwave projects/01_blinky/blinky_tb.gtkw
```

## Projects

| Project | Description |
|---------|-------------|
| `01_blinky` | LED blink test - basic I/O verification |
| `02_hdmi_test` | HDMI test pattern output (480x800@60Hz color bars) |
| `03_i2s_direct_loopback` | I2S mic-to-amp loopback via direct bit-stream pass-through (no SerDes) |
| `04_i2s_serdes_loopback` | I2S mic-to-amp loopback via parallel samples (SPH0645 → MAX98357A) |
| `05_hdmi_graph` | HDMI line graph display (portrait timing, rotated to landscape) |
| `06_live_fft` | Live FFT spectrum analyzer (I2S mic → 256-point FFT → 128-bin HDMI graph) |
| `07_live_real_fft` | Real-valued FFT optimization (512-point real FFT via 256-point complex → 256-bin display) |
| `08_pdm_bitstream_loopback` | Raw PDM bitstream loopback (PDM mic → PDM amp, no DSP) |
| `09_pdm_pcm_loopback` | PDM PCM loopback — CIC decimation → signed gain/mute → sigma-delta re-modulation → PDM amp |
| `10_pdm_to_i2s_loopback` | PDM mic-to-I2S amp loopback (PDM → I2S conversion via CIC filter) |
| `11_uart_loopback` | UART loopback via iCELink USB-CDC virtual COM port (type in terminal, FPGA echoes back) |
| `12_fft_uart` | FFT spectrum analyzer with UART output — streams 256-bin magnitude to host Python display script |
| `13_i2s_record_to_uart` | Record 4096 I2S samples to BRAM on command, dump as raw 16-bit PCM over UART, plot with Python |
| `14_pdm_hil` | Hardware-in-the-loop transfer function characterizer — upload test signal, replay through speaker while recording mic, dump result; compute H(f) on host |

## Project Structure

```
icesugar-pro_sound2fft/
├── Makefile              # Top-level build orchestration
├── .devcontainer/
│   └── devcontainer.json # VS Code Dev Container configuration
├── docker/
│   ├── Dockerfile        # FPGA toolchain container
│   └── docker-compose.yml
├── rtl/                  # Shared RTL modules
│   ├── display_ram.v     # Dual-clock display RAM (FFT → graph renderer)
│   ├── ecp5_stubs.v      # ECP5 primitive stubs for simulation
│   ├── fft256.v          # 256-point radix-2 FFT engine
│   ├── fft_real512.v     # 512-point real FFT (via 256-point complex + unscramble)
│   ├── graph_renderer.v  # Filled line graph renderer
│   ├── i2s_clkgen.v      # I2S BCLK/LRCLK clock generator
│   ├── i2s_rx.v          # I2S serial-to-parallel receiver
│   ├── i2s_tx.v          # I2S parallel-to-serial transmitter
│   ├── pdm_cic.v         # PDM CIC decimation filter (sinc³)
│   ├── pdm_modulator.v   # 1st-order sigma-delta PDM modulator (PCM → PDM)
│   ├── pll.v             # PLL for pixel/shift clocks
│   ├── tmds_encoder.v    # DVI/HDMI 8b/10b TMDS encoder
│   ├── tmds_serializer.v # 10:1 DDR TMDS serializer
│   ├── uart_rx.v         # UART receiver (8N1, parameterised baud rate)
│   ├── uart_tx.v         # UART transmitter (8N1, parameterised baud rate)
│   └── video_timing.v    # Video sync/timing generator
├── tests/                # RTL unit tests (cocotb)
│   ├── test_fft256/      # 256-point FFT engine tests
│   ├── test_i2s_clkgen/  # I2S clock generator tests
│   ├── test_i2s_rx/      # I2S receiver tests
│   ├── test_i2s_tx/      # I2S transmitter tests
│   └── test_pdm_cic/     # PDM CIC decimation filter tests
├── projects/             # FPGA projects
│   ├── 01_blinky/        # LED blinky example
│   ├── 02_hdmi_test/     # HDMI test pattern generator
│   ├── 03_i2s_direct_loopback/ # I2S direct bit-stream loopback
│   ├── 04_i2s_serdes_loopback/ # I2S mic-to-amp loopback
│   ├── 05_hdmi_graph/    # HDMI line graph display
│   ├── 06_live_fft/      # Live FFT spectrum analyzer
│   ├── 07_live_real_fft/ # Real-valued FFT (256 bins)
│   ├── 08_pdm_bitstream_loopback/ # Raw PDM bitstream loopback
│   ├── 09_pdm_pcm_loopback/ # PDM PCM loopback with signed gain and mute
│   ├── 10_pdm_to_i2s_loopback/ # PDM mic-to-I2S amp loopback
│   ├── 11_uart_loopback/ # UART loopback via iCELink USB-CDC
│   ├── 12_fft_uart/      # FFT spectrum over UART + Python display
│   │   └── display_fft.py # Host-side spectrum viewer (run outside container)
│   ├── 13_i2s_record_to_uart/ # Record I2S audio to BRAM, dump over UART
│   │   └── record_and_plot.py  # Host-side record, dump, and plot script
│   └── 14_pdm_hil/       # HIL transfer function characterizer
│       └── hil_test.py        # Host-side HIL measurement script
├── requirements.txt      # Python dependencies for host scripts
└── README.md
```

## Shared RTL Modules

Reusable modules live in `rtl/` and are shared across projects.

### I2S clock domain design

The three I2S modules (`i2s_clkgen`, `i2s_tx`, `i2s_rx`) all run in the **system clock domain**. Rather than treating `bclk` as a second clock, `i2s_clkgen` produces a `bclk_falling` strobe: a single-cycle pulse on every BCLK falling edge, expressed as a combinational signal in the system clock domain:

```verilog
wire bclk_toggle  = (bclk_counter == DIV_MAX);   // fires once per BCLK half-period
assign bclk_falling = bclk_toggle && bclk_reg;   // only when BCLK is currently high
```

`i2s_tx` and `i2s_rx` advance their state machines only when `bclk_falling` is asserted:

```verilog
if (bclk_falling) begin
    // shift one bit
end
```

This keeps all three modules in a single clock domain, which simplifies synthesis timing constraints and avoids the need for CDC (clock domain crossing) logic.

## License

See [LICENSE](LICENSE) file.

---

Built with [Claude Code](https://claude.ai/claude-code)
