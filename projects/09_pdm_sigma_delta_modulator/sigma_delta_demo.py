# %% [markdown] --------------------------------------------
# # Sigma-Delta Modulation
#
# Mirrors the algorithms implemented in rtl/pdm_modulator.v:
#   - 1st-order error-feedback (NTF = 1 − z⁻¹)
#   - 2nd-order CIFB          (NTF = (1 − z⁻¹)²)
#
# Run cells individually in VS Code (# %%) or execute the whole file.
# Requires: numpy, matplotlib, scipy

import numpy as np
import matplotlib.pyplot as plt
from scipy import signal as sig

# %% [markdown] --------------------------------------------
# ## 1. Generate a test sine wave
# 64 samples of a full sine period, 16-bit signed, same as the Verilog ROM.

N_SAMPLES = 64
pcm = np.round(32767 * np.sin(2 * np.pi * np.arange(N_SAMPLES) / N_SAMPLES)).astype(
    np.int32
)

plt.figure(figsize=(10, 3))
plt.stem(pcm, markerfmt="C0.", basefmt="k-")
plt.title("PCM sine wave (64 samples, 16-bit signed)")
plt.xlabel("Sample index")
plt.ylabel("Amplitude")
plt.tight_layout()
plt.show()

# %% [markdown] --------------------------------------------
# ## 2. First-order sigma-delta modulator
#
# Algorithm (from pdm_modulator.v ORDER=1):
#   ```python
#   new_acc = accum + pcm_in
#   pdm_out = 1 if new_acc >= 0 else 0
#   accum   = new_acc - (32768 if pdm_out else -32768)
#   ```
#
# The accumulator tracks the running quantisation error. The output bit
# is chosen so that the *average* PDM density tracks the input level.


def sigma_delta_1st(pcm_in):
    """First-order sigma-delta: returns 1-bit PDM stream (0/1 per sample)."""
    out = np.zeros(len(pcm_in), dtype=np.int32)
    accum = 0
    for i, x in enumerate(pcm_in):
        new_acc = accum + int(x)
        bit = 1 if new_acc >= 0 else 0
        out[i] = bit
        accum = new_acc - (32768 if bit else -32768)
    return out


# %% [markdown] --------------------------------------------
# ## 3. Second-order sigma-delta modulator
#
# Algorithm (from pdm_modulator.v ORDER=2, CIFB topology):
#   ```python
#   sum1    = acc1 + pcm_in       (first integrator)
#   sum2    = acc2 + sum1         (second integrator)
#   pdm_out = 1 if sum2 >= 0 else 0
#   fb      = +32768 if pdm_out else -32768
#   acc1    = clamp(sum1 - fb)    (clamped to ±2²³)
#   acc2    = clamp(sum2 - fb)
#   ```
#
# The second integrator adds another pole of noise shaping, pushing
# quantisation noise further into high frequencies (40 dB/decade vs 20).

CLAMP_HI = (1 << 23) - 1  #  8388607
CLAMP_LO = -(1 << 23)  # -8388608


def clamp(x):
    return max(CLAMP_LO, min(CLAMP_HI, x))


def sigma_delta_2nd(pcm_in):
    """Second-order CIFB sigma-delta: returns 1-bit PDM stream."""
    out = np.zeros(len(pcm_in), dtype=np.int32)
    acc1, acc2 = 0, 0
    for i, x in enumerate(pcm_in):
        sum1 = acc1 + int(x)
        sum2 = acc2 + sum1
        bit = 1 if sum2 >= 0 else 0
        fb = 32768 if bit else -32768
        acc1 = clamp(sum1 - fb)
        acc2 = clamp(sum2 - fb)
        out[i] = bit
    return out


# %% [markdown] --------------------------------------------
# ## 4. Run both modulators with oversampling
#
# On the FPGA, each PCM sample is held for 64 PDM clocks (OSR = 64).
# We replicate that here: each sine sample is repeated 64 times, then
# the modulator processes one PDM output per clock.

OSR = 64  # oversampling ratio (matches the FPGA design)
N_PERIODS = 4  # number of sine periods to simulate

# Repeat each sample OSR times (zero-order hold), tile for multiple periods
pcm_held = np.repeat(np.tile(pcm, N_PERIODS), OSR)

