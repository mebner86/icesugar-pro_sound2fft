# Unit Tests

This directory contains cocotb-based unit tests for the RTL modules in `rtl/`.
Each sub-directory targets one module (or a small group of closely related
modules) and is self-contained: it has its own `Makefile` and, where needed, a
thin Verilog wrapper that wires multiple modules together.

## Structure

| Directory | Module(s) under test | Simulator top-level |
|---|---|---|
| `test_i2s_clkgen/` | `i2s_clkgen` | `i2s_clkgen` (direct) |
| `test_i2s_tx/` | `i2s_clkgen` + `i2s_tx` | `i2s_tx_top` wrapper |
| `test_i2s_rx/` | `i2s_clkgen` + `i2s_tx` + `i2s_rx` | `i2s_rx_top` wrapper |

## Running the Tests

Each test directory contains a `Makefile` that drives cocotb with Icarus
Verilog.  Run a suite from its own directory:

```
cd test_i2s_clkgen
make
```

Or run all suites from the repository root (requires a `make test` target in the
top-level `Makefile`, if present).

## Test Strategy

### Simulation clock

All tests drive the design with a **40 ns (25 MHz)** system clock started by
`cocotb.Clock`, matching the on-board oscillator of the iCESugar-Pro.  This has
no effect on test correctness — all assertions are cycle-based, not
time-based — but it means the nanosecond timestamps in the simulation log
correspond directly to real hardware time, which is useful when correlating a
simulation trace against a logic analyser capture.

Every signal observation is made on a **rising edge of `clk`** so that the
testbench samples signals in exactly the same way the synthesized design
would — one cycle after the registered output is updated.

### Synchronous sampling idiom

Because all RTL outputs are registered (updated on `clk` rising edges), the
testbench always advances time in steps of one system clock using
`await RisingEdge(dut.clk)` and then reads signal values.

A common pattern used throughout is waiting for a derived clock signal (such as
`bclk`) to reach a particular state *as seen at a `clk` rising edge*:

```python
while dut.bclk.value == 0:
    await RisingEdge(dut.clk)
```

This loop advances one system clock at a time and exits at the first `clk`
rising edge where `bclk` is already `1`.  It detects the **0→1 transition of
`bclk` as sampled by `clk`** — equivalent to how the hardware sees it — rather
than using `await RisingEdge(dut.bclk)`, which would fire at the raw signal
transition and land the testbench between two `clk` edges.  Keeping everything
synchronised to `clk` is important when the following code measures durations by
counting `clk` cycles.

The same pattern is applied in reverse (`while dut.bclk.value == 1`) to detect
the 1→0 transition, and generalises to any registered signal (e.g. `lrclk`).

A superficially similar alternative is `await RisingEdge(dut.bclk)` followed by
`await RisingEdge(dut.clk)`.  This re-synchronises to `clk` after the signal
event, but it lands one `clk` cycle **later** than the while loop: the
`RisingEdge(dut.bclk)` fires at the same simulation time as edge N (the
transition edge), and the subsequent `RisingEdge(dut.clk)` then advances to
edge N+1.  Any measurement loop that starts at N+1 misses the first clock of
the high period and counts one too few cycles.  The while loop exits exactly at
edge N, so the measurement is correct.

The `RisingEdge(signal)` + `RisingEdge(clk)` pattern is appropriate when you
only need to *wait for an event* and will not start counting from that edge.
Whenever the starting state is known (e.g. guaranteed `0` after `reset_dut`),
the while idiom is preferred throughout this test suite because it is
consistent, precise, and avoids the off-by-one risk.

### Test isolation and shared helpers

Each `@cocotb.test()` coroutine is run independently by the cocotb test runner,
sequentially in file order.  All tests share the **same DUT instance** for the
duration of a simulation run — there is no automatic reset between them.  This
means each test is responsible for bringing the DUT into a known state before
exercising it.

Tests cannot invoke each other as tests.  Shared logic is factored into plain
`async` helper functions (e.g. `reset_dut`, `wait_for_bclk_fall`,
`capture_i2s_slot`) that any test can `await`.  If one test fails, the remaining
tests still execute.

### Reset

Every test applies an active-low reset for a few cycles before the DUT is
exercised.  The `reset_dut` helper deasserts reset and then waits one additional
`clk` rising edge so the first registered outputs are visible.

### test_i2s_clkgen

Tests the clock generator in isolation with `CLK_DIV=4`.

- **test_reset_state** — verifies `bclk` and `lrclk` are low immediately after
  reset.
- **test_bclk_period** — counts `clk` cycles while `bclk` is high and then
  while it is low; asserts each equals `CLK_DIV` (one half-period).
- **test_bclk_falling_pulse** — monitors `bclk_falling` over ten `bclk` cycles
  and checks that it pulses for exactly one `clk` cycle on every 1→0 transition
  of `bclk`.
- **test_lrclk_period** — measures the number of `clk` cycles between two
  consecutive `lrclk` transitions and asserts it equals 32 × `BCLK_PERIOD`.
- **test_lrclk_symmetry** — measures the high and low halves of `lrclk`
  separately and asserts 50 % duty cycle.

### test_i2s_tx

Tests the TX serializer through a wrapper (`i2s_tx_top`) that instantiates
`i2s_clkgen` alongside `i2s_tx`.  `CLK_DIV=2`, `DATA_BITS=24`.

`sdata` is sampled by detecting `bclk` 1→0 transitions via
`wait_for_bclk_fall`, which uses the same synchronous sampling idiom described
above.  Before capturing a slot, `capture_i2s_slot` first synchronises to
`bclk=0` to avoid straddling a partial BCLK cycle at the LRCLK boundary.

- **test_reset_output** — asserts `sdata` is 0 after reset.
- **test_left_channel_data** — drives a known 24-bit value into `left_data`,
  waits for an `lrclk` falling edge (start of the left slot), captures 32
  serial bits, and checks the 24 data bits match the input.
- **test_right_channel_data** — same for the right channel (triggered on
  `lrclk` rising edge).
- **test_padding_bits_zero** — verifies that the 8 padding bits after the 24
  data bits are always 0.
- **test_alternating_frames** — changes `left_data`/`right_data` across two
  consecutive frames and verifies both channels serialize the correct values
  each time.

### test_i2s_rx

Tests the RX deserializer through a loopback wrapper (`i2s_rx_top`) that
instantiates `i2s_clkgen`, `i2s_tx`, and `i2s_rx` with `sdata` wired directly
from TX output to RX input.  `CLK_DIV=2`, `DATA_BITS=24`.

The RX pipeline takes approximately two full I2S frames to fill after reset, so
most tests wait for two `rx_left_valid` / `rx_right_valid` pulses before
reading the output registers.

- **test_reset_state** — asserts `rx_left`, `rx_right`, and both valid signals
  are 0 after reset.
- **test_loopback_left** — drives a known value on `tx_left` and verifies
  `rx_left` matches after two valid pulses.
- **test_loopback_right** — same for the right channel.
- **test_loopback_both_channels** — drives both channels simultaneously and
  checks both outputs are correct.
- **test_valid_pulses_single_cycle** — checks that each valid signal is
  asserted for exactly one `clk` cycle.
- **test_changing_data** — updates TX data across three frames and verifies the
  RX output tracks the changes.
