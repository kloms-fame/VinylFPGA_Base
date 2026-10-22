`timescale 1ns/1ps
module tb_closure_lyric_equiv;
 reg enable=0,de=0,valid=0,scroll=0;
 reg [9:0] x=0,y=0;
 reg [29:0] lengths=0;
 reg [767:0] glyphs=0;
 reg [5:0] offset=0;
 reg [7:0] count=0;
 reg [127:0] empty_text=0;
 wire [44:0] current,previous;
 integer i,j,xx,yy,pass_count=0;
 reg [31:0] random_word;
 lrc_five_osd now_dut(.focus_only(1'b0),.enable(enable),.de(de),.pixel_x(x),.pixel_y(y),
  .window_valid(valid),.scroll_active(scroll),.row_lengths(lengths),.row_glyphs(glyphs),
  .scroll_offset(offset),.line_count(count),.no_lyrics_glyphs(empty_text),
  .font_request(current[44]),.font_glyph(current[43:36]),.font_column(current[35:32]),
  .font_pixel_column(current[31:28]),.font_row(current[27:24]),.text_color(current[23:0]));
 lrc_five_osd_before old_dut(.enable(enable),.de(de),.pixel_x(x),.pixel_y(y),
  .window_valid(valid),.scroll_active(scroll),.row_lengths(lengths),.row_glyphs(glyphs),
  .scroll_offset(offset),.line_count(count),.no_lyrics_glyphs(empty_text),
  .font_request(previous[44]),.font_glyph(previous[43:36]),.font_column(previous[35:32]),
  .font_pixel_column(previous[31:28]),.font_row(previous[27:24]),.text_color(previous[23:0]));
 task compare;
  begin #1;if(current!==previous) $fatal(1,"lyric mismatch x%0d y%0d offset%0d now%h old%h",x,y,offset,current,previous);pass_count=pass_count+1;end
 endtask
 initial begin
  for(i=0;i<25000;i=i+1) begin
   random_word=$random;x=random_word%640;random_word=$random;y=random_word%480;
   {enable,de,valid,scroll}=i[3:0];lengths=$random;offset=$random;count=(i%7==0)?0:8'd12;
   for(j=0;j<24;j=j+1) glyphs[j*32+:32]=$random;
   for(j=0;j<4;j=j+1) empty_text[j*32+:32]=$random;
   compare;
  end
  enable=1;de=1;valid=1;count=12;lengths={6{5'd16}};
  for(i=0;i<2;i=i+1) begin
   offset=i?47:0;scroll=i;
   for(yy=0;yy<480;yy=yy+1) for(xx=0;xx<640;xx=xx+1) begin x=xx;y=yy;compare;end
  end
  $display("PASS lyric combinational equivalence %0d vectors including two full screens",pass_count);$finish;
 end
endmodule
