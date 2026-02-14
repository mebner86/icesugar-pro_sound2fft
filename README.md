# icesugar-pro_sound2fft

[![CI](https://github.com/mebner86/icesugar-pro_sound2fft/actions/workflows/ci.yml/badge.svg)](https://github.com/mebner86/icesugar-pro_sound2fft/actions/workflows/ci.yml)

Real-time audio spectrum analyzer on the iCESugar-Pro (ECP5) FPGA — I2S microphone to HDMI display.


https://github.com/user-attachments/assets/a4d3b1ac-cda3-45de-9872-42211985f9db


## Overview

This project demonstrates real-time FFT visualization on an HDMI display, using audio input from an I2S microphone. It targets the iCESugar-Pro FPGA board and uses a fully open source toolchain.

## Requirements

- [Python 3](https://www.python.org/downloads/)
- [Docker](https://www.docker.com/get-started/)
- Make
- iCESugar-Pro FPGA board ([ECP5-25F](https://github.com/wuxx/icesugar-pro))
- I2S MEMS microphone (e.g., [SPH0645](https://www.adafruit.com/product/3421))
- I2S amplifier (e.g., [MAX98357A](https://www.adafruit.com/product/3006))
- HDMI display (e.g., [Waveshare 3.2inch HDMI LCD (H)](https://www.waveshare.com/3.2inch-hdmi-lcd-h.htm))

### Installing Make (Windows)

If you don't have `make` installed, you can install it with:

```bash
winget install ezwinports.make
```

Restart your terminal after installation for the command to become available.

## Quick Start

### 1. Build the Development Container

```bash
make docker-build
```

This builds a Docker container with the complete open source FPGA toolchain (Yosys, nextpnr-ecp5, Project Trellis, Icarus Verilog, Verilator, cocotb, Amaranth). All `make build/sim/clean/lint` commands invoke this container automatically — you do **not** need to enter the container first.

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

# Program the FPGA
make program 01

# Clean build artifacts
make clean 01    # Single project
make clean       # All projects
```

### Available Make Commands

| Command | Description |
|---------|-------------|
| `make list` | List available projects |
| `make build [<project>]` | Build bitstream (or all) |
| `make sim [<project>]` | Run simulation (or all) |
| `make clean [<project>]` | Clean build files (or all) |
| `make program <project>` | Program FPGA |
| `make upload <project> [DRIVE=<path>]` | Copy bitstream to USB drive (default `D:\`, Linux: `DRIVE=/media/$USER/iCESugar-Pro`) |
| `make setup` | Install pre-commit hooks |
| `make lint` | Run linters on all files |
| `make docker-build` | Build the FPGA toolchain container |
| `make docker-shell` | Open interactive shell in container |
| `make docker-down` | Stop and remove container |

### Interactive Docker Shell

For interactive debugging or running tools directly, you can open a shell inside the container:

```bash
make docker-shell
```

This opens a bash shell with the full toolchain available. The project directory is mounted at `/workspace`.

## Development Setup

### Python Environment

Python is needed on the host for pre-commit hooks (Ruff formatting/linting runs locally, Verilator linting runs via Docker). Create a virtual environment and install pre-commit:

```bash
python -m venv .venv

# Activate the environment
source .venv/bin/activate   # Linux/macOS
.venv\Scripts\activate      # Windows

pip install pre-commit
```

Then install the git hooks:

```bash
make setup
```

This enables automatic linting on commit:
- Trailing whitespace and EOF fixes
- YAML validation
- Verilog/SystemVerilog linting (Verilator, via Docker)
- Python formatting (Ruff)

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
| `03_i2s_loopback` | I2S mic-to-amp loopback via parallel samples (SPH0645 → MAX98357A) |
| `04_hdmi_graph` | HDMI line graph display (portrait timing, rotated to landscape) |
| `05_live_fft` | Live FFT spectrum analyzer (I2S mic → 256-point FFT → 128-bin HDMI graph) |
| `06_live_real_fft` | Real-valued FFT optimization (512-point real FFT via 256-point complex → 256-bin display) |

## Project Structure

```
icesugar-pro_sound2fft/
├── Makefile              # Top-level build orchestration
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
│   ├── pll.v             # PLL for pixel/shift clocks
│   ├── tmds_encoder.v    # DVI/HDMI 8b/10b TMDS encoder
│   ├── tmds_serializer.v # 10:1 DDR TMDS serializer
│   └── video_timing.v    # Video sync/timing generator
├── projects/             # FPGA projects
│   ├── 01_blinky/        # LED blinky example
│   ├── 02_hdmi_test/     # HDMI test pattern generator
│   ├── 03_i2s_loopback/  # I2S mic-to-amp loopback
│   ├── 04_hdmi_graph/    # HDMI line graph display
│   ├── 05_live_fft/      # Live FFT spectrum analyzer
│   └── 06_live_real_fft/ # Real-valued FFT (256 bins)
└── README.md
```

## License

See [LICENSE](LICENSE) file.

---

Built with [Claude Code](https://claude.ai/claude-code)
