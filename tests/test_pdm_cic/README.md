# test_pdm_cic

cocotb unit tests for `rtl/pdm_cic.v` — the PDM→PCM Cascaded Integrator-Comb
decimation filter.

## Test strategy

The core approach is **bit-exact reference comparison**:

1. A first-order sigma-delta modulator (standard, textbook algorithm) converts
   known PCM signals into PDM bitstreams.
2. The same PDM stream is fed to both the DUT and a Python reference model that
   mirrors `pdm_cic.v`'s non-blocking-assignment semantics exactly.
3. Every `pcm_out` value from the DUT is compared against the Python reference.
   Bit-exact agreement is required — any discrepancy points to a bug in the RTL.

The reference model (`cic_reference` in `test_pdm_cic.py`) replicates these
RTL details:

- **Integrator pipeline delay** — non-blocking assignments mean `integ2`
  accumulates the *old* `integ1`, and `integ3` accumulates the *old* `integ2`,
  introducing one extra pipeline register per stage.
- **Comb input timing** — `comb1_delay` captures `integ3` *before* the current
  PDM sample's integrator update (both on the same `posedge clk`, non-blocking).
- **Output registration** — `pcm_valid` and `pcm_out` are registered; they
  change the clock cycle *after* `dec_tick`.
- **Decimation counter** — `dec_tick` fires when `dec_count == DEC_RATIO-1`
  (counts 0 … DEC_RATIO-1), so the first output arrives after exactly
  `DEC_RATIO` `pdm_valid` pulses.

## Test cases

| Test | Checks |
|------|--------|
| `test_reset_state` | `pcm_out=0`, `pcm_valid=0` immediately after reset |
| `test_pcm_valid_timing` | Exactly one `pcm_valid` per `DEC_RATIO` `pdm_valid` pulses; correct spacing |
| `test_pcm_valid_single_cycle` | `pcm_valid` is a one-cycle strobe |
| `test_pdm_mapping_polarity` | All-ones → positive; all-zeros → negative; equal magnitudes |
| `test_alternating_silence` | Alternating `1,0,1,0,…` PDM converges to 0 in steady state |
| `test_dc_bit_exact` | All-ones PDM: bit-exact match with Python reference (primary structural test) |
| `test_sine_bit_exact` | Sigma-delta encoded sine: bit-exact match with Python reference (end-to-end) |
| `test_sequential_frames` | Two consecutive PDM blocks; each matches its own reference (state isolation) |

## Running

```bash
cd tests/test_pdm_cic
make
```

Or from the repository root (runs all test suites):

```bash
make test
```
