"""Unit tests for the fft256 module.

Data flow under test:
  feed 256 samples (S_COLLECT) → 8-stage butterfly (S_COMPUTE) →
  log2 magnitude for each bin (S_MAGNITUDE) → output mag_addr/mag_data/mag_valid

Timing budget per FFT frame:
  COLLECT  : 256 cycles   (one sample per clock)
  COMPUTE  : 3072 cycles  (8 stages × 128 butterflies × 3 steps)
  MAGNITUDE: 512 cycles   (256 bins × 2 steps each)
"""

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

N = 256
COLLECT_CYCLES = N
COMPUTE_CYCLES = 8 * 128 * 3  # 3072
MAG_CYCLES = N * 2  # 512
# Timeout for collect_magnitudes — called after feed_samples, so we only need
# COMPUTE + MAG + a generous margin.
MAG_TIMEOUT = COMPUTE_CYCLES + MAG_CYCLES + 200


def s16(val):
    """Clamp to signed 16-bit range and return the unsigned bit pattern."""
    val = int(round(val))
    val = max(-32768, min(32767, val))
    return val & 0xFFFF


def reference_mag_data(re_s16, im_s16):
    """Replicate fft256.v's magnitude approximation and log2 scaling exactly.

    Inputs are signed 16-bit integers matching what the RTL stores in re_mem /
    im_mem after the compute phase.  Returns the 9-bit mag_data value the RTL
    would produce for that (re, im) pair.
    """
    # Absolute values — matches RTL's (~x + 1) two's-complement negation
    abs_re = abs(re_s16) & 0xFFFF
    abs_im = abs(im_s16) & 0xFFFF
    mag_max = max(abs_re, abs_im)
    mag_min = min(abs_re, abs_im)
    # Approximation: max + min/4  (within ~5 % of true Euclidean magnitude)
    magnitude = (mag_max + (mag_min >> 2)) & 0xFFFF

    if magnitude == 0:
        return 0

    # Log2 via MSB position (4-bit integer part)
    log2_int = magnitude.bit_length() - 1
    # Left-align to bit 15 to extract the 4-bit fractional part
    mag_norm = (magnitude << (15 - log2_int)) & 0xFFFF
    log2_frac = (mag_norm >> 11) & 0xF
    log2_val = (log2_int << 4) | log2_frac
    # Scale to 0-438 pixel range: (val * 440) >> 8
    return (log2_val * 440) >> 8


def reference_fft_mags(samples):
    """Compute reference mag_data values for a list of samples using numpy.fft.

    numpy.fft.fft provides a validated, high-precision reference.  The result
    is divided by N to replicate the 8 stages × ½ scaling in the RTL (total
    factor 1/256), rounded to the nearest integer, clamped to signed 16-bit,
    and then passed through reference_mag_data to match the RTL's exact
    magnitude and log2 pipeline.
    """
    x = np.array([max(-32768, min(32767, round(v))) for v in samples], dtype=np.float64)
    X = np.fft.fft(x) / N
    re = np.clip(np.round(X.real), -32768, 32767).astype(np.int32)
    im = np.clip(np.round(X.imag), -32768, 32767).astype(np.int32)
    return [reference_mag_data(int(r), int(i)) for r, i in zip(re, im)]


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.sample_in.value = 0
    dut.sample_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def feed_samples(dut, samples):
    """Assert sample_valid for 256 consecutive clock cycles, one sample per cycle."""
    for val in samples:
        dut.sample_in.value = s16(val)
        dut.sample_valid.value = 1
        await RisingEdge(dut.clk)
    dut.sample_valid.value = 0
    dut.sample_in.value = 0


async def collect_magnitudes(dut, timeout=MAG_TIMEOUT):
    """Collect all 256 magnitude outputs.

    Returns (mags, count) where mags is a list of 256 values indexed by bin
    and count is the number of mag_valid pulses observed.
    """
    mags = [0] * N
    count = 0
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.mag_valid.value == 1:
            addr = int(dut.mag_addr.value)
            mags[addr] = int(dut.mag_data.value)
            count += 1
            if count == N:
                break
    return mags, count


