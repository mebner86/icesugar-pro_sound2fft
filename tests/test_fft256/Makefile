SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = ../../rtl/fft256.v
TOPLEVEL = fft256
MODULE = test_fft256

include $(shell cocotb-config --makefiles)/Makefile.sim

# Generate twiddle factors before the simulator binary is compiled.
# $readmemh("twiddle.hex", ...) in the RTL reads from the working directory
# (the directory where make is invoked, i.e., here).
twiddle.hex: gen_twiddle.py
	python3 gen_twiddle.py

$(SIM_BUILD)/sim.vvp: twiddle.hex
