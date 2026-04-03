#!/usr/bin/env python3
"""
create_input.py — Generate input CSV files for fpgactrl.

Writes a two-column CSV (time_s, speaker) that fpgactrl run -input can consume.

Usage:
  python3 create_input.py chirp  [options]
  python3 create_input.py sine   [options]
  python3 create_input.py noise  [options]

Common options (all signals):
  -o / --output FILE       Output CSV path          (default: <signal>.csv)
  -n / --samples N         Number of samples        (default: 4096)
  --fs FLOAT               Sample rate in Hz        (default: 48828.0)
  -a / --amplitude FLOAT   Peak amplitude 0.0–1.0   (default: 0.9)

Chirp options:
  --f0 FLOAT               Start frequency in Hz    (default: 200.0)
  --f1 FLOAT               Stop frequency in Hz     (default: 20000.0)

Sine options:
  --freq FLOAT             Sine frequency in Hz     (default: 1000.0)

Noise options:
  --seed INT               RNG seed for repeatability (default: 42)
"""

import argparse
import csv
import math
import sys

SAMPLE_RATE = 48_828.0
NUM_SAMPLES = 4096


# ---------------------------------------------------------------------------
# Signal generators
# ---------------------------------------------------------------------------


def gen_chirp(n, fs, f0, f1, amplitude):
    """Log-frequency sweep from f0 to f1 over n samples."""
    T = n / fs
    log_ratio = math.log(f1 / f0)
    out = []
    for i in range(n):
        phase = 2 * math.pi * f0 * T / log_ratio * (math.exp(i / n * log_ratio) - 1)
        out.append(amplitude * math.sin(phase))
    return out


def gen_sine(n, fs, freq, amplitude):
    """Continuous sine wave at the given frequency."""
    out = []
    for i in range(n):
        out.append(amplitude * math.sin(2 * math.pi * freq * i / fs))
    return out


def gen_noise(n, amplitude, seed):
    """Band-limited white noise (DC-removed, normalised)."""
    import random

    rng = random.Random(seed)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    mean = sum(raw) / n
    raw = [v - mean for v in raw]
    peak = max(abs(v) for v in raw)
    return [v / peak * amplitude for v in raw]


# ---------------------------------------------------------------------------
# CSV writer
# ---------------------------------------------------------------------------


def write_csv(path, fs, samples):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time_s", "speaker"])
        for i, v in enumerate(samples):
            w.writerow([f"{i / fs:.18e}", f"{v:.18e}"])
    print(f"Wrote {len(samples)} samples → {path}")


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------


def add_common_args(p):
    p.add_argument(
        "-o", "--output", default=None, help="Output CSV file (default: <signal>.csv)"
    )
    p.add_argument(
        "-n",
        "--samples",
        type=int,
        default=NUM_SAMPLES,
        help=f"Number of samples (default: {NUM_SAMPLES})",
    )
    p.add_argument(
        "--fs",
        type=float,
        default=SAMPLE_RATE,
        help=f"Sample rate in Hz (default: {SAMPLE_RATE})",
    )
    p.add_argument(
        "-a",
        "--amplitude",
        type=float,
        default=0.9,
        help="Peak amplitude 0.0–1.0 (default: 0.9)",
    )


def main():
    parser = argparse.ArgumentParser(
        description="Generate input CSV files for fpgactrl",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="signal", metavar="signal")
    sub.required = True

    # -- chirp ----------------------------------------------------------------
    p_chirp = sub.add_parser("chirp", help="Log-frequency sweep")
    add_common_args(p_chirp)
    p_chirp.add_argument(
        "--f0", type=float, default=200.0, help="Start frequency in Hz (default: 200)"
    )
    p_chirp.add_argument(
        "--f1",
        type=float,
        default=20_000.0,
        help="Stop frequency in Hz (default: 20000)",
    )

    # -- sine -----------------------------------------------------------------
    p_sine = sub.add_parser("sine", help="Continuous sine wave")
    add_common_args(p_sine)
    p_sine.add_argument(
        "--freq", type=float, default=1_000.0, help="Frequency in Hz (default: 1000)"
    )

    # -- noise ----------------------------------------------------------------
    p_noise = sub.add_parser("noise", help="White noise (DC-removed)")
    add_common_args(p_noise)
    p_noise.add_argument(
        "--seed", type=int, default=42, help="RNG seed for repeatability (default: 42)"
    )

    args = parser.parse_args()

    # Validate
    if not 0.0 < args.amplitude <= 1.0:
        sys.exit("error: --amplitude must be in range (0, 1]")
    if args.samples < 1:
        sys.exit("error: --samples must be >= 1")

    # Generate
    if args.signal == "chirp":
        if args.f0 <= 0 or args.f1 <= 0 or args.f0 >= args.f1:
            sys.exit("error: --f0 and --f1 must be positive and f0 < f1")
        samples = gen_chirp(args.samples, args.fs, args.f0, args.f1, args.amplitude)
        desc = f"{args.f0:.0f}–{args.f1:.0f} Hz log chirp"
    elif args.signal == "sine":
        if args.freq <= 0:
            sys.exit("error: --freq must be positive")
        samples = gen_sine(args.samples, args.fs, args.freq, args.amplitude)
        desc = f"{args.freq:.0f} Hz sine"
    elif args.signal == "noise":
        samples = gen_noise(args.samples, args.amplitude, args.seed)
        desc = f"white noise (seed={args.seed})"

    output = args.output or f"{args.signal}.csv"

    print(f"Signal:   {desc}")
    print(
        f"Samples:  {args.samples}  ({args.samples / args.fs * 1000:.1f} ms at {args.fs:.0f} Hz)"
    )
    print(f"Amplitude: {args.amplitude}")
    write_csv(output, args.fs, samples)


if __name__ == "__main__":
    main()
