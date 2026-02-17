// Test wrapper: i2s_clkgen + i2s_tx + i2s_rx wired as loopback
module i2s_rx_top #(
    parameter CLK_DIV   = 2,
    parameter DATA_BITS = 24
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_BITS-1:0]  tx_left,
    input  wire [DATA_BITS-1:0]  tx_right,

    output wire                  bclk,
    output wire                  lrclk,
    output wire                  bclk_falling,
    output wire                  sdata,
    output wire [DATA_BITS-1:0]  rx_left,
    output wire                  rx_left_valid,
    output wire [DATA_BITS-1:0]  rx_right,
    output wire                  rx_right_valid
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
        .left_data    (tx_left),
        .right_data   (tx_right),
        .sdata        (sdata)
    );

    i2s_rx #(.DATA_BITS(DATA_BITS)) rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .bclk_falling (bclk_falling),
        .lrclk        (lrclk),
        .sdata        (sdata),
        .left_data    (rx_left),
        .left_valid   (rx_left_valid),
        .right_data   (rx_right),
        .right_valid  (rx_right_valid)
    );

endmodule
