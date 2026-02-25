#!/usr/bin/env python3
"""
Live FFT spectrum display for 12_fft_uart.

Reads COBS-framed FFT frames from the FPGA over UART and renders a live
frequency spectrum using matplotlib.  Runs on Windows, Linux, or macOS.

Protocol
--------
Each frame is 257 bytes:
  [bin_0] [bin_1] ... [bin_255] [0x00]

  - Data bytes: magnitude in log2, 4.4 fixed-point, clamped to 0x01–0xFF.
  - 0x00 is the exclusive COBS frame delimiter.
  - ~44 frames/sec at 115200 baud.

Usage
-----
  python display_fft.py <port> [--baud BAUD]

  Windows : python display_fft.py COM5
  Linux   : python display_fft.py /dev/ttyACM0
  macOS   : python display_fft.py /dev/tty.usbmodem...
"""

import argparse

import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
import serial

# ============================================================================
# Constants
# ============================================================================

NUM_BINS = 256  # FFT output bins (unique half of 512-point real FFT)
FFT_SIZE = 512  # Total FFT points
SAMPLE_RATE = 48828  # Approximate sample rate (25 MHz / 512 clocks per frame)
FRAME_BYTES = NUM_BINS  # Data bytes per frame (excluding 0x00 terminator)

# Frequency axis: bin k → k × Fs / N  (0 Hz to Fs/2)
FREQ_KHZ = np.arange(NUM_BINS) * SAMPLE_RATE / FFT_SIZE / 1000.0


# Magnitude axis: 4.4 fixed-point log2.  1 LSB = 1/16 log2 ≈ 0.43 dB.
# Full range: 0x01 (≈ 0.4 dB) to 0xFF (≈ 96.5 dB).
def to_log2(b: int) -> float:
    return b / 16.0


# ============================================================================
# Serial frame reader
# ============================================================================


class FFTReader:
    def __init__(self, port: str, baud: int):
        self.ser = serial.Serial(port, baud, timeout=2.0)
        print(f"Opened {port} at {baud} baud", flush=True)

    def read_frame(self) -> list[int] | None:
        """
        Return the most recent complete COBS frame, discarding any stale ones
        that have accumulated in the OS serial buffer.

        If the buffer already holds one or more complete frames (≥ 257 bytes),
        drain them all and keep only the last valid one — this prevents the
        display from lagging behind when matplotlib renders slower than the
        FPGA transmits.  If no backlog exists, block until the next frame
        arrives.
        """
        last_valid: list[int] | None = None

        # Drain every complete frame already sitting in the OS buffer.
        # read_until() returns immediately when in_waiting ≥ FRAME_BYTES + 1.
        while self.ser.in_waiting >= FRAME_BYTES + 1:
            raw = self.ser.read_until(b"\x00")
            if len(raw) == FRAME_BYTES + 1:
                last_valid = list(raw[:FRAME_BYTES])

        if last_valid is not None:
            return last_valid

        # No backlog — block for the next fresh frame.
        raw = self.ser.read_until(b"\x00")
        if len(raw) != FRAME_BYTES + 1:  # wrong length → startup glitch
            return None
        return list(raw[:FRAME_BYTES])

    def close(self):
        self.ser.close()


# ============================================================================
# Main
# ============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Live FFT spectrum display for 12_fft_uart"
    )
    parser.add_argument(
        "port",
        help="Serial port, e.g. COM5 (Windows) or /dev/ttyACM0 (Linux/macOS)",
    )
    parser.add_argument(
        "--baud", type=int, default=115_200, help="Baud rate (default: 115200)"
    )
    args = parser.parse_args()

    reader = FFTReader(args.port, args.baud)

    # -------------------------------------------------------------------------
    # Figure setup
    # -------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(13, 5))
    fig.patch.set_facecolor("#0d1117")
    ax.set_facecolor("#161b22")

    bin_width = FREQ_KHZ[1] - FREQ_KHZ[0]  # kHz per bin
    bars = ax.bar(
        FREQ_KHZ,
        np.zeros(NUM_BINS),
        width=bin_width,
        align="edge",
        color="#39d0f5",
        edgecolor="none",
    )

    ax.set_xlim(0, SAMPLE_RATE / 2 / 1000)  # 0 – Fs/2 kHz
    ax.set_ylim(0, 16)  # 0 – 15.9375 log2 units
    ax.set_xlabel("Frequency (kHz)", color="#c9d1d9")
    ax.set_ylabel("log\u2082 magnitude (4.4 FP)", color="#c9d1d9")
    ax.tick_params(colors="#c9d1d9")
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    for spine in ("bottom", "left"):
        ax.spines[spine].set_color("#30363d")

    # Secondary dB axis on the right
    ax2 = ax.twinx()
    ax2.set_ylim(0, 16)
    ax2.set_yticks(range(0, 17, 2))
    ax2.set_yticklabels([f"{v * 6:.0f}" for v in range(0, 17, 2)], color="#c9d1d9")
    ax2.set_ylabel("Approx. dB (0 dBFS ≈ 96)", color="#c9d1d9")
    ax2.tick_params(colors="#c9d1d9")
    ax2.spines["right"].set_color("#30363d")
    ax2.spines["top"].set_visible(False)

    title_base = "Live FFT Spectrum  —  12_fft_uart  —  512-pt real, 48.8 kHz"
    title_text = ax.set_title(title_base, color="#c9d1d9", pad=10)

    frame_count = [0]
    skip_count = [0]
    dropped_count = [0]

    # -------------------------------------------------------------------------
    # Animation update callback
    # -------------------------------------------------------------------------
    def update(_frame_idx):
        # Remember how many bytes were waiting before the drain so we can
        # count how many frames were skipped to stay live.
        waiting_before = reader.ser.in_waiting
        frame = reader.read_frame()
        if frame is None:
            skip_count[0] += 1
            return

        # Estimate frames dropped during drain (each frame is 257 bytes).
        drained = max(0, waiting_before - (FRAME_BYTES + 1))
        dropped_count[0] += drained // (FRAME_BYTES + 1)

        frame_count[0] += 1
        magnitudes = [to_log2(b) for b in frame]
        for bar, h in zip(bars, magnitudes):
            bar.set_height(h)

        # Refresh title every 10 frames to show throughput
        if frame_count[0] % 10 == 0:
            title_text.set_text(
                f"{title_base}   "
                f"[rx: {frame_count[0]}  dropped: {dropped_count[0]}  bad: {skip_count[0]}]"
            )

    _ani = animation.FuncAnimation(  # kept alive to prevent GC
        fig,
        update,
        interval=1,  # ms; actual rate limited by UART (~22 ms/frame)
        blit=False,
        cache_frame_data=False,
    )

    plt.tight_layout()

    try:
        plt.show()
    except KeyboardInterrupt:
        pass
    finally:
        reader.close()
        print(f"\nDone. Frames received: {frame_count[0]}, skipped: {skip_count[0]}")


if __name__ == "__main__":
    main()
