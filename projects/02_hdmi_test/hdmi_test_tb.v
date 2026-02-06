// Testbench for HDMI Test Pattern Generator
`timescale 1ns / 1ps

module hdmi_test_tb;

    // Clock and reset
    reg clk_25m;
    reg rst_n;

    // LED outputs
    wire led_r;
    wire led_g;
    wire led_b;

    // Instantiate the design under test
    hdmi_test dut (
        .clk_25m(clk_25m),
        .rst_n(rst_n),
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b)
    );

    // Generate 25 MHz clock (40ns period)
    initial begin
        clk_25m = 0;
        forever #20 clk_25m = ~clk_25m;
    end

    // Test sequence
    initial begin
        $dumpfile("build/hdmi_test_tb.vcd");
        $dumpvars(0, hdmi_test_tb);

        // Initialize
        rst_n = 0;

        // Release reset after a few cycles
        #100;
        rst_n = 1;

        // Run simulation for enough time to see video timing
        // For 640x480@60Hz: frame time = ~16.7ms
        // Simulate a few lines for basic testing
        #1000000;  // 1ms

        $display("Simulation complete");
        $finish;
    end

endmodule
