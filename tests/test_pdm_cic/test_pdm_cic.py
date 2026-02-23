"""Unit tests for the pdm_cic module.

Data flow under test:
  pdm_bit / pdm_valid → [3 integrators at PDM rate]
  → dec_tick every DEC_RATIO pulses → [3 comb stages]
  → pcm_out / pcm_valid (registered, one cycle after dec_tick)

Test strategy
-------------
A first-order sigma-delta modulator converts known PCM signals into PDM
bitstreams (standard, well-understood algorithm).  The same PDM stream is fed
to both the DUT and a Python reference model that mirrors the RTL's
non-blocking-assignment semantics exactly.  The two outputs must agree
bit-for-bit; any discrepancy points to a bug in pdm_cic.v.

Key RTL timing facts reproduced in the reference model
-------------------------------------------------------
- Integrators use non-blocking assignments: integ2 accumulates *old* integ1,
  integ3 accumulates *old* integ2 (one extra pipeline delay per stage).
- dec_tick fires when dec_count == DEC_RATIO-1 (counts 0 … DEC_RATIO-1).
- At the dec_tick edge, comb1_delay captures integ3 *before* the current
  sample's integrator update (all on the same posedge, non-blocking).
- pcm_out and pcm_valid are registered: they change the cycle *after* dec_tick.
"""

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# Default DUT parameters (must match Makefile / RTL defaults)
DEC_RATIO = 64
CIC_WIDTH = 20  # 3 * log2(64) + 2
OUT_BITS = 16
SHIFT = CIC_WIDTH - OUT_BITS  # 4 — arithmetic right shift for truncation

# Timeout budget: large enough for DEC_RATIO samples + pipeline + margin
COLLECT_TIMEOUT = DEC_RATIO + 20


# ---------------------------------------------------------------------------
# Signal generation helpers
# ---------------------------------------------------------------------------


def sigma_delta_encode(pcm_normalized, oversample=DEC_RATIO):
    """First-order sigma-delta PDM encoder.

    Converts an array of floats in [-1, +1] (PCM values at the *output* sample
    rate) into a flat list of 0/1 PDM bits at *oversample* × the PCM rate.

    This is the standard 1st-order modulator used in virtually all textbook
    descriptions of delta-sigma conversion.  It is trivially verifiable by
    inspection: for a constant input c, the long-run density of 1s equals
    (c + 1) / 2.
    """
    error = 0.0
    bits = []
    for s in pcm_normalized:
        for _ in range(oversample):
            if error >= 0.0:
                bits.append(1)
                error += s - 1.0
            else:
                bits.append(0)
                error += s + 1.0
    return bits


# ---------------------------------------------------------------------------
# Python reference model (mirrors RTL non-blocking-assignment semantics)
# ---------------------------------------------------------------------------


def _wrap_signed(x, bits=CIC_WIDTH):
    """Wrap x into a signed integer of the given bit width."""
    mod = 1 << bits
    x = x % mod
    if x >= (mod >> 1):
        x -= mod
    return x


