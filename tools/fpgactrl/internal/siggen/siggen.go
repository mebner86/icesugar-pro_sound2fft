// Package siggen generates test signals for FPGA HIL testing.
package siggen

import (
	"fmt"
	"math"
)

const (
	SampleRate = 48828   // Hz (25e6 / 8 / 64)
	NumSamples = 4096    // samples per buffer
	FullScale  = 32768.0 // 16-bit signed full scale
)

// GenChirp generates a log-frequency sweep from f0 to f1.
func GenChirp(n int, fs float64, f0, f1, amplitude float64) []float64 {
	T := float64(n) / fs
	ratio := f1 / f0
	logRatio := math.Log(ratio)
	out := make([]float64, n)
	for i := range out {
		phase := 2 * math.Pi * f0 * T / logRatio * (math.Exp(float64(i)/float64(n)*logRatio) - 1)
		out[i] = amplitude * math.Sin(phase)
	}
	return out
}

// GenImpulse generates a single-sample impulse at the centre of the buffer.
func GenImpulse(n int, amplitude float64) []float64 {
	out := make([]float64, n)
	out[n/2] = amplitude
	return out
}

// GenSin generates a continuous sine wave at the given frequency.
func GenSin(n int, fs float64, freq, amplitude float64) []float64 {
	out := make([]float64, n)
	for i := range out {
		t := float64(i) / fs
		out[i] = amplitude * math.Sin(2*math.Pi*freq*t)
	}
	return out
}

// GenSinDelayed generates silence followed by a sine starting at onsetMs.
func GenSinDelayed(n int, fs float64, freq, onsetMs, amplitude float64) []float64 {
	onsetSample := int(onsetMs / 1000.0 * fs)
	out := make([]float64, n)
	for i := onsetSample; i < n; i++ {
		t := float64(i-onsetSample) / fs
		out[i] = amplitude * math.Sin(2*math.Pi*freq*t)
	}
	return out
}

// Generate returns a signal buffer for the named signal type using default parameters.
func Generate(signal string, amplitude float64) ([]float64, error) {
	switch signal {
	case "chirp":
		return GenChirp(NumSamples, SampleRate, 200, 20000, amplitude), nil
	case "impulse":
		return GenImpulse(NumSamples, amplitude), nil
	case "sin":
		return GenSin(NumSamples, SampleRate, 2000, amplitude), nil
	case "sin-delayed":
		return GenSinDelayed(NumSamples, SampleRate, 2000, 20, amplitude), nil
	default:
		return nil, fmt.Errorf("unknown signal type: %q (valid: chirp, impulse, sin, sin-delayed)", signal)
	}
}

// FloatToInt16 clips a float64 signal [-1,1] and quantises to int16.
func FloatToInt16(sig []float64) []int16 {
	out := make([]int16, len(sig))
	for i, v := range sig {
		if v > 1.0 {
			v = 1.0
		} else if v < -1.0 {
			v = -1.0
		}
		out[i] = int16(v * (FullScale - 1))
	}
	return out
}

// Int16ToFloat converts int16 samples to float64 [-1,1].
func Int16ToFloat(samples []int16) []float64 {
	out := make([]float64, len(samples))
	for i, s := range samples {
		out[i] = float64(s) / FullScale
	}
	return out
}
