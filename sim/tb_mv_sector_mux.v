`timescale 1ns/1ps
module tb_mv_sector_mux;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, a_req=0, v_req=0, allow_video=0, busy=0, valid=0, done=0;
reg [31:0] audio_lba=99;
wire req,av,vv,ad,vd,ab,vb; wire [31:0] lba;
mv_sector_mux dut(.clk(clk),.rst_n(rst_n),.audio_req(a_req),.audio_lba(audio_lba),
 .video_req(v_req),.video_lba(32'd22),.allow_video(allow_video),
 .audio_busy(ab),.video_busy(vb),.audio_valid(av),.video_valid(vv),
 .audio_done(ad),.video_done(vd),.sector_req(req),.sector_lba(lba),
 .sector_busy(busy),.sector_valid(valid),.sector_done(done));
initial begin
 #22 rst_n=1; #8 v_req=1; #1;
 if(req || !vb) $fatal(1,"video must wait for audio watermark");
 allow_video=1; a_req=1; #1;
 if(req || !vb) $fatal(1,"grant must precede downstream request");
 @(posedge clk); #1 audio_lba=11; a_req=0; #1;
 if(!req || lba!=11 || !vb) $fatal(1,"audio priority and post-grant LBA");
 @(posedge clk); #1 busy=1; a_req=0; valid=1; #1;
 if(!av || vv) $fatal(1,"audio owner");
 @(negedge clk); done=1; @(posedge clk); #1 done=0; valid=0; busy=0;
 @(posedge clk); #1;
 if(!req || lba!=22 || !vb) $fatal(1,"video grant");
 @(posedge clk); #1 busy=1; v_req=0; a_req=1; allow_video=0; valid=1; #1;
 if(av || !vv || !ab) $fatal(1,"owner must survive priority change");
 @(negedge clk); done=1; @(posedge clk); #1 done=0; valid=0; busy=0;
 @(posedge clk); #1;
 if(!req || lba!=11) $fatal(1,"audio resumes after one sector");
 $display("TEST_PASS mv_sector_mux priority watermark ownership"); $finish;
end
initial begin #10000; $fatal(1,"timeout"); end
endmodule
