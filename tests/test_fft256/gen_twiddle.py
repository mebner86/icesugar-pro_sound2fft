#!/usr/bin/env python3
"""Generate twiddle factor ROM for 256-point FFT.

Uses numpy for the trigonometric values so the result is backed by a
well-tested, widely-used library rather than a hand-rolled formula.

Outputs twiddle.hex with 128 entries, one per line.
Each entry is 32-bit hex: upper 16 bits = cos, lower 16 bits = sin.
Values are in signed Q1.14 fixed-point format (scale factor 2^14 = 16384).

Twiddle factor: W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)
We store cos and sin (positive sin); the butterfly applies the sign.
"""

import numpy as np

N = 256
SCALE = 2**14  # Q1.14 fixed-point

k = np.arange(N // 2)
angles = 2 * np.pi * k / N
cos_vals = np.clip(np.round(np.cos(angles) * SCALE), -32768, 32767).astype(np.int32)
sin_vals = np.clip(np.round(np.sin(angles) * SCALE), -32768, 32767).astype(np.int32)

with open("twiddle.hex", "w") as f:
    for c, s in zip(cos_vals, sin_vals):
        f.write(f"{int(c) & 0xFFFF:04x}{int(s) & 0xFFFF:04x}\n")

print(f"Generated twiddle.hex: {N // 2} entries for {N}-point FFT")
