"""Unit tests for i2s_tx module (via i2s_tx_top wrapper with i2s_clkgen).

CLK_DIV=2, DATA_BITS=24. BCLK period = 4 system clocks.
I2S format: MSB-first, 1-BCLK delay after LRCLK transition, 24 data bits, 8 padding bits.

Note: sdata is sampled by detecting bclk 1->0 transitions via RisingEdge(clk)
rather than using the bclk_falling wire or FallingEdge(bclk). After an LRCLK
edge, we first synchronize to bclk=0 to avoid catching a partial BCLK cycle
that coincides with the LRCLK transition itself.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

DATA_BITS = 24


async def reset_dut(dut):
    """Apply reset and wait for it to deassert."""
    dut.rst_n.value = 0
    dut.left_data.value = 0
    dut.right_data.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def wait_for_bclk_fall(dut):
    """Wait until bclk transitions 1->0, then return."""
    prev = int(dut.bclk.value)
    while True:
        await RisingEdge(dut.clk)
        cur = int(dut.bclk.value)
        if prev == 1 and cur == 0:
            return
        prev = cur


async def capture_i2s_slot(dut):
    """Capture one 32-bit I2S slot worth of sdata bits.

    Synchronizes to bclk low first (to skip any partial BCLK cycle at the
    LRCLK boundary), then samples sdata on each BCLK 1->0 transition.
    Returns the DATA_BITS-bit value and the raw bit list.
    """
    # Ensure we start from bclk low so wait_for_bclk_fall sees a full cycle
    while int(dut.bclk.value) != 0:
        await RisingEdge(dut.clk)

    bits = []
    for _ in range(32):
        await wait_for_bclk_fall(dut)
        bits.append(int(dut.sdata.value))

    # bits[0] = delay bit (should be 0), bits[1..24] = data, bits[25..31] = padding
    data_bits = bits[1 : DATA_BITS + 1]
    value = 0
    for b in data_bits:
        value = (value << 1) | b
    return value, bits


@cocotb.test()
async def test_reset_output(dut):
    """sdata should be 0 after reset."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    assert dut.sdata.value == 0, "sdata should be 0 after reset"


@cocotb.test()
async def test_left_channel_data(dut):
    """TX should serialize left_data correctly in the left channel slot."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_left = 0xABCDEF
    test_right = 0x123456
    dut.left_data.value = test_left
    dut.right_data.value = test_right

    await FallingEdge(dut.lrclk)
    value, bits = await capture_i2s_slot(dut)

    assert bits[0] == 0, "I2S delay bit should be 0"
    assert (
        value == test_left
    ), f"Left channel: got 0x{value:06X}, expected 0x{test_left:06X}"


@cocotb.test()
async def test_right_channel_data(dut):
    """TX should serialize right_data correctly in the right channel slot."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_left = 0xABCDEF
    test_right = 0x123456
    dut.left_data.value = test_left
    dut.right_data.value = test_right

    await RisingEdge(dut.lrclk)
    value, bits = await capture_i2s_slot(dut)

    assert bits[0] == 0, "I2S delay bit should be 0"
    assert (
        value == test_right
    ), f"Right channel: got 0x{value:06X}, expected 0x{test_right:06X}"


@cocotb.test()
async def test_padding_bits_zero(dut):
    """Padding bits (after DATA_BITS) should be 0."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    dut.left_data.value = 0xFFFFFF  # all ones
    dut.right_data.value = 0xFFFFFF

    await FallingEdge(dut.lrclk)
    _, bits = await capture_i2s_slot(dut)

    padding = bits[DATA_BITS + 1 :]
    assert all(b == 0 for b in padding), f"Padding bits should be 0, got {padding}"


@cocotb.test()
async def test_alternating_frames(dut):
    """TX should correctly serialize different data across consecutive frames."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    samples = [(0x111111, 0x222222), (0x333333, 0x444444)]

    for left_val, right_val in samples:
        dut.left_data.value = left_val
        dut.right_data.value = right_val

        # Capture left slot
        await FallingEdge(dut.lrclk)
        left_out, _ = await capture_i2s_slot(dut)

        # Capture right slot
        await RisingEdge(dut.lrclk)
        right_out, _ = await capture_i2s_slot(dut)

        assert (
            left_out == left_val
        ), f"Left: got 0x{left_out:06X}, expected 0x{left_val:06X}"
        assert (
            right_out == right_val
        ), f"Right: got 0x{right_out:06X}, expected 0x{right_val:06X}"
