SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = i2s_tx_top.v ../../rtl/i2s_clkgen.v ../../rtl/i2s_tx.v
TOPLEVEL = i2s_tx_top
MODULE = test_i2s_tx

COMPILE_ARGS = -PCLK_DIV=2 -PDATA_BITS=24

include $(shell cocotb-config --makefiles)/Makefile.sim
