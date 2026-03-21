# 16 — PDM Replay (Sine Tone Generator)

Continuously replays a 64-sample 16-bit signed sine wave stored in on-chip ROM
through the MAX98358 PDM amplifier, producing a steady **~763 Hz** tone.
No microphone and no UART are involved — the design is entirely self-contained.

Useful as a signal source for acoustic experiments (e.g. feeding a spectrum
analyser to verify the PDM→speaker chain is working correctly).

## Signal Flow

```
ROM [64 × 16-bit sine]
        │  pcm_valid (~48.828 kHz)
        ▼
  zero-order hold (pcm_held) ──► 1st-order sigma-delta ──► amp_clk/dat ──► MAX98358
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
change volume in ~6 dB steps:

| Shift | Divisor | Approx. level |
|-------|---------|---------------|
| `>>> 0` | 1 | 0 dB (full scale) |
| `>>> 1` | 2 | −6 dB |
| `>>> 3` | 8 | −18 dB |
| `>>> 5` | 32 | −30 dB ← current |
| `>>> 6` | 64 | −36 dB |

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

## Architecture

### Sine ROM

A 64 × 16-bit read-only memory initialised with `initial` assignments:

```
v[k] = round(32767 × sin(2π × k / 64))   k = 0..63
```

With no write ports, Yosys infers this as a LUT-based ROM (1 kbit).

### PCM-rate Divider

A 6-bit counter (`dec_cnt`) increments on every `pdm_valid` strobe and fires
`pcm_valid` every 64 counts, dividing the 3.125 MHz PDM clock down to the
~48.828 kHz sample rate at which the sine address advances.

### Sigma-Delta Modulator

`rtl/pdm_modulator.v` — 1st-order error-feedback, runs at the 3.125 MHz PDM
rate.  The zero-order hold (`pcm_held`) supplies a constant input between
`pcm_valid` updates.

## Build

```bash
cd projects/16_pdm_replay
make          # synthesise, place & route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open GTKWave (requires make sim first)
make lint     # Verilator static analysis
make program  # flash to board via icesprog
make clean    # remove build artefacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog · verilator

## Simulation

The testbench (`pdm_replay_tb.v`) runs for 2 complete sine periods
(2 × 64 × 512 = 65,536 system clocks after reset) and checks:

- Green LED on, red LED off during replay.
- `amp_dat` has many transitions (sigma-delta active).
- `pcm_held` reaches the positive sine peak (≥ +870 after ÷32).
- `pcm_held` reaches the negative sine peak (≤ −870 after ÷32).
- `sine_addr` is in the valid range 0..63.

Expected output:

```
OK   [leds]: green=on red=off during replay
OK   [amp_dat]: XXXX transitions over 2 sine periods
OK   [positive peak]: pcm_held reached sine maximum
OK   [negative peak]: pcm_held reached sine minimum
OK   [sine_addr]: 0 (in valid range 0..63)

PASS: all checks passed.
```
