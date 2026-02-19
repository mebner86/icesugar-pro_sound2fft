"""Unit tests for i2s_rx module (via loopback: i2s_clkgen + i2s_tx → i2s_rx).

CLK_DIV=2, DATA_BITS=24. The TX serializes data that the RX deserializes.
RX outputs are validated against the original TX inputs.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

DATA_BITS = 24
CLK_DIV = 2
BCLK_PERIOD = 2 * CLK_DIV  # system clocks per BCLK cycle
# One full I2S frame = 64 BCLK periods = 64 * BCLK_PERIOD system clocks
FRAME_CLOCKS = 64 * BCLK_PERIOD


async def reset_dut(dut):
    """Apply reset and wait for it to deassert."""
    dut.rst_n.value = 0
    dut.tx_left.value = 0
    dut.tx_right.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def wait_for_valid(dut, signal, timeout_clocks=FRAME_CLOCKS * 3):
    """Wait until a valid signal pulses high. Returns after the rising edge."""
    for _ in range(timeout_clocks):
        await RisingEdge(dut.clk)
        if signal.value == 1:
            return
    raise TimeoutError(f"Timed out waiting for {signal._name}")


@cocotb.test()
async def test_reset_state(dut):
    """RX outputs should be 0 and valid signals low after reset."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    assert dut.rx_left.value == 0, "rx_left should be 0 after reset"
    assert dut.rx_right.value == 0, "rx_right should be 0 after reset"
    assert dut.rx_left_valid.value == 0, "rx_left_valid should be 0 after reset"
    assert dut.rx_right_valid.value == 0, "rx_right_valid should be 0 after reset"


@cocotb.test()
async def test_loopback_left(dut):
    """RX should recover the left channel sample that TX serialized."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_val = 0xABCDEF
    dut.tx_left.value = test_val
    dut.tx_right.value = 0

    # Wait for rx_left_valid (takes ~2 frames for pipeline to fill)
    await wait_for_valid(dut, dut.rx_left_valid)

    # First valid may be from the initial zero frame — wait one more
    await wait_for_valid(dut, dut.rx_left_valid)

    result = int(dut.rx_left.value)
    assert (
        result == test_val
    ), f"Left loopback: got 0x{result:06X}, expected 0x{test_val:06X}"


@cocotb.test()
async def test_loopback_right(dut):
    """RX should recover the right channel sample that TX serialized."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    test_val = 0x123456
    dut.tx_left.value = 0
    dut.tx_right.value = test_val

    await wait_for_valid(dut, dut.rx_right_valid)
    await wait_for_valid(dut, dut.rx_right_valid)

    result = int(dut.rx_right.value)
    assert (
        result == test_val
    ), f"Right loopback: got 0x{result:06X}, expected 0x{test_val:06X}"


@cocotb.test()
async def test_loopback_both_channels(dut):
    """RX should recover both channels simultaneously."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    left_val = 0x555555
    right_val = 0xAAAAAA
    dut.tx_left.value = left_val
    dut.tx_right.value = right_val

    # Wait for both channels to produce valid output
    left_ok = False
    right_ok = False
    for _ in range(FRAME_CLOCKS * 4):
        await RisingEdge(dut.clk)
        if dut.rx_left_valid.value == 1:
            left_ok = True
        if dut.rx_right_valid.value == 1:
            right_ok = True
        if left_ok and right_ok:
            break

    assert left_ok, "Never received rx_left_valid"
    assert right_ok, "Never received rx_right_valid"

    # Wait one more full frame to get stable data
    await wait_for_valid(dut, dut.rx_left_valid)
    left_result = int(dut.rx_left.value)

    await wait_for_valid(dut, dut.rx_right_valid)
    right_result = int(dut.rx_right.value)

    assert (
        left_result == left_val
    ), f"Left: got 0x{left_result:06X}, expected 0x{left_val:06X}"
    assert (
        right_result == right_val
    ), f"Right: got 0x{right_result:06X}, expected 0x{right_val:06X}"


@cocotb.test()
async def test_valid_pulses_single_cycle(dut):
    """left_valid and right_valid should each be high for exactly one clock cycle."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    dut.tx_left.value = 0x100000
    dut.tx_right.value = 0x200000

    # Wait for a left_valid pulse and check it's only 1 cycle wide
    await wait_for_valid(dut, dut.rx_left_valid)
    await RisingEdge(dut.clk)
    assert dut.rx_left_valid.value == 0, "left_valid should be high for only 1 clock"

    await wait_for_valid(dut, dut.rx_right_valid)
    await RisingEdge(dut.clk)
    assert dut.rx_right_valid.value == 0, "right_valid should be high for only 1 clock"


@cocotb.test()
async def test_changing_data(dut):
    """RX should track changing TX data across frames."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    samples = [0x111111, 0x222222, 0x333333]

    for val in samples:
        dut.tx_left.value = val
        dut.tx_right.value = val

        # Wait enough frames for the new data to propagate through TX→RX
        for _ in range(3):
            await wait_for_valid(dut, dut.rx_left_valid)

        left_result = int(dut.rx_left.value)
        assert (
            left_result == val
        ), f"Left: got 0x{left_result:06X}, expected 0x{val:06X}"
