# 12_uart_loopback

UART loopback demo for the iCESugar-Pro board.

## Description

Bytes received on the UART RX line are echoed back on TX, demonstrating how the iCESugar-Pro's on-board iCELink debugger exposes a USB-CDC virtual COM port that connects directly to the FPGA fabric. With a single USB-C cable you can send data to the FPGA from a host terminal and read data back — no extra hardware needed.

Open a serial terminal at 115200 8N1, type any characters, and watch them appear in the terminal as the FPGA echoes each byte back.

## Architecture

```
Host PC
  │
  │  USB-C (USB-CDC virtual COM port via iCELink)
  │
  ▼
uart_rx (A9)
  │ rx_data [7:0] + rx_valid
  ▼
1-byte buffer
  │ tx_data + tx_valid / tx_ready handshake
  ▼
uart_tx (B9)
  │
  ▼
Host PC (echo appears in terminal)
```

Both `uart_rx` and `uart_tx` are parameterised with `CLK_FREQ` and `BAUD_RATE` so they can be reused in future projects.

## Signal Mapping

| Signal | FPGA Site | Direction | Notes |
|--------|-----------|-----------|-------|
| `uart_rx` | A9 | Host → FPGA | iCELink UART3-TX output |
| `uart_tx` | B9 | FPGA → Host | iCELink UART3-RX input |

## Status LEDs

| LED | Colour | Meaning |
|-----|--------|---------|
| `led_r` | Red | Off (always) |
| `led_g` | Green | Lit while FPGA is transmitting |
| `led_b` | Blue | Pulses when a byte is received |

## Build

From the project root (inside the Dev Container terminal):

```bash
make build 12   # Build bitstream
make sim 12     # Run simulation
make lint 12    # Lint check
```

Or from the project directory:

```bash
cd projects/12_uart_loopback
make        # Synthesize, place & route, generate bitstream
make sim    # Run simulation (Icarus Verilog)
make lint   # Run Verilator linting
make clean  # Remove build artifacts
```

## View Simulation Waveforms

After running simulation, open the waveform viewer:

```bash
gtkwave projects/12_uart_loopback/uart_loopback_tb.gtkw
```

The `.gtkw` save file preloads the UART lines, LED outputs, and RX/TX module internal states.

## Program

Copy the built bitstream to your host and flash it:

```bash
# Copy from container to host, then:
icesprog projects/12_uart_loopback/build/uart_loopback.bit
# or drag the .bit file to the USB drive that appears when the board is plugged in
```

## Usage

After programming the board, open a serial terminal on the COM port that appears when the board is plugged in. Settings: **115200 baud, 8 data bits, no parity, 1 stop bit**.

**Linux / macOS:**
```bash
screen /dev/ttyACM0 115200
# or
minicom -D /dev/ttyACM0 -b 115200
```

**Windows:**

Open PuTTY → Serial → set port to `COMx` (check Device Manager), speed 115200.

Type any characters in the terminal — each one will be echoed back immediately by the FPGA. The blue LED pulses on each received byte; the green LED lights during transmission.
