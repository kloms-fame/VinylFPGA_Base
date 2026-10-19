`timescale 1ns/1ps
// The runner extracts the immutable 9fbbf5b mux as stable_background_sector_mux.
module tb_stable_sd_priority_equiv;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [31:0] random_bits=32'h7f05a2c1;
 reg raw_busy=0,raw_valid=0,raw_done=0;
 integer beats=0,transactions=0,cycles=0;
 wire [42:0] candidate,reference;
 wire request=candidate[32];
 background_sector_mux candidate_mux(.clk(clk),.rst_n(rst_n),
  .audio_req(random_bits[0]),.audio_lba(32'd101),.audio_urgent(1'b1),
  .video_req(random_bits[1]),.video_lba(32'd202),
  .background_req(random_bits[2]),.background_lba(32'd303),.background_start(random_bits[3]),
  .allow_video(random_bits[4]),.allow_background(random_bits[5]),
  .audio_busy(candidate[42]),.video_busy(candidate[41]),.background_busy(candidate[40]),
  .background_grant(candidate[39]),.audio_valid(candidate[38]),.video_valid(candidate[37]),
  .background_valid(candidate[36]),.audio_done(candidate[35]),.video_done(candidate[34]),
  .background_done(candidate[33]),.sector_req(candidate[32]),.sector_lba(candidate[31:0]),
  .sector_busy(raw_busy),.sector_valid(raw_valid),.sector_done(raw_done));
 stable_background_sector_mux stable_mux(.clk(clk),.rst_n(rst_n),
  .audio_req(random_bits[0]),.audio_lba(32'd101),
  .video_req(random_bits[1]),.video_lba(32'd202),
  .background_req(random_bits[2]),.background_lba(32'd303),.background_start(random_bits[3]),
  .allow_video(random_bits[4]),.allow_background(random_bits[5]),
  .audio_busy(reference[42]),.video_busy(reference[41]),.background_busy(reference[40]),
  .background_grant(reference[39]),.audio_valid(reference[38]),.video_valid(reference[37]),
  .background_valid(reference[36]),.audio_done(reference[35]),.video_done(reference[34]),
  .background_done(reference[33]),.sector_req(reference[32]),.sector_lba(reference[31:0]),
  .sector_busy(raw_busy),.sector_valid(raw_valid),.sector_done(raw_done));
 always @(posedge clk)begin
  raw_valid<=0;raw_done<=0;
  if(!rst_n)begin raw_busy<=0;beats=0;end
  else if(request && !raw_busy)begin raw_busy<=1;beats=0;transactions=transactions+1;end
  else if(raw_busy)begin
   raw_valid<=1;beats=beats+1;
   if(beats==7)begin raw_busy<=0;raw_done<=1;end
  end
 end
 always @(negedge clk)begin
  if(rst_n)begin
   if(candidate!==reference)$fatal(1,"stable SD priority mismatch cycle=%0d candidate=%h reference=%h",cycles,candidate,reference);
   random_bits={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
   cycles=cycles+1;
   if(cycles==100000)begin
    if(transactions<1000)$fatal(1,"insufficient transaction coverage");
    $display("TEST_PASS stable_sd_priority_equiv 100000 cycles %0d transactions identical to 9fbbf5b",transactions);$finish;
   end
  end
 end
 initial begin #22;rst_n=1;end
endmodule
