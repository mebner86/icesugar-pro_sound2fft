"""Unit tests for the pdm_modulator module with ORDER=2.

The 2nd-order CIFB sigma-delta modulator uses two cascaded integrators with
dual DAC feedback, producing NTF = (1 − z⁻¹)².  This gives 40 dB/decade
noise shaping — double the 1st-order's 20 dB/decade.

Algorithm per pdm_valid cycle:
  sum1    = acc1 + pcm_in
  sum2    = acc2 + sum1
  pdm_out = (sum2 >= 0) ? 1 : 0
  fb      = pdm_out ? +32768 : −32768
  acc1    = clamp(sum1 − fb)        (clamp to ±2²³)
  acc2    = clamp(sum2 − fb)

Test strategy
-------------
A Python reference model mirrors the RTL.  In Icarus + cocotb, reading
dut.pdm_out after 'await RisingEdge(dut.clk)' returns the value registered
on the *previous* clock edge (pre-NBA read).  The reference model accounts
for this one-cycle delay.

Behavioural properties verified:
  - Reset: pdm_out=0 after reset, unchanged without pdm_valid
  - Gating: pdm_valid=0 suppresses updates
  - Silence (pcm_in=0): 50% duty cycle
  - Full negative (pcm_in=−32768): all-zero output
  - Full positive (pcm_in=+32767): near-100% duty cycle
  - Bit-exact agreement with reference for DC, ramp, and mixed PCM sequences
  - Duty cycle accuracy: average PDM density tracks PCM level within ±2%
  - Sparse pdm_valid: correct output even with idle clocks between strobes
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# ---------------------------------------------------------------------------
# Python reference model (2nd-order CIFB, accounts for pre-NBA read delay)
# ---------------------------------------------------------------------------

CLAMP_HI = 8388607  #  2^23 - 1
CLAMP_LO = -8388608  # -2^23


def _clamp(val):
    """Clamp to ±2²³ range."""
    if val > CLAMP_HI:
        return CLAMP_HI
    if val < CLAMP_LO:
        return CLAMP_LO
    return val


def _to_signed16(x):
    """Interpret as 16-bit two's-complement signed integer."""
    x = x & 0xFFFF
    if x >= 0x8000:
        x -= 0x10000
    return x


def pdm_mod2_reference(pcm_in_seq):
    """Reference model for ORDER=2, matching cocotb pre-NBA read timing.

    Returns a list of 0/1 PDM bits as they would be read by drive_and_collect().
    """
    acc1 = 0
    acc2 = 0
    pdm_out = 0
    bits = []
    for pcm_in in pcm_in_seq:
        bits.append(pdm_out)  # capture PRE-update registered value
        sum1 = acc1 + pcm_in
        sum2 = acc2 + sum1
        out_bit = 1 if sum2 >= 0 else 0
        fb = 32768 if out_bit else -32768
        acc1 = _clamp(sum1 - fb)
        acc2 = _clamp(sum2 - fb)
        pdm_out = out_bit
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

    Returns a list of bits (one per pcm_in_seq entry).
    """
    bits = []
    for pcm_val in pcm_in_seq:
        dut.pcm_in.value = pcm_val & 0xFFFF

        for _ in range(pdm_valid_every - 1):
            dut.pdm_valid.value = 0
            await RisingEdge(dut.clk)

        dut.pdm_valid.value = 1
        await RisingEdge(dut.clk)
        bits.append(int(dut.pdm_out.value))

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

    assert int(dut.pdm_out.value) == 0, "pdm_out should be 0 after reset"

    await ClockCycles(dut.clk, 10)
    assert int(dut.pdm_out.value) == 0, "pdm_out should stay 0 with no pdm_valid"


@cocotb.test()
async def test_pdm_valid_gating(dut):
    """pdm_valid=0 suppresses output updates even when pcm_in is non-zero."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    dut.pdm_valid.value = 0
    dut.pcm_in.value = 0x7FFF
    await ClockCycles(dut.clk, 20)

    assert (
        int(dut.pdm_out.value) == 0
    ), "pdm_out must stay at reset value when pdm_valid is never asserted"


