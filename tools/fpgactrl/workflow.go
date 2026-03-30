package main

import (
	"fmt"
	"math"

	"fpgactrl/internal/csvout"
	"fpgactrl/internal/siggen"
	"fpgactrl/internal/uart"
)

func runWorkflow(port string, baud int, signal string, amplitude float64, savePath string, recordOnly bool) error {
	// Generate signal
	played, err := siggen.Generate(signal, amplitude)
	if err != nil {
		return err
	}
	playedI16 := siggen.FloatToInt16(played)

	// Open serial port
	fmt.Printf("Opening %s at %d baud...\n", port, baud)
	ser, err := uart.OpenPort(port, baud)
	if err != nil {
		return err
	}
	defer ser.Close()

	var mic1I16, mic2I16 []int16

	if recordOnly {
		fmt.Print("Recording both mics (no playback)... ")
		if err := uart.RecordOnly(ser); err != nil {
			return err
		}
		fmt.Println("ACK OK")

		fmt.Print("Dumping mic 1 (outside)... ")
		mic1I16, err = uart.Dump(ser, siggen.NumSamples)
		if err != nil {
			return err
		}
		fmt.Println("done")

		fmt.Print("Dumping mic 2 (inside)... ")
		mic2I16, err = uart.Dump2(ser, siggen.NumSamples)
		if err != nil {
			return err
		}
		fmt.Println("done")

		mic1Peak := peakFloat(mic1I16)
		mic2Peak := peakFloat(mic2I16)
		fmt.Printf("Mic 1 (outside) peak: %.4f\n", mic1Peak)
		fmt.Printf("Mic 2 (inside)  peak: %.4f\n", mic2Peak)
	} else {
		fmt.Printf("Uploading %d samples (%d bytes)... ", len(playedI16), len(playedI16)*2)
		if err := uart.Upload(ser, playedI16); err != nil {
			return err
		}
		fmt.Println("ACK OK")

		fmt.Print("Playing and recording (both mics)... ")
		if err := uart.PlayRecord(ser); err != nil {
			return err
		}
		fmt.Println("ACK OK")

		fmt.Print("Dumping mic 1 (outside)... ")
		mic1I16, err = uart.Dump(ser, siggen.NumSamples)
		if err != nil {
			return err
		}
		fmt.Println("done")

		fmt.Print("Dumping mic 2 (inside)... ")
		mic2I16, err = uart.Dump2(ser, siggen.NumSamples)
		if err != nil {
			return err
		}
		fmt.Println("done")

		playedPeak := peakFloat(playedI16)
		mic1Peak := peakFloat(mic1I16)
		mic2Peak := peakFloat(mic2I16)
		fmt.Printf("Peak played amplitude:    %.4f\n", playedPeak)
		fmt.Printf("Mic 1 (outside) peak:     %.4f\n", mic1Peak)
		fmt.Printf("Mic 2 (inside)  peak:     %.4f\n", mic2Peak)
	}

	if savePath != "" {
		mic1F := siggen.Int16ToFloat(mic1I16)
		mic2F := siggen.Int16ToFloat(mic2I16)
		playedF := siggen.Int16ToFloat(playedI16)
		if err := csvout.WriteSignals(savePath, playedF, mic1F, mic2F); err != nil {
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
