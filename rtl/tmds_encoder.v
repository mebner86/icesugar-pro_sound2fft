// TMDS Encoder - 8b/10b encoding for DVI/HDMI
// Based on DVI 1.0 specification

module tmds_encoder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,    // 8-bit pixel data
    input  wire [1:0] ctrl,       // Control signals (hsync/vsync for blue channel)
    input  wire       data_en,    // High during active video
    output reg  [9:0] tmds_out    // 10-bit TMDS encoded output
);

    // Count number of 1s in input data
    wire [3:0] n_ones = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                        data_in[4] + data_in[5] + data_in[6] + data_in[7];

    // First stage: XOR or XNOR based on number of 1s
    wire use_xnor = (n_ones > 4) || (n_ones == 4 && data_in[0] == 0);
    wire [8:0] q_m;

    assign q_m[0] = data_in[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data_in[1]) : (q_m[0] ^ data_in[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data_in[2]) : (q_m[1] ^ data_in[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data_in[3]) : (q_m[2] ^ data_in[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data_in[4]) : (q_m[3] ^ data_in[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data_in[5]) : (q_m[4] ^ data_in[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data_in[6]) : (q_m[5] ^ data_in[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data_in[7]) : (q_m[6] ^ data_in[7]);
    assign q_m[8] = ~use_xnor;

    // Count 1s and 0s in q_m[7:0]
    wire [3:0] n_ones_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                          q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] n_zeros_qm = 4'd8 - n_ones_qm;

    // DC balance counter
    reg signed [4:0] cnt;

    // Control character encoding (during blanking)
    wire [9:0] ctrl_code;
    assign ctrl_code = (ctrl == 2'b00) ? 10'b1101010100 :
                       (ctrl == 2'b01) ? 10'b0010101011 :
                       (ctrl == 2'b10) ? 10'b0101010100 :
                                         10'b1010101011;

    // Second stage: DC balance
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmds_out <= 10'b0;
            cnt <= 5'sd0;
        end else if (!data_en) begin
            // Control period - output control character
            tmds_out <= ctrl_code;
            cnt <= 5'sd0;
        end else begin
            // Data period - DC balanced encoding
            if (cnt == 0 || n_ones_qm == 4) begin
                // No disparity or balanced q_m
                tmds_out[9] <= ~q_m[8];
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8]) begin
                    cnt <= cnt + $signed({1'b0, n_ones_qm}) - $signed({1'b0, n_zeros_qm});
                end else begin
                    cnt <= cnt + $signed({1'b0, n_zeros_qm}) - $signed({1'b0, n_ones_qm});
                end
            end else begin
                if ((cnt > 0 && n_ones_qm > 4) || (cnt < 0 && n_ones_qm < 4)) begin
                    // Invert to reduce disparity
                    tmds_out[9] <= 1'b1;
                    tmds_out[8] <= q_m[8];
                    tmds_out[7:0] <= ~q_m[7:0];
                    cnt <= cnt + $signed({1'b0, q_m[8], 1'b0}) +
                           $signed({1'b0, n_zeros_qm}) - $signed({1'b0, n_ones_qm});
                end else begin
                    // Don't invert
                    tmds_out[9] <= 1'b0;
                    tmds_out[8] <= q_m[8];
                    tmds_out[7:0] <= q_m[7:0];
                    cnt <= cnt - $signed({1'b0, ~q_m[8], 1'b0}) +
                           $signed({1'b0, n_ones_qm}) - $signed({1'b0, n_zeros_qm});
                end
            end
        end
    end

endmodule
