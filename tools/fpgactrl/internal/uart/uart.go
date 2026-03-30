// Package uart implements the FPGA UART protocol for HIL testing.
package uart

import (
	"encoding/binary"
	"fmt"
	"io"
	"time"

	"go.bug.st/serial"
)

// Protocol constants (must match Verilog).
const (
	CmdUpload  = 'U'
	CmdPlay    = 'P'
	CmdRecord  = 'R'
	CmdDump    = 'D'
	CmdDump2   = 'E'
	AckByte    = 'K'
	Timeout    = 5 * time.Second
)

// OpenPort opens and flushes a serial port.
func OpenPort(name string, baud int) (serial.Port, error) {
	mode := &serial.Mode{BaudRate: baud}
	p, err := serial.Open(name, mode)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", name, err)
	}
	p.SetReadTimeout(Timeout)
	p.ResetInputBuffer()
	p.ResetOutputBuffer()
	return p, nil
}

// readACK reads a single byte and verifies it is 'K'.
func readACK(r io.Reader) error {
	buf := make([]byte, 1)
	_, err := io.ReadFull(r, buf)
	if err != nil {
		return fmt.Errorf("reading ACK: %w", err)
	}
	if buf[0] != AckByte {
		return fmt.Errorf("expected ACK 0x%02X, got 0x%02X", AckByte, buf[0])
	}
	return nil
}

// Upload sends samples to the FPGA replay buffer.
func Upload(rw io.ReadWriter, samples []int16) error {
	// Send command byte
	if _, err := rw.Write([]byte{CmdUpload}); err != nil {
		return fmt.Errorf("sending upload command: %w", err)
	}
	// Send big-endian int16 payload
	payload := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.BigEndian.PutUint16(payload[i*2:], uint16(s))
	}
	if _, err := rw.Write(payload); err != nil {
		return fmt.Errorf("sending payload: %w", err)
	}
	return readACK(rw)
}

// PlayRecord triggers play+record and waits for ACK.
func PlayRecord(rw io.ReadWriter) error {
	if _, err := rw.Write([]byte{CmdPlay}); err != nil {
		return fmt.Errorf("sending play command: %w", err)
	}
	return readACK(rw)
}

// RecordOnly triggers mic-only recording and waits for ACK.
func RecordOnly(rw io.ReadWriter) error {
	if _, err := rw.Write([]byte{CmdRecord}); err != nil {
		return fmt.Errorf("sending record command: %w", err)
	}
	return readACK(rw)
}

// Dump downloads n samples from mic 1 (command 'D').
func Dump(rw io.ReadWriter, n int) ([]int16, error) {
	return dumpCmd(rw, CmdDump, n)
}

// Dump2 downloads n samples from mic 2 (command 'E').
func Dump2(rw io.ReadWriter, n int) ([]int16, error) {
	return dumpCmd(rw, CmdDump2, n)
}

func dumpCmd(rw io.ReadWriter, cmd byte, n int) ([]int16, error) {
	if _, err := rw.Write([]byte{cmd}); err != nil {
		return nil, fmt.Errorf("sending dump command: %w", err)
	}
	raw := make([]byte, n*2)
	if _, err := io.ReadFull(rw, raw); err != nil {
		return nil, fmt.Errorf("reading dump data: %w", err)
	}
	samples := make([]int16, n)
	for i := range samples {
		samples[i] = int16(binary.BigEndian.Uint16(raw[i*2:]))
	}
	return samples, nil
}
