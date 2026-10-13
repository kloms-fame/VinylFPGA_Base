`timescale 1ns/1ps
module tb_stage3a_page #(parameter IMAGE_BACKGROUND=0);
    reg clk=0, source_clk=0, sd_clk=0, rst_n=0;
    always #20 clk=~clk;
    always #10 source_clk=~source_clk;
    always #5 sd_clk=~sd_clk;
    reg vs=1, de=0, enable=1, browse=0;
    reg background_image_active=0;
    reg [9:0] x=0, test_y=0;
    reg [23:0] rgb=24'h123456;
    reg ev_valid=0;
    reg [3:0] ev_code=0;
    reg [15:0] ev_arg=0;
    wire home_tgl, mode_tgl;
    wire stop;
    integer stops=0, checks=0, xx, yy, hits;
    wire [23:0] out_rgb;
    wire out_de, out_vs;
    wire [9:0] out_x, ascii_addr;
    wire [7:0] ascii_row;
    ui_event_bridge bridge(.clk(source_clk),.rst_n(rst_n),
        .ev_valid(ev_valid),.ev_code(ev_code),.ev_arg(ev_arg),.ev_aux(16'd0),
        .home_tgl(home_tgl),.mode_tgl(mode_tgl));
    // Mirror the actual top-level KEY11 disconnect from playback return.
    browse_fsm control(.clk(sd_clk),.rst_n(rst_n),.ev_prev_tgl(1'b0),
        .ev_next_tgl(1'b0),.ev_confirm_tgl(1'b0),.ev_mode_tgl(mode_tgl),
        .ev_home_tgl(1'b0),.mode_play(enable),.play_stop(stop));
    always @(posedge sd_clk) if (rst_n && stop) stops=stops+1;
    ascii_font_rom ascii_rom(.clk(clk),.addr(ascii_addr),.dout(ascii_row));
    playback_page #(.IMAGE_BACKGROUND(IMAGE_BACKGROUND)) page(.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.pixel_x(x),
        .enable(enable),.browse_mode(browse),.bg_cycle_toggle_async(home_tgl),
        .background_image_active(background_image_active),
        .rgb_in(rgb),.song_id(2'd0),.title_length(5'd1),.artist_length(5'd1),
        .title_glyphs(128'd1),.artist_glyphs(128'd1),.line_count(8'd6),
        .lyric_window_valid(1'b1),.lyric_scroll_active(1'b0),
        .lyric_row_lengths({6{5'd1}}),.lyric_row_glyphs({6{128'd1}}),
        .lyric_scroll_offset(6'd0),.no_lyrics_glyphs(128'd1),
        .progress_fill(9'd100),.elapsed_time_ascii("00:34"),
        .remaining_time_ascii("-02:10"),.total_time_ascii("02:44"),
        .ascii_font_row(ascii_row),.ascii_font_addr(ascii_addr),
        .out_vs(out_vs),.out_de(out_de),.out_pixel_x(out_x),.out_rgb(out_rgb));
    task check;
        input ok;
        input [511:0] label;
        begin
            checks=checks+1;
            if (ok !== 1'b1) begin $display("FAIL %0s",label); $finish_and_return(1); end
        end
    endtask
    task key;
        input [15:0] index;
        begin
            @(negedge source_clk); ev_valid=1; ev_code=1; ev_arg=index;
            @(negedge source_clk); ev_valid=0;
            repeat(8) @(negedge clk);
        end
    endtask
    task frame;
        begin
            @(negedge clk); vs=0;
            @(negedge clk); vs=1;
            @(negedge clk);
        end
    endtask
    task pixel;
        input [9:0] px, py;
        begin
            @(negedge clk); x=px; test_y=py;
            @(posedge clk); #1;
            check(out_x===px && out_de===de && out_vs===vs,"pixel controls aligned");
        end
    endtask
    task glyph;
        input integer gx, gy, width;
        input [23:0] expected;
        begin
            hits=0;
            for(yy=gy;yy<gy+16;yy=yy+1)
                for(xx=gx;xx<gx+width;xx=xx+1) begin
                    pixel(xx,yy);
                    if(page.text_hit_q && page.font_pixel) begin
                        check(out_rgb===expected,"actual font pixel palette and timing");
                        hits=hits+1;
                    end
                end
            check(hits>0,"real ROM glyph contains visible pixels");
        end
    endtask
    initial begin
        force page.line_y=test_y;
        repeat(3) @(negedge clk); rst_n=1; de=1;
        pixel(16,48); check(out_rgb===rgb,"media top left preserved");
        pixel(335,287); check(out_rgb===rgb,"media bottom right preserved");
        pixel(336,287); check(out_rgb[23:16]>=105 && out_rgb[23:16]<=128 &&
            out_rgb[23:16]===out_rgb[15:8] && out_rgb[15:8]===out_rgb[7:0],"gray outside media");
        pixel(16,342); check(out_rgb===24'hFFFFFF,"played progress white");
        pixel(116,342); check(out_rgb===24'hB8BCC4,"unplayed progress light gray");
        glyph(16,298,16,24'hFFFFFF);
        glyph(16,318,16,24'hD0D4D8);
        glyph(16,350,40,24'hD0D4D8);
        glyph(356,176,16,24'hB0B4BC);
        glyph(356,224,16,24'hFFD700);
        key(10); check(page.background_mode_frame===0,"KEY11 waits for frame");
        frame; check(page.background_mode_frame===1,"KEY11 mode1");
        key(10); frame; check(page.background_mode_frame===2,"KEY11 mode2");
        key(10); frame; check(page.background_mode_frame===3,"KEY11 mode3");
        check(stops===0,"KEY11 never stops audio control");
        pixel(400,400); check(out_rgb===24'h08080C,"near black canvas");
        pixel(16,48); check(out_rgb===rgb,"black mode media preserved");
        glyph(16,318,16,24'h98A0A8);
        glyph(16,350,40,24'h98A0A8);
        glyph(356,176,16,24'h606068);
        key(6); check(stops===1,"KEY7 still stops and returns");
        enable=0; browse=1;
        key(10); frame; check(page.background_mode_frame===3,"browse KEY11 ignored");
        pixel(400,400); check(out_rgb===rgb,"browse canvas unchanged");
        glyph(164,424,16,24'hFFFFFF);
        glyph(188,424,16,24'hA09880);
        enable=1; browse=0; frame;
        check(page.background_mode_frame===3,"reenter keeps mode");
        key(10); frame; check(page.background_mode_frame===0,"cycle wraps to gray");
        de=0; pixel(400,400); check(out_rgb===0,"blanking black");
        // Resume actual line counting after the isolated pixel-compositor scan.
        release page.line_y;
        frame; check(page.line_y===0,"real scan VS resets line counter");
        @(negedge clk); de=1;
        repeat(3) @(negedge clk); de=0;
        @(negedge clk); check(page.line_y===1,"DE falling edge advances line");
        repeat(3) @(negedge clk);
        check(page.line_y===1,"blanking does not advance line");
        frame; check(page.line_y===0,"next VS starts new frame");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1;
        check(page.background_mode_frame===0,"video reset defaults gray");
        if(IMAGE_BACKGROUND) begin
            force page.line_y=test_y;
            de=1;background_image_active=1;
            pixel(400,400);check(out_rgb===rgb,"ready image passes through canvas");
            pixel(16,48);check(out_rgb===rgb,"ready image preserves media window");
            glyph(16,298,16,24'hFFFFFF);
            glyph(16,350,40,24'hD0D4D8);
            background_image_active=0;
            pixel(400,400);check(out_rgb!==rgb && out_rgb[23:16]>=105 && out_rgb[23:16]<=128,"image unavailable restores gray");
            release page.line_y;
        end
        $display("PASS stage3a page: %0d checks, real key bridge, return control and font ROMs",checks);
        $finish;
    end
    initial begin #10000000; $display("FAIL timeout"); $finish_and_return(1); end
endmodule
