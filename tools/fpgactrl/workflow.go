package main

import (
	"fmt"
	"math"

	"fpgactrl/internal/csvin"
	"fpgactrl/internal/csvout"
	"fpgactrl/internal/siggen"
	"fpgactrl/internal/uart"
)

func runWorkflow(port string, baud int, inputCSV string, mics int, recordSamplesOverride int, savePath string, recordOnly bool) error {
	var playedI16 []int16
	uploadN := 0

	if !recordOnly {
		if inputCSV == "" {
			return fmt.Errorf("-input is required unless -record-only is set")
		}
		playedF, err := csvin.ReadPlayed(inputCSV)
		if err != nil {
			return err
		}
		playedI16 = siggen.FloatToInt16(playedF)
		uploadN = len(playedI16)
	}

	recordN := uploadN
	if recordSamplesOverride > 0 {
		recordN = recordSamplesOverride
	}
	if recordN == 0 {
		recordN = siggen.NumSamples // fallback for record-only without override
	}

	fmt.Printf("Opening %s at %d baud...\n", port, baud)
	ser, err := uart.OpenPort(port, baud)
	if err != nil {
		return err
	}
	defer ser.Close()

	var mic1I16, mic2I16 []int16

	if recordOnly {
		fmt.Printf("Recording %d samples (no playback)... ", recordN)
		if err := uart.RecordOnly(ser, recordN); err != nil {
			return err
		}
		fmt.Println("ACK OK")
	} else {
		fmt.Printf("Uploading %d samples (%d bytes)... ", len(playedI16), len(playedI16)*2)
		if err := uart.Upload(ser, playedI16); err != nil {
			return err
		}
		fmt.Println("ACK OK")

		fmt.Printf("Playing and recording %d samples... ", recordN)
		if err := uart.PlayRecord(ser, recordN); err != nil {
			return err
		}
		fmt.Println("ACK OK")
	}

	fmt.Printf("Dumping mic 1 (%d samples)... ", recordN)
	mic1I16, err = uart.Dump(ser, recordN)
	if err != nil {
		return err
	}
	fmt.Println("done")

	if mics == 2 {
		fmt.Printf("Dumping mic 2 (%d samples)... ", recordN)
		mic2I16, err = uart.Dump2(ser, recordN)
		if err != nil {
			return err
		}
		fmt.Println("done")
	}

	mic1Peak := peakFloat(mic1I16)
	if recordOnly {
		fmt.Printf("Mic 1 peak: %.4f\n", mic1Peak)
		if mics == 2 {
			fmt.Printf("Mic 2 peak: %.4f\n", peakFloat(mic2I16))
		}
	} else {
		fmt.Printf("Peak played amplitude: %.4f\n", peakFloat(playedI16))
		fmt.Printf("Mic 1 peak:            %.4f\n", mic1Peak)
		if mics == 2 {
			fmt.Printf("Mic 2 peak:            %.4f\n", peakFloat(mic2I16))
		}
	}

	if savePath != "" {
		mic1F := siggen.Int16ToFloat(mic1I16)
		var headers []string
		var columns [][]float64
		if recordOnly {
			if mics == 2 {
				headers = []string{"mic1", "mic2"}
				columns = [][]float64{mic1F, siggen.Int16ToFloat(mic2I16)}
			} else {
				headers = []string{"mic1"}
				columns = [][]float64{mic1F}
			}
		} else {
			playedF := siggen.Int16ToFloat(playedI16)
			if mics == 2 {
				headers = []string{"speaker", "mic1", "mic2"}
				columns = [][]float64{playedF, mic1F, siggen.Int16ToFloat(mic2I16)}
			} else {
				headers = []string{"speaker", "mic1"}
				columns = [][]float64{playedF, mic1F}
			}
		}
		if err := csvout.WriteCSV(savePath, siggen.SampleRate, headers, columns...); err != nil {
			return fmt.Errorf("saving CSV: %w", err)
		}
		fmt.Printf("Saved: %s\n", savePath)
	}

	return nil
}

func runGen(signal string, amplitude float64, savePath string) error {
	played, err := siggen.Generate(signal, amplitude)
	if err != nil {
		return err
	}
	if err := csvout.WritePlayedOnly(savePath, played); err != nil {
		return fmt.Errorf("saving CSV: %w", err)
	}
	fmt.Printf("Generated %s signal (%d samples) → %s\n", signal, len(played), savePath)
	return nil
}

func peakFloat(samples []int16) float64 {
	var maxAbs int16
	for _, s := range samples {
		a := s
		if a < 0 {
			a = -a
		}
		if a > maxAbs {
			maxAbs = a
		}
	}
	return math.Abs(float64(maxAbs)) / siggen.FullScale
}
