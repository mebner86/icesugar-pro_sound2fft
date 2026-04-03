package main

import (
	"flag"
	"fmt"
	"os"
)

const usage = `fpgactrl — FPGA control CLI

Usage:
  fpgactrl <command> [flags]

Commands:
  run    Upload a CSV signal, play+record, and dump results
  gen    Generate a test signal and save to CSV (no hardware)

Run 'fpgactrl <command> -h' for command-specific help.
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(1)
	}

	switch os.Args[1] {
	case "run":
		cmdRun(os.Args[2:])
	case "gen":
		cmdGen(os.Args[2:])
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n%s", os.Args[1], usage)
		os.Exit(1)
	}
}

func cmdRun(args []string) {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	port := fs.String("port", "", "Serial port (e.g. /dev/ttyACM0) (required)")
	baud := fs.Int("baud", 115200, "UART baud rate")
	input := fs.String("input", "", "Input CSV file with 'played' column (required unless -record-only)")
	mics := fs.Int("mics", 1, "Number of microphones: 1 or 2")
	recordSamples := fs.Int("record-samples", 0, "Override record/dump sample count (default: same as upload count)")
	save := fs.String("save", "", "Save output signals to CSV file")
	recordOnly := fs.Bool("record-only", false, "Record without playback (-input not needed)")
	fs.Parse(args)

	if *port == "" {
		fmt.Fprintln(os.Stderr, "error: -port is required")
		fs.Usage()
		os.Exit(1)
	}
	if !*recordOnly && *input == "" {
		fmt.Fprintln(os.Stderr, "error: -input is required (or use -record-only)")
		fs.Usage()
		os.Exit(1)
	}
	if *mics != 1 && *mics != 2 {
		fmt.Fprintln(os.Stderr, "error: -mics must be 1 or 2")
		os.Exit(1)
	}

	if err := runWorkflow(*port, *baud, *input, *mics, *recordSamples, *save, *recordOnly); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func cmdGen(args []string) {
	fs := flag.NewFlagSet("gen", flag.ExitOnError)
	signal := fs.String("signal", "chirp", "Signal type: chirp|impulse|sin|sin-delayed")
	amplitude := fs.Float64("amplitude", 0.9, "Peak amplitude 0.0–1.0")
	save := fs.String("save", "signal.csv", "Output CSV file")
	fs.Parse(args)

	if err := runGen(*signal, *amplitude, *save); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