def cic_reference(
    pdm_bits, dec_ratio=DEC_RATIO, cic_width=CIC_WIDTH, out_bits=OUT_BITS
):
    """Exact Python replica of pdm_cic.v, mirroring non-blocking semantics.

    Returns a list of signed PCM values, one per dec_tick event.  The list
    is in the same order as DUT pcm_valid pulses.

    Non-blocking semantics reproduced:
    - All three integrators are updated from their *old* values in the same
      clock cycle (integ2 sees old integ1, integ3 sees old integ2).
    - comb1_delay captures integ3 *before* the current sample's update.
    - Comb outputs are computed from old delays and old integ3.
    - Delays are updated after the comb computation (same edge, non-blocking).
    """
    shift = cic_width - out_bits

    integ1 = integ2 = integ3 = 0
    comb1_d = comb2_d = comb3_d = 0
    dec_count = 0
    results = []

    for bit in pdm_bits:
        pdm_s = 1 if bit else -1

        # Save old integ3 before any update (mirrors non-blocking: comb1_delay
        # captures the value of integ3 *before* the integrator update fires).
        old_i3 = integ3

        # Compute new integrator values from OLD register contents
        new_i1 = _wrap_signed(integ1 + pdm_s, cic_width)
        new_i2 = _wrap_signed(integ2 + integ1, cic_width)  # old integ1
        new_i3 = _wrap_signed(integ3 + integ2, cic_width)  # old integ2

        fire_dec_tick = dec_count == dec_ratio - 1

        if fire_dec_tick:
            # Comb wires are combinatorial from OLD comb delays and OLD integ3
            c1 = _wrap_signed(old_i3 - comb1_d, cic_width)
            c2 = _wrap_signed(c1 - comb2_d, cic_width)
            c3 = _wrap_signed(c2 - comb3_d, cic_width)

            # Output: arithmetic right shift by SHIFT (= take MSBs)
            pcm = c3 >> shift
            results.append(pcm)

            # Update comb delays (non-blocking: use pre-update values)
            comb1_d = old_i3
            comb2_d = c1
            comb3_d = c2

        # Commit integrator updates
        integ1, integ2, integ3 = new_i1, new_i2, new_i3
        dec_count = (dec_count + 1) % dec_ratio

    return results


# ---------------------------------------------------------------------------
# cocotb helpers
# ---------------------------------------------------------------------------


async def reset_dut(dut):
    dut.pdm_bit.value = 0
    dut.pdm_valid.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_pdm(dut, pdm_bits):
    """Drive pdm_bit + pdm_valid=1 for each bit, one per clock cycle."""
    for bit in pdm_bits:
        dut.pdm_bit.value = int(bit)
        dut.pdm_valid.value = 1
        await RisingEdge(dut.clk)
    dut.pdm_valid.value = 0
    dut.pdm_bit.value = 0


async def collect_pcm(dut, n_samples, timeout=None):
    """Collect n_samples PCM values by waiting for pcm_valid pulses.

    Returns a list of signed integers.  Raises TimeoutError if fewer than
    n_samples pulses arrive within *timeout* clock cycles (default: generous
    margin per sample).
    """
    if timeout is None:
        timeout = n_samples * (DEC_RATIO + 20)
    results = []
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.pcm_valid.value == 1:
            results.append(dut.pcm_out.value.to_signed())
            if len(results) == n_samples:
                break
    else:
        raise TimeoutError(
            f"collect_pcm: expected {n_samples} samples, got {len(results)}"
        )
    return results


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@cocotb.test()
async def test_reset_state(dut):
    """After reset: pcm_out=0, pcm_valid=0."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    assert dut.pcm_valid.value == 0, "pcm_valid should be 0 after reset"
    assert dut.pcm_out.value.to_signed() == 0, "pcm_out should be 0 after reset"


@cocotb.test()
async def test_pcm_valid_timing(dut):
    """pcm_valid fires exactly once per DEC_RATIO pdm_valid pulses.

    Drives 4×DEC_RATIO PDM bits and verifies:
    - exactly 4 pcm_valid pulses arrive
    - consecutive pulses are separated by exactly DEC_RATIO clock cycles
      (one pdm_valid per cycle, pcm_valid one cycle after dec_tick)
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N_FRAMES = 4
    pdm_bits = [1] * (N_FRAMES * DEC_RATIO)

    pulse_times = []
    total_cycles = N_FRAMES * DEC_RATIO + 20

    # Drive PDM and record cycle numbers of pcm_valid pulses simultaneously
    drive_task = cocotb.start_soon(drive_pdm(dut, pdm_bits))

    for cycle in range(total_cycles):
        await RisingEdge(dut.clk)
        if dut.pcm_valid.value == 1:
            pulse_times.append(cycle)

    await drive_task

    assert (
        len(pulse_times) == N_FRAMES
    ), f"Expected {N_FRAMES} pcm_valid pulses, got {len(pulse_times)}"

    for i in range(1, len(pulse_times)):
        gap = pulse_times[i] - pulse_times[i - 1]
        assert (
            gap == DEC_RATIO
        ), f"Gap between pulse {i-1} and {i}: expected {DEC_RATIO}, got {gap}"


