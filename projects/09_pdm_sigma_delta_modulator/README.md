# 09 — PDM Sigma-Delta Modulator

Demonstrates the shared `rtl/pdm_modulator.v` sigma-delta modulator in isolation
by feeding a 64-sample sine ROM through the modulator to the MAX98358 PDM
amplifier, producing a steady **~763 Hz** tone. No microphone and no CIC filter
are involved — the design exercises only the PDM clock generator and the
sigma-delta modulator.

The `ORDER` parameter selects 1st-order (20 dB/decade noise shaping) or
2nd-order (40 dB/decade). Default is 2nd-order.

## Signal Flow

```
ROM [64 × 16-bit sine]
        │  pcm_valid (~48.828 kHz)
        ▼
  zero-order hold (pcm_held) ──► sigma-delta modulator ──► amp_clk/dat ──► MAX98358
```

## Tone Parameters

| Parameter | Value |
|-----------|-------|
| PDM clock | 3.125 MHz (25 MHz / 8) |
| PCM (ZOH) rate | 48,828 Hz (PDM clock / 64) |
| Sine table depth | 64 samples |
| Tone frequency | 48,828 / 64 ≈ **763 Hz** |
| Sample width | 16-bit signed |
| Full-scale amplitude | 32,767 |
| Output amplitude | 32,767 ÷ 32 ≈ **1,023** (−30 dB) |

The amplitude is reduced by `>>> 5` (arithmetic right-shift by 5, i.e. ÷32) in the
zero-order hold latch before the sigma-delta modulator.  Adjust the shift count to
change volume in ~6 dB steps.

## LED Indicators (active-low)

| rst_n | Red | Green | Meaning |
|-------|:---:|:-----:|---------|
| 0 (button held) | **on** | off | Reset / muted — sigma-delta zeroed |
| 1 (running) | off | **on** | Replaying sine tone |

Blue LED is always off.

## Hardware

Only the amplifier is needed; the microphone is not used.

| Signal | FPGA Site | Direction |
|--------|-----------|-----------|
| `clk_25m` | P6 | input |
| `rst_n` | L14 | input (user button, active-low) |
| `led_r` | B11 | output (active-low) |
| `led_g` | A11 | output (active-low) |
| `led_b` | A12 | output (active-low, always off) |
| `amp_clk` | J4 | output |
| `amp_dat` | J3 | output |

## Build

```bash
cd projects/09_pdm_sigma_delta_modulator
make          # synthesise, place & route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open GTKWave (requires make sim first)
make lint     # Verilator static analysis
make program  # flash to board via icesprog
make clean    # remove build artefacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog · verilator

## Interactive Python Demo

`sigma_delta_demo.py` is a cell-based Python script (use `# %%` cells in
VS Code with the Jupyter extension) that walks through sigma-delta modulation
step by step:

1. Generate a 16-bit sine wave test signal
2. Run 1st-order and 2nd-order sigma-delta modulators
3. Visualise PDM bitstream density
4. Recover the original signal with a moving-average (CIC-like) filter
5. Compare quantisation noise spectra (20 vs 40 dB/decade shaping)
6. Plot SNR vs oversampling ratio

The algorithms match the Verilog implementation in `rtl/pdm_modulator.v`
exactly, making it easy to verify RTL behaviour against a Python reference.

Requires: `pip install numpy matplotlib scipy` (see `requirements.txt`).

## Simulation

The testbench (`pdm_sigma_delta_modulator_tb.v`) runs for 2 complete sine periods
(2 × 64 × 512 = 65,536 system clocks after reset) and checks:

- Green LED on, red LED off during operation.
- `amp_dat` has many transitions (sigma-delta active).
- `pcm_held` reaches the positive sine peak (≥ +870 after ÷32).
- `pcm_held` reaches the negative sine peak (≤ −870 after ÷32).
- `sine_addr` is in the valid range 0..63.

Expected output:

```
OK   [leds]: green=on red=off during operation
OK   [amp_dat]: XXXX transitions over 2 sine periods
OK   [positive peak]: pcm_held reached sine maximum
OK   [negative peak]: pcm_held reached sine minimum
OK   [sine_addr]: 0 (in valid range 0..63)

PASS: all checks passed.
```
