// TMDS Serializer for ECP5
// Converts 10-bit parallel TMDS to serial pseudo-differential output
// Uses 5x pixel clock with DDR output for 10:1 serialization

module tmds_serializer (
    input  wire       clk_pixel,   // Pixel clock (30 MHz)
    input  wire       clk_shift,   // Shift clock (150 MHz, 5x pixel)
    input  wire       rst_n,
    input  wire [9:0] tmds_in,     // 10-bit TMDS encoded data
    output wire       tmds_p,      // Pseudo-differential positive
    output wire       tmds_n       // Pseudo-differential negative (inverted)
);

    // Shift register for serialization
    reg [9:0] shift_reg;
    reg [9:0] shift_load;

    // Synchronize pixel clock to shift clock domain
    reg [2:0] pixel_clk_sync;
    wire load_pulse;

    always @(posedge clk_shift or negedge rst_n) begin
        if (!rst_n) begin
            pixel_clk_sync <= 3'b000;
        end else begin
            pixel_clk_sync <= {pixel_clk_sync[1:0], clk_pixel};
        end
    end

    // Detect rising edge of pixel clock (in shift clock domain)
    assign load_pulse = (pixel_clk_sync[2:1] == 2'b01);

    // Latch data on pixel clock for stability
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            shift_load <= 10'd0;
        end else begin
            shift_load <= tmds_in;
        end
    end

    // Shift register operation at shift clock
    always @(posedge clk_shift or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'd0;
        end else if (load_pulse) begin
            shift_reg <= shift_load;
        end else begin
            // Shift out 2 bits (for DDR)
            shift_reg <= {2'b00, shift_reg[9:2]};
        end
    end

    // DDR output for positive signal
    ODDRX1F ddr_pos (
        .Q(tmds_p),
        .D0(shift_reg[0]),
        .D1(shift_reg[1]),
        .SCLK(clk_shift),
        .RST(~rst_n)
    );

    // DDR output for negative signal (inverted data)
    ODDRX1F ddr_neg (
        .Q(tmds_n),
        .D0(~shift_reg[0]),
        .D1(~shift_reg[1]),
        .SCLK(clk_shift),
        .RST(~rst_n)
    );

endmodule
