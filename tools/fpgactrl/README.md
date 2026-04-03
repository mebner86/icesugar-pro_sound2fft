# fpgactrl

CLI tool for FPGA hardware-in-the-loop (HIL) testing. Uploads a signal to the FPGA over UART, triggers playback and recording, and retrieves the microphone capture.

## Build

```bash
# Native binary (Linux/macOS)
make build

# Cross-compile for Windows
make windows

# Remove binaries
make clean
```

## Usage

```
fpgactrl <command> [flags]
```

### Commands

| Command | Description |
|---------|-------------|
| `run`   | Upload a CSV signal, play and record, dump results |
| `gen`   | Generate a test signal and save to CSV (no hardware) |

---

## `run` — Play and record via FPGA

```
fpgactrl run -port <device> -input <file.csv> [flags]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-port STRING` | _(required)_ | Serial port (e.g. `/dev/ttyACM0` or `COM4`) |
| `-input FILE` | _(required)_ | Input CSV with a `speaker` column |
| `-baud INT` | `115200` | UART baud rate |
| `-mics INT` | `1` | Number of microphones to capture (`1` or `2`) |
| `-record-samples N` | same as upload | Override the number of samples to record/dump |
| `-fpga-samples N` | `16384` | FPGA buffer size; upload is clamped to this limit |
| `-save FILE` | | Save output signals to a CSV file |
| `-record-only` | `false` | Record without playback (`-input` not needed) |

### Output CSV columns

| Mode | Columns |
|------|---------|
| Play + record, 1 mic | `time_s`, `speaker`, `mic1` |
| Play + record, 2 mics | `time_s`, `speaker`, `mic1`, `mic2` |
| Record-only, 1 mic | `time_s`, `mic1` |
| Record-only, 2 mics | `time_s`, `mic1`, `mic2` |

### Examples

```bash
# Play a chirp and record one microphone
fpgactrl run -port /dev/ttyACM0 -input sig_chirp.csv -save out.csv

# Record two microphones, save results
fpgactrl run -port /dev/ttyACM0 -input sig_chirp.csv -mics 2 -save out.csv

# Record-only (no playback)
fpgactrl run -port /dev/ttyACM0 -record-only -record-samples 4096 -save out.csv
```

---

## `gen` — Generate a test signal

Generates a signal and saves it as a CSV without requiring hardware. Useful for preparing input files for `run -input`.

```
fpgactrl gen [flags]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-signal STRING` | `chirp` | Signal type: `chirp`, `impulse`, `sin`, `sin-delayed` |
| `-amplitude FLOAT` | `0.9` | Peak amplitude (0.0–1.0) |
| `-save FILE` | `signal.csv` | Output CSV path |

### Signal types

| Type | Description |
|------|-------------|
| `chirp` | Log-frequency sweep from 200 Hz to 20 kHz over 4096 samples |
| `impulse` | Single-sample impulse at the centre of the buffer |
| `sin` | Continuous 2 kHz sine wave |
| `sin-delayed` | 2 kHz sine wave with 20 ms of silence at the start |

### Examples

```bash
# Default chirp → signal.csv
fpgactrl gen

# Impulse at full amplitude
fpgactrl gen -signal impulse -amplitude 1.0 -save impulse.csv
```

---

## Signal parameters

| Parameter | Value |
|-----------|-------|
| Sample rate | 48828 Hz (25 MHz / 8 / 64) |
| Buffer size | 4096 samples (~83.9 ms) |
| Sample format | 16-bit signed integer |