# ============================================================
# Tests
# ============================================================


@cocotb.test()
async def test_reset_state(dut):
    """After reset: busy=0, mag_valid=0."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    assert dut.busy.value == 0, "busy should be 0 after reset"
    assert dut.mag_valid.value == 0, "mag_valid should be 0 after reset"


@cocotb.test()
async def test_busy_during_compute(dut):
    """busy goes high on the clock edge that accepts the 256th sample."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    assert dut.busy.value == 0

    # Feed 255 samples — still in S_COLLECT, sample_count reaches 255
    for _ in range(255):
        dut.sample_in.value = 0x0100
        dut.sample_valid.value = 1
        await RisingEdge(dut.clk)

    assert dut.busy.value == 0, "busy should still be 0 before the 256th sample"

    # 256th sample: sample_count == 255 → state transitions to S_COMPUTE
    await RisingEdge(dut.clk)
    dut.sample_valid.value = 0

    # busy is a combinatorial wire derived from the state register.  Advance
    # one more cycle so we check it at a stable point inside S_COMPUTE rather
    # than in the same delta cycle as the register update.
    await RisingEdge(dut.clk)
    assert dut.busy.value == 1, "busy should be 1 once in compute phase"


@cocotb.test()
async def test_zero_input(dut):
    """All-zero samples → all 256 magnitude outputs are zero."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    await feed_samples(dut, [0] * N)
    mags, count = await collect_magnitudes(dut)

    assert count == N, f"Expected {N} mag_valid pulses, got {count}"
    for k, v in enumerate(mags):
        assert v == 0, f"Bin {k}: expected 0, got {v}"


@cocotb.test()
async def test_dc_input(dut):
    """DC input (all samples equal) produces a large magnitude only at bin 0.

    With all samples = A, each butterfly stage cancels the difference term,
    leaving only X[0] = A after 8 stages of 1/2 scaling.  All other bins
    remain zero.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    A = 0x4000  # 16384 — well within signed 16-bit range, gives mag_data ≈ 385
    await feed_samples(dut, [A] * N)
    mags, count = await collect_magnitudes(dut)

    assert count == N, f"Expected {N} outputs, got {count}"
    assert mags[0] > 0, "Bin 0 should have non-zero magnitude for DC input"
    for k in range(1, N):
        assert mags[k] <= 1, f"Bin {k}: expected ~0 for DC input, got {mags[k]}"


@cocotb.test()
async def test_single_tone(dut):
    """Single-frequency sine wave produces dominant peaks at the expected bin pair.

    A sine at normalised frequency k/N has energy only at bins k and N-k.
    The log2-scaled peak should greatly exceed the average of all other bins.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    BIN = 16
    AMPLITUDE = 16000
    n = np.arange(N)
    samples = (AMPLITUDE * np.sin(2 * np.pi * BIN * n / N)).tolist()
    await feed_samples(dut, samples)
    mags, count = await collect_magnitudes(dut)

    assert count == N, f"Expected {N} outputs, got {count}"

    peak_val = max(mags)
    assert peak_val > 0, "Expected non-zero magnitude for sine input"

    # Both conjugate bins should carry the peak
    expected = {BIN, N - BIN}
    peak_bins = {k for k, v in enumerate(mags) if v == peak_val}
    assert (
        peak_bins & expected
    ), f"Expected peaks at bins {expected}, but dominant bins are {peak_bins}"

    # Peak should be at least 5× the average of all non-expected bins
    other_vals = [v for k, v in enumerate(mags) if k not in expected]
    avg_other = sum(other_vals) / len(other_vals)
    assert (
        peak_val > avg_other * 5
    ), f"Peak ({peak_val}) should dominate non-tone bins (avg {avg_other:.1f})"


@cocotb.test()
async def test_output_count(dut):
    """Exactly 256 mag_valid pulses fire for one complete FFT frame."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    await feed_samples(dut, [0x1000] * N)
    _, count = await collect_magnitudes(dut)

    assert count == N, f"Expected {N} mag_valid pulses, got {count}"


