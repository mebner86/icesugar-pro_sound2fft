#!/usr/bin/env python3
"""Generate twiddle factor ROM for 512-point real FFT (via 256-point complex FFT).

Outputs twiddle.hex with 256 entries, one per line.
Each entry is 32-bit hex: upper 16 bits = cos, lower 16 bits = sin.
Values are in signed Q1.14 fixed-point format (scale factor 2^14 = 16384).

Twiddle factor: W_512^k = cos(2*pi*k/512) - j*sin(2*pi*k/512)
We store cos and sin (positive sin); the butterfly applies the sign.

The 256-point butterfly stages access W_256^j = W_512^(2j) at even addresses.
The unscramble stage accesses W_512^k directly.
"""

import math

N = 512
SCALE = 2**14  # Q1.14 fixed-point


def to_u16(val):
    """Convert signed 16-bit integer to unsigned for hex output."""
    return val & 0xFFFF


with open("twiddle.hex", "w") as f:
    for k in range(N // 2):
        angle = 2 * math.pi * k / N
        cos_val = round(math.cos(angle) * SCALE)
        sin_val = round(math.sin(angle) * SCALE)
        # Clamp to signed 16-bit range
        cos_val = max(-32768, min(32767, cos_val))
        sin_val = max(-32768, min(32767, sin_val))
        f.write(f"{to_u16(cos_val):04x}{to_u16(sin_val):04x}\n")

print(f"Generated twiddle.hex: {N // 2} entries for {N}-point real FFT")
