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
  run    Full workflow: generate → upload → play+record → dump → save
  gen    Generate test signal and save to CSV (no hardware)

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
	signal := fs.String("signal", "chirp", "Signal type: chirp|impulse|sin|sin-delayed")
	amplitude := fs.Float64("amplitude", 0.9, "Peak amplitude 0.0–1.0")
	save := fs.String("save", "", "Save signals to CSV file")
	recordOnly := fs.Bool("record-only", false, "Record without playback")
	fs.Parse(args)

	if *port == "" {
		fmt.Fprintln(os.Stderr, "error: -port is required")
		fs.Usage()
		os.Exit(1)
	}

	if err := runWorkflow(*port, *baud, *signal, *amplitude, *save, *recordOnly); err != nil {
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
