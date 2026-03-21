# I2S Record to UART Makefile for iCESugar-Pro (ECP5-25F)

TOP         = i2s_record_to_uart
CONSTRAINTS = icesugar_pro.lpf
DEVICE      = 25k
PACKAGE     = CABGA256

RTL_DIR = ../../rtl

# Build sources: top + I2S chain + UART RX/TX
VERILOG_SRC = i2s_record_to_uart.v \
              $(RTL_DIR)/i2s_clkgen.v $(RTL_DIR)/i2s_rx.v \
              $(RTL_DIR)/uart_rx.v $(RTL_DIR)/uart_tx.v

# ECP5 primitive stubs (for lint and simulation only)
ECP5_STUBS = $(RTL_DIR)/ecp5_stubs.v

# Simulation sources: top + UART RX/TX (no I2S clkgen primitives needed in sim)
SIM_SRC = i2s_record_to_uart_tb.v i2s_record_to_uart.v \
          $(RTL_DIR)/i2s_clkgen.v $(RTL_DIR)/i2s_rx.v \
          $(RTL_DIR)/uart_rx.v $(RTL_DIR)/uart_tx.v

BUILD_DIR = build
JSON      = $(BUILD_DIR)/$(TOP).json
CONFIG    = $(BUILD_DIR)/$(TOP)_out.config
BITSTREAM = $(BUILD_DIR)/$(TOP).bit

SIM_TOP = i2s_record_to_uart_tb
VVP     = $(BUILD_DIR)/$(SIM_TOP).vvp
VCD     = $(BUILD_DIR)/$(SIM_TOP).vcd

.PHONY: all clean lint sim waves program

all: $(BITSTREAM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Synthesis
$(JSON): $(VERILOG_SRC) | $(BUILD_DIR)
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

# Lint (include ECP5 stubs for i2s_clkgen primitives)
lint:
	verilator --lint-only -Wall --top-module $(TOP) $(ECP5_STUBS) $(VERILOG_SRC)

# Simulation
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
