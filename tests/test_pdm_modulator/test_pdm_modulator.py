"""Unit tests for the pdm_modulator module.

The pdm_modulator converts a signed 16-bit PCM sample to a 1-bit PDM
bitstream using a first-order sigma-delta algorithm:

  new_acc = accum + pcm_in          (17-bit signed intermediate)
  pdm_out = (new_acc >= 0) ? 1 : 0  (quantiser)
  accum   = new_acc - (pdm_out ? +32768 : -32768)  (error feedback)

Updates occur only when pdm_valid is high; pcm_in is held between updates.

Test strategy
-------------
A Python reference model mirrors the RTL's register-read timing.  In Icarus +
cocotb, 'await RisingEdge(dut.clk)' resumes in the active region *before*
non-blocking assignments commit, so reading dut.pdm_out immediately after the
trigger returns the value registered on the *previous* clock edge.  The
reference model accounts for this one-cycle read delay: reference[i] is the
value that was in the register *before* the i-th pdm_valid pulse fires.

Behavioural properties verified:
  - Reset: pdm_out=0 after reset, unchanged without pdm_valid
  - Gating: pdm_valid=0 suppresses accumulator and output updates
  - Silence (pcm_in=0): stream is 0,1,0,1,... from reset (alternating)
  - Full negative (pcm_in=-32768): all-zero output
  - Full positive (pcm_in=+32767): near-100% duty cycle; exactly one 0 in
    the first N bits due to the reset-state output captured on the first read
  - Bit-exact agreement with reference for DC, ramp, and mixed PCM sequences
  - Sparse pdm_valid: correct output even when pdm_valid fires once every N clocks
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# ---------------------------------------------------------------------------
# Python reference model (accounts for pre-NBA read delay in Icarus + cocotb)
# ---------------------------------------------------------------------------


def _to_signed16(x):
    """Truncate to 16-bit two's-complement signed integer."""
    x = x & 0xFFFF
    if x >= 0x8000:
        x -= 0x10000
    return x


def pdm_modulator_reference(pcm_in_seq):
    """Reference model matching cocotb's pre-NBA read timing.

    In Icarus + cocotb, reading dut.pdm_out right after 'await RisingEdge'
    returns the value that was registered *before* the current edge committed
    its non-blocking assignments.  This model captures that one-cycle delay:
    reference[i] = the pdm_out register value *before* the i-th update.

    Accepts a list of signed 16-bit integers (pcm_in values, one per
    pdm_valid pulse) and returns the corresponding list of 0/1 PDM bits
    as they would be read by drive_and_collect().
    """
    accum = 0  # signed 16-bit, reset state
    pdm_out = 0  # registered output, reset state
    bits = []
    for pcm_in in pcm_in_seq:
        bits.append(pdm_out)  # capture PRE-update registered value
        new_acc = accum + pcm_in  # 17-bit signed arithmetic
        pdm_out = 1 if new_acc >= 0 else 0  # quantiser
        next_accum = (new_acc - 32768) if pdm_out else (new_acc + 32768)
        accum = _to_signed16(next_accum)  # keep lower 16 bits, signed
    return bits


# ---------------------------------------------------------------------------
# cocotb helpers
# ---------------------------------------------------------------------------


async def reset_dut(dut):
    """Assert reset for 5 clock cycles then release."""
    dut.pcm_in.value = 0
    dut.pdm_valid.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_and_collect(dut, pcm_in_seq, pdm_valid_every=1):
    """Drive pcm_in with pdm_valid pulses and collect pdm_out bits.

    For each value in pcm_in_seq:
      - holds pdm_valid low for (pdm_valid_every - 1) idle clocks
      - then asserts pdm_valid for one clock, reading pdm_out after that edge

    Because cocotb resumes in the active region (before NBA), each read
    captures the value registered on the *previous* edge.  The reference model
    is written to match this behaviour.

    Returns a list of bits (one per pcm_in_seq entry).
    """
    bits = []
    for pcm_val in pcm_in_seq:
        dut.pcm_in.value = pcm_val & 0xFFFF  # two's-complement for negatives

        for _ in range(pdm_valid_every - 1):
            dut.pdm_valid.value = 0
            await RisingEdge(dut.clk)

        dut.pdm_valid.value = 1
        await RisingEdge(dut.clk)
        bits.append(int(dut.pdm_out.value))  # pre-NBA read: previous registered value

    dut.pdm_valid.value = 0
    return bits


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@cocotb.test()
async def test_reset_state(dut):
    """After reset: pdm_out=0 and stays 0 without any pdm_valid pulses."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    assert int(dut.pdm_out.value) == 0, "pdm_out should be 0 immediately after reset"

    await ClockCycles(dut.clk, 10)
    assert int(dut.pdm_out.value) == 0, "pdm_out should stay 0 with no pdm_valid"


@cocotb.test()
async def test_pdm_valid_gating(dut):
    """pdm_valid=0 suppresses output updates even when pcm_in is non-zero."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    dut.pdm_valid.value = 0
    dut.pcm_in.value = 0x7FFF  # +32767
    await ClockCycles(dut.clk, 20)

    assert (
        int(dut.pdm_out.value) == 0
    ), "pdm_out must stay at reset value (0) when pdm_valid is never asserted"


