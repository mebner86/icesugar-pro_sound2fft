#!/usr/bin/env python3
"""
hil_test.py — Host-side script for the pdm_hil_2mics project (project 17).

Dual-microphone version of the project 15 HIL test.  Records from two PDM
microphones simultaneously and compares their signals.

Workflow:
  1. Generate a test signal (log chirp, impulse, or white noise).
  2. Upload it to the FPGA replay buffer via the 'U' UART command.
  3. Trigger play+record with the 'P' command; wait for 'K' ACK.
  4. Download mic 1 buffer via 'D' and mic 2 buffer via 'E'.
  5. Compute and compare transfer functions for both channels.
  6. Plot both mic signals side-by-side plus cross-channel analysis.
  7. Optionally save raw PCM files.

Usage:
  python3 hil_test.py /dev/ttyACM0 [--signal chirp|impulse|noise|sin|sin-delayed]
                      [--save] [--record-only] [--baud 115200]

Requirements:
  pip install pyserial numpy matplotlib
"""

import argparse
import struct
import sys

import numpy as np

# ---------------------------------------------------------------------------
# Hardware constants (must match pdm_hil_2mics.v parameters)
# ---------------------------------------------------------------------------
SAMPLE_RATE = 48_828  # Hz  (25e6 / 8 / 64)
NUM_SAMPLES = 4096  # samples per buffer
FULL_SCALE = 32768.0  # 16-bit signed full scale

CMD_UPLOAD = b"U"
CMD_PLAY = b"P"
CMD_RECORD = b"R"
CMD_DUMP = b"D"
CMD_DUMP2 = b"E"
ACK_BYTE = 0x4B  # 'K'


# ---------------------------------------------------------------------------
# Signal generators (same as project 15)
# ---------------------------------------------------------------------------


def gen_chirp(n=NUM_SAMPLES, fs=SAMPLE_RATE, f0=200, f1=20_000, amplitude=0.9):
    """Log-frequency sweep from f0 to f1 over n samples."""
    T = n / fs
    phase = (
        2
        * np.pi
        * f0
        * T
        / np.log(f1 / f0)
        * (np.exp(np.arange(n) / n * np.log(f1 / f0)) - 1)
    )
    return amplitude * np.sin(phase)


