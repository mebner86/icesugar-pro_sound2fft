# Todo
- 05_live_fft: log-frequency X-axis with LUT + rework connector logic (see `.claude/log-log-display-plan.md`)
- 03_i2s_loopback: get noise-detection LED working

# Done
- Add `make upload` command to copy bitstream to USB drive (default `D:\`, configurable via `DRIVE=`)
- Refactor README.md: add Python setup instructions, move `make docker-shell` notes below the other make commands so users don't think everything must run inside the container
- Moved `display_ram.v` from project-local copies into shared `rtl/` directory
- 06_live_real_fft: 512-point real FFT via 256-point complex FFT, 256-bin output spectrum
- 05_live_fft: unique half (bins 1-128) + log2 magnitude in fft256.v (step 1 of log-log display)
- Create project 05_live_fft: live FFT spectrum analyzer (I2S mic → 256-point FFT → HDMI graph)
- Refactor project 03 (I2S loopback) to extract reusable I2S modules (`i2s_clkgen`, `i2s_rx`, `i2s_tx`) into `rtl/` and rewire loopback through parallel samples
- Positional project arg with prefix matching in Makefile (e.g. `make build 04` matches `04_hdmi_graph`)
- Investigate and fix Waveshare 3.2inch HDMI display failing to switch on reliably
