#!/usr/bin/env python3
"""Generate static FFT-like test data for the HDMI graph display.

Produces fft_test_data.hex: 256 bins, 9-bit values (0-440) representing
a synthetic audio spectrum with several peaks on a noise floor.
"""

import math
import os
import random

NUM_BINS = 256
MAX_VAL = 440
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "fft_test_data.hex")

# Reproducible output
random.seed(42)


def gaussian(x, center, sigma, amplitude):
    return amplitude * math.exp(-0.5 * ((x - center) / sigma) ** 2)


data = []
for i in range(NUM_BINS):
    # Noise floor (slight random variation)
    val = random.uniform(15, 45)

    # Spectral peaks (center, sigma, amplitude)
    val += gaussian(i, 28, 7, 340)  # Strong fundamental
    val += gaussian(i, 58, 5, 200)  # 2nd harmonic
    val += gaussian(i, 90, 4, 140)  # 3rd harmonic
    val += gaussian(i, 130, 10, 80)  # Broad mid-range
    val += gaussian(i, 185, 5, 60)  # Weak high peak

    # High-frequency roll-off
    val *= math.exp(-i / 350)

    # Clamp to valid range
    val = max(0, min(MAX_VAL, int(val)))
    data.append(val)

with open(OUTPUT_FILE, "w") as f:
    for v in data:
        f.write(f"{v:03X}\n")

print(f"Wrote {NUM_BINS} values to {OUTPUT_FILE} (range 0-{MAX_VAL})")