@cocotb.test()
async def test_silence_50pct_duty(dut):
    """pcm_in=0 produces ~50% duty cycle.

    The 2nd-order pattern for silence is 1,0,0,1,1,0,0,1,... (period 4)
    rather than the 1st-order's 1,0,1,0,... but both average to 50%.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 200
    bits = await drive_and_collect(dut, [0] * N)
    ones = sum(bits)
    duty = ones / N

    assert (
        abs(duty - 0.5) < 0.02
    ), f"Silence duty cycle should be ~50%, got {duty*100:.1f}%"


@cocotb.test()
async def test_full_negative_all_zeros(dut):
    """pcm_in=−32768 produces an all-zero PDM stream.

    Trace from reset (acc1=0, acc2=0):
      sum1 = 0+(-32768) = -32768; sum2 = 0+(-32768) = -32768 < 0 → out=0
      fb = -32768; acc1 = clamp(-32768+32768)=0; acc2 = clamp(-32768+32768)=0
      → stable at acc1=0, acc2=0, out=0 forever
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

    The 2nd-order modulator at near-full-scale produces almost all 1s,
    with rare 0 insertions.  Over 200 samples from reset, the first
    captured bit is 0 (reset state) and the rest are nearly all 1.
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 200
    bits = await drive_and_collect(dut, [32767] * N)
    ref = pdm_mod2_reference([32767] * N)

    # Verify bit-exact match with reference
    errors = [
        f"  bit {i}: DUT={d}, ref={r}"
        for i, (d, r) in enumerate(zip(bits, ref))
        if d != r
    ]
    assert not errors, "Mismatch for pcm_in=+32767:\n" + "\n".join(errors[:10])

    # Also check high duty cycle
    ones = sum(bits)
    assert ones >= N - 5, f"Expected near-100% duty for pcm_in=+32767, got {ones}/{N}"


@cocotb.test()
async def test_bit_exact_dc_levels(dut):
    """DC pcm_in values: DUT output matches Python reference bit-for-bit."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())

    for pcm_val in [0, 16384, -16384, 8192, -8192]:
        await reset_dut(dut)
        N = 200
        ref = pdm_mod2_reference([pcm_val] * N)
        dut_bits = await drive_and_collect(dut, [pcm_val] * N)

        errors = [
            f"  bit {i}: DUT={d}, ref={r}"
            for i, (d, r) in enumerate(zip(dut_bits, ref))
            if d != r
        ]
        assert not errors, f"Mismatch for pcm_in={pcm_val}:\n" + "\n".join(errors[:10])


@cocotb.test()
async def test_bit_exact_ramp(dut):
    """Ramp PCM sequence: DUT matches Python reference bit-for-bit."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 256
    pcm_seq = [
        max(-32768, min(32767, int(-32768 + i * 65535 / (N - 1)))) for i in range(N)
    ]

    ref = pdm_mod2_reference(pcm_seq)
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
    """Varying PCM values: DUT matches Python reference bit-for-bit."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    pcm_seq = [0, 32767, -32768, 16384, -16384, 8192, -8192, 1000, -1000] * 20

    ref = pdm_mod2_reference(pcm_seq)
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
async def test_duty_cycle_accuracy(dut):
    """Average PDM density tracks PCM level for several DC inputs.

    For each DC level, run enough samples to get a stable average and
    verify it matches the expected duty cycle within ±2%.
    Expected: duty = (pcm_in + 32768) / 65536
    """
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())

    for pcm_val in [0, 16384, -16384, 24000, -24000, 32767, -32768]:
        await reset_dut(dut)
        N = 2000
        bits = await drive_and_collect(dut, [pcm_val] * N)

        expected_duty = (pcm_val + 32768) / 65536
        actual_duty = sum(bits) / N
        assert abs(actual_duty - expected_duty) < 0.02, (
            f"pcm_in={pcm_val}: expected duty={expected_duty:.3f}, "
            f"got {actual_duty:.3f}"
        )


@cocotb.test()
async def test_pdm_valid_sparse(dut):
    """Sparse pdm_valid (once every 4 clocks): output still matches reference."""
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())
    await reset_dut(dut)

    N = 100
    pcm_seq = [0] * N

    ref = pdm_mod2_reference(pcm_seq)
    dut_bits = await drive_and_collect(dut, pcm_seq, pdm_valid_every=4)

    errors = [
        f"  step {i}: DUT={d}, ref={r}"
        for i, (d, r) in enumerate(zip(dut_bits, ref))
        if d != r
    ]
    assert not errors, f"{len(errors)} mismatches with sparse pdm_valid:\n" + "\n".join(
        errors[:10]
    )
