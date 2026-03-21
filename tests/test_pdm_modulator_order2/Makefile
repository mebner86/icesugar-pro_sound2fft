SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = ../../rtl/pdm_modulator.v
TOPLEVEL = pdm_modulator
MODULE = test_pdm_modulator_order2

# Override the ORDER parameter for 2nd-order testing
ifeq ($(SIM),icarus)
    COMPILE_ARGS += -Ppdm_modulator.ORDER=2
else ifeq ($(SIM),verilator)
    COMPILE_ARGS += -GORDER=2
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
