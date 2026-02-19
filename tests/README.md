# Unit Tests

This directory contains cocotb-based unit tests for the RTL modules in `rtl/`.
Each sub-directory targets one module (or a small group of closely related
modules) and is self-contained: it has its own `Makefile` and, where needed, a
thin Verilog wrapper that wires multiple modules together.

## Test suites

| Directory | Module(s) under test | Details |
|---|---|---|
| [`test_i2s_clkgen/`](test_i2s_clkgen/README.md) | `i2s_clkgen` | Clock generator — BCLK, LRCLK, bclk_falling |
| [`test_i2s_tx/`](test_i2s_tx/README.md) | `i2s_clkgen` + `i2s_tx` | TX serializer via `i2s_tx_top` wrapper |
| [`test_i2s_rx/`](test_i2s_rx/README.md) | `i2s_clkgen` + `i2s_tx` + `i2s_rx` | RX deserializer via loopback wrapper |

## Running the tests

Run a single suite from its own directory:

```bash
cd test_i2s_clkgen
make
```

Or run all suites from the repository root:

```bash
make test
```

## Test strategy

### Simulation clock

All tests drive the design with a **40 ns (25 MHz)** system clock started by
`cocotb.Clock`, matching the on-board oscillator of the iCESugar-Pro. This has
no effect on test correctness — all assertions are cycle-based, not
time-based — but it means the nanosecond timestamps in the simulation log
correspond directly to real hardware time, which is useful when correlating a
simulation trace against a logic analyser capture.

### Synchronous sampling idiom

Because all RTL outputs are registered (updated on `clk` rising edges), the
testbench always advances time in steps of one system clock using
`await RisingEdge(dut.clk)` and then reads signal values.

A common pattern throughout is waiting for a derived signal to reach a
particular state *as seen at a `clk` rising edge*:

```python
while dut.bclk.value == 0:
    await RisingEdge(dut.clk)
```

This exits at the first `clk` rising edge where `bclk` is already `1`,
detecting the **0→1 transition as sampled by `clk`** — equivalent to how the
hardware sees it. Using `await RisingEdge(dut.bclk)` instead would fire at the
raw signal transition and land the testbench between two `clk` edges, making
subsequent cycle-counting incorrect.

A superficially similar alternative — `await RisingEdge(dut.bclk)` followed by
`await RisingEdge(dut.clk)` — re-synchronises to `clk` but lands one cycle
later (edge N+1 instead of N), causing any measurement loop started immediately
after to count one too few cycles. The while loop exits at exactly edge N.

`RisingEdge(signal)` + `RisingEdge(clk)` is appropriate when you only need to
*wait for an event* and will not start counting from that edge.

### Test isolation and shared helpers

Each `@cocotb.test()` coroutine is run independently by the cocotb test runner,
sequentially in file order. All tests share the **same DUT instance** for the
duration of a simulation run — there is no automatic reset between them. Each
test is therefore responsible for bringing the DUT into a known state before
exercising it.

Shared logic is factored into plain `async` helper functions (e.g.
`reset_dut`, `wait_for_bclk_fall`, `capture_i2s_slot`) that any test can
`await`. If one test fails, the remaining tests still execute.

### Reset

Every test applies an active-low reset for a few cycles before the DUT is
exercised. The `reset_dut` helper deasserts reset and then waits one additional
`clk` rising edge so the first registered outputs are visible.
