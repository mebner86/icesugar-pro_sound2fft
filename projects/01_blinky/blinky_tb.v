// Testbench for blinky example
`timescale 1ns / 1ps

module blinky_tb;

    reg clk_25m;
    reg rst_n;
    wire led_r, led_g, led_b;

    // Instantiate the DUT
    blinky dut (
        .clk_25m(clk_25m),
        .rst_n(rst_n),
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b)
    );

    // 25 MHz clock = 40ns period
    initial clk_25m = 0;
    always #20 clk_25m = ~clk_25m;

    // VCD dump
    initial begin
        $dumpfile("build/blinky_tb.vcd");
        $dumpvars(0, blinky_tb);
    end

    // Run simulation
    initial begin
        $display("Starting blinky simulation...");

        // Apply reset
        rst_n = 0;
        #100;
        rst_n = 1;
        $display("Reset released at %0t", $time);

        // Run for enough cycles to see LED changes
        // Counter bit 21 toggles every 2^21 cycles = ~84ms at 25MHz
        // Simulate ~100us worth (2500 cycles)
        #100000;

        $display("LED states: R=%b G=%b B=%b", led_r, led_g, led_b);
        $display("Simulation complete.");
        $finish;
    end

endmodule
