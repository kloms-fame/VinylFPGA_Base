`timescale 1ns/1ps
`include "playback_layout.vh"

// Real UI bridge -> asynchronous clocks -> real page and glyph selector.
// VINYL_FOCUS_BASELINE omits only the new ports to reproduce the old behavior.
module tb_lyric_focus;
    reg clk=0, source_clk=0, rst_n=0;
    always #20 clk=~clk;
    always #10 source_clk=~source_clk;
    reg vs=1, de=1, enable=1, browse=0;
    reg ev_valid=0;
    reg [3:0] ev_code=0;
    reg [15:0] ev_arg=0;
    reg [9:0] x=`PLAYBACK_LYRIC_X, test_y=176;
    reg scroll=0, highlight=1, window_valid=1;
    reg [5:0] offset=0;
    reg [2:0] base=0;
    reg [7:0] count=8;
    reg [1:0] song_id=0;
    reg [767:0] glyphs=0;
    wire focus_tgl;
    wire [23:0] out_rgb;
    integer checks=0, s, p, b, r;

    ui_event_bridge bridge(.clk(source_clk),.rst_n(rst_n),
        .ev_valid(ev_valid),.ev_code(ev_code),.ev_arg(ev_arg),.ev_aux(16'd0)
`ifndef VINYL_FOCUS_BASELINE
        ,.lyric_focus_tgl(focus_tgl)
`endif
    );
    playback_page page(.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.pixel_x(x),
        .enable(enable),.browse_mode(browse),.end_mode(2'd0),
        .bg_cycle_toggle_async(1'b0),.background_image_active(1'b0),
`ifndef VINYL_FOCUS_BASELINE
        .lyric_focus_toggle_async(focus_tgl),
`endif
        .rgb_in(24'h123456),.song_id(song_id),.title_length(5'd0),.artist_length(5'd0),
        .title_glyphs(128'd0),.artist_glyphs(128'd0),.line_count(count),
        .lyric_window_valid(window_valid),.lyric_highlight_valid(highlight),
        .lyric_scroll_active(scroll),.lyric_row_base_slot(base),
        .lyric_row_lengths({6{5'd16}}),.lyric_row_glyphs(glyphs),
        .lyric_scroll_offset(offset),.no_lyrics_glyphs({16{8'h19}}),
        .progress_fill(9'd0),.elapsed_time_ascii(40'd0),
        .remaining_time_ascii(48'd0),.total_time_ascii(40'd0),
        .ascii_font_row(8'd0),.out_rgb(out_rgb));

    initial force page.line_y=test_y;
    task check;
        input ok;
        input [8*100-1:0] label;
        begin
            checks=checks+1;
            if(ok !== 1'b1) $fatal(1,"FAIL %0s",label);
        end
    endtask
    task key;
        input [3:0] code;
        input [15:0] index;
        begin
            @(negedge source_clk);ev_valid=1;ev_code=code;ev_arg=index;
            @(negedge source_clk);ev_valid=0;
            repeat(8) @(negedge clk);
        end
    endtask
    task frame;
        begin
            @(negedge clk);vs=0;
            @(negedge clk);vs=1;
            @(negedge clk);
        end
    endtask
    task pixel;
        input integer py;
        begin test_y=py;#1;end
    endtask
    task neighbor;
        input expected;
        begin
            pixel(176);
            check(page.lyric_font_request === expected,"neighbor visibility");
        end
    endtask

    initial begin
        for(s=0;s<6;s=s+1) glyphs[s*128+:128]={16{(8'h40+s[7:0])}};
        repeat(4) @(negedge clk);rst_n=1;
        repeat(8) @(negedge clk);frame;
        neighbor(1);
        key(4'd1,16'd5);
        neighbor(1); // A synchronized event must not tear the current frame.
        frame;
        neighbor(0); // Baseline fails here: KEY6 has no display business.

        // Ring wrapping, every 3-pixel scroll phase, full 16-pixel glyph rows.
        for(b=0;b<6;b=b+1) begin
            base=b;
            for(p=0;p<=16;p=p+1) begin
                scroll=(p!=16);offset=(p%16)*3;
                for(s=0;s<6;s=s+1) begin
                  for(r=0;r<16;r=r+1) begin
                    pixel(128+s*48-offset+r);
                    if(test_y>=48 && test_y<360) begin
                        check(page.lyric_font_request === (s==(scroll?3:2)),
                              "focus selects only current logical row");
                        if(s==(scroll?3:2)) begin
                            check(page.lyric_font_glyph === (8'h40+((s+b)%6)),
                                  "focus uses wrapped physical glyph slot");
                            check(page.lyric_text_color === 24'hFFD700,
                                  "current row remains gold during scrolling");
                            check(page.lyric_font_row === r[3:0],
                                  "glyph row stays aligned through scrolling");
                        end
                    end
                  end
                end
            end
        end
        base=0;scroll=0;offset=0;
        highlight=0;pixel(224);
        check(page.lyric_font_request && page.lyric_text_color==24'h606068,
              "prelude keeps neutral first-line preview");
        highlight=1;count=0;pixel(224);
        check(page.lyric_font_request && page.lyric_font_glyph==8'h19,
              "NO LYRICS remains visible in focus mode");
        count=8;window_valid=0;#1;
        check(!page.lyric_font_request,"invalid window remains hidden");
        window_valid=1;

        // Non-key-down, upper-bit aliases and other controls do not switch.
        key(4'd2,16'd5);key(4'd1,16'h0015);key(4'd1,16'd8);frame;neighbor(0);
        // Two accepted presses before a frame preserve parity.
        key(4'd1,16'd5);key(4'd1,16'd5);frame;neighbor(0);
        key(4'd1,16'd5);neighbor(0);frame;neighbor(1);
        key(4'd1,16'd5);frame;neighbor(0);
        // Browse input is drained and does not modify the persistent mode.
        enable=0;browse=1;
        key(4'd1,16'd5);frame;
        enable=1;browse=0;frame;neighbor(0);
        // Leaving playback before CDC consumption discards that event too.
        @(negedge source_clk);ev_valid=1;ev_code=1;ev_arg=5;
        @(negedge source_clk);ev_valid=0;enable=0;browse=1;
        repeat(8) @(negedge clk);frame;
        enable=1;browse=0;frame;neighbor(0);
        // Metadata changes and idle frames do not clear this display mode.
        song_id=3;frame;neighbor(0);
        song_id=1;frame;neighbor(0);
        repeat(3) frame;neighbor(0);
        @(negedge clk);rst_n=0;
        repeat(3) @(negedge clk);rst_n=1;
        repeat(8) @(negedge clk);frame;neighbor(1);
        $display("PASS lyric focus: key-to-page, frame CDC, ring/scroll, prelude, no lyrics, browse, reset; checks=%0d",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"FAIL watchdog");end
endmodule
