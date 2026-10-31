`timescale 1ns/1ps
`ifndef EXP_EC2_PARAM_OSD_V
`define EXP_EC2_PARAM_OSD_V
`include "playback_layout.vh"

// Opaque, one-pixel registered EC2 parameter panel. Coordinates remain aligned
// with RGB/DE/VS so the downstream boot and HDMI stages see one coherent stream.
module ec2_param_osd (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vs,
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [23:0] rgb_in,
    input  wire        visible,
    input  wire [1:0]  ui_state,       // 1=SELECT, 2=ADJUST
    input  wire [2:0]  selected_param,// 0=VOL, 1=BRI, 2=CON, 3=ROT, 4=WSL, 5=MIC
    input  wire [7:0]  volume,
    input  wire [11:0] volume_bcd,
    input  wire [2:0]  brightness_level,
    input  wire [2:0]  contrast_level,
    input  wire [2:0]  rotation_level,
    input  wire [2:0]  ws_level,
    input  wire [2:0]  mic_level,
    input  wire [7:0]  ascii_font_row,
    output wire [9:0]  ascii_font_addr,
    output wire        ascii_font_request,
    output reg         out_vs,
    output reg         out_de,
    output reg  [9:0]  out_pixel_x,
    output reg  [23:0] out_rgb
);
    localparam [2:0] PARAM_VOL = 3'd0;
    localparam [2:0] PARAM_BRI = 3'd1;
    localparam [2:0] PARAM_CON = 3'd2;
    localparam [2:0] PARAM_ROT = 3'd3;
    localparam [2:0] PARAM_WSL = 3'd4;
    localparam [2:0] PARAM_MIC = 3'd5;

    reg [9:0] line_y;
    reg       de_q;
    reg       vs_q;
    reg       visible_d;
    reg [1:0] state_d;
    reg [2:0] selected_d;
    reg [7:0] volume_d;
    reg [11:0] volume_bcd_d;
    reg [2:0] brightness_d;
    reg [2:0] contrast_d;
    reg [2:0] rotation_d;
    reg [2:0] ws_d;
    reg [2:0] mic_d;
    reg [9:0] pixel_y_d;
    reg [23:0] rgb_d;

    wire [9:0] title_dx = pixel_x - `PLAYBACK_EC2_TEXT_X;
    wire [9:0] status_dx = pixel_x - `PLAYBACK_EC2_STATUS_X;
    wire [9:0] value_dy = line_y - `PLAYBACK_EC2_VALUE_Y;
    wire [9:0] title_dy = line_y - `PLAYBACK_EC2_TITLE_Y;
    wire title_region = de && (line_y >= `PLAYBACK_EC2_TITLE_Y) &&
                        (line_y < (`PLAYBACK_EC2_TITLE_Y + 10'd8)) &&
                        (pixel_x >= `PLAYBACK_EC2_TEXT_X) &&
                        (pixel_x < (`PLAYBACK_EC2_TEXT_X + 10'd24));
    wire status_region = de && (line_y >= `PLAYBACK_EC2_TITLE_Y) &&
                         (line_y < (`PLAYBACK_EC2_TITLE_Y + 10'd8)) &&
                         (pixel_x >= `PLAYBACK_EC2_STATUS_X) &&
                         (pixel_x < (`PLAYBACK_EC2_STATUS_X + 10'd24));
    wire value_region = de && (line_y >= `PLAYBACK_EC2_VALUE_Y) &&
                        (line_y < (`PLAYBACK_EC2_VALUE_Y + 10'd8)) &&
                        (pixel_x >= `PLAYBACK_EC2_TEXT_X) &&
                        (pixel_x < (`PLAYBACK_EC2_TEXT_X + 10'd40));

    function [31:0] ratio_text;
        input [2:0] param_id;
        input [2:0] level;
        begin
            ratio_text = {8'h20, 8'h20, 8'h20, 8'h20};
            if (param_id == PARAM_BRI) begin
                case (level)
                    3'd0: ratio_text = {8'h31,8'h2f,8'h34,8'h58}; // 1/4X
                    3'd1: ratio_text = {8'h31,8'h2f,8'h32,8'h58}; // 1/2X
                    3'd2: ratio_text = {8'h33,8'h2f,8'h34,8'h58}; // 3/4X
                    3'd3: ratio_text = {8'h31,8'h58,8'h20,8'h20}; // 1X
                    3'd4: ratio_text = {8'h35,8'h2f,8'h34,8'h58}; // 5/4X
                    default: ;
                endcase
            end else if (param_id == PARAM_CON) begin
                case (level)
                    3'd0: ratio_text = {8'h31,8'h2f,8'h32,8'h58}; // 1/2X
                    3'd1: ratio_text = {8'h33,8'h2f,8'h34,8'h58}; // 3/4X
                    3'd2: ratio_text = {8'h31,8'h58,8'h20,8'h20}; // 1X
                    3'd3: ratio_text = {8'h35,8'h2f,8'h34,8'h58}; // 5/4X
                    3'd4: ratio_text = {8'h33,8'h2f,8'h32,8'h58}; // 3/2X
                    default: ;
                endcase
            end else if (param_id == PARAM_ROT) begin
                case (level)
                    3'd0: ratio_text = {8'h4F,8'h46,8'h46,8'h20}; // OFF
                    3'd1: ratio_text = {8'h32,8'h53,8'h20,8'h20}; // 2S
                    3'd2: ratio_text = {8'h33,8'h53,8'h20,8'h20}; // 3S
                    3'd3: ratio_text = {8'h35,8'h53,8'h20,8'h20}; // 5S
                    3'd4: ratio_text = {8'h31,8'h30,8'h53,8'h20}; // 10S
                    3'd5: ratio_text = {8'h32,8'h30,8'h53,8'h20}; // 20S
                    default: ;
                endcase
            end else if (param_id == PARAM_MIC) begin
                // 0X or 4X..7X follow the level encoding directly.
                case (level)
                    3'd0: ratio_text = {8'h30,8'h58,8'h20,8'h20}; // 0X
                    3'd4: ratio_text = {8'h34,8'h58,8'h20,8'h20}; // 4X
                    3'd5: ratio_text = {8'h35,8'h58,8'h20,8'h20}; // 5X
                    3'd6: ratio_text = {8'h36,8'h58,8'h20,8'h20}; // 6X
                    default: ratio_text = {8'h37,8'h58,8'h20,8'h20}; // 7X
                endcase
            end else begin
                case (level)
                    3'd0: ratio_text = {8'h30,8'h25,8'h20,8'h20}; // 0%
                    3'd1: ratio_text = {8'h32,8'h35,8'h25,8'h20}; // 25%
                    3'd2: ratio_text = {8'h35,8'h30,8'h25,8'h20}; // 50%
                    3'd3: ratio_text = {8'h37,8'h35,8'h25,8'h20}; // 75%
                    3'd4: ratio_text = {8'h31,8'h30,8'h30,8'h25}; // 100%
                    default: ;
                endcase
            end
        end
    endfunction

    // Formatting one 32-bit ratio string per call costs a full mux tree, so
    // the active parameter's level is selected first and formatted once.
    reg [2:0] adjust_level;
    always @* begin
        if (selected_param == PARAM_BRI) adjust_level = brightness_level;
        else if (selected_param == PARAM_CON) adjust_level = contrast_level;
        else if (selected_param == PARAM_ROT) adjust_level = rotation_level;
        else if (selected_param == PARAM_WSL) adjust_level = ws_level;
        else adjust_level = mic_level;
    end

    reg [6:0] font_char;
    reg [2:0] font_row_index;
    reg [2:0] text_slot;
    reg [31:0] ratio_value;
    always @* begin
        font_char      = 7'h20;
        font_row_index = 3'd0;
        text_slot      = 3'd0;
        ratio_value    = 32'h20202020;

        if (title_region) begin
            text_slot = title_dx[4:3];
            font_row_index = title_dy[2:0];
            case (selected_param)
                PARAM_VOL: begin
                    case (text_slot)
                        3'd0: font_char = 7'd86; // V
                        3'd1: font_char = 7'd79; // O
                        default: font_char = 7'd76; // L
                    endcase
                end
                PARAM_BRI: begin
                    case (text_slot)
                        3'd0: font_char = 7'd66; // B
                        3'd1: font_char = 7'd82; // R
                        default: font_char = 7'd73; // I
                    endcase
                end
                PARAM_ROT: begin
                    case (text_slot)
                        3'd0: font_char = 7'd82; // R
                        3'd1: font_char = 7'd79; // O
                        default: font_char = 7'd84; // T
                    endcase
                end
                PARAM_WSL: begin
                    case (text_slot)
                        3'd0: font_char = 7'd87; // W
                        3'd1: font_char = 7'd83; // S
                        default: font_char = 7'd76; // L
                    endcase
                end
                PARAM_MIC: begin
                    case (text_slot)
                        3'd0: font_char = 7'd77; // M
                        3'd1: font_char = 7'd73; // I
                        default: font_char = 7'd67; // C
                    endcase
                end
                default: begin
                    case (text_slot)
                        3'd0: font_char = 7'd67; // C
                        3'd1: font_char = 7'd79; // O
                        default: font_char = 7'd78; // N
                    endcase
                end
            endcase
        end else if (status_region) begin
            text_slot = status_dx[4:3];
            font_row_index = title_dy[2:0];
            if (ui_state == 2'd2) begin
                case (text_slot)
                    3'd0: font_char = 7'd65; // A
                    3'd1: font_char = 7'd68; // D
                    default: font_char = 7'd74; // J
                endcase
            end else begin
                case (text_slot)
                    3'd0: font_char = 7'd83; // S
                    3'd1: font_char = 7'd69; // E
                    default: font_char = 7'd76; // L
                endcase
            end
        end else if (value_region) begin
            text_slot = (pixel_x - `PLAYBACK_EC2_TEXT_X) >> 3;
            font_row_index = value_dy[2:0];
            if (selected_param == PARAM_VOL) begin
                case (text_slot)
                    3'd0: font_char = 7'd48 + volume_bcd[11:8];
                    3'd1: font_char = 7'd48 + volume_bcd[7:4];
                    3'd2: font_char = 7'd48 + volume_bcd[3:0];
                    default: font_char = 7'h20;
                endcase
            end else begin
                ratio_value = ratio_text(selected_param, adjust_level);
                case (text_slot)
                    3'd0: font_char = ratio_value[31:24];
                    3'd1: font_char = ratio_value[23:16];
                    3'd2: font_char = ratio_value[15:8];
                    3'd3: font_char = ratio_value[7:0];
                    default: font_char = 7'h20;
                endcase
            end
        end
    end

    wire [9:0] font_addr = {font_char, font_row_index};
    assign ascii_font_addr = font_addr;
    assign ascii_font_request = title_region || status_region || value_region;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y        <= 10'd0;
            de_q          <= 1'b0;
            vs_q          <= 1'b1;
            out_vs        <= 1'b1;
            out_de        <= 1'b0;
            out_pixel_x   <= 10'd0;
            pixel_y_d     <= 10'd0;
            rgb_d         <= 24'h000000;
            visible_d     <= 1'b0;
            state_d       <= 2'd0;
            selected_d    <= PARAM_VOL;
            volume_d      <= 8'd0;
            volume_bcd_d  <= 12'd0;
            brightness_d  <= 3'd3;
            contrast_d    <= 3'd2;
            rotation_d    <= 3'd2;
            ws_d          <= 3'd4;
            mic_d         <= 3'd5;
        end else begin
            de_q <= de;
            vs_q <= vs;
            if (!vs)
                line_y <= 10'd0;
            else if (de_q && !de)
                line_y <= line_y + 10'd1;

            out_de       <= de;
            out_vs       <= vs;
            out_pixel_x  <= pixel_x;
            pixel_y_d    <= line_y;
            rgb_d        <= rgb_in;
            visible_d    <= visible;
            state_d      <= ui_state;
            selected_d   <= selected_param;
            volume_d     <= volume;
            volume_bcd_d <= volume_bcd;
            brightness_d <= brightness_level;
            contrast_d   <= contrast_level;
            rotation_d   <= rotation_level;
            ws_d         <= ws_level;
            mic_d        <= mic_level;
        end
    end

    // Unsigned wrap keeps the window test valid for pixels left of the panel.
    localparam integer PANEL_WIDTH  = `PLAYBACK_EC2_OSD_X1 - `PLAYBACK_EC2_OSD_X0;
    localparam integer PANEL_HEIGHT = `PLAYBACK_EC2_OSD_Y1 - `PLAYBACK_EC2_OSD_Y0;
    wire [9:0] panel_dx = out_pixel_x - `PLAYBACK_EC2_OSD_X0;
    wire [9:0] panel_dy = pixel_y_d - `PLAYBACK_EC2_OSD_Y0;
    wire in_panel = visible_d && out_de &&
                    (panel_dx < PANEL_WIDTH) && (panel_dy < PANEL_HEIGHT);
    wire panel_border = (panel_dx == 10'd0) || (panel_dx == PANEL_WIDTH - 1) ||
                        (panel_dy == 10'd0) || (panel_dy == PANEL_HEIGHT - 1);
    wire title_text_area = (pixel_y_d >= `PLAYBACK_EC2_TITLE_Y) &&
                           (pixel_y_d < (`PLAYBACK_EC2_TITLE_Y + 10'd8)) &&
                           (((out_pixel_x >= `PLAYBACK_EC2_TEXT_X) &&
                             (out_pixel_x < (`PLAYBACK_EC2_TEXT_X + 10'd24))) ||
                            ((out_pixel_x >= `PLAYBACK_EC2_STATUS_X) &&
                             (out_pixel_x < (`PLAYBACK_EC2_STATUS_X + 10'd24))));
    wire value_text_area = (pixel_y_d >= `PLAYBACK_EC2_VALUE_Y) &&
                           (pixel_y_d < (`PLAYBACK_EC2_VALUE_Y + 10'd8)) &&
                           (out_pixel_x >= `PLAYBACK_EC2_TEXT_X) &&
                           (out_pixel_x < (`PLAYBACK_EC2_TEXT_X + 10'd40));
    wire [2:0] text_col = (title_text_area && out_pixel_x >= `PLAYBACK_EC2_STATUS_X)
                        ? (out_pixel_x - `PLAYBACK_EC2_STATUS_X)
                        : (out_pixel_x - `PLAYBACK_EC2_TEXT_X);
    wire font_pixel = ascii_font_row[3'd7 - text_col];
    wire bar_y = (pixel_y_d >= `PLAYBACK_EC2_BAR_Y) &&
                 (pixel_y_d < (`PLAYBACK_EC2_BAR_Y + 10'd6));
    wire [9:0] bar_x = out_pixel_x - `PLAYBACK_EC2_TEXT_X;
    wire [7:0] volume_bar_len = volume_d - (volume_d >> 3);
    // Every parameter shares one five-step bar ladder. MIC keeps its sparse
    // 0X/4X/5X/6X/7X encoding, the others all use 0/56/112/168/224.
    reg [8:0] level_bar_len;
    always @* begin
        if (selected_d == PARAM_MIC) begin
            case (mic_d)
                3'd0: level_bar_len = 9'd0;
                3'd4: level_bar_len = 9'd56;
                3'd5: level_bar_len = 9'd112;
                3'd6: level_bar_len = 9'd168;
                default: level_bar_len = 9'd224;
            endcase
        end else begin
            case (selected_d == PARAM_BRI ? brightness_d :
                  selected_d == PARAM_CON ? contrast_d :
                  selected_d == PARAM_ROT ? rotation_d : ws_d)
                3'd0: level_bar_len = 9'd0;
                3'd1: level_bar_len = 9'd56;
                3'd2: level_bar_len = 9'd112;
                3'd3: level_bar_len = 9'd168;
                default: level_bar_len = 9'd224;
            endcase
        end
    end
    wire bar_filled = (selected_d == PARAM_VOL)
                    ? (bar_x < {2'b00, volume_bar_len})
                    : (bar_x < {1'b0, level_bar_len});

    always @* begin
        out_rgb = rgb_d;
        if (in_panel) begin
            if (panel_border)
                out_rgb = 24'h52677C;
            else if (bar_y && bar_x < 10'd224)
                out_rgb = bar_filled ? 24'h45D7B0 : 24'h273744;
            else if ((title_text_area || value_text_area) && font_pixel)
                out_rgb = (state_d == 2'd2 && title_text_area &&
                           out_pixel_x < `PLAYBACK_EC2_STATUS_X)
                        ? 24'h71E4C4 : 24'hE6EEF5;
            else
                out_rgb = 24'h111B27;
        end
    end
endmodule
`endif
