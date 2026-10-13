`timescale 1ns/1ps
module tb_closure_window_equiv;
 reg clk=0,rst_n=0,vs=1,enable=0,generation=0;
 reg [31:0] time_ms=0,line_time=0;
 reg [1:0] song=0;
 reg [7:0] count=0;
 reg line_valid=0,scroll=0,commit=0;
 reg [4:0] length=0;
 reg [127:0] glyphs=0;
 reg [6:0] scroll_target=0;
 wire [832:0] current,previous;
 integer i,j,checks=0,shifts=0,fills=0,tails=0;
 always #5 clk=~clk;
 lrc_window_controller dut(
 .clk(clk),.rst_n(rst_n),.vs(vs),.enable(enable),.time_ms(time_ms),
 .song_id_async(song),.generation_async(generation),.rom_line_count(count),
 .rom_line_valid(line_valid),.rom_line_time_ms(line_time),.rom_line_length(length),
 .rom_line_glyphs(glyphs),.scroll_active(scroll),.scroll_target_index(scroll_target),.scroll_commit(commit),
 .song_id_frame(current[832:831]),.generation_frame(current[830]),.rom_line_index(current[829:823]),
 .song_line_count_frame(current[822:815]),.target_valid(current[814]),.target_index(current[813:807]),
 .window_valid(current[806]),.window_ready(current[805]),.window_center_index(current[804:798]),
 .row_lengths(current[797:768]),.row_glyphs(current[767:0]));
 lrc_window_controller_before old_dut(
 .clk(clk),.rst_n(rst_n),.vs(vs),.enable(enable),.time_ms(time_ms),
 .song_id_async(song),.generation_async(generation),.rom_line_count(count),
 .rom_line_valid(line_valid),.rom_line_time_ms(line_time),.rom_line_length(length),
 .rom_line_glyphs(glyphs),.scroll_active(scroll),.scroll_target_index(scroll_target),.scroll_commit(commit),
 .song_id_frame(previous[832:831]),.generation_frame(previous[830]),.rom_line_index(previous[829:823]),
 .song_line_count_frame(previous[822:815]),.target_valid(previous[814]),.target_index(previous[813:807]),
 .window_valid(previous[806]),.window_ready(previous[805]),.window_center_index(previous[804:798]),
 .row_lengths(previous[797:768]),.row_glyphs(previous[767:0]));
 always @(posedge clk) begin
  if(rst_n && !dut.frame_start) begin
   if(commit && current[806]) shifts=shifts+1;
   else if(dut.fill_clear || dut.fill_read) fills=fills+1;
   else if(dut.tail_clear || dut.tail_read) tails=tails+1;
  end
  #1;
  if(current!==previous) $fatal(1,"window cycle mismatch at %0d",checks);
  checks=checks+1;
 end
 initial begin
  repeat(3) @(negedge clk);rst_n=1;enable=1;count=12;
  // A coherent next-line transition exercises the tail read, followed by
  // an end-of-song scroll exercising out-of-range fill/zero behavior.
  time_ms=2000;line_valid=1;length=16;glyphs={16{8'h41}};
  for(i=0;i<1200;i=i+1) begin
   @(negedge clk);vs=(i%200!=0);
   if(i==600) time_ms=3000;
   line_time=dut.scan_pending_index*1000;
   commit=(i==808);scroll=0;scroll_target=3;
  end
  for(i=0;i<60000;i=i+1) begin
   @(negedge clk);
   vs=(i%400!=0);
   if(i%400==0) begin
    count=(i/400)%128;time_ms=$random;enable=(i%4400!=0);
    if(i%2000==0) begin song=song+1;generation=~generation;end
   end
   rst_n=(i%13001!=0);
   line_time=$random;line_valid=(i%5!=0);length=$random;
   for(j=0;j<4;j=j+1) glyphs[j*32+:32]=$random;
   scroll=(i%3==0);scroll_target=$random;
   commit=(i%23==0);
  end
  @(negedge clk);
  if(shifts==0 || fills==0 || tails==0) $fatal(1,"missing cache-path coverage shift%0d fill%0d tail%0d",shifts,fills,tails);
  $display("PASS lyric window cycle equivalence %0d cycles shift%0d fill%0d tail%0d",checks,shifts,fills,tails);
  $finish;
 end
endmodule
