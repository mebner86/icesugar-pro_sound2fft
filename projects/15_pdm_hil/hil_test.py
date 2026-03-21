#!/usr/bin/env python3
"""
hil_test.py — Host-side script for the pdm_hil project (project 15).

Characterises the acoustic transfer function between the MAX98358 speaker
and the MP34DT01-M microphone on the iCESugar-Pro board.

Workflow:
  1. Generate a test signal (log chirp, impulse, or white noise).
  2. Upload it to the FPGA replay buffer via the 'U' UART command.
  3. Trigger play+record with the 'P' command; wait for 'K' ACK.
  4. Download the recorded buffer via the 'D' command.
  5. Compute H(f) = FFT(recorded) / FFT(played) with Tikhonov regularisation.
  6. Plot input, output, H(f) magnitude/phase, and impulse response h(t).
  7. Optionally save raw PCM files and H(f) as CSV.

Usage:
  python3 hil_test.py /dev/ttyACM0 [--signal chirp|impulse|noise]
                      [--save] [--record-only] [--baud 115200]

Requirements:
  pip install pyserial numpy matplotlib
"""

import argparse
import struct
import sys

import numpy as np

# ---------------------------------------------------------------------------
# Hardware constants (must match pdm_hil.v parameters)
# ---------------------------------------------------------------------------
SAMPLE_RATE = 48_828  # Hz  (25e6 / 8 / 64)
NUM_SAMPLES = 4096  # samples per buffer
FULL_SCALE = 32768.0  # 16-bit signed full scale

CMD_UPLOAD = b"U"
CMD_PLAY = b"P"
CMD_RECORD = b"R"
CMD_DUMP = b"D"
ACK_BYTE = 0x4B  # 'K'


# ---------------------------------------------------------------------------
# Signal generators
# ---------------------------------------------------------------------------


def gen_chirp(n=NUM_SAMPLES, fs=SAMPLE_RATE, f0=200, f1=20_000, amplitude=0.9):
    """Log-frequency sweep from f0 to f1 over n samples."""
    T = n / fs
    # Instantaneous phase for log chirp
    phase = (
        2
        * np.pi
        * f0
        * T
        / np.log(f1 / f0)
        * (np.exp(np.arange(n) / n * np.log(f1 / f0)) - 1)
    )
    sig = amplitude * np.sin(phase)
    return sig