pdm_1st = sigma_delta_1st(pcm_held)
pdm_2nd = sigma_delta_2nd(pcm_held)

total_len = len(pcm_held)
print(f"Total PDM samples: {total_len}")
print(f"1st-order ones density: {pdm_1st.mean():.4f}  (0.5 = silence)")
print(f"2nd-order ones density: {pdm_2nd.mean():.4f}  (0.5 = silence)")

# %% [markdown] --------------------------------------------
# ## 5. Visualise the PDM bitstream
#
# Zoom into one sine period to see how the bit density varies with the
# input amplitude. Near the positive peak the output is almost all 1s;
# near the negative peak it's almost all 0s.

one_period = OSR * N_SAMPLES  # PDM clocks per sine period
t = np.arange(one_period)

fig, axes = plt.subplots(3, 1, figsize=(12, 7), sharex=True)

axes[0].plot(t, pcm_held[:one_period], color="C0")
axes[0].set_ylabel("PCM input")
axes[0].set_title("One sine period: PCM input and PDM bitstreams")

axes[1].fill_between(t, pdm_1st[:one_period], step="mid", alpha=0.7, color="C1")
axes[1].set_ylabel("1st-order PDM")
axes[1].set_ylim(-0.1, 1.1)

axes[2].fill_between(t, pdm_2nd[:one_period], step="mid", alpha=0.7, color="C2")
axes[2].set_ylabel("2nd-order PDM")
axes[2].set_ylim(-0.1, 1.1)
axes[2].set_xlabel("PDM clock cycle")

plt.tight_layout()
plt.show()

# %% [markdown] --------------------------------------------
# ## 6. Recover the analog signal with a moving-average (CIC-like) filter
#
# A real PDM receiver (like the CIC filter in rtl/cic_decimator.v) low-pass
# filters the bitstream to recover the original PCM signal. Here we use a
# simple boxcar (moving average) of length OSR — equivalent to a 1st-order
# CIC decimator.

kernel = np.ones(OSR) / OSR

recovered_1st = np.convolve(pdm_1st.astype(float), kernel, mode="same")
recovered_2nd = np.convolve(pdm_2nd.astype(float), kernel, mode="same")

# Scale from [0, 1] density back to signed PCM range: pcm ≈ (density − 0.5) × 65536
recovered_1st = (recovered_1st - 0.5) * 65536
recovered_2nd = (recovered_2nd - 0.5) * 65536

fig, axes = plt.subplots(2, 1, figsize=(12, 5), sharex=True)

axes[0].plot(pcm_held, label="Original PCM", alpha=0.5)
axes[0].plot(recovered_1st, label="Recovered (1st-order)", linewidth=1.5)
axes[0].legend()
axes[0].set_title("PDM → PCM recovery (moving-average filter, OSR=64)")
axes[0].set_ylabel("Amplitude")

axes[1].plot(pcm_held, label="Original PCM", alpha=0.5)
axes[1].plot(recovered_2nd, label="Recovered (2nd-order)", linewidth=1.5)
axes[1].legend()
axes[1].set_xlabel("PDM clock cycle")
axes[1].set_ylabel("Amplitude")

plt.tight_layout()
plt.show()

# %% [markdown] --------------------------------------------
# ## 7. Noise spectrum: 1st-order vs 2nd-order
#
# This is the key advantage of sigma-delta modulation: quantisation noise
# is *shaped* away from the signal band into higher frequencies.
#
# > $$\text{1st-order NTF} = |1 - e^{-j\omega}| \rightarrow \text{20 dB/decade slope}$$
# > $$\text{2nd-order NTF} = |1 - e^{-j\omega}|^2 \rightarrow \text{40 dB/decade slope}$$
#
# We compute the spectrum of the quantisation error (PDM output minus input)
# to show this noise shaping clearly.

# Quantisation error: PDM output level minus the ideal analog level
# PDM output = 0 or 1; scale to ±32768 to match input range
pdm_analog_1st = pdm_1st * 65536 - 32768  # map {0,1} → {-32768, +32768}
pdm_analog_2nd = pdm_2nd * 65536 - 32768

