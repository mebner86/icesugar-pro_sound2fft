# PDM Bitstream Loopback Makefile for iCESugar-Pro (ECP5-25F)

TOP = pdm_bitstream_loopback
CONSTRAINTS = icesugar_pro.lpf
DEVICE = 25k
PACKAGE = CABGA256

# Source files (no shared RTL modules needed — design is self-contained)
VERILOG_SRC = pdm_bitstream_loopback.v

# Output files
BUILD_DIR = build
JSON = $(BUILD_DIR)/$(TOP).json
CONFIG = $(BUILD_DIR)/$(TOP)_out.config
BITSTREAM = $(BUILD_DIR)/$(TOP).bit

.PHONY: all clean program lint

all: $(BITSTREAM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Synthesis with Yosys
$(JSON): $(VERILOG_SRC) | $(BUILD_DIR)
	yosys -p "read_verilog $(VERILOG_SRC); synth_ecp5 -top $(TOP) -json $@"

# Place and Route with nextpnr
$(CONFIG): $(JSON) $(CONSTRAINTS)
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --lpf $(CONSTRAINTS) --json $(JSON) --textcfg $@

# Generate bitstream with ecppack
$(BITSTREAM): $(CONFIG)
	ecppack --compress --input $< --bit $@

# Program the FPGA via icesprog
program: $(BITSTREAM)
	icesprog $<

# Lint with Verilator
lint:
	verilator --lint-only -Wall $(VERILOG_SRC)

clean:
	rm -rf $(BUILD_DIR)
