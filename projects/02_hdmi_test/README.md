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

## Video Timing

Target display: 480x800 @ 60Hz (portrait orientation)

### PLL Configuration

| Clock | Frequency | Purpose |
|-------|-----------|---------|
| Input | 25 MHz | Board oscillator |
| VCO | 600 MHz | Internal PLL frequency |
| clk_pixel | 30 MHz | Pixel clock |
| clk_shift | 150 MHz | TMDS serializer (5x pixel, DDR) |

### Timing Parameters

| Parameter | Value |
|-----------|-------|
| H active | 480 |
| H front porch | 24 |
| H sync | 48 |
| H back porch | 48 |
| **H total** | **600** |
| V active | 800 |
| V front porch | 3 |
| V sync | 5 |
| V back porch | 25 |
| **V total** | **833** |
| **Refresh rate** | **60.02 Hz** |

Pixel clock calculation: 600 x 833 x 60 = 29.988 MHz ~ 30 MHz

## Implementation

### Architecture

```
clk_25m ──► PLL ──┬─► clk_pixel (30 MHz) ──► Video Timing ──► Test Pattern ──► TMDS Encoders ──┐
                  │                                                                             │
                  └─► clk_shift (150 MHz) ─────────────────────────────────────► Serializers ◄──┘
                                                                                     │
                                                                              gpdi_dp/dn[3:0]
```

### Source Files

| File | Description |
|------|-------------|
| `hdmi_test.v` | Top module - instantiates and connects all components |
| `pll.v` | ECP5 PLL - generates pixel and shift clocks from 25 MHz |
| `video_timing.v` | H/V sync, blanking, and pixel coordinate generation |
| `test_pattern.v` | 8 vertical color bars (white, yellow, cyan, green, magenta, red, blue, black) |
| `tmds_encoder.v` | DVI-compliant 8b/10b encoding with DC balance |
| `tmds_serializer.v` | 10:1 DDR serialization using ODDRX1F primitives |

### TMDS Output

The ECP5 uses pseudo-differential LVCMOS33 output for HDMI. Each TMDS channel uses two ODDRX1F primitives to generate complementary DDR signals at 150 MHz (300 Mbps effective).

Channel mapping:
- `gpdi_dp/dn[0]` - Blue (carries hsync/vsync during blanking)
- `gpdi_dp/dn[1]` - Green
- `gpdi_dp/dn[2]` - Red
- `gpdi_dp/dn[3]` - Pixel clock

### Status LED

The green LED (active low) indicates PLL lock status.
