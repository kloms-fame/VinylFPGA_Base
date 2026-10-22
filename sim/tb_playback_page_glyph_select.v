`timescale 1ns/1ps
`include "playback_layout.vh"

module playback_background (
    input wire clk, input wire rst_n, input wire frame_start, input wire enable,
    input wire cycle_toggle_async, input wire [9:0] pixel_x, input wire [9:0] pixel_y,
    output reg [1:0] mode_frame, output wire [23:0] background_rgb
);
    always @(posedge clk or negedge rst_n)
        if (!rst_n) mode_frame <= 2'd0;
        else if (frame_start && enable) mode_frame <= mode_frame + 2'd1;
    assign background_rgb = 24'h707070;
endmodule

module lrc_five_osd (
    input wire focus_only,
    input wire enable, input wire de, input wire [9:0] pixel_x, input wire [9:0] pixel_y,
    input wire window_valid, input wire highlight_valid, input wire scroll_active,
    input wire [2:0] row_base_slot,
    input wire [29:0] row_lengths, input wire [767:0] row_glyphs,
    input wire [5:0] scroll_offset, input wire [7:0] line_count,
    input wire [127:0] no_lyrics_glyphs,
    output wire font_request, output wire [7:0] font_glyph,
    output wire [3:0] font_column, output wire [3:0] font_pixel_column,
    output wire [3:0] font_row, output wire [23:0] text_color
);
    assign font_request = 1'b0;
    assign font_glyph = 8'd0;
    assign font_column = 4'd0;
    assign font_pixel_column = 4'd0;
    assign font_row = 4'd0;
    assign text_color = 24'hB0B4BC;
endmodule

