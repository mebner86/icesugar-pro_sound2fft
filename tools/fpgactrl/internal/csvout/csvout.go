// Package csvout writes signal data to CSV files.
package csvout

import (
	"fmt"
	"os"
	"strings"

	"fpgactrl/internal/siggen"
)

// WriteCSV writes a time_s column followed by the named data columns to path.
// All columns must have the same length.  sampleRate is used to compute the
// time axis.
func WriteCSV(path string, sampleRate float64, headers []string, columns ...[]float64) error {
	if len(headers) != len(columns) {
		return fmt.Errorf("WriteCSV: %d headers but %d columns", len(headers), len(columns))
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	fmt.Fprintf(f, "time_s,%s\n", strings.Join(headers, ","))
	n := len(columns[0])
	for i := 0; i < n; i++ {
		t := float64(i) / sampleRate
		fmt.Fprintf(f, "%.18e", t)
		for _, col := range columns {
			fmt.Fprintf(f, ",%.18e", col[i])
		}
		fmt.Fprintln(f)
	}
	return nil
}

// WritePlayedOnly writes just the speaker signal to a CSV file (for gen command).
func WritePlayedOnly(path string, played []float64) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	fmt.Fprintln(f, "time_s,speaker")
	for i, v := range played {
		t := float64(i) / float64(siggen.SampleRate)
		fmt.Fprintf(f, "%.18e,%.18e\n", t, v)
	}
	return nil
}
