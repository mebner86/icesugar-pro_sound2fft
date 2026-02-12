// Video Timing Generator
// Default: 480x800@60Hz (portrait), parameterizable for other modes

module video_timing #(
    parameter H_ACTIVE      = 480,
    parameter H_FRONT_PORCH = 24,
    parameter H_SYNC        = 48,
    parameter H_BACK_PORCH  = 48,
    parameter H_TOTAL       = 600,

    parameter V_ACTIVE      = 800,
    parameter V_FRONT_PORCH = 3,
    parameter V_SYNC        = 5,
    parameter V_BACK_PORCH  = 25,
    parameter V_TOTAL       = 833
) (
    input  wire clk_pixel,
    input  wire rst_n,

    output wire hsync,
    output wire vsync,
    output wire active,       // High during active video
    output wire [9:0] pixel_x, // Horizontal pixel coordinate during active
    output wire [9:0] pixel_y  // Vertical pixel coordinate during active
);

    // Sync pulse positions
    localparam H_SYNC_START = H_ACTIVE + H_FRONT_PORCH;
    localparam H_SYNC_END   = H_SYNC_START + H_SYNC;
    localparam V_SYNC_START = V_ACTIVE + V_FRONT_PORCH;
    localparam V_SYNC_END   = V_SYNC_START + V_SYNC;

    // Counters
    reg [9:0] h_count;
    reg [9:0] v_count;

    // Horizontal counter
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    // Vertical counter
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1) begin
                v_count <= 10'd0;
            end else begin
                v_count <= v_count + 1'b1;
            end
        end
    end

    // Generate sync signals (active low)
    assign hsync = ~((h_count >= H_SYNC_START) && (h_count < H_SYNC_END));
    assign vsync = ~((v_count >= V_SYNC_START) && (v_count < V_SYNC_END));

    // Active video area
    assign active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // Pixel coordinates (only valid when active)
    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule
