# 05_live_fft - Live FFT Spectrum Display

Real-time audio spectrum analyzer. Reads audio from an SPH0645 I2S microphone, computes a 256-point FFT, and displays the frequency spectrum as a filled line graph on an HDMI display (800x480@60Hz).

## Architecture

```
clk_25m ──► PLL ──► clk_pixel (30 MHz) ──► video_timing (480x800 portrait)
                    clk_shift (150 MHz)         │
                                          pixel_x/y, sync
            i2s_clkgen                          │
              │                           coordinate rotation (landscape)
            i2s_rx                              │
              │                           graph_renderer ◄── display_ram ◄─┐
         24-bit samples                         │                          │
              │                           RGB + delayed sync               │
         truncate to 16-bit                     │                          │
              │                           TMDS encode (3ch)                │
           fft256 ──────────────────────────────┘                          │
              │         magnitude output (256 x 9-bit)                     │
              └────────────────────────────────────────────────────────────┘
                                          TMDS serialize (4ch)
                                                │
                                          HDMI output (gpdi_dp/dn)
```

## FFT Engine

- **Algorithm**: Radix-2 decimation-in-time (DIT) with bit-reversed input ordering
- **Size**: 256 points (128 unique frequency bins for real input)
- **Arithmetic**: 16-bit signed fixed-point, Q1.14 twiddle factors
- **Normalization**: 1/2 scaling per butterfly stage (1/N total)
- **Magnitude**: max(|Re|, |Im|) + min(|Re|, |Im|)/4 approximation
- **Timing**: ~3600 cycles (~144 us at 25 MHz) per FFT frame

### Data Flow

1. **Collect**: 256 audio samples stored at bit-reversed addresses (~5.2 ms at 48.8 kHz)
2. **Compute**: 8 butterfly stages x 128 butterflies x 3 cycles = 3072 cycles
3. **Magnitude**: 256 bins x 2 cycles = 512 cycles, scaled and capped at 440

### Twiddle Factors

`twiddle.hex` contains 128 entries of cos/sin pairs in Q1.14 fixed-point format. Regenerate with:

```bash
python gen_twiddle.py
```

## Video Timing

Same landscape 800x480 at 60 Hz as project 04, using portrait 480x800 timing with coordinate rotation.

## Pin Connections

| Signal | Site | Connector | Description |
|--------|------|-----------|-------------|
| mic_bclk | R7 | P4.5 | I2S bit clock |
| mic_lrclk | D5 | P4.7 | I2S word select |
| mic_data | D4 | P4.9 | I2S serial data |
| mic_sel | E4 | P4.11 | Channel select (low = left) |
| gpdi_dp/dn[0] | G1/F1 | HDMI | Blue TMDS |
| gpdi_dp/dn[1] | J1/H2 | HDMI | Green TMDS |
| gpdi_dp/dn[2] | L1/K2 | HDMI | Red TMDS |
| gpdi_dp/dn[3] | E2/D3 | HDMI | Clock TMDS |

## Status LEDs

| LED | Meaning |
|-----|---------|
| Green | PLL locked |
| Red | FFT computing (brief flash each frame) |

## Build

```bash
# From repo root (runs in Docker)
make build 05
make sim 05
make program 05
```
