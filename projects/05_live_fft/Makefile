# Live FFT Spectrum Display Makefile for iCESugar-Pro (ECP5-25F)

TOP = live_fft
CONSTRAINTS = icesugar_pro.lpf
DEVICE = 25k
PACKAGE = CABGA256

# Shared RTL modules
RTL_DIR = ../../rtl

# Source files
VERILOG_SRC = live_fft.v display_ram.v \
              $(RTL_DIR)/fft256.v \
              $(RTL_DIR)/i2s_clkgen.v $(RTL_DIR)/i2s_rx.v \
              $(RTL_DIR)/pll.v $(RTL_DIR)/graph_renderer.v \
              $(RTL_DIR)/video_timing.v $(RTL_DIR)/tmds_encoder.v $(RTL_DIR)/tmds_serializer.v

# ECP5 primitive stubs for linting and simulation
ECP5_STUBS = $(RTL_DIR)/ecp5_stubs.v

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

# Synthesis with Yosys (depends on twiddle factor hex file)
$(JSON): $(VERILOG_SRC) twiddle.hex | $(BUILD_DIR)
	yosys -p "read_verilog $(VERILOG_SRC); synth_ecp5 -top $(TOP) -json $@"

# Place and Route with nextpnr (heap placer is much faster than default SA)
$(CONFIG): $(JSON) $(CONSTRAINTS)
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --placer heap --lpf $(CONSTRAINTS) --json $(JSON) --textcfg $@

# Generate bitstream with ecppack
$(BITSTREAM): $(CONFIG)
	ecppack --compress --input $< --bit $@

# Program the FPGA via icesprog
program: $(BITSTREAM)
	icesprog $<

# Lint with Verilator (include ECP5 primitive stubs for full coverage)
lint:
	verilator --lint-only -Wall -Wno-fatal $(ECP5_STUBS) $(VERILOG_SRC)

# Simulation with Icarus Verilog
sim: $(VCD)
	@echo "Simulation complete: $(VCD)"

$(VVP): $(ECP5_STUBS) $(VERILOG_SRC) $(SIM_SRC) | $(BUILD_DIR)
	iverilog -o $@ $(ECP5_STUBS) $(VERILOG_SRC) $(SIM_SRC)

$(VCD): $(VVP)
	vvp $< -vcd

# Open waveform viewer
waves: $(VCD)
	gtkwave $(TOP)_tb.gtkw &

clean:
	rm -rf $(BUILD_DIR)
