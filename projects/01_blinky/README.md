# 01_blinky

Basic LED blinky example for the iCESugar-Pro board.

## Description

Cycles through RGB LED colors using a 24-bit counter driven by the 25 MHz clock.

## Build

From the project root, use the top-level Makefile (runs in Docker automatically):

```bash
make build PROJECT=01_blinky   # Build bitstream
make sim PROJECT=01_blinky     # Run simulation
```

Or inside the Docker container (`make docker-shell`), run directly:

```bash
cd projects/01_blinky
make        # Synthesize, place & route, generate bitstream
make sim    # Run simulation (Icarus Verilog)
make lint   # Run Verilator linting
make clean  # Remove build artifacts
```

## View Simulation Waveforms

After running simulation, view the waveforms with GTKWave (see main README for installation):

```bash
gtkwave projects/01_blinky/top_tb.gtkw
```

The `.gtkw` save file preloads signals and sets a reasonable zoom level.

## Program

Run from the host (requires icesprog installed):

```bash
make program PROJECT=01_blinky
```

Or inside the project directory:

```bash
make program
```
