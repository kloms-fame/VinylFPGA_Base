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
    localparam integer SONG_LINE_ADDR_W = 6;
    reg [164:0] line_mem [0:47];
    initial begin
        line_mem[0] = 165'h000000000B00000000001A2525261F00281E2C1E14;
        line_mem[1] = 165'h000001770B0000000000272B002B262E001E2C211F;
        line_mem[2] = 165'h000002EE0B00000000001A2525261F00281E2C1E25;
        line_mem[3] = 165'h000004650C00000000252D261D002B262E002A1E23;
        line_mem[4] = 165'h000005DC0B00000000001A2525261F00281E2C1E25;
        line_mem[5] = 165'h000007530A0000000000001D252B26281A00252B28;
        line_mem[6] = 165'h000008CA0E00002B262E002A281E291E1D001D251A;
        line_mem[7] = 165'h00000A410B00000000001A2525261F00281E2C1E25;
        line_mem[8] = 165'h00000BB80C000000002E281C002B262E001E221A24;
        line_mem[9] = 165'h00000D2F0B00000000001A2525261F00281E2C1E25;
        line_mem[10] = 165'h00000EA60B00000000001E2E1B1D26261F002E1A29;
        line_mem[11] = 165'h0000101D0C000000002B262E002A282B20001D251A;
        line_mem[12] = 165'h00000000050000000000000000000000737A644AA5;
        line_mem[13] = 165'h00000177050000000000000000000000AA30473585;
        line_mem[14] = 165'h000002EE050000000000000000000000A06348A77A;
        line_mem[15] = 165'h00000465050000000000000000000000568F3F4A9D;
        line_mem[16] = 165'h000005DC0500000000000000000000006F38A96B6A;
        line_mem[17] = 165'h00000753050000000000000000000000444C7C939E;
        line_mem[18] = 165'h000008CA0500000000000000000000004E664AB0AF;
        line_mem[19] = 165'h00000A4105000000000000000000000053553B5135;
        line_mem[20] = 165'h00000BB8050000000000000000000000975D5EA978;
        line_mem[21] = 165'h00000D2F0500000000000000000000003C7E90A657;
        line_mem[22] = 165'h00000EA6050000000000000000000000398632734A;
        line_mem[23] = 165'h0000101D0500000000000000000000007933844236;
        line_mem[24] = 165'h00000000050000000000000000000000A26B7F3AA3;
        line_mem[25] = 165'h000001770500000000000000000000008D308895A5;
        line_mem[26] = 165'h000002EE05000000000000000000000047355FAE6C;
        line_mem[27] = 165'h00000465050000000000000000000000609F89513A;
        line_mem[28] = 165'h000005DC050000000000000000000000523661707D;
        line_mem[29] = 165'h0000075305000000000000000000000072489A3E96;
        line_mem[30] = 165'h000008CA05000000000000000000000074783799AF;
        line_mem[31] = 165'h00000A410500000000000000000000006D6C9CA956;
        line_mem[32] = 165'h00000BB8050000000000000000000000AD784D4175;
        line_mem[33] = 165'h00000D2F050000000000000000000000A1674BA26B;
        line_mem[34] = 165'h00000EA6050000000000000000000000468731774E;
        line_mem[35] = 165'h0000101D0500000000000000000000009B7BABB150;
        line_mem[36] = 165'h00000000050000000000000000000000575C8C8281;
        line_mem[37] = 165'h000001770500000000000000000000007759656969;
        line_mem[38] = 165'h000002EE050000000000000000000000458564838B;
        line_mem[39] = 165'h000004650500000000000000000000009162684F93;
        line_mem[40] = 165'h000005DC050000000000000000000000A887499957;
        line_mem[41] = 165'h0000075305000000000000000000000098977C9492;
        line_mem[42] = 165'h000008CA05000000000000000000000058862F692F;
        line_mem[43] = 165'h00000A4105000000000000000000000096933D4F93;
        line_mem[44] = 165'h00000BB8050000000000000000000000439F715A59;
        line_mem[45] = 165'h00000D2F05000000000000000000000076A44D8281;
        line_mem[46] = 165'h00000EA605000000000000000000000057362F545B;
        line_mem[47] = 165'h0000101D0500000000000000000000008A8631AC85;
    end
    reg [SONG_LINE_ADDR_W-1:0] line_base;
    wire [SONG_LINE_ADDR_W-1:0] line_addr = line_base + line_index;
    assign no_lyrics_glyphs = 128'h00000000000000170F11161913001514;
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
                line_count = 8'd12;
                line_base = 6'd0;
                title_length = 5'd11;
                artist_length = 5'd11;
                title_glyphs = 128'h00000000001A2525261000281E2C1E14;
                artist_glyphs = 128'h00000000002E1E232A290E00221C2116;
                song_text_valid = 1'b1;
            end
            2'd1: begin
                line_count = 8'd12;
                line_base = 6'd12;
                title_length = 5'd4;
                artist_length = 5'd4;
                title_glyphs = 128'h000000000000000000000000A2347A4A;
                artist_glyphs = 128'h00000000000000000000000080409E4A;
                song_text_valid = 1'b1;
            end
            2'd2: begin
                line_count = 8'd12;
                line_base = 6'd24;
                title_length = 5'd4;
                artist_length = 5'd4;
                title_glyphs = 128'h000000000000000000000000707D6B6E;
                artist_glyphs = 128'h00000000000000000000000080409E8E;
                song_text_valid = 1'b1;
            end
            2'd3: begin
                line_count = 8'd12;
                line_base = 6'd36;
                title_length = 5'd4;
                artist_length = 5'd4;
                title_glyphs = 128'h00000000000000000000000099578281;
                artist_glyphs = 128'h00000000000000000000000080409993;
                song_text_valid = 1'b1;
            end
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if ((line_index < line_count) && (line_addr < 6'd48)) begin
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
            8'd71: ui_glyph = 8'd16;
            8'd73: ui_glyph = 8'd17;
            8'd75: ui_glyph = 8'd18;
            8'd76: ui_glyph = 8'd19;
            8'd78: ui_glyph = 8'd20;
            8'd79: ui_glyph = 8'd21;
            8'd82: ui_glyph = 8'd22;
            8'd83: ui_glyph = 8'd23;
            8'd84: ui_glyph = 8'd24;
            8'd89: ui_glyph = 8'd25;
            8'd97: ui_glyph = 8'd26;
            8'd98: ui_glyph = 8'd27;
            8'd99: ui_glyph = 8'd28;
            8'd100: ui_glyph = 8'd29;
            8'd101: ui_glyph = 8'd30;
            8'd103: ui_glyph = 8'd31;
            8'd104: ui_glyph = 8'd32;
            8'd105: ui_glyph = 8'd33;
            8'd107: ui_glyph = 8'd34;
            8'd108: ui_glyph = 8'd35;
            8'd109: ui_glyph = 8'd36;
            8'd110: ui_glyph = 8'd37;
            8'd111: ui_glyph = 8'd38;
            8'd112: ui_glyph = 8'd39;
            8'd114: ui_glyph = 8'd40;
            8'd115: ui_glyph = 8'd41;
            8'd116: ui_glyph = 8'd42;
            8'd117: ui_glyph = 8'd43;
            8'd118: ui_glyph = 8'd44;
            8'd119: ui_glyph = 8'd45;
            8'd121: ui_glyph = 8'd46;
            default: ui_glyph = 8'd0;
        endcase
    end
endmodule
`endif
