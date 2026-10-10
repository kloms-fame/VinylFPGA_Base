// 由 tools/gen_lrc_assets.py --songs-manifest 自动生成，请勿手改。
`ifndef EXP_SONG_TEXT_ROM_V
`define EXP_SONG_TEXT_ROM_V
module song_text_rom (
    input  wire        clk,
    input  wire [1:0]  song_id,
    input  wire [6:0]  line_index,
    output reg  [7:0]  line_count,
    output reg         line_valid,
    output reg  [31:0] line_time_ms,
    output reg  [4:0]  line_length,
    output reg  [127:0] line_glyphs,
    output reg         song_text_valid,
    output reg  [4:0]  title_length,
    output reg  [4:0]  artist_length,
    output reg  [127:0] title_glyphs,
    output reg  [127:0] artist_glyphs,
    output wire [127:0] no_lyrics_glyphs,
    input  wire [7:0]  ui_ascii_code,
    output reg  [7:0]  ui_glyph
);
    localparam integer SONG_LINE_ADDR_W = 1;
    reg [164:0] line_mem [0:0];
    initial begin
        line_mem[0] = 165'h000000000000000000000000000000000000000000;
    end
    reg [SONG_LINE_ADDR_W-1:0] line_base;
    wire [SONG_LINE_ADDR_W-1:0] line_addr = line_base + line_index;
    assign no_lyrics_glyphs = 128'h00000000000000160F10151812001413;
    always @* begin
        line_count = 8'd0;
        line_base = {SONG_LINE_ADDR_W{1'b0}};
        song_text_valid = 1'b0;
        title_length = 5'd0;
        artist_length = 5'd0;
        title_glyphs = 128'd0;
        artist_glyphs = 128'd0;
        case (song_id)
            2'd0: begin
                line_count = 8'd0;
                line_base = 1'd0;
                title_length = 5'd0;
                artist_length = 5'd0;
                title_glyphs = 128'h00000000000000000000000000000000;
                artist_glyphs = 128'h00000000000000000000000000000000;
                song_text_valid = 1'b0;
            end
            2'd1: begin
                line_count = 8'd0;
                line_base = 1'd0;
                title_length = 5'd0;
                artist_length = 5'd0;
                title_glyphs = 128'h00000000000000000000000000000000;
                artist_glyphs = 128'h00000000000000000000000000000000;
                song_text_valid = 1'b0;
            end
            2'd2: begin
                line_count = 8'd0;
                line_base = 1'd0;
                title_length = 5'd0;
                artist_length = 5'd0;
                title_glyphs = 128'h00000000000000000000000000000000;
                artist_glyphs = 128'h00000000000000000000000000000000;
                song_text_valid = 1'b0;
            end
            2'd3: begin
                line_count = 8'd0;
                line_base = 1'd0;
                title_length = 5'd0;
                artist_length = 5'd0;
                title_glyphs = 128'h00000000000000000000000000000000;
                artist_glyphs = 128'h00000000000000000000000000000000;
                song_text_valid = 1'b0;
            end
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if ((line_index < line_count) && (line_addr < 1'd1)) begin
            line_time_ms <= line_mem[line_addr][164:133];
            line_length <= line_mem[line_addr][132:128];
            line_glyphs <= line_mem[line_addr][127:0];
            line_valid <= 1'b1;
        end else begin
            line_time_ms <= 32'hFFFFFFFF;
            line_length <= 5'd0;
            line_glyphs <= 128'd0;
            line_valid <= 1'b0;
        end
    end
    always @* begin
        ui_glyph = 8'd0;
        case (ui_ascii_code)
            8'd32: ui_glyph = 8'd0;
            8'd45: ui_glyph = 8'd1;
            8'd47: ui_glyph = 8'd2;
            8'd48: ui_glyph = 8'd3;
            8'd49: ui_glyph = 8'd4;
            8'd50: ui_glyph = 8'd5;
            8'd51: ui_glyph = 8'd6;
            8'd52: ui_glyph = 8'd7;
            8'd53: ui_glyph = 8'd8;
            8'd54: ui_glyph = 8'd9;
            8'd55: ui_glyph = 8'd10;
            8'd56: ui_glyph = 8'd11;
            8'd57: ui_glyph = 8'd12;
            8'd58: ui_glyph = 8'd13;
            8'd65: ui_glyph = 8'd14;
            8'd67: ui_glyph = 8'd15;
            8'd73: ui_glyph = 8'd16;
            8'd75: ui_glyph = 8'd17;
            8'd76: ui_glyph = 8'd18;
            8'd78: ui_glyph = 8'd19;
            8'd79: ui_glyph = 8'd20;
            8'd82: ui_glyph = 8'd21;
            8'd83: ui_glyph = 8'd22;
            8'd84: ui_glyph = 8'd23;
            8'd89: ui_glyph = 8'd24;
            default: ui_glyph = 8'd0;
        endcase
    end
endmodule
`endif
