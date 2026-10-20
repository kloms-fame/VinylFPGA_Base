`timescale 1ns/1ps
module tb_final_browse_text;
reg clk=0; always #20 clk=~clk;
reg rst_n=0; reg [9:0] x=204; reg [1:0] song=0;
wire [4:0] title_length,artist_length; wire [127:0] title_glyphs,artist_glyphs;
song_text_rom textrom(.clk(clk),.song_id(song),.line_index(7'd0),.title_length(title_length),.artist_length(artist_length),.title_glyphs(title_glyphs),.artist_glyphs(artist_glyphs),.ui_ascii_code(8'h20));
playback_page page(.clk(clk),.rst_n(rst_n),.vs(1'b1),.de(1'b1),.pixel_x(x),.enable(1'b0),.browse_mode(1'b1),.end_mode(2'd2),.bg_cycle_toggle_async(1'b0),.background_image_active(1'b0),.rgb_in(24'd0),.song_id(song),.title_length(title_length),.artist_length(artist_length),.title_glyphs(title_glyphs),.artist_glyphs(artist_glyphs),.line_count(8'd0),.lyric_window_valid(1'b0),.lyric_highlight_valid(1'b0),.lyric_scroll_active(1'b0),.lyric_row_base_slot(3'd0),.lyric_row_lengths(30'd0),.lyric_row_glyphs(768'd0),.lyric_scroll_offset(6'd0),.no_lyrics_glyphs(128'd0),.progress_fill(9'd0),.elapsed_time_ascii(40'd0),.remaining_time_ascii(48'd0),.total_time_ascii(40'd0),.ascii_font_row(8'd0));
integer sid,px,artist_start;
reg expected_request;
initial begin
    force page.line_y=10'd424;
    repeat(3) @(negedge clk);rst_n=1;
    for(sid=0;sid<4;sid=sid+1) begin
        song=sid;repeat(4) @(negedge clk);
        artist_start=164+title_length*16+8;
        for(px=164;px<524;px=px+1) begin
            x=px;#1;
            expected_request=(px < artist_start+artist_length*16);
            if(page.text_request !== expected_request)
                $fatal(1,"song%0d x%0d text request=%b expected=%b",sid+1,px,page.text_request,expected_request);
        end
    end
    $display("PASS final browse text: four songs, full metadata row bounds");$finish;
end
endmodule
