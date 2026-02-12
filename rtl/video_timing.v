// Video Timing Generator for 480x800@60Hz
// Active: 480x800, Total: 600x833

module video_timing (
    input  wire clk_pixel,
    input  wire rst_n,

    output wire hsync,
    output wire vsync,
    output wire active,       // High during active video
    output wire [9:0] pixel_x, // 0-479 during active
    output wire [9:0] pixel_y  // 0-799 during active
);

    // Horizontal timing (active low sync)
    localparam H_ACTIVE      = 480;
    localparam H_FRONT_PORCH = 24;
    localparam H_SYNC        = 48;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = 600;

    // Vertical timing (active low sync)
    localparam V_ACTIVE      = 800;
    localparam V_FRONT_PORCH = 3;
    localparam V_SYNC        = 5;
    localparam V_BACK_PORCH  = 25;
    localparam V_TOTAL       = 833;

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
