BIN     := fpgactrl
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -ldflags "-X main.version=$(VERSION)"

.PHONY: all build windows clean

all:
	@echo "Specify a target:"
	@echo "  make build    — native binary for the current OS (Linux/macOS)"
	@echo "  make windows  — cross-compile for Windows (amd64)"
	@echo "  make clean    — remove built binaries"

## build — native binary (Linux/macOS)
build:
	go build $(LDFLAGS) -o $(BIN) .

## windows — cross-compile for Windows (amd64)
windows:
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o $(BIN).exe .

## clean — remove built binaries
clean:
	rm -f $(BIN) $(BIN).exe