def gen_impulse(n=NUM_SAMPLES, amplitude=0.9):
    """Single-sample impulse at the centre of the buffer."""
    sig = np.zeros(n)
    sig[n // 2] = amplitude
    return sig


def gen_noise(n=NUM_SAMPLES, amplitude=0.5):
    """Band-limited white noise (DC-blocked)."""
    rng = np.random.default_rng(seed=42)
    sig = rng.uniform(-1.0, 1.0, n)
    # Remove DC
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
    """Upload signed int16 array to the FPGA replay buffer.

    Sends 'U' followed by len(samples_i16)*2 bytes (big-endian).
    Waits for 'K' ACK.
    """
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
        print("Playing and recording...", end=" ", flush=True)
    ser.write(CMD_PLAY)
    ack = ser.read(1)
    if not ack or ack[0] != ACK_BYTE:
        raise RuntimeError(f"Play ACK not received (got {ack!r})")
    if verbose:
        print("ACK OK")


def record_only(ser, verbose=True):
    """Trigger mic-only recording on the FPGA.  Wait for 'K' ACK."""
    if verbose:
        print("Recording (no playback)...", end=" ", flush=True)
    ser.write(CMD_RECORD)
    ack = ser.read(1)
    if not ack or ack[0] != ACK_BYTE:
        raise RuntimeError(f"Record ACK not received (got {ack!r})")
    if verbose:
        print("ACK OK")


def dump(ser, n=NUM_SAMPLES, verbose=True):
    """Download the record buffer from the FPGA.

    Returns signed int16 NumPy array of length n.
    """
    if verbose:
        print(f"Dumping {n} samples ({n*2} bytes)...", end=" ", flush=True)
    ser.write(CMD_DUMP)
    raw = ser.read(n * 2)
    if len(raw) != n * 2:
        raise RuntimeError(f"Dump underrun: expected {n*2} bytes, got {len(raw)}")
    samples = struct.unpack(f">{n}h", raw)
    if verbose:
        print("done")
    return np.array(samples, dtype=np.int16)


# ---------------------------------------------------------------------------
# Transfer function computation
# ---------------------------------------------------------------------------


def compute_transfer_function(played_i16, recorded_i16, regularisation=1e-6):
    """Compute H(f) = FFT(recorded) / FFT(played) with Tikhonov regularisation.

    Returns:
        freqs      — frequency axis (Hz), length N//2+1
        H_mag_db   — |H(f)| in dBFS
        H_phase_deg— angle(H(f)) in degrees
        h_t        — impulse response (IFFT of H, real part)
    """
    played = int16_to_float(played_i16)
    recorded = int16_to_float(recorded_i16)

    P = np.fft.rfft(played)
    R = np.fft.rfft(recorded)

    # Tikhonov: H = R * P* / (|P|² + epsilon)
    epsilon = regularisation * np.max(np.abs(P) ** 2)
    H = R * np.conj(P) / (np.abs(P) ** 2 + epsilon)

    freqs = np.fft.rfftfreq(len(played), d=1.0 / SAMPLE_RATE)
    H_mag_db = 20 * np.log10(np.abs(H) + 1e-12)
    H_phase_deg = np.angle(H, deg=True)

    # Impulse response via IFFT
    h_t = np.fft.irfft(H, n=len(played))

    return freqs, H_mag_db, H_phase_deg, h_t


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------


def plot_results(played_i16, recorded_i16, freqs, H_mag_db, H_phase_deg, h_t):
    import matplotlib.pyplot as plt

    played = int16_to_float(played_i16)
    recorded = int16_to_float(recorded_i16)
    t = np.arange(NUM_SAMPLES) / SAMPLE_RATE * 1000  # ms
    t_ir = np.arange(len(h_t)) / SAMPLE_RATE * 1000  # ms

    fig, axes = plt.subplots(3, 2, figsize=(14, 10))
    fig.suptitle("PDM HIL — Acoustic Transfer Function Measurement", fontsize=13)

    # Time-domain signals
    axes[0, 0].plot(t, played, lw=0.8)
    axes[0, 0].set(
        title="Played signal (replay buffer)", xlabel="Time (ms)", ylabel="Amplitude"
    )
    axes[0, 0].grid(True, alpha=0.4)

    axes[0, 1].plot(t, recorded, lw=0.8, color="tab:orange")
    axes[0, 1].set(
        title="Recorded signal (mic)", xlabel="Time (ms)", ylabel="Amplitude"
    )
    axes[0, 1].grid(True, alpha=0.4)

    # Transfer function — magnitude
    axes[1, 0].plot(freqs / 1000, H_mag_db, lw=0.8, color="tab:green")
    axes[1, 0].set(
        title="|H(f)| — Magnitude response", xlabel="Frequency (kHz)", ylabel="dB"
    )
    axes[1, 0].set_xlim([0, SAMPLE_RATE / 2000])
    axes[1, 0].grid(True, alpha=0.4)

    # Transfer function — phase
    axes[1, 1].plot(freqs / 1000, H_phase_deg, lw=0.8, color="tab:red")
    axes[1, 1].set(
        title="∠H(f) — Phase response", xlabel="Frequency (kHz)", ylabel="Degrees"
    )
    axes[1, 1].set_xlim([0, SAMPLE_RATE / 2000])
    axes[1, 1].grid(True, alpha=0.4)

    # Impulse response
    axes[2, 0].plot(t_ir, h_t, lw=0.8, color="tab:purple")
    axes[2, 0].set(
        title="h(t) — Impulse response (IFFT of H)",
        xlabel="Time (ms)",
        ylabel="Amplitude",
    )
    axes[2, 0].grid(True, alpha=0.4)

    # Spectrogram of recorded signal
    axes[2, 1].specgram(recorded, Fs=SAMPLE_RATE, cmap="inferno")
    axes[2, 1].set(
        title="Recorded signal spectrogram", xlabel="Time (s)", ylabel="Frequency (Hz)"
    )

    plt.tight_layout()
    plt.show()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="PDM HIL transfer function measurement"
    )
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyACM0)")
    parser.add_argument(
        "--baud", type=int, default=115_200, help="UART baud rate (default 115200)"
    )
    parser.add_argument(
        "--signal",
        choices=["chirp", "impulse", "noise"],
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
    parser.add_argument("--no-plot", action="store_true", help="Skip matplotlib plot")
    args = parser.parse_args()

    # --- Generate test signal ---
    if args.signal == "chirp":
        played_f = gen_chirp()
    elif args.signal == "impulse":
        played_f = gen_impulse()
    else:
        played_f = gen_noise()

    played_i16 = float_to_int16(played_f)

    # --- Open serial port ---
    print(f"Opening {args.port} at {args.baud} baud...")
    ser = open_port(args.port, args.baud)

    try:
        if args.record_only:
            # Background noise capture (no playback)
            record_only(ser)
            recorded_i16 = dump(ser)
            print(
                f"Peak recorded amplitude: {np.abs(recorded_i16).max() / FULL_SCALE:.4f}"
            )
        else:
            # Full HIL measurement
            upload(ser, played_i16)
            play_record(ser)
            recorded_i16 = dump(ser)

            print(
                f"Peak played amplitude:    {np.abs(played_i16).max() / FULL_SCALE:.4f}"
            )
            print(
                f"Peak recorded amplitude:  {np.abs(recorded_i16).max() / FULL_SCALE:.4f}"
            )

            # --- Compute transfer function ---
            freqs, H_mag_db, H_phase_deg, h_t = compute_transfer_function(
                played_i16, recorded_i16
            )

            # --- Save (optional) ---
            if args.save:
                np.array(played_i16).astype(">i2").tofile("played.pcm")
                np.array(recorded_i16).astype(">i2").tofile("recorded.pcm")
                csv_data = np.column_stack([freqs, H_mag_db, H_phase_deg])
                np.savetxt(
                    "transfer_function.csv",
                    csv_data,
                    delimiter=",",
                    header="freq_hz,mag_db,phase_deg",
                    comments="",
                )
                print("Saved: played.pcm, recorded.pcm, transfer_function.csv")
                print(
                    "  Convert to WAV: sox -r 48828 -e signed -b 16 -c 1 recorded.pcm recorded.wav"
                )

            # --- Plot ---
            if not args.no_plot:
                try:
                    import matplotlib  # noqa: F401

                    plot_results(
                        played_i16, recorded_i16, freqs, H_mag_db, H_phase_deg, h_t
                    )
                except ImportError:
                    print(
                        "matplotlib not found — skipping plot. Install with: pip install matplotlib"
                    )
    finally:
        ser.close()


if __name__ == "__main__":
    main()