@cocotb.test()
async def test_pcm_valid_single_cycle(dut):
    """pcm_valid is a one-cycle strobe, not a sustained level."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    # Feed one decimation block and wait for the first pcm_valid
    cocotb.start_soon(drive_pdm(dut, [1] * DEC_RATIO))

    timeout = DEC_RATIO + 20
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.pcm_valid.value == 1:
            break
    else:
        raise TimeoutError("pcm_valid never asserted")

    await RisingEdge(dut.clk)
    assert dut.pcm_valid.value == 0, "pcm_valid should drop the cycle after it pulses"


@cocotb.test()
async def test_pdm_mapping_polarity(dut):
    """PDM mapping: all-ones produces positive output; all-zeros produces negative.

    Verifies that pdm_bit=1 maps to +1 (not -1) and the sign is preserved
    through the CIC pipeline.  Uses 10 decimation blocks as warmup before
    checking, so transients have settled.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())

    WARMUP = 10
    MEASURE = 4

    # --- All-ones: should produce positive pcm_out ---
    await reset_dut(dut)
    drive_task = cocotb.start_soon(
        drive_pdm(dut, [1] * ((WARMUP + MEASURE) * DEC_RATIO))
    )
    all_samples = await collect_pcm(dut, WARMUP + MEASURE)
    await drive_task
    pos_samples = all_samples[WARMUP:]  # discard warmup transient

    for i, v in enumerate(pos_samples):
        assert v > 0, f"All-ones PDM sample {i}: expected positive, got {v}"

    # --- All-zeros: should produce negative pcm_out ---
    await reset_dut(dut)
    drive_task = cocotb.start_soon(
        drive_pdm(dut, [0] * ((WARMUP + MEASURE) * DEC_RATIO))
    )
    all_samples = await collect_pcm(dut, WARMUP + MEASURE)
    await drive_task
    neg_samples = all_samples[WARMUP:]

    for i, v in enumerate(neg_samples):
        assert v < 0, f"All-zeros PDM sample {i}: expected negative, got {v}"

    # Symmetry: magnitudes should be equal (+-1 mapping is symmetric)
    for i, (p, n) in enumerate(zip(pos_samples, neg_samples)):
        assert (
            p == -n
        ), f"Sample {i}: all-ones output {p} should equal -(all-zeros output {n})"


@cocotb.test()
async def test_alternating_silence(dut):
    """Alternating 1,0,1,0,... PDM (zero mean) produces output that converges to 0.

    The CIC filter is a low-pass filter; its DC gain for a zero-mean input is 0.
    After enough warmup cycles the steady-state output should be exactly 0.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    WARMUP = 12
    MEASURE = 4
    pdm = [1, 0] * (((WARMUP + MEASURE) * DEC_RATIO) // 2)

    drive_task = cocotb.start_soon(drive_pdm(dut, pdm))
    all_samples = await collect_pcm(dut, WARMUP + MEASURE)
    await drive_task
    steady = all_samples[WARMUP:]

    for i, v in enumerate(steady):
        assert v == 0, f"Alternating PDM sample {i}: expected 0, got {v}"


@cocotb.test()
async def test_dc_bit_exact(dut):
    """All-ones PDM: DUT output must match the Python reference bit-for-bit.

    Drives 20 decimation blocks of all-ones PDM through both the DUT and the
    reference model and asserts exact equality.  This is the primary structural
    test: any difference in integrator order, cascade wiring, bit truncation, or
    decimation timing will show up here.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N_FRAMES = 20
    pdm_bits = [1] * (N_FRAMES * DEC_RATIO)

    ref = cic_reference(pdm_bits)
    assert len(ref) == N_FRAMES

    cocotb.start_soon(drive_pdm(dut, pdm_bits))
    dut_out = await collect_pcm(dut, N_FRAMES)

    errors = []
    for i, (d, r) in enumerate(zip(dut_out, ref)):
        if d != r:
            errors.append(f"  sample {i:3d}: DUT={d}  ref={r}  diff={d-r}")

    assert not errors, f"{len(errors)} mismatches (all-ones PDM):\n" + "\n".join(
        errors[:10]
    )


