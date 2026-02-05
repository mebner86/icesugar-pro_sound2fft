# icesugar-pro_sound2fft

FPGA FFT demo via HDMI from I2S microphone on the iCESugar-Pro (ECP5) board.

## Overview

This project demonstrates real-time FFT visualization on an HDMI display, using audio input from an I2S microphone. It targets the iCESugar-Pro FPGA board and uses a fully open source toolchain.

## Requirements

- Docker
- Make
- iCESugar-Pro FPGA board (ECP5-25F)
- I2S MEMS microphone (e.g., INMP441)
- HDMI display

### Installing Make (Windows)

If you don't have `make` installed, you can install it with:

```bash
winget install ezwinports.make
```

Restart your terminal after installation for the command to become available.

## Quick Start

### Build the Development Container

```bash
make docker-build
```

This builds a Docker container with the complete open source FPGA toolchain:

- **Yosys** - Synthesis
- **nextpnr-ecp5** - Place & Route
- **Project Trellis** - ECP5 bitstream tools
- **Icarus Verilog** - Simulation
- **Verilator** - Fast simulation/linting
- **cocotb** - Python testbench framework
- **Amaranth** - Python HDL (optional)

### Enter the Container

```bash
make docker-shell
```

This opens an interactive shell with all tools available. The project directory is mounted at `/workspace`.

### Building a Project

```bash
# List available projects
make list-projects

# Build a project (inside container or with tools installed)
make build PROJECT=01_blinky

# Run simulation
make sim PROJECT=01_blinky

# View simulation waveforms (requires GTKWave on host)
gtkwave projects/01_blinky/top_tb.gtkw

# Program the FPGA
make program PROJECT=01_blinky

# Clean build artifacts
make clean PROJECT=01_blinky  # Single project
make clean                     # All projects
```

### Available Make Commands

| Command | Description |
|---------|-------------|
| `make build PROJECT=<name>` | Build bitstream for a project |
| `make sim PROJECT=<name>` | Run simulation for a project |
| `make program PROJECT=<name>` | Program FPGA with a project |
| `make clean PROJECT=<name>` | Clean project build files |
| `make clean` | Clean all projects |
| `make list-projects` | List available projects |
| `make setup` | Install pre-commit hooks |
| `make lint` | Run linters on all files |
| `make docker-build` | Build the FPGA toolchain container |
| `make docker-shell` | Open interactive shell in container |
| `make docker-down` | Stop and remove container |

## Development Setup

### Optional Host Tools

For viewing simulation waveforms, install GTKWave:

```bash
sudo apt install gtkwave   # Debian/Ubuntu
brew install gtkwave       # macOS
```

### Pre-commit Hooks

First, install [pre-commit](https://pre-commit.com/):

```bash
# Using pipx (recommended)
pipx install pre-commit

# Or using pip
pip install pre-commit

# Or using your package manager
brew install pre-commit  # macOS
apt install pre-commit   # Debian/Ubuntu
```

Then install the git hooks:

```bash
make setup
```

This enables automatic linting on commit:
- Trailing whitespace and EOF fixes
- YAML validation
- Verilog/SystemVerilog linting (Verilator)
- Python formatting (Ruff)

## Project Structure

```
icesugar-pro_sound2fft/
├── Makefile              # Top-level build orchestration
├── docker/
│   ├── Dockerfile        # FPGA toolchain container
│   └── docker-compose.yml
├── projects/             # FPGA projects
│   └── 01_blinky/        # LED blinky example
│       ├── Makefile      # Project-specific build
│       ├── top.v         # Top-level module
│       ├── top_tb.v      # Testbench
│       └── icesugar_pro.lpf  # Pin constraints
└── README.md
```

## License

See [LICENSE](LICENSE) file.
