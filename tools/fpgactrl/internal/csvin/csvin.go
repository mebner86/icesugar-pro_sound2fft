// Package csvin reads signal data from CSV files.
package csvin

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// ReadPlayed opens a CSV file, prints any leading # comment lines, finds the
// column named "speaker", and returns its values as a []float64 slice in row
// order.  The file must have a header row; all other columns are ignored.
func ReadPlayed(path string) ([]float64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	// Split into comment lines and data lines.
	var dataLines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "#") {
			fmt.Println(line)
		} else {
			dataLines = append(dataLines, line)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}

	r := csv.NewReader(strings.NewReader(strings.Join(dataLines, "\n")))
	r.TrimLeadingSpace = true

	header, err := r.Read()
	if err != nil {
		return nil, fmt.Errorf("reading header of %s: %w", path, err)
	}

	colIdx := -1
	for i, name := range header {
		if name == "speaker" {
			colIdx = i
			break
		}
	}
	if colIdx < 0 {
		return nil, fmt.Errorf("%s: no 'speaker' column in header %v", path, header)
	}

	rows, err := r.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("reading rows of %s: %w", path, err)
	}

	out := make([]float64, 0, len(rows))
	for i, row := range rows {
		if colIdx >= len(row) {
			return nil, fmt.Errorf("%s: row %d has %d columns, need at least %d", path, i+2, len(row), colIdx+1)
		}
		v, err := strconv.ParseFloat(row[colIdx], 64)
		if err != nil {
			return nil, fmt.Errorf("%s: row %d: %w", path, i+2, err)
		}
		out = append(out, v)
	}
	return out, nil
}
