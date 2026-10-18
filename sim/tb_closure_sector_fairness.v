`timescale 1ns/1ps
module tb_closure_sector_fairness;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0, a=1, v=1, b=0, urgent=0, allow_v=1, busy=0, valid=0, done=0;
 wire ab,vb,bb,av,vv,bv,ad,vd,bd,grant,req; wire [31:0] lba;
 integer ac=0,vc=0,bc=0, video_gap=0, max_gap=0, i;
 background_sector_mux dut(.clk(clk),.rst_n(rst_n),.audio_req(a),.audio_lba(32'd11),
  .audio_urgent(urgent),.video_req(v),.video_lba(32'd22),
  .background_req(b),.background_lba(32'd33),.background_start(1'b1),
  .allow_video(allow_v),.allow_background(1'b1),.audio_busy(ab),.video_busy(vb),
  .background_busy(bb),.background_grant(grant),.audio_valid(av),.video_valid(vv),
  .background_valid(bv),.audio_done(ad),.video_done(vd),.background_done(bd),
  .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
 always @(posedge clk) if(rst_n) begin
  if(a && !ab && !dut.take_audio) $fatal(1,"audio accepted a sector assigned to another client");
  if(v && !vb && !dut.take_video) $fatal(1,"video accepted a sector assigned to another client");
  if(dut.take_audio) begin ac=ac+1;video_gap=0;end
  if(dut.take_video) begin
   vc=vc+1;video_gap=video_gap+1;if(video_gap>max_gap)max_gap=video_gap;
   if(a && video_gap>15) $fatal(1,"audio starvation beyond fifteen video sectors");
  end
  if(dut.take_background) bc=bc+1;
 end
 task service;
 input integer expected;
 reg [31:0] held;
 begin
  wait(req);held=lba;
  if(expected!=0 && held!=expected) $fatal(1,"wrong owner %0d expected %0d",held,expected);
  @(posedge clk);@(negedge clk);busy=1;valid=1;
  repeat(3) begin
   @(negedge clk);
   if(lba!=held || ({av,vv,bv}!=3'b100 && held==11) ||
      ({av,vv,bv}!=3'b010 && held==22) || ({av,vv,bv}!=3'b001 && held==33))
    $fatal(1,"in-flight owner changed or response was misrouted");
  end
  done=1;@(negedge clk);done=0;busy=0;valid=0;
 end endtask
 initial begin
  #22;rst_n=1;
  for(i=0;i<32;i=i+1) service(0);
  a=0;v=0;
  if(ac<2 || vc<30 || max_gap!=15) $fatal(1,"weighted service missing ac=%0d vc=%0d max=%0d",ac,vc,max_gap);
  repeat(3)@(negedge clk);
  urgent=1;a=1;v=1;
  for(i=0;i<8;i=i+1)service(11);
  a=0;v=0;urgent=0;b=1;
  service(33);
  @(negedge clk);b=0;
  $display("TEST_PASS closure_sector_fairness grant handshake weighted service urgency ownership");$finish;
 end
 initial begin #100000;$fatal(1,"sector arbitration timeout");end
endmodule
