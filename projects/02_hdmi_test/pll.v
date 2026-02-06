// PLL for HDMI timing - 480x800@60Hz
// Input:  25 MHz
// Output: 30 MHz pixel clock, 150 MHz shift clock (5x for DDR TMDS)
//
// VCO = 25 MHz × 6 × 4 = 600 MHz
// clk_pixel = 600 / 20 = 30 MHz
// clk_shift = 600 / 4 = 150 MHz

module pll (
    input  wire clk_25m,
    output wire clk_pixel,   // 30 MHz
    output wire clk_shift,   // 150 MHz (5x pixel for DDR)
    output wire locked
);

    EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(1),
        .CLKFB_DIV(6),
        .CLKOP_DIV(4),       // 600/4 = 150 MHz (shift clock)
        .CLKOS_DIV(20),      // 600/20 = 30 MHz (pixel clock)
        .CLKOS2_DIV(1),
        .CLKOS3_DIV(1),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS2_ENABLE("DISABLED"),
        .CLKOS3_ENABLE("DISABLED"),
        .CLKOP_CPHASE(3),
        .CLKOS_CPHASE(19),
        .CLKOP_FPHASE(0),
        .CLKOS_FPHASE(0),
        .FEEDBK_PATH("CLKOP")
    ) pll_inst (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clk_25m),
        .CLKOP(clk_shift),
        .CLKOS(clk_pixel),
        .CLKOS2(),
        .CLKOS3(),
        .CLKFB(clk_shift),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b0),
        .PHASESTEP(1'b0),
        .PHASELOADREG(1'b0),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .ENCLKOS(1'b0),
        .ENCLKOS2(1'b0),
        .ENCLKOS3(1'b0),
        .LOCK(locked)
    );

endmodule
