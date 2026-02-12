# 04_hdmi_graph - HDMI Graph Display

HDMI line graph display in landscape orientation (800x480@60Hz). Shows a static FFT-like test spectrum as a filled line graph. Designed for later connection to live FFT data.

## Architecture

```
clk_25m ──► PLL ──► clk_pixel (30 MHz) ──► video_timing (800x480)
                    clk_shift (150 MHz)         │
                                          pixel_x/y, sync
                                                │
                                          graph_renderer ◄── graph_data_rom
                                                │                (256x9 ROM)
                                          RGB + delayed sync
                                                │
                                          TMDS encode (3ch)
                                                │
                                          TMDS serialize (4ch)
                                                │
                                          HDMI output (gpdi_dp/dn)
```

## Video Timing

Landscape 800x480 at 60 Hz using the same 30 MHz pixel clock as project 02:

| Parameter | Value |
|-----------|-------|
| H active | 800 |
| H front porch | 40 |
| H sync pulse | 48 |
| H back porch | 40 |
| **H total** | **928** |
| V active | 480 |
| V front porch | 13 |
| V sync pulse | 3 |
| V back porch | 42 |
| **V total** | **538** |
| **Refresh** | **60.08 Hz** |

## Graph Rendering

- **Plot area**: 768x440 pixels (256 bins x 3 pixels each, with margins)
- **Data**: 256 x 9-bit values (0-440) from ROM, representing amplitude per frequency bin
- **Visuals**: Dark background, bright green line with dark green fill below, gray grid, axis lines
- **Pipeline**: 2-stage (ROM address generation + color determination), with sync signal delay for alignment

### Data Interface

The renderer uses a ROM-like read port (`data_addr` out, `data_value` in). To display live FFT data, replace `graph_data_rom` with a dual-port RAM written by the FFT pipeline.

## Test Data

`fft_test_data.hex` contains a synthetic FFT-like spectrum with several Gaussian peaks on a noise floor. Regenerate with:

```bash
python gen_test_data.py
```

## Build

```bash
# From repo root (runs in Docker)
make build PROJECT=04_hdmi_graph
make sim PROJECT=04_hdmi_graph
make program PROJECT=04_hdmi_graph
```
