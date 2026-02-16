# 07_pdm_to_i2s_loopback

PDM-to-I2S audio loopback for the iCESugar-Pro board.

## Description

Reads audio from an MP34DT01-M PDM microphone, decimates the 1-bit PDM stream into 16-bit PCM samples using a 3rd-order CIC filter, then serializes and sends to a MAX98357A I2S amplifier. This creates a real-time audio passthrough from PDM mic to I2S speaker.

### Signal Flow

```
MP34DT01-M PDM mic
    │ pdm_dat (1-bit @ 3.125 MHz)
    ▼
2-stage synchronizer
    │
    ▼
CIC sinc³ decimation filter (R=64)
    │ integ1 → integ2 → integ3 → comb1 → comb2 → comb3
    │ 16-bit PCM @ 48.8 kHz
    ▼
Left-align to 24-bit
    │
    ▼
I2S TX → MAX98357A amplifier
```

### CIC Filter Architecture

A great resource for understanding CIC filters: [Understanding CIC Compensation Filters](https://www.dsprelated.com/showarticle/1337.php) on dsprelated.com.

The CIC (Cascaded Integrator-Comb) filter converts the oversampled 1-bit PDM stream into multi-bit PCM:

| Parameter | Value |
|-----------|-------|
| Order (N) | 3 (sinc³) |
| Decimation ratio (R) | 64 |
| PDM clock | 3.125 MHz (BCLK) |
| Output sample rate | 48.828 kHz |
| Internal width | 20 bits signed |
| Output width | 16 bits (top 16 of 20) |

The PDM input is mapped to signed values (+1/-1) to eliminate DC offset. Three integrator stages accumulate at the PDM rate, a decimation counter selects every 64th sample, and three comb stages compute cascaded differences at the output rate.

### Signal Mapping

#### MP34DT01-M PDM Microphone

| Signal | FPGA Port | Board Label | Direction |
|--------|-----------|-------------|-----------|
| Clock | `pdm_clk` | CLK | FPGA → Mic |
| Data | `pdm_dat` | DAT | Mic → FPGA |
| L/R select | `pdm_sel` | SEL | FPGA → Mic |

#### MAX98357A I2S Amplifier

| Signal | FPGA Port | Board Label | Direction |
|--------|-----------|-------------|-----------|
| Bit clock | `amp_bclk` | BCLK | FPGA → Amp |
| Word select | `amp_lrclk` | LRC | FPGA → Amp |
| Data out | `amp_din` | DIN | FPGA → Amp |
| Shutdown | `amp_sd` | SD | FPGA → Amp |
| Gain | `amp_gain` | GAIN | FPGA → Amp (tri-state) |

## Build

From the project root, use the top-level Makefile (runs in Docker automatically):

```bash
make build PROJECT=07_pdm_to_i2s_loopback   # Build bitstream
make sim PROJECT=07_pdm_to_i2s_loopback     # Run simulation
```

Or inside the Docker container (`make docker-shell`), run directly:

```bash
cd projects/07_pdm_to_i2s_loopback
make        # Synthesize, place & route, generate bitstream
make sim    # Run simulation (Icarus Verilog)
make lint   # Run Verilator linting
make clean  # Remove build artifacts
```

## View Simulation Waveforms

After running simulation, view the waveforms with GTKWave (see main README for installation):

```bash
gtkwave projects/07_pdm_to_i2s_loopback/pdm_to_i2s_loopback_tb.gtkw
```

The `.gtkw` save file preloads PDM, CIC internals (integrators, combs), and I2S output signals.

## Program

Run from the host (requires icesprog installed):

```bash
make program PROJECT=07_pdm_to_i2s_loopback
```

Or inside the project directory:

```bash
make program
```

## Pin Assignments

### PDM Microphone

| FPGA Site | Signal | Device |
|-----------|--------|--------|
| K4 | `pdm_sel` | Mic SEL |
| H3 | `pdm_clk` | Mic CLK |
| K3 | `pdm_dat` | Mic DAT |

### I2S Amplifier (P4 right column)

| P4 Pin | FPGA Site | Signal | Device |
|--------|-----------|--------|--------|
| P4.6 | R8 | `amp_bclk` | Amp BCLK |
| P4.8 | C4 | `amp_lrclk` | Amp LRC |
| P4.10 | C3 | `amp_din` | Amp DIN |
| P4.12 | E3 | `amp_sd` | Amp SD |
| P4.14 | F3 | `amp_gain` | Amp GAIN |
