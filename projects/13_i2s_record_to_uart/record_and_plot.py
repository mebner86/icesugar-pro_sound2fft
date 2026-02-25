#!/usr/bin/env python3
"""Record a block of audio from the FPGA and plot the waveform + spectrum."""

import argparse
import struct
import sys
import time

import numpy as np
import matplotlib.pyplot as plt
import serial

SAMPLE_RATE = 48_828  # Hz  (CLK_DIV=4)
NUM_SAMPLES = 4096
BAUD_RATE = 115_200
RECORD_WAIT_S = 0.12  # slightly more than the ~84 ms record window
DUMP_BYTES = NUM_SAMPLES * 2


def record_and_dump(port: str) -> np.ndarray:
    print(f"Opening {port} at {BAUD_RATE} baud …")
    with serial.Serial(port, BAUD_RATE, timeout=2) as s:
        s.reset_input_buffer()

        print("Sending 'R' (record) …")
        s.write(b"R")
        time.sleep(RECORD_WAIT_S)

        print("Sending 'D' (dump) …")
        s.write(b"D")

        raw = s.read(DUMP_BYTES)

    if len(raw) != DUMP_BYTES:
        print(f"ERROR: expected {DUMP_BYTES} bytes, got {len(raw)}", file=sys.stderr)
        sys.exit(1)

    # Big-endian signed 16-bit
    samples = np.array(struct.unpack(f">{NUM_SAMPLES}h", raw), dtype=np.float32)
    print(
        f"Received {NUM_SAMPLES} samples  "
        f"(min={samples.min():.0f}, max={samples.max():.0f}, "
        f"rms={np.sqrt(np.mean(samples**2)):.1f})"
    )
    return samples


def plot(samples: np.ndarray) -> None:
    t = np.arange(NUM_SAMPLES) / SAMPLE_RATE * 1000  # ms

    # Remove DC before FFT and waveform display
    samples_ac = samples - samples.mean()

    # FFT (one-sided)
    window = np.hanning(NUM_SAMPLES)
    fft_mag = np.abs(np.fft.rfft(samples_ac * window))
    fft_db = 20 * np.log10(fft_mag / fft_mag.max() + 1e-9)
    freqs = np.fft.rfftfreq(NUM_SAMPLES, d=1.0 / SAMPLE_RATE)

    fig, (ax_t, ax_f) = plt.subplots(2, 1, figsize=(10, 7))
    fig.suptitle(f"I2S capture — {NUM_SAMPLES} samples @ {SAMPLE_RATE} Hz")

    # --- Waveform ---
    ax_t.plot(t, samples_ac, linewidth=0.6)
    ax_t.set_xlabel("Time (ms)")
    ax_t.set_ylabel("Amplitude (counts, DC removed)")
    ax_t.set_title(f"Waveform  (DC offset: {samples.mean():.0f} counts)")
    ax_t.set_xlim(t[0], t[-1])
    ax_t.grid(True, alpha=0.3)

    # --- Spectrum ---
    ax_f.plot(freqs / 1000, fft_db, linewidth=0.7)
    ax_f.set_xlabel("Frequency (kHz)")
    ax_f.set_ylabel("Magnitude (dBFS)")
    ax_f.set_title("Spectrum (Hanning window)")
    ax_f.set_xlim(0, SAMPLE_RATE / 2000)
    ax_f.set_ylim(-90, 5)
    ax_f.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.show()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "port",
        nargs="?",
        default="/dev/ttyACM0",
        help="Serial port (default: /dev/ttyACM0)",
    )
    parser.add_argument(
        "--save",
        metavar="FILE",
        help="Save raw 16-bit PCM to FILE (for use with sox etc.)",
    )
    args = parser.parse_args()

    samples = record_and_dump(args.port)

    if args.save:
        raw = struct.pack(f">{NUM_SAMPLES}h", *samples.astype(np.int16))
        with open(args.save, "wb") as f:
            f.write(raw)
        print(f"Raw PCM saved to {args.save}")
        print(f"  sox -r {SAMPLE_RATE} -e signed -b 16 -c 1 {args.save} out.wav")

    plot(samples)


if __name__ == "__main__":
    main()
