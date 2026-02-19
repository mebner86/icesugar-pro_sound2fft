# test_i2s_rx

Unit tests for [`rtl/i2s_rx.v`](../../rtl/i2s_rx.v).

## DUT

The simulator top-level is [`i2s_rx_top.v`](i2s_rx_top.v), a loopback wrapper
that instantiates all three I2S modules and connects them in series:

```
tx_left  ──►┐
             │  i2s_tx ──► sdata ──► i2s_rx ──► rx_left  + rx_left_valid
tx_right ──►┘                                ──► rx_right + rx_right_valid
                 ↑                  ↑
            i2s_clkgen  (bclk_falling, lrclk shared by both)
```

Rather than bit-banging a valid I2S bit stream from Python, `i2s_tx` is trusted
to produce correct I2S and used to drive `i2s_rx`. The test injects values at
the TX parallel inputs and verifies they appear at the RX parallel outputs.

Tests use `CLK_DIV=2` and `DATA_BITS=24`. One I2S frame is 64 BCLK cycles =
256 system clocks (`FRAME_CLOCKS`).

## Pipeline latency

After reset the TX and RX state machines start from zero. The first `valid`
pulse from the RX reflects the frame that was in flight during reset
initialisation, which carries zeros. Most tests therefore wait for **two**
`valid` pulses before reading the output — the second pulse is guaranteed to
carry the value that was set after reset.

## Helper: `wait_for_valid(dut, signal)`

Polls for a single-cycle high pulse on `signal` (either `rx_left_valid` or
`rx_right_valid`) by stepping through `clk` rising edges. Raises `TimeoutError`
after `FRAME_CLOCKS × 3` cycles with no pulse, which cocotb reports as a test
failure.

## Test cases

- **test_reset_state** — asserts `rx_left`, `rx_right`, `rx_left_valid`, and
  `rx_right_valid` are all 0 immediately after reset.
- **test_loopback_left** — drives a known value on `tx_left` (right channel
  zeroed), waits for two `rx_left_valid` pulses, and checks `rx_left` matches.
- **test_loopback_right** — same for the right channel.
- **test_loopback_both_channels** — drives distinct values on both channels
  simultaneously; polls until both `rx_left_valid` and `rx_right_valid` have
  been seen, waits one more frame for stable data, then reads and checks both
  outputs.
- **test_valid_pulses_single_cycle** — after a `valid` pulse goes high, advances
  one more `clk` cycle and asserts the signal is already low; verifies the valid
  signal is a one-cycle strobe, not a level.
- **test_changing_data** — iterates over three sample values, updating
  `tx_left`/`tx_right` for each; waits three `valid` pulses per value to allow
  the new data to fully propagate through the TX→RX pipeline, then checks the
  RX output matches.
