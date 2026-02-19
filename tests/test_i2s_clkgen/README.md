# test_i2s_clkgen

Unit tests for [`rtl/i2s_clkgen.v`](../../rtl/i2s_clkgen.v).

## DUT

`i2s_clkgen` is instantiated directly (no wrapper). The simulator top-level is
the module itself. Tests use `CLK_DIV=4`, giving:

- `BCLK` half-period = 4 system clocks, full period = 8 system clocks
- `LRCLK` half-period = 32 × 8 = 256 system clocks

## Test cases

- **test_reset_state** — verifies `bclk` and `lrclk` are low immediately after
  reset.
- **test_bclk_period** — waits for the first `bclk` rising edge, then counts
  `clk` cycles while `bclk` is high and while it is low; asserts each half
  equals `CLK_DIV`.
- **test_bclk_falling_pulse** — monitors both `bclk` and `bclk_falling` over
  ten `bclk` cycles; checks that `bclk_falling` pulses for exactly one `clk`
  cycle on every 1→0 transition of `bclk`, and that the pulse count equals the
  observed edge count.
- **test_lrclk_period** — waits for the first `lrclk` 0→1 transition, then
  counts `clk` cycles until the next 1→0 transition; asserts the count equals
  `32 × BCLK_PERIOD`.
- **test_lrclk_symmetry** — measures the high and low halves of `lrclk`
  separately (starting from the same 0→1 edge) and asserts both equal
  `32 × BCLK_PERIOD`, confirming a 50 % duty cycle.