@cocotb.test()
async def test_mag_valid_single_cycle(dut):
    """mag_valid is a one-cycle strobe, not a sustained level."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    await feed_samples(dut, [0x1000] * N)

    # Wait for the first mag_valid pulse, then confirm it drops on the next cycle
    for _ in range(MAG_TIMEOUT):
        await RisingEdge(dut.clk)
        if dut.mag_valid.value == 1:
            break
    else:
        raise TimeoutError("mag_valid never asserted")

    await RisingEdge(dut.clk)
    assert dut.mag_valid.value == 0, "mag_valid should be low the cycle after it pulses"


@cocotb.test()
async def test_returns_to_collect(dut):
    """busy returns to 0 after the magnitude output phase completes."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    await feed_samples(dut, [0x0800] * N)
    _, count = await collect_magnitudes(dut)
    assert count == N

    await ClockCycles(dut.clk, 5)
    assert dut.busy.value == 0, "busy should return to 0 after the magnitude phase"


@cocotb.test()
async def test_sequential_frames(dut):
    """Module correctly processes two back-to-back FFT frames.

    Frame 1: DC signal → peak at bin 0, zeros elsewhere.
    Frame 2: all zeros  → all bins zero.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    # --- Frame 1: DC ---
    A = 0x2000
    await feed_samples(dut, [A] * N)
    mags1, c1 = await collect_magnitudes(dut)

    assert c1 == N, f"Frame 1: expected {N} outputs, got {c1}"
    assert mags1[0] > 0, "Frame 1: bin 0 should carry the DC peak"
    for k in range(1, N):
        assert mags1[k] <= 1, f"Frame 1, bin {k}: expected ~0, got {mags1[k]}"

    # Return to collect state before feeding the second frame
    await ClockCycles(dut.clk, 2)

    # --- Frame 2: silence ---
    await feed_samples(dut, [0] * N)
    mags2, c2 = await collect_magnitudes(dut)

    assert c2 == N, f"Frame 2: expected {N} outputs, got {c2}"
    for k, v in enumerate(mags2):
        assert v == 0, f"Frame 2, bin {k}: expected 0, got {v}"


@cocotb.test()
async def test_triangle_wave(dut):
    """Triangle wave DUT output matches the numpy.fft reference within tolerance.

    A triangle wave has a known harmonic spectrum: odd harmonics only, with
    amplitudes decaying as 1/k².  Using numpy.fft as the reference gives us a
    validated float64 FFT to compare against the fixed-point DUT.

    The tolerance of ±3 counts (on a 0-438 log2-scaled output) accounts for
    the fixed-point rounding/truncation that accumulates over 8 butterfly
    stages and the Q1.14 twiddle factor quantisation.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    # Triangle wave: period = 32 samples → fundamental at bin N // 32 = 8.
    # Odd harmonics appear at bins 8, 24, 40, … with amplitudes ∝ 1/k².
    PERIOD = 32
    AMPLITUDE = 28000  # near full scale for high SNR
    n = np.arange(N)
    t_frac = (n % PERIOD) / PERIOD  # 0.0 to <1.0 within each period
    samples = (AMPLITUDE * (1 - 4 * np.abs(t_frac - 0.5))).tolist()

    ref_mags = reference_fft_mags(samples)

    await feed_samples(dut, samples)
    dut_mags, count = await collect_magnitudes(dut)

    assert count == N, f"Expected {N} outputs, got {count}"

    TOLERANCE = 3
    errors = []
    for k in range(N):
        diff = abs(dut_mags[k] - ref_mags[k])
        if diff > TOLERANCE:
            errors.append(
                f"  bin {k:3d}: DUT={dut_mags[k]:4d}  ref={ref_mags[k]:4d}  diff={diff}"
            )

    assert not errors, (
        f"{len(errors)} bins exceeded tolerance ±{TOLERANCE}:\n"
        + "\n".join(errors[:10])
        + ("\n  ..." if len(errors) > 10 else "")
    )
