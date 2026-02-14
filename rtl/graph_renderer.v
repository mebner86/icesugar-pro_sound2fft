// Graph Renderer - Filled line graph for FFT-style spectrum display
// 2-stage pipeline: stage 0 generates ROM address, stage 1 determines pixel color
//
// Data interface: output data_addr, input data_value (ROM-like read port)
// This allows swapping the ROM for live FFT data without changing the renderer.

module graph_renderer #(
    parameter H_ACTIVE   = 800,
    parameter V_ACTIVE   = 480,
    parameter DATA_BITS  = 9
) (
    input  wire                  clk_pixel,
    input  wire                  rst_n,

    // Video timing inputs
    input  wire [9:0]            pixel_x,
    input  wire [9:0]            pixel_y,
    input  wire                  active,

    // Graph data interface (synchronous ROM-like read port)
    output wire [7:0]            data_addr,
    input  wire [DATA_BITS-1:0]  data_value,

    // RGB output (1-cycle delayed relative to pixel_x/pixel_y)
    output reg  [7:0]            red,
    output reg  [7:0]            green,
    output reg  [7:0]            blue
);

    // ======================================================================
    // Layout constants
    // ======================================================================
    // Plot area: 768 x 440 pixels (256 bins x 3 pixels each)
    localparam MARGIN_LEFT   = 20;
    localparam MARGIN_RIGHT  = 12;
    localparam MARGIN_TOP    = 16;
    localparam MARGIN_BOTTOM = 24;

    localparam PLOT_X0 = MARGIN_LEFT;                   // 20
    localparam PLOT_X1 = H_ACTIVE - MARGIN_RIGHT - 1;   // 787
    localparam PLOT_Y0 = MARGIN_TOP;                     // 16
    localparam PLOT_Y1 = V_ACTIVE - MARGIN_BOTTOM - 1;   // 455

    // ======================================================================
    // Colors
    // ======================================================================
    localparam [7:0] BG_R  = 8'h0A, BG_G  = 8'h0A, BG_B  = 8'h14;  // Dark blue-black
    localparam [7:0] LN_R  = 8'h00, LN_G  = 8'hFF, LN_B  = 8'h80;  // Bright green
    localparam [7:0] FL_R  = 8'h00, FL_G  = 8'h38, FL_B  = 8'h18;  // Dark green fill
    localparam [7:0] GR_R  = 8'h1A, GR_G  = 8'h1A, GR_B  = 8'h2A;  // Grid
    localparam [7:0] AX_R  = 8'h40, AX_G  = 8'h40, AX_B  = 8'h60;  // Axis

    // ======================================================================
    // Stage 0: Address generation (combinational from current pixel_x)
    // ======================================================================

    // Relative position within plot area
    wire [9:0] rel_x = pixel_x - PLOT_X0[9:0];

    // Bin index = rel_x / 3, using: (rel_x * 683) >> 11
    // For rel_x 0..767: max product = 767*683 = 524261, fits in 20 bits
    // 524261 >> 11 = 255. Correct.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [19:0] bin_product = rel_x * 20'd683;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [7:0]  bin_index   = bin_product[18:11];

    assign data_addr = bin_index;

    // ======================================================================
    // Pipeline registers (stage 0 -> stage 1)
    // ======================================================================
    reg [9:0]  px_d1, py_d1;
    reg        active_d1;
    reg [7:0]  bin_index_d1;

    // Track previous bin's value for vertical line connections
    reg [DATA_BITS-1:0] prev_value;
    reg [7:0]           prev_bin;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            px_d1      <= 10'd0;
            py_d1      <= 10'd0;
            active_d1  <= 1'b0;
            bin_index_d1 <= 8'd0;
            prev_value <= {DATA_BITS{1'b0}};
            prev_bin   <= 8'd0;
        end else begin
            px_d1      <= pixel_x;
            py_d1      <= pixel_y;
            active_d1  <= active;
            bin_index_d1 <= bin_index;

            // Update previous bin value at bin transitions
            if (bin_index != prev_bin) begin
                prev_value <= data_value;
                prev_bin   <= bin_index;
            end
        end
    end

    // ======================================================================
    // Stage 1: Color determination (combinational from delayed coords + data)
    // ======================================================================

    // Plot area bounds check (using delayed coordinates)
    wire in_plot = (px_d1 >= PLOT_X0[9:0]) && (px_d1 <= PLOT_X1[9:0])
                && (py_d1 >= PLOT_Y0[9:0]) && (py_d1 <= PLOT_Y1[9:0]);

    // Graph Y position: data_value=0 at bottom (PLOT_Y1), data_value=440 at top (PLOT_Y0)
    wire [9:0] graph_y = PLOT_Y1[9:0] - {1'b0, data_value};

    // Vertical connector between adjacent bins
    wire [DATA_BITS-1:0] val_min = (data_value < prev_value) ? data_value : prev_value;
    wire [DATA_BITS-1:0] val_max = (data_value > prev_value) ? data_value : prev_value;
    wire [9:0] connect_y_top = PLOT_Y1[9:0] - {1'b0, val_max};
    wire [9:0] connect_y_bot = PLOT_Y1[9:0] - {1'b0, val_min};

    // Sub-pixel position within 3-pixel bin column
    /* verilator lint_off UNUSEDSIGNAL */
    wire [9:0] rel_x_d1  = px_d1 - PLOT_X0[9:0];
    wire [9:0] bin_start  = {1'b0, bin_index_d1, 1'b0} + {2'b0, bin_index_d1}; // bin_index * 3
    /* verilator lint_on UNUSEDSIGNAL */
    wire [1:0] sub_x      = rel_x_d1[1:0] - bin_start[1:0];

    // Line detection (2px thick at current bin's data point)
    wire on_line = (py_d1 >= graph_y) && (py_d1 <= graph_y + 10'd1);

    // Vertical connector at bin boundary (first pixel of each 3-pixel column)
    wire on_connector = (sub_x == 2'd0) && (bin_index_d1 != 8'd0)
                     && (py_d1 >= connect_y_top) && (py_d1 <= connect_y_bot);

    // Fill below the line
    wire on_fill = (py_d1 > graph_y + 10'd1) && (py_d1 <= PLOT_Y1[9:0]);

    // Grid lines
    wire [9:0] rel_y_d1 = py_d1 - PLOT_Y0[9:0];
    wire on_h_grid = (rel_y_d1 == 10'd88)  || (rel_y_d1 == 10'd176)
                  || (rel_y_d1 == 10'd264) || (rel_y_d1 == 10'd352);
    wire on_v_grid = (bin_index_d1[4:0] == 5'd0) && (sub_x == 2'd0) && (bin_index_d1 != 8'd0);

    // Axis lines (left edge and bottom edge of plot)
    wire on_axis = ((px_d1 == PLOT_X0[9:0]) && (py_d1 >= PLOT_Y0[9:0]) && (py_d1 <= PLOT_Y1[9:0]))
                || ((py_d1 == PLOT_Y1[9:0]) && (px_d1 >= PLOT_X0[9:0]) && (px_d1 <= PLOT_X1[9:0]));

    // ======================================================================
    // Color output (priority: blanking > margin > axis > line > fill > grid > background)
    // ======================================================================
    always @(*) begin
        if (!active_d1) begin
            red   = 8'h00;
            green = 8'h00;
            blue  = 8'h00;
        end else if (!in_plot) begin
            red   = 8'h00;
            green = 8'h00;
            blue  = 8'h00;
        end else if (on_axis) begin
            red   = AX_R;
            green = AX_G;
            blue  = AX_B;
        end else if (on_line || on_connector) begin
            red   = LN_R;
            green = LN_G;
            blue  = LN_B;
        end else if (on_fill) begin
            red   = FL_R;
            green = FL_G;
            blue  = FL_B;
        end else if (on_h_grid || on_v_grid) begin
            red   = GR_R;
            green = GR_G;
            blue  = GR_B;
        end else begin
            red   = BG_R;
            green = BG_G;
            blue  = BG_B;
        end
    end

endmodule
