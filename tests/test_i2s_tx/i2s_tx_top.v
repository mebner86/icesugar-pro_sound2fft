// Test wrapper: i2s_clkgen + i2s_tx wired together
module i2s_tx_top #(
    parameter CLK_DIV   = 2,
    parameter DATA_BITS = 24
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_BITS-1:0]  left_data,
    input  wire [DATA_BITS-1:0]  right_data,

    output wire                  bclk,
    output wire                  lrclk,
    output wire                  bclk_falling,
    output wire                  sdata
);

    i2s_clkgen #(.CLK_DIV(CLK_DIV)) clkgen (
        .clk          (clk),
        .rst_n        (rst_n),
        .bclk         (bclk),
        .lrclk        (lrclk),
        .bclk_falling (bclk_falling)
    );

    i2s_tx #(.DATA_BITS(DATA_BITS)) tx (
        .clk          (clk),
        .rst_n        (rst_n),
        .bclk_falling (bclk_falling),
        .lrclk        (lrclk),
        .left_data    (left_data),
        .right_data   (right_data),
        .sdata        (sdata)
    );

endmodule
