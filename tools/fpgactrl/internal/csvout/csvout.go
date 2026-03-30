// Package csvout writes signal data to CSV files.
package csvout

import (
	"fmt"
	"os"

	"fpgactrl/internal/siggen"
)

// WriteSignals writes played + mic1 + mic2 data to a CSV file.
// All slices must have the same length.
func WriteSignals(path string, played, mic1, mic2 []float64) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	fmt.Fprintln(f, "time_s,played,mic1_outside,mic2_inside")
	for i := range played {
		t := float64(i) / float64(siggen.SampleRate)
		fmt.Fprintf(f, "%.18e,%.18e,%.18e,%.18e\n", t, played[i], mic1[i], mic2[i])
	}
	return nil
}

// WritePlayedOnly writes just the played signal to a CSV file (for gen command).
func WritePlayedOnly(path string, played []float64) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	fmt.Fprintln(f, "time_s,played")
	for i, v := range played {
		t := float64(i) / float64(siggen.SampleRate)
		fmt.Fprintf(f, "%.18e,%.18e\n", t, v)
	}
	return nil
}
