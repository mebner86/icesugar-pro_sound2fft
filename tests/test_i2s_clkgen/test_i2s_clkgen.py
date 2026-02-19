"""Unit tests for i2s_clkgen module.

Tests the I2S clock generator with CLK_DIV=4 (default).
Expected timing:
  - BCLK toggles every CLK_DIV=4 system clocks → period = 8 clocks
  - LRCLK toggles every 32 BCLK falling edges → period = 64 BCLK periods = 512 clocks
  - bclk_falling is a single-cycle pulse when BCLK falls
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

CLK_DIV = 4
BCLK_HALF_PERIOD = CLK_DIV  # system clocks per BCLK half-period
BCLK_PERIOD = 2 * CLK_DIV  # system clocks per full BCLK cycle
LRCLK_HALF_PERIOD = 32 * BCLK_PERIOD  # system clocks per LRCLK half-period


async def reset_dut(dut):
    """Apply reset and wait for it to deassert."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset_state(dut):
    """All outputs should be low after reset."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    assert dut.bclk.value == 0, "BCLK should be 0 after reset"
    assert dut.lrclk.value == 0, "LRCLK should be 0 after reset"


@cocotb.test()
async def test_bclk_period(dut):
    """BCLK should toggle every CLK_DIV system clocks."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Wait for first BCLK rising edge (sampled by clk)
    while dut.bclk.value == 0:
        await RisingEdge(dut.clk)

    # Measure: count clk edges until BCLK falls and then rises again
    clk_count = 0
    while dut.bclk.value == 1:
        await RisingEdge(dut.clk)
        clk_count += 1
    high_time = clk_count

    clk_count = 0
    while dut.bclk.value == 0:
        await RisingEdge(dut.clk)
        clk_count += 1
    low_time = clk_count

    assert (
        high_time == BCLK_HALF_PERIOD
    ), f"BCLK high time {high_time} != expected {BCLK_HALF_PERIOD}"
    assert (
        low_time == BCLK_HALF_PERIOD
    ), f"BCLK low time {low_time} != expected {BCLK_HALF_PERIOD}"


@cocotb.test()
async def test_bclk_falling_pulse(dut):
    """bclk_falling should pulse for exactly one system clock on each BCLK falling edge."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Collect bclk_falling events over several BCLK cycles
    pulse_count = 0
    bclk_edges = 0
    prev_bclk = 0

    for _ in range(BCLK_PERIOD * 10):
        await RisingEdge(dut.clk)
        cur_bclk = int(dut.bclk.value)

        if prev_bclk == 1 and cur_bclk == 0:
            bclk_edges += 1

        if dut.bclk_falling.value == 1:
            pulse_count += 1
            # The pulse should coincide with BCLK transitioning high→low
            assert prev_bclk == 1, "bclk_falling asserted but BCLK was not high"

        prev_bclk = cur_bclk

    assert (
        pulse_count == bclk_edges
    ), f"bclk_falling pulse count {pulse_count} != BCLK falling edges {bclk_edges}"
    assert pulse_count > 0, "No bclk_falling pulses detected"


@cocotb.test()
async def test_lrclk_period(dut):
    """LRCLK should toggle every 32 BCLK falling edges."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Wait for first LRCLK transition (0→1)
    while dut.lrclk.value == 0:
        await RisingEdge(dut.clk)

    # Measure system clocks until next LRCLK transition (1→0)
    clk_count = 0
    while dut.lrclk.value == 1:
        await RisingEdge(dut.clk)
        clk_count += 1

    assert (
        clk_count == LRCLK_HALF_PERIOD
    ), f"LRCLK half-period {clk_count} != expected {LRCLK_HALF_PERIOD}"


@cocotb.test()
async def test_lrclk_symmetry(dut):
    """LRCLK should have a 50% duty cycle (both halves = 32 BCLK periods)."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Wait for first LRCLK transition (0→1)
    while dut.lrclk.value == 0:
        await RisingEdge(dut.clk)

    # Measure high half
    high_count = 0
    while dut.lrclk.value == 1:
        await RisingEdge(dut.clk)
        high_count += 1

    # Measure low half
    low_count = 0
    while dut.lrclk.value == 0:
        await RisingEdge(dut.clk)
        low_count += 1

    assert (
        high_count == LRCLK_HALF_PERIOD
    ), f"LRCLK high time {high_count} != expected {LRCLK_HALF_PERIOD}"
    assert (
        low_count == LRCLK_HALF_PERIOD
    ), f"LRCLK low time {low_count} != expected {LRCLK_HALF_PERIOD}"
