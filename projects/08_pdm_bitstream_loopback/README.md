# 08 — PDM Bitstream Loopback

Routes the raw PDM bitstream from an MP34DT01-M microphone directly to a MAX98358 PDM amplifier with no decimation or DSP. The FPGA acts purely as a clock source and CDC synchronizer.

Compare with [project 10](../10_pdm_to_i2s_loopback/), which converts the same PDM microphone signal to I2S via a CIC filter.

## Signal Flow

```
                 3.125 MHz
FPGA ──── mic_clk ─────────────► MP34DT01-M
                                       │
FPGA ◄─── mic_dat ─────────────────────┘ (PDM bitstream, data valid on CLK rising edge)
  │
  │  2-stage FF synchronizer (25 MHz, +80 ns)
  │
  ├──── amp_clk ─────────────► MAX98358
  └──── amp_dat ─────────────► MAX98358
```

The MAX98358 samples left-channel data on the PDM_CLK rising edge, which matches the microphone output polarity (`mic_sel = 0`).

## Hardware

| Device | Interface | Notes |
|--------|-----------|-------|
| MP34DT01-M | PDM output | On-board mic module |
| MAX98358 | PDM input | Speaker amp on Port4 |

### Port4 Pin Assignments

| Signal | FPGA Site | Direction | Description |
|--------|-----------|-----------|-------------|
| `mic_clk` | H3 | output | PDM clock to microphone |
| `mic_dat` | K3 | input  | PDM data from microphone |
| `mic_sel` | K4 | output | Channel select (tied low = left) |
| `amp_clk` | J4 | output | PDM clock to MAX98358 |
| `amp_dat` | J3 | output | PDM data to MAX98358 |

The MAX98358 SD_MODE pin is pulled to 3.3 V via a 2 kΩ resistor on the module (amplifier always enabled; no FPGA pin required).

## Architecture

### PDM Clock

The shared `rtl/pdm_clkgen.v` module produces a 3.125 MHz clock (25 MHz / 8). This is within the valid range for both devices:

- MP34DT01-M: 1.0–3.25 MHz
- MAX98358: see datasheet Table 2 for PDM_CLK rates

Both `mic_clk` and `amp_clk` are driven from the same register, so they are phase-aligned.

### CDC Synchronizer

`mic_dat` is an asynchronous input from the microphone. A two-stage flip-flop synchronizer (clocked at 25 MHz) eliminates metastability before forwarding the bit to the amplifier. The added latency (2 × 40 ns = 80 ns) is negligible relative to the 160 ns PDM clock half-period.

## Build

```bash
cd projects/08_pdm_bitstream_loopback
make          # synthesize, place-and-route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open VCD in GTKWave
make program  # flash to board via icesprog
make lint     # static analysis with Verilator
make clean    # remove build artifacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog
