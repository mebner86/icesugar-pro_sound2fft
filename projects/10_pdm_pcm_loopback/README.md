# 10 — PDM PCM Loopback

Extends [project 08](../08_pdm_bitstream_loopback/) by converting the PDM
bitstream to 16-bit PCM words, applying configurable gain, then re-modulating
back to PDM via a 2nd-order sigma-delta modulator before forwarding to the
MAX98358 PDM amplifier. The loopback now occurs at the PCM level, enabling
audio DSP in between.

Compare with [project 08](../08_pdm_bitstream_loopback/), which passes the
raw PDM bitstream through with no conversion, and [project 11](../11_pdm_to_i2s_loopback/),
which converts the same PDM stream to I2S and drives a different amplifier.

## Signal Flow

```
                3.125 MHz
FPGA ──── mic_clk ─────────────► MP34DT01-M
                                      │
FPGA ◄─── mic_dat ────────────────────┘ (PDM bitstream)
  │
  │  2-stage FF synchronizer (25 MHz)
  │
  ▼
CIC sinc³ decimation (R=64)              [rtl/pdm_cic.v]
  │  16-bit signed PCM @ 48.828 kHz
  │
  ▼
Gain: signed shift GAIN_SHIFT (~6 dB/step, ±, with saturation)
  │
  ▼
Zero-order hold (latch per pcm_valid)
  │
  ▼
2nd-order sigma-delta modulator          [rtl/pdm_modulator.v]
  │  1-bit PDM @ 3.125 MHz
  │
  ├──── amp_clk ─────────────► MAX98358
  └──── amp_dat ─────────────► MAX98358
```

## Gain and Mute

| Control | Mechanism |
|---------|-----------|
| **Gain** | `GAIN_SHIFT` synthesis parameter (signed integer, ~6 dB per step). |
| **Mute** | Hold the reset button (`rst_n` low). The design enters reset: the CIC and modulator zero out, and `amp_dat` goes to 0. Release to resume. |

The red LED lights while the button is held; the green LED lights during normal operation. Both are driven combinationally from `rst_n` so there is no latency.

### GAIN_SHIFT values

| `GAIN_SHIFT` | Effect | Use case |
|:---:|---|---|
| `+3` | +18 dB (amplify ×8, saturating) | Very quiet microphone |
| `+2` | +12 dB (amplify ×4, saturating) | Quiet environment |
| `+1` | +6 dB (amplify ×2, saturating) | Slight boost |
| `0` | Unity gain (default) | Normal use, matches project 08 |
| `-1` | −6 dB | Mild attenuation |
| `-4` | −24 dB | Open-air loopback (prevents feedback) |
| `-6` | −36 dB | Very loud microphone |

Amplification uses a left-shift with signed saturation clamping — when the shifted value exceeds the 16-bit signed range the output is clamped to `±32767 / −32768` rather than wrapping, preventing harsh distortion. Attenuation is a pure arithmetic right-shift (sign-preserving) with no saturation needed.

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
| `amp_dat` | J3 | output | Reconstructed PDM data to MAX98358 |

## Architecture

### PDM Clock

The shared `rtl/pdm_clkgen.v` module produces a 3.125 MHz clock (25 MHz / 8)
and a single-cycle `pdm_clk_rise` strobe every 8 system clocks, used as
`pdm_valid` by both the CIC and the modulator.

### CIC Decimation

A 3rd-order sinc³ CIC filter (from `rtl/pdm_cic.v`) decimates the 1-bit PDM
stream by 64, producing 16-bit signed PCM at 48.828 kHz.

| Parameter | Value |
|-----------|-------|
| Order (N) | 3 (sinc³) |
| Decimation ratio (R) | 64 |
| PDM clock | 3.125 MHz |
| Output sample rate | 48.828 kHz |
| Internal width | 20 bits signed |
| Output width | 16 bits (top 16 of 20) |

### Gain Block

`GAIN_SHIFT` is a signed integer parameter (~6 dB per step). The PCM sample
is sign-extended to 32 bits, shifted, then saturated back to 16 bits:

- **Amplification** (`GAIN_SHIFT > 0`): arithmetic left-shift with saturation
  clamp to `[−32768, +32767]`. Prevents harsh wrapping distortion when the
  signal clips.
- **Unity** (`GAIN_SHIFT = 0`): pass-through.
- **Attenuation** (`GAIN_SHIFT < 0`): arithmetic right-shift (sign-extending).
  Cannot overflow, so no saturation is needed.

### PDM Modulator

`rtl/pdm_modulator.v` with `ORDER=2` implements a 2nd-order CIFB
(Cascade of Integrators, FeedBack) sigma-delta modulator. It runs at the
PDM rate (3.125 MHz, driven by the same `pdm_valid` strobe as the CIC),
holding the PCM sample between updates.

The 2nd-order topology gives NTF = (1 − z⁻¹)², providing 40 dB/decade
noise shaping — double the 1st-order's 20 dB/decade. This significantly
reduces audible quantization hiss compared to the 1st-order modulator.

**Algorithm (each PDM clock cycle):**

```
sum1    = acc1 + pcm_in
sum2    = acc2 + sum1
pdm_out = (sum2 ≥ 0) ? 1 : 0
fb      = pdm_out ? +32768 : −32768
acc1    = clamp(sum1 − fb)          // clamp to ±2²³
acc2    = clamp(sum2 − fb)
```

Both integrators are clamped to ±2²³ to prevent runaway at extreme inputs.
The average duty cycle of `pdm_out` linearly tracks `pcm_in`:

| `pcm_in` | PDM duty cycle |
|----------|---------------|
| −32768   | ~0 %  (full negative) |
| 0        | ~50 % (silence) |
| +32767   | ~100 % (full positive) |

## Build

```bash
cd projects/10_pdm_pcm_loopback
make          # synthesize, place-and-route, generate bitstream
make sim      # run testbench with Icarus Verilog
make waves    # open VCD in GTKWave
make program  # flash to board via icesprog
make lint     # static analysis with Verilator
make clean    # remove build artifacts
```

Toolchain: Yosys · nextpnr-ecp5 · ecppack · icesprog · iverilog
