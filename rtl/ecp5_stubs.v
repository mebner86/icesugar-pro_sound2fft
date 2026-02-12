// ECP5 primitive stubs for Verilator linting
// These are minimal black box definitions for the primitives used in this project.
// The actual behavior comes from the FPGA hardware.

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */

// ECP5 PLL primitive
module EHXPLLL (
    input  CLKI,
    input  CLKFB,
    input  PHASESEL1,
    input  PHASESEL0,
    input  PHASEDIR,
    input  PHASESTEP,
    input  PHASELOADREG,
    input  STDBY,
    input  PLLWAKESYNC,
    input  RST,
    input  ENCLKOP,
    input  ENCLKOS,
    input  ENCLKOS2,
    input  ENCLKOS3,
    output CLKOP,
    output CLKOS,
    output CLKOS2,
    output CLKOS3,
    output LOCK,
    output INTLOCK,
    output REFCLK,
    output CLKINTFB
);
    parameter CLKI_DIV = 1;
    parameter CLKFB_DIV = 1;
    parameter CLKOP_DIV = 1;
    parameter CLKOS_DIV = 1;
    parameter CLKOS2_DIV = 1;
    parameter CLKOS3_DIV = 1;
    parameter CLKOP_ENABLE = "ENABLED";
    parameter CLKOS_ENABLE = "DISABLED";
    parameter CLKOS2_ENABLE = "DISABLED";
    parameter CLKOS3_ENABLE = "DISABLED";
    parameter CLKOP_CPHASE = 0;
    parameter CLKOS_CPHASE = 0;
    parameter CLKOS2_CPHASE = 0;
    parameter CLKOS3_CPHASE = 0;
    parameter CLKOP_FPHASE = 0;
    parameter CLKOS_FPHASE = 0;
    parameter CLKOS2_FPHASE = 0;
    parameter CLKOS3_FPHASE = 0;
    parameter FEEDBK_PATH = "CLKOP";
    parameter OUTDIVIDER_MUXA = "DIVA";
    parameter OUTDIVIDER_MUXB = "DIVB";
    parameter OUTDIVIDER_MUXC = "DIVC";
    parameter OUTDIVIDER_MUXD = "DIVD";
    parameter PLLRST_ENA = "DISABLED";
    parameter STDBY_ENABLE = "DISABLED";
    parameter DPHASE_SOURCE = "DISABLED";
    parameter INTFB_WAKE = "DISABLED";

    // Stub behavior: pass through for simulation
    assign CLKOP = CLKI;
    assign CLKOS = CLKI;
    assign CLKOS2 = CLKI;
    assign CLKOS3 = CLKI;
    assign LOCK = 1'b1;
    assign INTLOCK = 1'b1;
    assign REFCLK = CLKI;
    assign CLKINTFB = CLKI;
endmodule

// ECP5 DDR output primitive
module ODDRX1F (
    input  D0,
    input  D1,
    input  SCLK,
    input  RST,
    output Q
);
    // Stub behavior: output D0 (simplified)
    assign Q = D0;
endmodule

/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on DECLFILENAME */
