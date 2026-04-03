# gensig

Generate input CSV files for `fpgactrl`.

Produces a two-column CSV (`time_s`, `speaker`) that `fpgactrl run -input` can consume.

## Usage

```
python3 gensig.py <signal> [options]
```

### Signals

| Signal | Description |
|--------|-------------|
| `chirp` | Log-frequency sweep from f0 to f1 |
| `sine`  | Continuous sine wave at a fixed frequency |
| `noise` | White noise (DC-removed, normalised) |

### Common options

| Option | Default | Description |
|--------|---------|-------------|
| `-o`, `--output FILE` | `sig_<signal>.csv` | Output CSV path |
| `-n`, `--samples N` | `4096` | Number of samples |
| `--fs FLOAT` | `48828.0` | Sample rate in Hz |
| `-a`, `--amplitude FLOAT` | `0.9` | Peak amplitude (0.0–1.0) |

### Chirp options

| Option | Default | Description |
|--------|---------|-------------|
| `--f0 FLOAT` | `200.0` | Start frequency in Hz |
| `--f1 FLOAT` | `20000.0` | Stop frequency in Hz |

### Sine options

| Option | Default | Description |
|--------|---------|-------------|
| `--freq FLOAT` | `1000.0` | Sine frequency in Hz |

### Noise options

| Option | Default | Description |
|--------|---------|-------------|
| `--seed INT` | `42` | RNG seed for repeatability |

## Examples

```bash
# Log chirp from 200 Hz to 20 kHz, 4096 samples → sig_chirp.csv
python3 gensig.py chirp

# Chirp with custom frequency range and output path
python3 gensig.py chirp --f0 500 --f1 8000 -o my_chirp.csv

# 2 kHz sine wave
python3 gensig.py sine --freq 2000

# White noise with a fixed seed
python3 gensig.py noise --seed 123
```

## Output format

```
time_s,speaker
0.000000000000000000e+00,8.715574274765817341e-01
2.048000000000000000e-05,9.009688679024191090e-01
...
```

Each row contains the sample timestamp (seconds) and the normalised speaker amplitude in the range `[-1.0, 1.0]`.
