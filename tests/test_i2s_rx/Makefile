SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = i2s_rx_top.v ../../rtl/i2s_clkgen.v ../../rtl/i2s_tx.v ../../rtl/i2s_rx.v
TOPLEVEL = i2s_rx_top
MODULE = test_i2s_rx

COMPILE_ARGS = -PCLK_DIV=2 -PDATA_BITS=24

include $(shell cocotb-config --makefiles)/Makefile.sim
