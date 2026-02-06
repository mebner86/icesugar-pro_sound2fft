// Test Pattern Generator - Vertical Color Bars
// 8 vertical bars: white, yellow, cyan, green, magenta, red, blue, black

module test_pattern (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       active,

    output wire [7:0] red,
    output wire [7:0] green,
    output wire [7:0] blue
);

    // 480 pixels / 8 bars = 60 pixels per bar
    wire [2:0] bar_index = pixel_x[9:6]; // Divide by 64 (close enough to 60)

    // Color bar pattern (active high RGB)
    // Bar 0: White   (111) -> R=FF, G=FF, B=FF
    // Bar 1: Yellow  (110) -> R=FF, G=FF, B=00
    // Bar 2: Cyan    (011) -> R=00, G=FF, B=FF
    // Bar 3: Green   (010) -> R=00, G=FF, B=00
    // Bar 4: Magenta (101) -> R=FF, G=00, B=FF
    // Bar 5: Red     (100) -> R=FF, G=00, B=00
    // Bar 6: Blue    (001) -> R=00, G=00, B=FF
    // Bar 7: Black   (000) -> R=00, G=00, B=00

    reg [7:0] r_out, g_out, b_out;

    always @(*) begin
        if (!active) begin
            r_out = 8'd0;
            g_out = 8'd0;
            b_out = 8'd0;
        end else begin
            case (bar_index)
                3'd0: begin r_out = 8'hFF; g_out = 8'hFF; b_out = 8'hFF; end // White
                3'd1: begin r_out = 8'hFF; g_out = 8'hFF; b_out = 8'h00; end // Yellow
                3'd2: begin r_out = 8'h00; g_out = 8'hFF; b_out = 8'hFF; end // Cyan
                3'd3: begin r_out = 8'h00; g_out = 8'hFF; b_out = 8'h00; end // Green
                3'd4: begin r_out = 8'hFF; g_out = 8'h00; b_out = 8'hFF; end // Magenta
                3'd5: begin r_out = 8'hFF; g_out = 8'h00; b_out = 8'h00; end // Red
                3'd6: begin r_out = 8'h00; g_out = 8'h00; b_out = 8'hFF; end // Blue
                3'd7: begin r_out = 8'h00; g_out = 8'h00; b_out = 8'h00; end // Black
            endcase
        end
    end

    assign red   = r_out;
    assign green = g_out;
    assign blue  = b_out;

endmodule
