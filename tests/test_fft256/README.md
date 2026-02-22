# test_fft256

Unit tests for [`rtl/fft256.v`](../../rtl/fft256.v).

## DUT

`fft256` is tested directly — no wrapper is needed because it has a
self-contained interface: 16-bit signed samples in, 9-bit log-scaled magnitude
values out.

```
sample_in[15:0] ──► ┌──────────┐ ──► mag_addr[7:0]
sample_valid    ──► │  fft256  │ ──► mag_data[8:0]
                    │          │ ──► mag_valid
clk / rst_n     ──► └──────────┘ ──► busy
```

## Twiddle factors

The RTL reads `twiddle.hex` at elaboration time via `$readmemh`.  The
[`gen_twiddle.py`](gen_twiddle.py) script generates this file (128 entries,
Q1.14 fixed-point cos/sin pairs) using `numpy` for the trigonometric values,
and is run automatically by the `Makefile` before the simulator binary is
compiled.

## Timing

One FFT frame occupies roughly 3840 clock cycles:

| Phase     | Cycles                         |
|-----------|-------------------------------|
| COLLECT   | 256 (one sample per clock)     |
| COMPUTE   | 3072 (8 stages × 128 butterflies × 3 steps) |
| MAGNITUDE | 512 (256 bins × 2 steps each)  |

The test timeout for `collect_magnitudes` is set generously above the
COMPUTE + MAGNITUDE total so that tests fail with a clear message rather than
hanging.

## Helper functions

- **`reset_dut`** — holds `rst_n` low for 5 cycles, then deasserts and waits
  one extra clock edge so registered outputs are visible.
- **`feed_samples(dut, samples)`** — drives `sample_valid=1` for 256
  consecutive rising edges, one sample value per cycle, then clears the input.
- **`collect_magnitudes(dut)`** — polls for `mag_valid` pulses and records
  `(mag_addr, mag_data)` pairs until all 256 bins have been collected or the
  timeout expires.  Returns a list indexed by bin number and the pulse count.
- **`reference_mag_data(re_s16, im_s16)`** — pure-Python replica of the RTL's
  exact magnitude pipeline (`max + min/4` approximation followed by the 4.4
  fixed-point log2 and 0–438 scaling), used to compute expected `mag_data`
  values from floating-point FFT output.
- **`reference_fft_mags(samples)`** — runs `numpy.fft.fft` (float64) on the
  input, divides by N to match the RTL's 1/256 normalisation, rounds to signed
  16-bit integers, and passes each bin through `reference_mag_data`.

## Test cases

- **test_reset_state** — immediately after reset: `busy=0`, `mag_valid=0`.
- **test_busy_during_compute** — feeds 255 samples (still collecting), checks
  `busy=0`, feeds the 256th sample, then asserts `busy=1`.
- **test_zero_input** — all-zero samples produce all-zero magnitude outputs.
- **test_dc_input** — constant input A=16384 causes all butterfly difference
  terms to cancel; only `X[0]` retains a non-zero value after 8 stages,
  so `mag_data` should be large at bin 0 and ≤ 1 everywhere else.
- **test_single_tone** — a sine wave at normalised frequency 16/256 should
  produce dominant peaks at bins 16 and 240 (the conjugate pair), at least
  5× larger than the average of all other bins.
- **test_output_count** — exactly 256 `mag_valid` pulses fire per frame.
- **test_mag_valid_single_cycle** — `mag_valid` drops to 0 on the cycle
  immediately following its assertion (one-cycle strobe).
- **test_returns_to_collect** — after all 256 magnitude outputs have been
  emitted `busy` returns to 0 within a few cycles.
- **test_sequential_frames** — two consecutive frames: DC followed by silence.
  Verifies the module re-enters S_COLLECT and produces correct output for the
  second frame.
- **test_triangle_wave** — feeds a period-32 triangle wave (fundamental at
  bin 8, odd harmonics at 24, 40, …) and asserts every bin's `mag_data` is
  within ±3 counts of the `reference_fft_mags` numpy reference.  This is the
  most comprehensive end-to-end test: it validates the full fixed-point
  pipeline against a known-good float64 FFT for a realistic, multi-harmonic
  input signal.
