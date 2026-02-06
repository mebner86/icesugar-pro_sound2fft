# Blinky Makefile for iCESugar-Pro (ECP5-25F)

TOP = blinky
CONSTRAINTS = icesugar_pro.lpf
DEVICE = 25k
PACKAGE = CABGA256

# Source files
VERILOG_SRC = blinky.v

# Output files
BUILD_DIR = build
JSON = $(BUILD_DIR)/$(TOP).json
CONFIG = $(BUILD_DIR)/$(TOP)_out.config
BITSTREAM = $(BUILD_DIR)/$(TOP).bit

# Simulation
SIM_TOP = $(TOP)_tb
SIM_SRC = $(SIM_TOP).v
VVP = $(BUILD_DIR)/$(SIM_TOP).vvp
VCD = $(BUILD_DIR)/$(SIM_TOP).vcd

.PHONY: all clean program lint sim waves

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

# Simulation with Icarus Verilog
sim: $(VCD)
	@echo "Simulation complete: $(VCD)"

$(VVP): $(VERILOG_SRC) $(SIM_SRC) | $(BUILD_DIR)
	iverilog -o $@ $(VERILOG_SRC) $(SIM_SRC)

$(VCD): $(VVP)
	vvp $< -vcd

# Open waveform viewer
waves: $(VCD)
	gtkwave $(TOP)_tb.gtkw &

clean:
	rm -rf $(BUILD_DIR)
