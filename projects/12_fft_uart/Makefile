# FFT UART Makefile for iCESugar-Pro (ECP5-25F)

TOP         = fft_uart
CONSTRAINTS = icesugar_pro.lpf
DEVICE      = 25k
PACKAGE     = CABGA256

RTL_DIR = ../../rtl

# Build sources: top + serializer + FFT/I2S chain + UART TX
VERILOG_SRC = fft_uart.v uart_serializer.v \
              $(RTL_DIR)/fft_real512.v \
              $(RTL_DIR)/i2s_clkgen.v $(RTL_DIR)/i2s_rx.v \
              $(RTL_DIR)/uart_tx.v

# ECP5 primitive stubs (for lint and simulation only)
ECP5_STUBS = $(RTL_DIR)/ecp5_stubs.v

# Simulation sources: serializer + UART TX only (no FFT/I2S/PLL needed)
SIM_SRC     = fft_uart_tb.v uart_serializer.v $(RTL_DIR)/uart_tx.v

BUILD_DIR = build
JSON      = $(BUILD_DIR)/$(TOP).json
CONFIG    = $(BUILD_DIR)/$(TOP)_out.config
BITSTREAM = $(BUILD_DIR)/$(TOP).bit

SIM_TOP = fft_uart_tb
VVP     = $(BUILD_DIR)/$(SIM_TOP).vvp
VCD     = $(BUILD_DIR)/$(SIM_TOP).vcd

.PHONY: all clean lint sim waves program

all: $(BITSTREAM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Twiddle factor ROM (shared with 07_live_real_fft)
twiddle.hex: gen_twiddle.py
	python3 gen_twiddle.py

# Synthesis
$(JSON): $(VERILOG_SRC) twiddle.hex | $(BUILD_DIR)
	yosys -p "read_verilog $(VERILOG_SRC); synth_ecp5 -top $(TOP) -json $@"

# Place and route (heap placer is much faster than default SA)
$(CONFIG): $(JSON) $(CONSTRAINTS)
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --placer heap \
	    --lpf $(CONSTRAINTS) --json $(JSON) --textcfg $@

# Bitstream
$(BITSTREAM): $(CONFIG)
	ecppack --compress --input $< --bit $@

# Program via icesprog
program: $(BITSTREAM)
	icesprog $<

# Lint (include ECP5 stubs for i2s_clkgen/i2s_rx primitives)
lint:
	verilator --lint-only -Wall --top-module $(TOP) $(ECP5_STUBS) $(VERILOG_SRC)

# Simulation (serializer + UART TX only — fast, no FFT required)
sim: $(VCD)
	@echo "Simulation complete: $(VCD)"

$(VVP): $(SIM_SRC) | $(BUILD_DIR)
	iverilog -o $@ $(SIM_SRC)

$(VCD): $(VVP)
	vvp $< -vcd

# Open waveform viewer
waves: $(VCD)
	gtkwave $(SIM_TOP).gtkw &

clean:
	rm -rf $(BUILD_DIR)
