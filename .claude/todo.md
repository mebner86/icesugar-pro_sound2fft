# Todo
- 03_i2s_loopback: fix loud pop/click noise on powerup
- 03_i2s_loopback: get noise-detection LED working

# Done
- Create project 05_live_fft: live FFT spectrum analyzer (I2S mic → 256-point FFT → HDMI graph)
- Refactor project 03 (I2S loopback) to extract reusable I2S modules (`i2s_clkgen`, `i2s_rx`, `i2s_tx`) into `rtl/` and rewire loopback through parallel samples
- Positional project arg with prefix matching in Makefile (e.g. `make build 04` matches `04_hdmi_graph`)
- Investigate and fix Waveshare 3.2inch HDMI display failing to switch on reliably
