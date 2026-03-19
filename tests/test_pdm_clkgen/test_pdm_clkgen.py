"""Unit tests for the pdm_clkgen module.

The pdm_clkgen divides a system clock to produce a PDM clock and a
single-cycle rising-edge strobe.  Default CLK_DIV=4 gives a half-period
of 4 system clocks, so the full PDM period is 8 system clocks
(25 MHz / 8 = 3.125 MHz).

Test strategy
-------------
In Icarus + cocotb, 'await RisingEdge(dut.clk)' resumes in the active
region *before* non-blocking assignments commit.  So reading registered
outputs immediately after the trigger returns the value from the
*previous* clock edge.  The tests account for this one-cycle read delay.

Behavioural properties verified:
  - Reset: pdm_clk=0 and pdm_clk_rise=0 after reset
  - Period: pdm_clk toggles every CLK_DIV system clocks (default 4)
  - 50% duty cycle over many cycles
  - Rising-edge strobe: pdm_clk_rise is high for exactly 1 system clock,
    coinciding with the system clock edge where pdm_clk transitions 0→1
  - Strobe does not fire on falling edges of pdm_clk
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


CLK_PERIOD_NS = 40  # 25 MHz
CLK_DIV = 4  # Default parameter value


async def reset_dut(dut):
    """Assert reset for 5 clocks then release."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset_state(dut):
    """After reset: pdm_clk=0 and pdm_clk_rise=0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    assert int(dut.pdm_clk.value) == 0, "pdm_clk should be 0 after reset"
    assert int(dut.pdm_clk_rise.value) == 0, "pdm_clk_rise should be 0 after reset"

    # Stay idle for a few more clocks — outputs should remain stable
    await ClockCycles(dut.clk, 3)
    # Note: after 3 clocks the counter hasn't wrapped yet (needs CLK_DIV=4 clocks)
    # so pdm_clk is still 0


@cocotb.test()
async def test_period(dut):
    """pdm_clk toggles every CLK_DIV system clocks, giving a full period of 2*CLK_DIV."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    # Collect pdm_clk values over several periods
    num_clocks = CLK_DIV * 2 * 10  # 10 full periods
    values = []
    for _ in range(num_clocks):
        await RisingEdge(dut.clk)
        values.append(int(dut.pdm_clk.value))

    # Find rising edges (0→1 transitions)
    rising_edges = []
    for i in range(1, len(values)):
        if values[i - 1] == 0 and values[i] == 1:
            rising_edges.append(i)

    # Verify period between consecutive rising edges
    for i in range(1, len(rising_edges)):
        period = rising_edges[i] - rising_edges[i - 1]
        assert period == 2 * CLK_DIV, (
            f"Expected period {2 * CLK_DIV}, got {period} "
            f"between edges at {rising_edges[i - 1]} and {rising_edges[i]}"
        )


@cocotb.test()
async def test_duty_cycle(dut):
    """pdm_clk has 50% duty cycle."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    num_clocks = CLK_DIV * 2 * 20  # 20 full periods
    high_count = 0
    for _ in range(num_clocks):
        await RisingEdge(dut.clk)
        if int(dut.pdm_clk.value) == 1:
            high_count += 1

    assert (
        high_count == num_clocks // 2
    ), f"Expected 50% duty cycle ({num_clocks // 2} highs), got {high_count}"


@cocotb.test()
async def test_rise_strobe_timing(dut):
    """pdm_clk_rise is high for exactly 1 clock, on the edge where pdm_clk goes 0→1.

    In Icarus + cocotb, await RisingEdge(dut.clk) resumes before NBAs
    commit.  Both pdm_clk_rise (combinational: toggle && !clk_reg) and
    pdm_clk (registered: clk_reg) reflect pre-update state.  So when the
    strobe reads as 1, pdm_clk still shows 0 (about to become 1).  On the
    *next* sample pdm_clk reads as 1.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    num_clocks = CLK_DIV * 2 * 10  # 10 full periods
    pdm_vals = []
    rise_vals = []

    for _ in range(num_clocks):
        await RisingEdge(dut.clk)
        pdm_vals.append(int(dut.pdm_clk.value))
        rise_vals.append(int(dut.pdm_clk_rise.value))

    # Every pdm_clk_rise=1 should precede a 0→1 transition of pdm_clk
    rise_indices = [i for i, v in enumerate(rise_vals) if v == 1]
    assert len(rise_indices) > 0, "No rising-edge strobes detected"

    for idx in rise_indices:
        # Pre-NBA: pdm_clk is still 0 (about to transition to 1)
        assert pdm_vals[idx] == 0, (
            f"pdm_clk_rise=1 at index {idx} but pdm_clk={pdm_vals[idx]} "
            f"(expected 0, pre-NBA read)"
        )
        # Next sample: pdm_clk should now be 1 (NBA committed)
        if idx + 1 < len(pdm_vals):
            assert pdm_vals[idx + 1] == 1, (
                f"pdm_clk_rise=1 at index {idx} but next pdm_clk={pdm_vals[idx + 1]} "
                f"(expected 1 after NBA commits)"
            )

    # Verify no strobe when pdm_clk is high (would indicate a falling edge strobe)
    for i in range(len(pdm_vals)):
        if rise_vals[i] == 1:
            assert pdm_vals[i] == 0, (
                f"pdm_clk_rise=1 at index {i} but pdm_clk is already 1 "
                f"(strobe should only fire on 0→1 transitions)"
            )


@cocotb.test()
async def test_strobe_is_single_cycle(dut):
    """pdm_clk_rise is never high for two consecutive system clocks."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    num_clocks = CLK_DIV * 2 * 20
    prev_rise = 0
    strobe_count = 0

    for i in range(num_clocks):
        await RisingEdge(dut.clk)
        curr_rise = int(dut.pdm_clk_rise.value)
        assert not (
            prev_rise == 1 and curr_rise == 1
        ), f"pdm_clk_rise was high for consecutive clocks at index {i}"
        if curr_rise:
            strobe_count += 1
        prev_rise = curr_rise

    # Should see exactly one strobe per PDM period
    expected = num_clocks // (CLK_DIV * 2)
    assert (
        strobe_count == expected
    ), f"Expected {expected} strobes in {num_clocks} clocks, got {strobe_count}"
