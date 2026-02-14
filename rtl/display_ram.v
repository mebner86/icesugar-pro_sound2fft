// Dual-port Display RAM
// Write port: FFT engine writes magnitude values (clk_25m domain)
// Read port: graph renderer reads for display (clk_pixel domain)
// 256 entries x 9 bits (amplitude range 0-440)

module display_ram (
    // Write port (FFT / system clock domain)
    input  wire       wr_clk,
    input  wire       wr_en,
    input  wire [7:0] wr_addr,
    input  wire [8:0] wr_data,

    // Read port (pixel clock domain)
    input  wire       rd_clk,
    input  wire [7:0] rd_addr,
    output reg  [8:0] rd_data
);

    reg [8:0] mem [0:255];

    always @(posedge wr_clk)
        if (wr_en) mem[wr_addr] <= wr_data;

    always @(posedge rd_clk)
        rd_data <= mem[rd_addr];

endmodule
