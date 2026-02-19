# test_i2s_tx

Unit tests for [`rtl/i2s_tx.v`](../../rtl/i2s_tx.v).

## DUT

`i2s_tx` cannot be tested alone because it depends on the `bclk_falling` and
`lrclk` strobes produced by `i2s_clkgen`. The simulator top-level is
[`i2s_tx_top.v`](i2s_tx_top.v), a thin wrapper that instantiates both modules
and exposes the internal signals (`bclk`, `lrclk`, `bclk_falling`, `sdata`) as
outputs so the testbench can observe them directly.

Tests use `CLK_DIV=2` and `DATA_BITS=24`. One BCLK period is 4 system clocks;
one I2S frame is 64 BCLK cycles = 256 system clocks.

## I2S serial format

Each 32-bit slot on `sdata` (one per channel per frame) is structured as:

| Bits | Content |
|------|---------|
| bit 0 | I2S delay — always 0 |
| bits 1–24 | 24-bit sample, MSB first |
| bits 25–31 | padding zeros |

Data is valid on `sdata` during `bclk` high; the receiver samples on the
falling edge.

## Helpers

### `wait_for_bclk_fall(dut)`

Detects a `bclk` 1→0 transition by comparing the current and previous values at
each `clk` rising edge. Uses the synchronous sampling idiom rather than
`FallingEdge(dut.bclk)` to stay aligned with the system clock.

### `capture_i2s_slot(dut)`

Captures one 32-bit I2S slot from `sdata`:

1. Synchronises to `bclk=0` first, to avoid straddling a partial BCLK cycle at
   an LRCLK boundary.
2. Calls `wait_for_bclk_fall` 32 times, sampling `sdata` after each falling
   edge.
3. Returns the decoded 24-bit integer (bits 1–24, MSB-first) and the raw 32-bit
   list for inspection.

This makes the testbench act as a software I2S receiver, verifying the TX
output independently of `i2s_rx`.

## Test cases

- **test_reset_output** — asserts `sdata` is 0 immediately after reset.
- **test_left_channel_data** — drives a known value on `left_data`, waits for
  an `lrclk` falling edge (start of the left channel slot), captures 32 serial
  bits with `capture_i2s_slot`, and checks both the delay bit (must be 0) and
  the decoded 24-bit value.
- **test_right_channel_data** — same for the right channel, triggered on the
  `lrclk` rising edge.
- **test_padding_bits_zero** — drives all-ones (`0xFFFFFF`) on both channels to
  maximise the chance of leaking data into padding; captures a slot and asserts
  bits 25–31 are all 0.
- **test_alternating_frames** — iterates over two `(left, right)` value pairs,
  updating the inputs before each frame, then captures and verifies both the
  left and right slots; confirms the TX latches new data at each LRCLK
  transition.
