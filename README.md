# icesugar-pro_sound2fft

FPGA FFT demo via HDMI from I2S microphone on the iCESugar-Pro (ECP5) board.

## Overview

This project demonstrates real-time FFT visualization on an HDMI display, using audio input from an I2S microphone. It targets the iCESugar-Pro FPGA board and uses a fully open source toolchain.

## Requirements

- Docker
- iCESugar-Pro FPGA board (ECP5-25F)
- I2S MEMS microphone (e.g., INMP441)
- HDMI display

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

### Available Make Commands

| Command | Description |
|---------|-------------|
| `make docker-build` | Build the FPGA toolchain container |
| `make docker-shell` | Open interactive shell in container |
| `make docker-down` | Stop and remove container |

## Project Structure

```
icesugar-pro_sound2fft/
├── Makefile              # Top-level build orchestration
├── docker/
│   ├── Dockerfile        # FPGA toolchain container
│   └── docker-compose.yml
└── README.md
```

## License

See [LICENSE](LICENSE) file.
