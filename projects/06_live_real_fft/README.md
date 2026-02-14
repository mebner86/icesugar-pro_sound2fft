# 06_live_real_fft - Real-valued FFT Spectrum Display

Real-time audio spectrum analyzer with double the frequency resolution of project 05. Exploits the real-valued property of audio input to compute a **512-point real FFT using a 256-point complex FFT engine**, producing 256 unique frequency bins with no additional block RAM — compared to the naive approach of doubling the complex FFT size.

## Difference from Project 05

| | 05_live_fft | 06_live_real_fft |
|---|---|---|
| FFT type | 256-point complex | 512-point real (via 256-point complex) |
| Output bins | 128 (unique half) | 256 (full unique spectrum) |
| Pixels per bin | 6 | 3 |
| Sample collection | 256 samples (~5.2 ms) | 512 samples (~10.4 ms) |
| FFT working RAM | 2x 256x16-bit | 2x 256x16-bit (same) |
| Twiddle ROM | 128 entries | 256 entries |
| Frame rate | ~192 Hz | ~93 Hz |

The key insight: for real-valued input, `X[k] = conj(X[N-k])`, so half the output bins of a complex FFT are redundant. By packing two real samples into one complex value (`z[n] = x[2n] + j*x[2n+1]`), a 256-point complex FFT followed by a post-processing "unscramble" step recovers all 256 unique bins of a 512-point real DFT.

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
         fft_real512 ─────────────────────────────┘                        │
              │         log2 magnitude (256 bins x 9-bit)                  │
              └────────────────────────────────────────────────────────────┘
                                          TMDS serialize (4ch)
                                                │
                                          HDMI output (gpdi_dp/dn)
```

## FFT Engine (fft_real512)

- **Algorithm**: Radix-2 DIT complex FFT + real-valued unscramble post-processing
- **Size**: 512 real samples → 256 unique frequency bins
- **Arithmetic**: 16-bit signed fixed-point, Q1.14 twiddle factors
- **Normalization**: 1/2 scaling per butterfly stage (1/N total)
- **Magnitude**: max(|Re|, |Im|) + min(|Re|, |Im|)/4 approximation, then log2 (4.4 fixed-point)
- **Dynamic range**: ~96 dB (16-bit log2), mapped to 440 pixel height (~4.6 px/dB)
- **Timing**: ~4400 cycles (~176 us at 25 MHz) per FFT frame

### Data Flow

1. **Collect**: 512 real samples packed pairwise into 256 complex values at bit-reversed addresses (~10.4 ms at 48.8 kHz)
2. **Compute**: 8 butterfly stages x 128 butterflies x 3 cycles = 3072 cycles (identical to fft256)
3. **Unscramble + Magnitude**: For each bin k (0-255), read Z[k] and Z[(256-k)%256], compute Ze/Zo decomposition, apply W_512^k twiddle, compute log2 magnitude — 3 cycles per bin = 768 cycles

### Unscramble Algorithm

Given 256-point complex FFT result Z[k]:

```
Ze[k] = (Z[k] + Z*[(256-k) % 256]) / 2     -- even-indexed sub-DFT
Zo[k] = (Z[k] - Z*[(256-k) % 256]) / (2j)   -- odd-indexed sub-DFT
X[k]  = Ze[k] + W_512^k * Zo[k]              -- 512-point real DFT bin
```

### Twiddle Factors

`twiddle.hex` contains 256 entries of W_512^k (cos/sin pairs in Q1.14 format). The butterfly stages access W_256^j = W_512^(2j) at even addresses; the unscramble step accesses W_512^k directly. Regenerate with:

```bash
python gen_twiddle.py
```

## Video Timing

Same landscape 800x480 at 60 Hz as projects 04 and 05, using portrait 480x800 timing with coordinate rotation.

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
make build 06
make sim 06
make program 06
```
