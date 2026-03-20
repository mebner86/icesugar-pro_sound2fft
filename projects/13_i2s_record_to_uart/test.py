# %%
import numpy as np
import matplotlib.pyplot as plt

raw = open("raw_silence_24bit.raw", "rb").read()
num_samples = len(raw) // 3
samples = np.array(
    [int.from_bytes(raw[i : i + 3], "big", signed=True) for i in range(0, len(raw), 3)],
    dtype=np.int32,
)

samples >>= 6  # truncate 24-bit to 18-bit significant bits

print(f"Samples: {num_samples}, min: {samples.min():.0f}, max: {samples.max():.0f}")

# %%
plt.plot(samples)
plt.xlabel("Sample")
plt.ylabel("Amplitude")
plt.title("raw_sin_2kHz.raw")
plt.grid(True, alpha=0.3)
plt.show()

# %%
