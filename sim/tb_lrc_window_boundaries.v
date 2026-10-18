`timescale 1ns/1ps
`include "playback_layout.vh"
module tb_lrc_window_boundaries;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg vs = 1;
    reg enable = 1;
    reg [31:0] time_ms = 0;
    reg [1:0] song_id = 0;
    reg generation = 0;
    reg [31:0] rom_time_ms = 0;
    reg [4:0] rom_length = 0;
    reg [127:0] rom_glyphs = 0;
    reg rom_valid = 0;
    reg [7:0] fixture_line_count = 8;
    reg scroll_active = 0;
    reg [6:0] scroll_target_index = 0;
    reg scroll_commit = 0;
    wire [6:0] rom_line_index;
    wire [7:0] song_line_count_frame;
    wire target_valid;
    wire [6:0] target_index;
    wire window_valid, window_ready;
    wire [6:0] window_center_index;
    wire [2:0] row_base_slot;
    wire [29:0] row_lengths;
    wire [767:0] row_glyphs;
    wire preview_font_request;
    wire [7:0] preview_glyph;
    wire [23:0] preview_color;
    reg [9:0] preview_y = `PLAYBACK_LYRIC_Y;
    reg [31:0] timestamps [0:7];
    integer tail_requests = 0;
    integer last_tail_index = -1;
    integer i;

    lrc_window_controller dut (
        .clk(clk), .rst_n(rst_n), .vs(vs), .enable(enable),
        .time_ms(time_ms), .song_id_async(song_id),
        .generation_async(generation), .rom_line_count(fixture_line_count),
        .rom_line_valid(rom_valid), .rom_line_time_ms(rom_time_ms),
        .rom_line_length(rom_length), .rom_line_glyphs(rom_glyphs),
        .scroll_active(scroll_active), .scroll_target_index(scroll_target_index),
        .scroll_commit(scroll_commit), .song_id_frame(), .generation_frame(),
        .rom_line_index(rom_line_index),
        .song_line_count_frame(song_line_count_frame),
        .target_valid(target_valid), .target_index(target_index),
        .window_valid(window_valid), .window_ready(window_ready),
        .window_center_index(window_center_index),
        .row_base_slot(row_base_slot),
        .row_lengths(row_lengths), .row_glyphs(row_glyphs)
    );

    lrc_five_osd preview_osd (
        .enable(1'b1), .de(1'b1), .pixel_x(`PLAYBACK_LYRIC_X),
        .pixel_y(preview_y), .window_valid(window_valid),
        .highlight_valid(target_valid), .scroll_active(1'b0),
        .row_base_slot(row_base_slot),
        .row_lengths(row_lengths), .row_glyphs(row_glyphs),
        .scroll_offset(6'd0), .line_count(song_line_count_frame),
        .no_lyrics_glyphs(128'd0), .font_request(preview_font_request),
        .font_glyph(preview_glyph), .font_column(), .font_pixel_column(), .font_row(),
        .text_color(preview_color)
    );

    // A one-cycle synchronous ROM model with deterministic timestamps and
    // glyph IDs: line n contains 16 copies of byte 0x40+n.
    always @(posedge clk) begin
        rom_valid <= (rom_line_index < fixture_line_count);
        rom_time_ms <= timestamps[rom_line_index];
        rom_length <= (rom_line_index < fixture_line_count) ? 5'd16 : 5'd0;
        rom_glyphs <= (rom_line_index < fixture_line_count) ?
            {16{(8'h40 + {1'b0, rom_line_index})}} : 128'd0;
        if (rst_n && (dut.state == 3'd5) && dut.tail_index_in_range) begin
            tail_requests <= tail_requests + 1;
            last_tail_index <= rom_line_index;
        end
    end

    task frame_scan;
        input [31:0] requested_time;
        begin
            time_ms = requested_time;
            @(negedge clk); vs = 0;
            @(negedge clk); vs = 1;
            // Scan and fill each take fewer than 64 cycles for this fixture.
            repeat (80) @(negedge clk);
        end
    endtask

    task do_scroll_commit;
        begin
            @(negedge clk); scroll_commit = 1;
            @(negedge clk); scroll_commit = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    task require;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) $fatal(1, "%0s", message);
        end
    endtask

    initial begin
        timestamps[0]=1000; timestamps[1]=2000; timestamps[2]=3000;
        timestamps[3]=4000; timestamps[4]=5000; timestamps[5]=6000;
        timestamps[6]=7000; timestamps[7]=8000;
        repeat (4) @(negedge clk); rst_n = 1;

        // Prelude before line 0's timestamp: show it in the center, neutral.
        frame_scan(0);
        require(window_valid && window_ready && !target_valid &&
                (window_center_index == 0), "prelude preview was not published at row 0");
        require(row_lengths[14:10] == 16 && row_glyphs[383:376] == 8'h40,
                "prelude center row does not contain deterministic line 0");
        require(preview_font_request && preview_color == 24'h606068,
                "prelude preview was not rendered as neutral gray");

        // Start and first scroll: timestamp equality selects the exact line;
        // one committed scroll exposes old center+4 as the incoming tail row.
        frame_scan(1000);
        require(target_valid && target_index == 0, "first timestamp did not select line 0");
        require(preview_color == 24'hFFD700,
                "timestamp-selected current lyric did not receive active highlight");
        frame_scan(2000);
        require(target_valid && target_index == 1 && window_center_index == 0,
                "first next-line selection was not held at center+1");
        scroll_target_index = 1;
        do_scroll_commit();
        frame_scan(2000);
        require(window_center_index == 1 && last_tail_index == 4,
                "first scroll tail skipped or repeated a lyric row");
        require(row_base_slot == 1 && row_glyphs[7:0] == 8'h44,
                "first scroll incoming row is not deterministic line 4");
        preview_y = `PLAYBACK_LYRIC_Y + 10'd96; #1;
        require(preview_font_request && preview_glyph == 8'h43,
                "first ring rotation changed the visible logical row order");

        // Continuous scrolling must request the next sequential tail index.
        frame_scan(3000);
        require(target_valid && target_index == 2, "continuous scroll target line 2 missing");
        scroll_target_index = 2;
        do_scroll_commit();
        frame_scan(3000);
        require(window_center_index == 2 && row_base_slot == 2 &&
                row_glyphs[135:128] == 8'h45 && last_tail_index == 5,
                "continuous scroll tail index did not advance sequentially to line 5");
        preview_y = `PLAYBACK_LYRIC_Y + 10'd96; #1;
        require(preview_font_request && preview_glyph == 8'h44,
                "second ring rotation changed the visible logical row order");

        // Seek generation changes invalidate the old window and refill around
        // the selected line in both directions.
        generation = ~generation;
        frame_scan(4000);
        require(target_valid && target_index == 3 && window_center_index == 3,
                "forward seek did not refill at line 3");
        generation = ~generation;
        frame_scan(1000);
        require(target_valid && target_index == 0 && window_center_index == 0,
                "backward seek did not refill at line 0");

        // After the final timestamp, the last lyric remains selected and all
        // beyond-end cache slots are zero-filled without wrapping the index.
        frame_scan(32'hFFFFFFFF);
        require(target_valid && target_index == 7 && window_center_index == 7,
                "song-end timestamp did not clamp selection to final line");
        require(row_glyphs[383:376] == 8'h47 && row_lengths[14:10] == 16,
                "final lyric row was lost at song end");
        require(row_glyphs[767:640] == 0 && row_lengths[29:25] == 0,
                "out-of-range song-end row was not cleared");

        $display("PASS lyrics: prelude, exact timestamp, first/continuous tail indices, forward/back seek, song-end clamp");
        $finish;
    end
endmodule
