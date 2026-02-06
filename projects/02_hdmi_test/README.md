# 02_hdmi_test

HDMI test pattern generator for the iCESugar-Pro board.

## Description

Generates a test image output via the HDMI connector. Useful for verifying HDMI connectivity and timing.

## Build

From the project root, use the top-level Makefile (runs in Docker automatically):

```bash
make build PROJECT=02_hdmi_test   # Build bitstream
make sim PROJECT=02_hdmi_test     # Run simulation
```

Or inside the Docker container (`make docker-shell`), run directly:

```bash
cd projects/02_hdmi_test
make        # Synthesize, place & route, generate bitstream
make sim    # Run simulation (Icarus Verilog)
make lint   # Run Verilator linting
make clean  # Remove build artifacts
```

## View Simulation Waveforms

After running simulation, view the waveforms with GTKWave (see main README for installation):

```bash
gtkwave projects/02_hdmi_test/top_tb.gtkw
```

The `.gtkw` save file preloads signals and sets a reasonable zoom level.

## Program

Run from the host (requires icesprog installed):

```bash
make program PROJECT=02_hdmi_test
```

Or inside the project directory:

```bash
make program
```

## Implementation Notes

The HDMI output requires:
1. **PLL**: Generate pixel clock from 25 MHz input
2. **Video timing**: H/V sync generation and blanking control
3. **Test pattern**: Color bars, gradients, or other test images
4. **TMDS encoding**: 8b/10b encoding for DVI/HDMI
5. **Serializer**: Convert parallel data to high-speed serial TMDS
