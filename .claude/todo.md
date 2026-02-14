# Todo
- 05_live_fft: log-frequency X-axis with LUT + rework connector logic (see `.claude/log-log-display-plan.md`)
- 03_i2s_loopback: get noise-detection LED working
- "make program" uses iceprog to program the FPGA. in windows, the icesugar-pro, however, shows up as a drive D:\ . so we can also upload code simply by "cp .\projects\04_hdmi_graph\build\hdmi_graph.bit D:\" can you add another command upload to make that does this? it probably makes sense to add a parameter DRIVE or similar to specify the target. it would be nice to set D:\ as the standard if the paramter is not supplied

# Done
- 05_live_fft: unique half (bins 1-128) + log2 magnitude in fft256.v (step 1 of log-log display)
- Create project 05_live_fft: live FFT spectrum analyzer (I2S mic → 256-point FFT → HDMI graph)
- Refactor project 03 (I2S loopback) to extract reusable I2S modules (`i2s_clkgen`, `i2s_rx`, `i2s_tx`) into `rtl/` and rewire loopback through parallel samples
- Positional project arg with prefix matching in Makefile (e.g. `make build 04` matches `04_hdmi_graph`)
- Investigate and fix Waveshare 3.2inch HDMI display failing to switch on reliably
