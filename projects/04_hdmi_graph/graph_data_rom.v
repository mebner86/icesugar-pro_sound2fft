// Graph Data ROM - 256x9-bit synchronous read
// Stores static FFT-like test spectrum loaded from fft_test_data.hex
// Replace this module with dual-port RAM for live FFT data

module graph_data_rom (
    input  wire       clk,
    input  wire [7:0] addr,
    output reg  [8:0] data
);

    reg [8:0] mem [0:255];

    initial begin
        $readmemh("fft_test_data.hex", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end

endmodule