@cocotb.test()
async def test_silence_alternating(dut):
    """pcm_in=0 produces a 0,1,0,1,... stream starting from reset.

    Due to the pre-NBA read, the first sample captured is the reset value (0).
    The underlying PDM pattern is then 1,0,1,0,... as proven below; shifted
    by the one-cycle read delay this appears as 0,1,0,1,...

    Analytical trace from reset (accum=0):
      cycle 1: new_acc=0 >= 0 -> out=1, accum=-32768  [read: 0 (reset)]
      cycle 2: new_acc=-32768 < 0 -> out=0, accum=0   [read: 1]
      cycle 3: same as cycle 1                         [read: 0]
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 20
    bits = await drive_and_collect(dut, [0] * N)

    for i, b in enumerate(bits):
        expected = i % 2  # 0 on even indices, 1 on odd indices
        assert b == expected, f"bit {i}: expected {expected}, got {b} (pcm_in=0)"


@cocotb.test()
async def test_full_negative_all_zeros(dut):
    """pcm_in=-32768 produces an all-zero PDM stream.

    Analytical trace from reset (accum=0):
      cycle 1: new_acc = 0+(-32768) = -32768 < 0 -> out=0, accum=0
      cycle 2: identical (accum stays 0 forever)
    The pre-NBA read captures 0 (reset) on the first cycle, then 0 (stable),
    so all captured bits are 0.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 50
    bits = await drive_and_collect(dut, [-32768] * N)

    for i, b in enumerate(bits):
        assert b == 0, f"bit {i}: expected 0 for pcm_in=-32768, got {b}"


@cocotb.test()
async def test_full_positive_high_density(dut):
    """pcm_in=+32767 produces near-100% duty cycle.

    From reset, accum goes 0, -1, -2, ...; new_acc = accum+32767 >= 0 for all
    accum in [-32767, 0], so every update produces pdm_out=1.  The first zero
    output only occurs after 32769 updates.  Over N=200 cycles the registered
    PDM stream is [1]*200, but the pre-NBA read captures the reset value (0) on
    the very first sample, giving exactly N-1 ones.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 200
    bits = await drive_and_collect(dut, [32767] * N)
    ones = sum(bits)

    # First bit is always 0 (reset registered value), rest are 1.
    assert (
        ones == N - 1
    ), f"Expected {N - 1} ones in {N} bits for pcm_in=+32767 from reset, got {ones}"


@cocotb.test()
async def test_bit_exact_dc_levels(dut):
    """DC pcm_in values: DUT output matches Python reference bit-for-bit.

    Tests three DC levels: silence (0), +half-scale (+16384), -half-scale (-16384).
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())

    for pcm_val in [0, 16384, -16384]:
        await reset_dut(dut)
        N = 100
        ref = pdm_modulator_reference([pcm_val] * N)
        dut_bits = await drive_and_collect(dut, [pcm_val] * N)

        errors = [
            f"  bit {i}: DUT={d}, ref={r}"
            for i, (d, r) in enumerate(zip(dut_bits, ref))
            if d != r
        ]
        assert not errors, f"Mismatch for pcm_in={pcm_val}:\n" + "\n".join(errors[:10])


@cocotb.test()
async def test_bit_exact_ramp(dut):
    """Ramp PCM sequence: DUT matches Python reference bit-for-bit.

    Ramps from -32768 to +32767 over 256 steps, exercising the accumulator
    across its full signed range and catching any wrong feedback sign or
    accumulator bit-width issue.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 256
    pcm_seq = [
        max(-32768, min(32767, int(-32768 + i * 65535 / (N - 1)))) for i in range(N)
    ]

    ref = pdm_modulator_reference(pcm_seq)
    dut_bits = await drive_and_collect(dut, pcm_seq)

    errors = [
        f"  step {i}: pcm_in={pcm_seq[i]}, DUT={d}, ref={r}"
        for i, (d, r) in enumerate(zip(dut_bits, ref))
        if d != r
    ]
    assert not errors, f"{len(errors)} mismatches in ramp test:\n" + "\n".join(
        errors[:10]
    )


@cocotb.test()
async def test_bit_exact_varying(dut):
    """Varying PCM values: DUT matches Python reference bit-for-bit.

    Exercises transitions between common values to catch state-carrying bugs
    (wrong accumulator update on sign change, etc.).
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    pcm_seq = [0, 32767, -32768, 16384, -16384, 8192, -8192, 1000, -1000] * 20

    ref = pdm_modulator_reference(pcm_seq)
    dut_bits = await drive_and_collect(dut, pcm_seq)

    errors = [
        f"  step {i}: pcm_in={pcm_seq[i % 9]}, DUT={d}, ref={r}"
        for i, (d, r) in enumerate(zip(dut_bits, ref))
        if d != r
    ]
    assert not errors, f"{len(errors)} mismatches in varying PCM test:\n" + "\n".join(
        errors[:10]
    )


@cocotb.test()
async def test_pdm_valid_sparse(dut):
    """Sparse pdm_valid (once every 4 clocks): output still matches reference.

    Verifies that the accumulator is not unintentionally clocked during idle
    cycles and that the DUT's zero-order hold on pcm_in is correct.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 50
    pcm_seq = [0] * N  # silence -> analytically alternating

    ref = pdm_modulator_reference(pcm_seq)
    dut_bits = await drive_and_collect(dut, pcm_seq, pdm_valid_every=4)

    errors = [
        f"  step {i}: DUT={d}, ref={r}"
        for i, (d, r) in enumerate(zip(dut_bits, ref))
        if d != r
    ]
    assert not errors, f"{len(errors)} mismatches with sparse pdm_valid:\n" + "\n".join(
        errors[:10]
    )
