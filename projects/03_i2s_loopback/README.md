# 03_i2s_loopback

I2S audio loopback for the iCESugar-Pro board.

## Description

Reads audio from an SPH0645 MEMS microphone over I2S and forwards it directly to a MAX98357A I2S amplifier. This creates a real-time audio passthrough from mic to speaker.

### I2S Signal Mapping

| Signal | FPGA Port | Mic Board Label | Amp Board Label | Direction |
|--------|-----------|-----------------|-----------------|-----------|
| Bit clock | `mic_bclk` | BCLK | — | FPGA → Mic |
| Word select | `mic_lrclk` | LRCL | — | FPGA → Mic |
| Data in | `mic_data` | DOUT | — | Mic → FPGA |
| Channel select | `mic_sel` | SEL | — | FPGA → Mic |
| Bit clock | `amp_bclk` | — | BCLK | FPGA → Amp |
| Word select | `amp_lrclk` | — | LRC | FPGA → Amp |
| Data out | `amp_din` | — | DIN | FPGA → Amp |
| Shutdown | `amp_sd` | — | SD | FPGA → Amp |
| Gain | `amp_gain` | — | GAIN | FPGA → Amp (tri-state) |

### Non-FPGA Pins

| Board | Label | Connection |
|-------|-------|------------|
| Mic | 3V | 3V3 (P4.1) |
| Mic | GND | GND (P4.3) |
| Amp | Vin | 3V3 (P4.2) |
| Amp | GND | GND (P4.4) |

## Build

From the project root, use the top-level Makefile (runs in Docker automatically):

```bash
make build PROJECT=03_i2s_loopback   # Build bitstream
make sim PROJECT=03_i2s_loopback     # Run simulation
```

Or inside the Docker container (`make docker-shell`), run directly:

```bash
cd projects/03_i2s_loopback
make        # Synthesize, place & route, generate bitstream
make sim    # Run simulation (Icarus Verilog)
make lint   # Run Verilator linting
make clean  # Remove build artifacts
```

## View Simulation Waveforms

After running simulation, view the waveforms with GTKWave (see main README for installation):

```bash
gtkwave projects/03_i2s_loopback/i2s_loopback_tb.gtkw
```

The `.gtkw` save file preloads signals and sets a reasonable zoom level.

## Program

Run from the host (requires icesprog installed):

```bash
make program PROJECT=03_i2s_loopback
```

Or inside the project directory:

```bash
make program
```

## Pin Assignments (Connector P4)

All I2S signals use connector P4. Mic on the left column, amp on the right:

| P4 Pin | FPGA Site | Signal | Device |
|--------|-----------|--------|--------|
| P4.1 | — | 3V3 | Mic 3V |
| P4.2 | — | 3V3 | Amp Vin |
| P4.3 | — | GND | Mic GND |
| P4.4 | — | GND | Amp GND |
| P4.5 | R7 | `mic_bclk` | Mic BCLK |
| P4.6 | R8 | `amp_bclk` | Amp BCLK |
| P4.7 | D5 | `mic_lrclk` | Mic LRCL |
| P4.8 | C4 | `amp_lrclk` | Amp LRC |
| P4.9 | D4 | `mic_data` | Mic DOUT |
| P4.10 | C3 | `amp_din` | Amp DIN |
| P4.11 | E4 | `mic_sel` | Mic SEL |
| P4.12 | E3 | `amp_sd` | Amp SD |
| P4.14 | F3 | `amp_gain` | Amp GAIN |
