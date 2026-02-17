SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = ../../rtl/i2s_clkgen.v
TOPLEVEL = i2s_clkgen
MODULE = test_i2s_clkgen

# Set default CLK_DIV parameter for simulation
COMPILE_ARGS = -PCLK_DIV=4

include $(shell cocotb-config --makefiles)/Makefile.sim