error_1st = pdm_analog_1st.astype(float) - pcm_held.astype(float)
error_2nd = pdm_analog_2nd.astype(float) - pcm_held.astype(float)

# Power spectral density via Welch's method
fs = OSR * 48828  # effective PDM sample rate (matches FPGA: 3.125 MHz)
nperseg = 1024

f1, psd1 = sig.welch(error_1st, fs=fs, nperseg=nperseg)
f2, psd2 = sig.welch(error_2nd, fs=fs, nperseg=nperseg)

fig, ax = plt.subplots(figsize=(10, 5))
ax.semilogy(f1 / 1e3, psd1, label="1st-order (20 dB/dec)", alpha=0.8)
ax.semilogy(f2 / 1e3, psd2, label="2nd-order (40 dB/dec)", alpha=0.8)
ax.axvline(48.828, color="gray", linestyle="--", label="PCM Nyquist (48.8 kHz)")
ax.set_xlabel("Frequency (kHz)")
ax.set_ylabel("Error PSD")
ax.set_title("Quantisation noise spectrum: sigma-delta noise shaping")
ax.legend()
ax.set_xlim(0, fs / 2 / 1e3)
plt.tight_layout()
plt.show()

# %% [markdown] --------------------------------------------
# ## 8. SNR vs oversampling ratio
#
# Sigma-delta modulators improve SNR by increasing the oversampling ratio.
# Theory predicts:
# - 1st-order: SNR improves by 9 dB per doubling of OSR (1.5 bits/octave)
# - 2nd-order: SNR improves by 15 dB per doubling of OSR (2.5 bits/octave)

osr_values = [8, 16, 32, 64, 128, 256]
snr_1st = []
snr_2nd = []

# Use a full-scale sine for SNR measurement (no attenuation)
test_pcm = np.round(32767 * np.sin(2 * np.pi * np.arange(256) / 256)).astype(np.int32)

for osr in osr_values:
    held = np.repeat(np.tile(test_pcm, 4), osr)

    # Modulate
    p1 = sigma_delta_1st(held)
    p2 = sigma_delta_2nd(held)

    # Recover with moving-average filter, then decimate
    k = np.ones(osr) / osr
    r1 = np.convolve(p1.astype(float), k, mode="same")[::osr]
    r2 = np.convolve(p2.astype(float), k, mode="same")[::osr]

    # Scale back
    r1 = (r1 - 0.5) * 65536
    r2 = (r2 - 0.5) * 65536
    ref = held[::osr].astype(float)

    # Trim edges (filter transient) and compute SNR
    trim = len(test_pcm)  # skip one period of transient
    s = ref[trim:-trim]
    n1 = r1[trim:-trim] - s
    n2 = r2[trim:-trim] - s

    snr_1st.append(10 * np.log10(np.mean(s**2) / np.mean(n1**2)))
    snr_2nd.append(10 * np.log10(np.mean(s**2) / np.mean(n2**2)))

fig, ax = plt.subplots(figsize=(8, 5))
ax.plot(osr_values, snr_1st, "o-", label="1st-order")
ax.plot(osr_values, snr_2nd, "s-", label="2nd-order")
ax.set_xscale("log", base=2)
ax.set_xlabel("Oversampling Ratio (OSR)")
ax.set_ylabel("SNR (dB)")
ax.set_title("SNR vs oversampling ratio")
ax.legend()
ax.grid(True, alpha=0.3)
ax.set_xticks(osr_values)
ax.set_xticklabels(osr_values)
plt.tight_layout()
plt.show()

# %% [markdown] --------------------------------------------
# ## Summary
#
# Key takeaways:
#
# 1. A sigma-delta modulator converts multi-bit PCM to a 1-bit stream
#    whose *average density* encodes the signal amplitude.
#
# 2. The accumulator acts as an error integrator — it tracks the difference
#    between what the output *should* be and what it *has been*.
#
# 3. Higher-order modulators push quantisation noise further away from the
#    signal band, giving better SNR for the same oversampling ratio.
#
# 4. Recovery is simple low-pass filtering (moving average / CIC).
#
# 5. The FPGA implementation (rtl/pdm_modulator.v) uses the exact same
#    algorithms shown here, running at 3.125 MHz PDM clock with OSR=64.