@cocotb.test()
async def test_sine_bit_exact(dut):
    """Sine PCM via sigma-delta PDM: DUT output matches Python reference bit-for-bit.

    A 16-sample-period sine wave (440 Hz equivalent at 8 kHz output rate) is
    encoded with the 1st-order sigma-delta modulator and fed to the DUT.  The
    same PDM stream is processed by the reference model.  Bit-exact agreement
    is required.

    This is the end-to-end fidelity test: it exercises the full pipeline with a
    non-trivial, time-varying signal and will catch bugs that constant DC input
    might miss (e.g., wrong comb differential delay).
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N_FRAMES = 64  # 4 complete sine periods (period = 16 output samples)
    AMPLITUDE = 0.7  # keep well within PDM dynamic range
    PERIOD = 16  # output samples per sine period

    n = np.arange(N_FRAMES)
    pcm_norm = (AMPLITUDE * np.sin(2 * np.pi * n / PERIOD)).tolist()

    pdm_bits = sigma_delta_encode(pcm_norm, oversample=DEC_RATIO)
    assert len(pdm_bits) == N_FRAMES * DEC_RATIO

    ref = cic_reference(pdm_bits)
    assert len(ref) == N_FRAMES

    cocotb.start_soon(drive_pdm(dut, pdm_bits))
    dut_out = await collect_pcm(dut, N_FRAMES)

    errors = []
    for i, (d, r) in enumerate(zip(dut_out, ref)):
        if d != r:
            errors.append(f"  sample {i:3d}: DUT={d:7d}  ref={r:7d}  diff={d-r}")

    assert not errors, (
        f"{len(errors)} mismatches (sine PDM):\n"
        + "\n".join(errors[:10])
        + ("\n  ..." if len(errors) > 10 else "")
    )


@cocotb.test()
async def test_sequential_frames(dut):
    """Two back-to-back PDM blocks produce independent, correct outputs.

    Block 1: all-ones PDM — steady-state should be positive.
    Block 2: all-zeros PDM — steady-state should be negative.

    Verifies that state carried over between blocks (integrators, comb delays)
    does not corrupt the second frame's output relative to the reference model.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    WARMUP = 10
    MEASURE = 5

    pdm_block1 = [1] * ((WARMUP + MEASURE) * DEC_RATIO)
    pdm_block2 = [0] * ((WARMUP + MEASURE) * DEC_RATIO)
    pdm_combined = pdm_block1 + pdm_block2

    ref_combined = cic_reference(pdm_combined)
    ref1 = ref_combined[WARMUP : WARMUP + MEASURE]
    ref2 = ref_combined[WARMUP + MEASURE + WARMUP : WARMUP + MEASURE + WARMUP + MEASURE]

    cocotb.start_soon(drive_pdm(dut, pdm_combined))
    dut_combined = await collect_pcm(dut, 2 * (WARMUP + MEASURE))
    dut1 = dut_combined[WARMUP : WARMUP + MEASURE]
    dut2 = dut_combined[WARMUP + MEASURE + WARMUP : WARMUP + MEASURE + WARMUP + MEASURE]

    errors = []
    for i, (d, r) in enumerate(zip(dut1, ref1)):
        if d != r:
            errors.append(f"  block1 sample {i}: DUT={d}  ref={r}")
    for i, (d, r) in enumerate(zip(dut2, ref2)):
        if d != r:
            errors.append(f"  block2 sample {i}: DUT={d}  ref={r}")

    assert not errors, f"{len(errors)} mismatches in sequential frames:\n" + "\n".join(
        errors
    )