def gen_impulse(n=NUM_SAMPLES, amplitude=0.9):
    """Single-sample impulse at the centre of the buffer."""
    sig = np.zeros(n)
    sig[n // 2] = amplitude
    return sig


def gen_sin(n=NUM_SAMPLES, fs=SAMPLE_RATE, freq=2000, amplitude=0.9):
    """Continuous 2 kHz sine wave."""
    t = np.arange(n) / fs
    return amplitude * np.sin(2 * np.pi * freq * t)


def gen_sin_delayed(
    n=NUM_SAMPLES, fs=SAMPLE_RATE, freq=2000, onset_ms=20, amplitude=0.9
):
    """Silence followed by a 2 kHz sine starting at onset_ms."""
    onset_sample = int(onset_ms / 1000.0 * fs)
    sig = np.zeros(n)
    t = np.arange(n - onset_sample) / fs
    sig[onset_sample:] = amplitude * np.sin(2 * np.pi * freq * t)
    return sig


def gen_noise(n=NUM_SAMPLES, amplitude=0.5):
    """Band-limited white noise (DC-blocked)."""
    rng = np.random.default_rng(seed=42)
    sig = rng.uniform(-1.0, 1.0, n)
    sig -= sig.mean()
    sig = sig / np.abs(sig).max() * amplitude
    return sig


def float_to_int16(sig):
    """Clip and quantise float signal [-1, 1] to signed 16-bit integer array."""
    clipped = np.clip(sig, -1.0, 1.0)
    return (clipped * (FULL_SCALE - 1)).astype(np.int16)


def int16_to_float(samples):
    """Convert signed 16-bit integer array to float [-1, 1]."""
    return np.array(samples, dtype=np.float64) / FULL_SCALE


# ---------------------------------------------------------------------------
# UART helpers
# ---------------------------------------------------------------------------


def open_port(port, baud):
    try:
        import serial
    except ImportError:
        sys.exit("pyserial not found. Install with: pip install pyserial")

    s = serial.Serial(port, baud, timeout=5)
    s.reset_input_buffer()
    s.reset_output_buffer()
    return s


def upload(ser, samples_i16, verbose=True):
    """Upload signed int16 array to the FPGA replay buffer."""
    payload = struct.pack(f">{len(samples_i16)}h", *samples_i16)
    if verbose:
        print(
            f"Uploading {len(samples_i16)} samples ({len(payload)} bytes)...",
            end=" ",
            flush=True,
        )
    ser.write(CMD_UPLOAD)
    ser.write(payload)
    ack = ser.read(1)
    if not ack or ack[0] != ACK_BYTE:
        raise RuntimeError(f"Upload ACK not received (got {ack!r})")
    if verbose:
        print("ACK OK")


def play_record(ser, verbose=True):
    """Trigger PLAY_RECORD on the FPGA.  Wait for 'K' ACK."""
    if verbose:
        print("Playing and recording (both mics)...", end=" ", flush=True)
    ser.write(CMD_PLAY)
    ack = ser.read(1)
    if not ack or ack[0] != ACK_BYTE:
        raise RuntimeError(f"Play ACK not received (got {ack!r})")
    if verbose:
        print("ACK OK")


def record_only(ser, verbose=True):
    """Trigger mic-only recording on the FPGA.  Wait for 'K' ACK."""
    if verbose:
        print("Recording both mics (no playback)...", end=" ", flush=True)
    ser.write(CMD_RECORD)
    ack = ser.read(1)
    if not ack or ack[0] != ACK_BYTE:
        raise RuntimeError(f"Record ACK not received (got {ack!r})")
    if verbose:
        print("ACK OK")


def dump(ser, n=NUM_SAMPLES, verbose=True):
    """Download mic 1 record buffer from the FPGA."""
    if verbose:
        print(
            f"Dumping mic 1 (outside): {n} samples ({n*2} bytes)...",
            end=" ",
            flush=True,
        )
    ser.write(CMD_DUMP)
    raw = ser.read(n * 2)
    if len(raw) != n * 2:
        raise RuntimeError(f"Dump underrun: expected {n*2} bytes, got {len(raw)}")
    samples = struct.unpack(f">{n}h", raw)
    if verbose:
        print("done")
    return np.array(samples, dtype=np.int16)


def dump2(ser, n=NUM_SAMPLES, verbose=True):
    """Download mic 2 record buffer from the FPGA."""
    if verbose:
        print(
            f"Dumping mic 2 (inside): {n} samples ({n*2} bytes)...", end=" ", flush=True
        )
    ser.write(CMD_DUMP2)
    raw = ser.read(n * 2)
    if len(raw) != n * 2:
        raise RuntimeError(f"Dump2 underrun: expected {n*2} bytes, got {len(raw)}")
    samples = struct.unpack(f">{n}h", raw)
    if verbose:
        print("done")
    return np.array(samples, dtype=np.int16)


# ---------------------------------------------------------------------------
# Transfer function computation
# ---------------------------------------------------------------------------


def compute_transfer_function(played_i16, recorded_i16, regularisation=1e-6):
    """Compute H(f) = FFT(recorded) / FFT(played) with Tikhonov regularisation."""
    played = int16_to_float(played_i16)
    recorded = int16_to_float(recorded_i16)

    P = np.fft.rfft(played)
    R = np.fft.rfft(recorded)

    epsilon = regularisation * np.max(np.abs(P) ** 2)
    H = R * np.conj(P) / (np.abs(P) ** 2 + epsilon)

    freqs = np.fft.rfftfreq(len(played), d=1.0 / SAMPLE_RATE)
    H_mag_db = 20 * np.log10(np.abs(H) + 1e-12)
    H_phase_deg = np.angle(H, deg=True)
    h_t = np.fft.irfft(H, n=len(played))

    return freqs, H_mag_db, H_phase_deg, h_t


def compute_cross_correlation(mic1_i16, mic2_i16):
    """Compute normalised cross-correlation and time delay between mic channels."""
    m1 = int16_to_float(mic1_i16)
    m2 = int16_to_float(mic2_i16)

    # Remove DC
    m1 = m1 - m1.mean()
    m2 = m2 - m2.mean()

    # Normalised cross-correlation via FFT
    M1 = np.fft.rfft(m1, n=2 * len(m1))
    M2 = np.fft.rfft(m2, n=2 * len(m2))
    xcorr = np.fft.irfft(M1 * np.conj(M2))
    norm = np.sqrt(np.sum(m1**2) * np.sum(m2**2))
    if norm > 0:
        xcorr /= norm

    # Time delay (peak of cross-correlation)
    n = len(m1)
    lags = np.arange(-n + 1, n)
    xcorr = np.roll(xcorr[: 2 * n - 1], n - 1)
    peak_idx = np.argmax(np.abs(xcorr))
    delay_samples = lags[peak_idx]
    delay_us = delay_samples / SAMPLE_RATE * 1e6

    return lags, xcorr, delay_samples, delay_us


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------


def plot_results(played_i16, mic1_i16, mic2_i16):
    import matplotlib.pyplot as plt
    import matplotlib.ticker as ticker

    freq_ticks = [100, 1000, 10000]
    freq_labels = ["100", "1k", "10k"]

    def set_freq_ticks(ax):
        ax.set_xticks(freq_ticks)
        ax.set_xticklabels(freq_labels)
        ax.xaxis.set_minor_formatter(ticker.NullFormatter())

    played = int16_to_float(played_i16)
    mic1 = int16_to_float(mic1_i16)
    mic2 = int16_to_float(mic2_i16)
    t = np.arange(NUM_SAMPLES) / SAMPLE_RATE * 1000  # ms

    fig, axes = plt.subplots(3, 2, figsize=(11.2, 8.4))
    fig.suptitle(
        "Dual-Mic PDM HIL — Hearing Protection Damping Measurement", fontsize=13
    )

    # Consistent colors: played=blue, outside=orange, inside=green
    C_PLAYED = "tab:blue"
    C_OUTSIDE = "tab:orange"
    C_INSIDE = "tab:green"

    # Row 0: played signal and overlay of both mic recordings
    axes[0, 0].plot(t, played, lw=0.8, color=C_PLAYED)
    axes[0, 0].set(title="Played signal", xlabel="Time (ms)", ylabel="Amplitude")
    axes[0, 0].grid(True, alpha=0.4)

    axes[0, 1].plot(
        t, mic1, lw=0.8, label="Mic 1 (outside)", alpha=0.8, color=C_OUTSIDE
    )
    axes[0, 1].plot(t, mic2, lw=0.8, label="Mic 2 (inside)", alpha=0.8, color=C_INSIDE)
    axes[0, 1].set(title="Recorded signals", xlabel="Time (ms)", ylabel="Amplitude")
    axes[0, 1].legend()
    axes[0, 1].grid(True, alpha=0.4)

    # Row 1: FFT magnitude of all three signals + transfer function
    fft_freqs = np.fft.rfftfreq(len(played), d=1.0 / SAMPLE_RATE)
    P = np.fft.rfft(played)
    M1 = np.fft.rfft(mic1)
    M2 = np.fft.rfft(mic2)

    played_mag_db = 20 * np.log10(np.abs(P) + 1e-12)
    mic1_mag_db = 20 * np.log10(np.abs(M1) + 1e-12)
    mic2_mag_db = 20 * np.log10(np.abs(M2) + 1e-12)

    axes[1, 0].plot(fft_freqs, played_mag_db, lw=0.8, label="Played", color=C_PLAYED)
    axes[1, 0].plot(
        fft_freqs, mic1_mag_db, lw=0.8, label="Mic 1 (outside)", color=C_OUTSIDE
    )
    axes[1, 0].plot(
        fft_freqs, mic2_mag_db, lw=0.8, label="Mic 2 (inside)", color=C_INSIDE
    )
    axes[1, 0].set(
        title="FFT — Played vs Outside vs Inside", xlabel="Frequency (Hz)", ylabel="dB"
    )
    axes[1, 0].set_xscale("log")
    axes[1, 0].set_xlim([100, SAMPLE_RATE / 2])
    axes[1, 0].legend(fontsize=8)
    axes[1, 0].grid(True, alpha=0.4)
    set_freq_ticks(axes[1, 0])

    # Row 1 right: transfer function H(f) = Inside / Outside (damping)
    epsilon = 1e-6 * np.max(np.abs(M1) ** 2)
    H = M2 * np.conj(M1) / (np.abs(M1) ** 2 + epsilon)
    H_mag_db = 20 * np.log10(np.abs(H) + 1e-12)

    axes[1, 1].plot(fft_freqs, H_mag_db, lw=0.8, color="tab:red")
    axes[1, 1].set(
        title="|H(f)| = Inside / Outside (damping)",
        xlabel="Frequency (Hz)",
        ylabel="dB",
    )
    axes[1, 1].set_xscale("log")
    axes[1, 1].set_xlim([100, SAMPLE_RATE / 2])
    axes[1, 1].axhline(0, color="gray", ls="--", lw=0.8)
    axes[1, 1].grid(True, alpha=0.4)
    set_freq_ticks(axes[1, 1])

    # Row 2: unwrapped phase of H(f) + empty
    H_phase_unwrap = np.rad2deg(np.unwrap(np.angle(H)))

    axes[2, 0].plot(fft_freqs, H_phase_unwrap, lw=0.8, color="tab:red")
    axes[2, 0].set(
        title="Phase of H(f) (unwrapped)", xlabel="Frequency (Hz)", ylabel="Degrees"
    )
    axes[2, 0].set_xscale("log")
    axes[2, 0].set_xlim([100, SAMPLE_RATE / 2])
    axes[2, 0].grid(True, alpha=0.4)
    set_freq_ticks(axes[2, 0])

    # Row 2 right: measured damping vs ANSI reference (log freq axis)
    measured_damping_db = -H_mag_db  # insertion loss = -20*log10(|Inside/Outside|)

    # Load ANSI reference data
    import os

    ref_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "ansi_reference.csv"
    )
    try:
        ref = np.loadtxt(ref_path, delimiter=",", skiprows=4)
        ref_freq = ref[:, 0]
        ref_il = ref[:, 1]
        axes[2, 1].plot(
            ref_freq,
            ref_il,
            "s-",
            color="tab:blue",
            lw=1.2,
            markersize=5,
            label="ANSI reference",
        )
    except (OSError, ValueError):
        pass  # reference file not found — skip

    axes[2, 1].plot(
        fft_freqs, measured_damping_db, lw=0.8, color="tab:red", label="Measured"
    )
    axes[2, 1].set(
        title="Insertion Loss — Measured vs ANSI Reference",
        xlabel="Frequency (Hz)",
        ylabel="Insertion Loss (dB)",
    )
    axes[2, 1].set_xscale("log")
    axes[2, 1].set_xlim([125, 8000])
    il_ticks = [125, 250, 500, 1000, 2000, 4000, 8000]
    axes[2, 1].set_xticks(il_ticks)
    axes[2, 1].set_xticklabels([str(f) for f in il_ticks])
    axes[2, 1].xaxis.set_minor_formatter(ticker.NullFormatter())
    axes[2, 1].legend(fontsize=8)
    axes[2, 1].grid(True, alpha=0.4)
    axes[2, 1].invert_yaxis()

    plt.tight_layout()
    plt.show()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Dual-mic PDM HIL transfer function measurement"
    )
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyACM0)")
    parser.add_argument(
        "--baud", type=int, default=115_200, help="UART baud rate (default 115200)"
    )
    parser.add_argument(
        "--signal",
        choices=["chirp", "impulse", "noise", "sin", "sin-delayed"],
        default="chirp",
        help="Test signal type (default: chirp)",
    )
    parser.add_argument(
        "--save", action="store_true", help="Save PCM and H(f) CSV files"
    )
    parser.add_argument(
        "--record-only",
        action="store_true",
        help="Record background noise without playback",
    )
    parser.add_argument(
        "--amplitude",
        type=float,
        default=0.9,
        help="Peak amplitude of the played signal, 0.0-1.0 (default 0.9)",
    )
    parser.add_argument("--no-plot", action="store_true", help="Skip matplotlib plot")
    args = parser.parse_args()

    # --- Generate test signal ---
    amp = args.amplitude
    if args.signal == "chirp":
        played_f = gen_chirp(amplitude=amp)
    elif args.signal == "impulse":
        played_f = gen_impulse(amplitude=amp)
    elif args.signal == "sin":
        played_f = gen_sin(amplitude=amp)
    elif args.signal == "sin-delayed":
        played_f = gen_sin_delayed(amplitude=amp)
    else:
        played_f = gen_noise(amplitude=amp)

    played_i16 = float_to_int16(played_f)

    # --- Open serial port ---
    print(f"Opening {args.port} at {args.baud} baud...")
    ser = open_port(args.port, args.baud)

    try:
        if args.record_only:
            record_only(ser)
            mic1_i16 = dump(ser)
            mic2_i16 = dump2(ser)
            print(f"Mic 1 (outside) peak: {np.abs(mic1_i16).max() / FULL_SCALE:.4f}")
            print(f"Mic 2 (inside)  peak: {np.abs(mic2_i16).max() / FULL_SCALE:.4f}")
        else:
            upload(ser, played_i16)
            play_record(ser)
            mic1_i16 = dump(ser)
            mic2_i16 = dump2(ser)

            print(
                f"Peak played amplitude:    {np.abs(played_i16).max() / FULL_SCALE:.4f}"
            )
            print(
                f"Mic 1 (outside) peak:     {np.abs(mic1_i16).max() / FULL_SCALE:.4f}"
            )
            print(
                f"Mic 2 (inside)  peak:     {np.abs(mic2_i16).max() / FULL_SCALE:.4f}"
            )

            # --- Compute transfer functions ---
            freqs, H1_mag_db, H1_phase_deg, h1_t = compute_transfer_function(
                played_i16, mic1_i16
            )
            _, H2_mag_db, H2_phase_deg, h2_t = compute_transfer_function(
                played_i16, mic2_i16
            )

            # --- Cross-correlation ---
            _, _, delay_samples, delay_us = compute_cross_correlation(
                mic1_i16, mic2_i16
            )
            print(
                f"Inter-mic delay:        {delay_us:.1f} us ({delay_samples} samples)"
            )

            # --- Save (optional) ---
            if args.save:
                np.array(played_i16).astype(">i2").tofile("played.pcm")
                np.array(mic1_i16).astype(">i2").tofile("mic1.pcm")
                np.array(mic2_i16).astype(">i2").tofile("mic2.pcm")
                csv_data = np.column_stack(
                    [freqs, H1_mag_db, H1_phase_deg, H2_mag_db, H2_phase_deg]
                )
                np.savetxt(
                    "transfer_function.csv",
                    csv_data,
                    delimiter=",",
                    header="freq_hz,h1_mag_db,h1_phase_deg,h2_mag_db,h2_phase_deg",
                    comments="",
                )
                print("Saved: played.pcm, mic1.pcm, mic2.pcm, transfer_function.csv")
                print("  Convert: sox -r 48828 -e signed -b 16 -c 1 mic1.pcm mic1.wav")

            # --- Plot ---
            if not args.no_plot:
                try:
                    import matplotlib  # noqa: F401

                    plot_results(played_i16, mic1_i16, mic2_i16)
                except ImportError:
                    print(
                        "matplotlib not found -- skipping plot. "
                        "Install with: pip install matplotlib"
                    )
    finally:
        ser.close()


if __name__ == "__main__":
    main()