module song_font_rom (
    input wire clk, input wire [12:0] addr, output reg [15:0] dout
);
    always @(posedge clk) dout <= {3'b000, addr};
endmodule

module tb_playback_page_glyph_select;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg vs = 1'b1;
    reg de = 1'b1;
    reg enable = 1'b1;
    reg browse_mode = 1'b0;
    reg [9:0] pixel_x = 10'd0;
    reg [9:0] test_y = 10'd0;
    reg [1:0] song_id = 2'b10;
    reg [4:0] title_length = 5'd16;
    reg [4:0] artist_length = 5'd16;
    reg [127:0] title_glyphs = 128'd0;
    reg [127:0] artist_glyphs = 128'd0;
    reg [39:0] elapsed_time_ascii = "12:34";
    reg [47:0] remaining_time_ascii = "-05:06";
    reg [39:0] total_time_ascii = "09:08";
    wire [1:0] background_mode;
    wire [9:0] ascii_font_addr;
    wire ascii_font_request;
    reg [7:0] ascii_font_row = 8'hFF;
    wire out_vs, out_de;
    wire [9:0] out_pixel_x;
    wire [23:0] out_rgb;
    integer checks = 0;
    integer failures = 0;
    integer i;
    integer expected_addr;

    always #5 clk = ~clk;

    playback_page dut (
        .lyric_focus_toggle_async(1'b0),
        .clk(clk), .rst_n(rst_n), .vs(vs), .de(de), .pixel_x(pixel_x),
        .enable(enable), .browse_mode(browse_mode), .bg_cycle_toggle_async(1'b0),
        .background_image_active(1'b0), .background_mode(background_mode),
        .rgb_in(24'h123456), .song_id(song_id), .title_length(title_length),
        .artist_length(artist_length), .title_glyphs(title_glyphs),
        .artist_glyphs(artist_glyphs), .line_count(8'd0),
        .lyric_window_valid(1'b0), .lyric_highlight_valid(1'b0),
        .lyric_scroll_active(1'b0), .lyric_row_base_slot(3'd0), .lyric_row_lengths(30'd0),
        .lyric_row_glyphs(768'd0), .lyric_scroll_offset(6'd0),
        .no_lyrics_glyphs(128'd0), .progress_fill(9'd0),
        .elapsed_time_ascii(elapsed_time_ascii),
        .remaining_time_ascii(remaining_time_ascii),
        .total_time_ascii(total_time_ascii), .ascii_font_row(ascii_font_row),
        .ascii_font_addr(ascii_font_addr), .ascii_font_request(ascii_font_request),
        .out_vs(out_vs), .out_de(out_de), .out_pixel_x(out_pixel_x), .out_rgb(out_rgb)
    );

    task check;
        input condition;
        input [8*48-1:0] label_text;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL %0s at x=%0d y=%0d", label_text, pixel_x, test_y);
            end
        end
    endtask

    task check_glyph;
        input [9:0] px;
        input [9:0] py;
        input artist_bank;
        input valid;
        input [7:0] expected_glyph;
        reg [9:0] row;
        begin
            pixel_x = px;
            test_y = py;
            #1;
            check(dut.text_request == valid, "glyph request valid");
            check(!dut.ascii_mode, "glyph uses shared song font");
            if (valid) begin
                check(dut.direct_glyph === expected_glyph, "selected glyph byte");
                check(dut.selected_kind == (artist_bank ? 3'd1 : 3'd0), "selected text bank");
                if (browse_mode)
                    row = py - 10'd424;
                else
                    row = artist_bank ? (py - `PLAYBACK_ARTIST_Y) : (py - `PLAYBACK_TITLE_Y);
                expected_addr = (song_id[1] ? 4096 : 0) + (expected_glyph * 16) + row;
                check(dut.font_addr === expected_addr[12:0], "shared song-font address");
                check(!ascii_font_request, "no ASCII request for song glyph");
            end else begin
                check(dut.direct_glyph === 8'd0, "no glyph selected outside length");
                check(!ascii_font_request, "no ASCII request outside length");
            end
        end
    endtask

    task check_ascii;
        input [9:0] px;
        input [9:0] py;
        input [7:0] expected_ascii;
        input valid;
        reg [9:0] expected_ascii_addr;
        begin
            pixel_x = px;
            test_y = py;
            #1;
            check(dut.text_request == valid, "ASCII request valid");
            check(dut.ascii_mode == valid, "ASCII mode select");
            check(ascii_font_request == valid, "ASCII font request");
            if (valid) begin
                check(dut.selected_ascii === expected_ascii, "selected ASCII byte");
                expected_ascii_addr = {expected_ascii[6:0], dut.selected_row[3:1]};
                check(ascii_font_addr === expected_ascii_addr, "ASCII font address");
            end
        end
    endtask

    initial begin
        force dut.line_y = test_y;
        for (i = 0; i < 16; i = i + 1) begin
            title_glyphs[i*8 +: 8] = 8'h20 + i;
            artist_glyphs[i*8 +: 8] = 8'h80 + i;
        end
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Playback title/artist select every byte in both packed 16-glyph banks.
        browse_mode = 1'b0;
        enable = 1'b1;
        title_length = 5'd16;
        artist_length = 5'd16;
        for (i = 0; i < 16; i = i + 1) begin
            check_glyph(`PLAYBACK_TITLE_X + i*16, `PLAYBACK_TITLE_Y + 5,
                        1'b0, 1'b1, 8'h20 + i);
            check_glyph(`PLAYBACK_ARTIST_X + i*16, `PLAYBACK_ARTIST_Y + 7,
                        1'b1, 1'b1, 8'h80 + i);
        end

        // Length boundaries and the existing ASCII fallback strings.
        title_length = 5'd0;
        check_ascii(`PLAYBACK_TITLE_X + 10'd0, `PLAYBACK_TITLE_Y + 10'd3, 8'h54, 1'b1);
        check_ascii(`PLAYBACK_TITLE_X + 10'd16, `PLAYBACK_TITLE_Y + 10'd3, 8'h52, 1'b1);
        check_ascii(`PLAYBACK_TITLE_X + 10'd128, `PLAYBACK_TITLE_Y + 10'd3, 8'h20, 1'b0);
        title_length = 5'd1;
        check_glyph(`PLAYBACK_TITLE_X, `PLAYBACK_TITLE_Y + 5, 1'b0, 1'b1, 8'h20);
        check_glyph(`PLAYBACK_TITLE_X + 10'd16, `PLAYBACK_TITLE_Y + 5,
                    1'b0, 1'b0, 8'd0);
        title_length = 5'd15;
        check_glyph(`PLAYBACK_TITLE_X + 10'd224, `PLAYBACK_TITLE_Y + 5,
                    1'b0, 1'b1, 8'h2E);
        check_glyph(`PLAYBACK_TITLE_X + 10'd240, `PLAYBACK_TITLE_Y + 5,
                    1'b0, 1'b0, 8'd0);
        title_length = 5'd16;
        check_glyph(`PLAYBACK_TITLE_X + 10'd240, `PLAYBACK_TITLE_Y + 5,
                    1'b0, 1'b1, 8'h2F);

        artist_length = 5'd0;
        check_ascii(`PLAYBACK_ARTIST_X + 10'd0, `PLAYBACK_ARTIST_Y + 10'd3, 8'h41, 1'b1);
        check_ascii(`PLAYBACK_ARTIST_X + 10'd112, `PLAYBACK_ARTIST_Y + 10'd3, 8'h2D, 1'b1);
        check_ascii(`PLAYBACK_ARTIST_X + 10'd144, `PLAYBACK_ARTIST_Y + 10'd3, 8'h20, 1'b0);
        artist_length = 5'd1;
        check_glyph(`PLAYBACK_ARTIST_X, `PLAYBACK_ARTIST_Y + 5, 1'b1, 1'b1, 8'h80);
        check_glyph(`PLAYBACK_ARTIST_X + 10'd16, `PLAYBACK_ARTIST_Y + 5,
                    1'b1, 1'b0, 8'd0);
        artist_length = 5'd15;
        check_glyph(`PLAYBACK_ARTIST_X + 10'd224, `PLAYBACK_ARTIST_Y + 5,
                    1'b1, 1'b1, 8'h8E);
        check_glyph(`PLAYBACK_ARTIST_X + 10'd240, `PLAYBACK_ARTIST_Y + 5,
                    1'b1, 1'b0, 8'd0);
        artist_length = 5'd16;
        check_glyph(`PLAYBACK_ARTIST_X + 10'd240, `PLAYBACK_ARTIST_Y + 5,
                    1'b1, 1'b1, 8'h8F);

        // Browse title, separator half-cell, and artist beginning at each
        // boundary. These regions share the same packed data banks.
        browse_mode = 1'b1;
        enable = 1'b0;
        title_length = 5'd6;
        artist_length = 5'd16;
        for (i = 0; i < 6; i = i + 1)
            check_glyph(10'd164 + i*16, 10'd429, 1'b0, 1'b1, 8'h20 + i);
        for (i = 0; i < 8; i = i + 1)
            check_ascii(10'd260 + i, 10'd429, 8'h2D, 1'b1);
        for (i = 0; i < 16; i = i + 1)
            check_glyph(10'd268 + i*16, 10'd429, 1'b1, 1'b1, 8'h80 + i);
        artist_length = 5'd0;
        check_glyph(10'd268, 10'd429, 1'b1, 1'b0, 8'd0);

        // Browse duration remains ASCII-only and the scan pipeline keeps
        // x/de/vs aligned at the registered output boundary.
        browse_mode = 1'b1;
        de = 1'b1;
        pixel_x = 10'd544;
        test_y = 10'd429;
        #1;
        check(dut.text_request && dut.ascii_mode && ascii_font_request,
              "browse duration ASCII request");
        check(dut.selected_ascii === 8'h30, "browse duration first character");
        @(posedge clk); #1;
        check(out_pixel_x === pixel_x && out_de === de && out_vs === vs,
              "registered video controls stay aligned");

        release dut.line_y;
        if (failures != 0) begin
            $display("FAIL tb_playback_page_glyph_select: %0d/%0d checks failed", failures, checks);
            $fatal(1);
        end
        $display("PASS tb_playback_page_glyph_select: %0d checks", checks);
        $finish;
    end
endmodule
