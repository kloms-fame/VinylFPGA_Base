`timescale 1ns/1ps
module tb_closure_mv_service;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,trigger=0,busy=0,finish=0;
 reg [9:0] count=0;reg [31:0] held=0;reg audio_reading=0;
 wire ar=!audio_reading;
 wire vr,ab,vb,av,vv,ad,vd,sreq,mdone,failed,wr,pv;
 wire [31:0] vl,sl,pixel;wire [1:0] wb;
 wire valid=busy && count<512, done=busy && count==512;
 wire [7:0] data=held==11 ? 8'h5a : (count[0]?8'hf8:8'd0);
 integer audio_sectors=0,video_sectors=0,pixels=0,clock_count=0;
 background_sector_mux mux(.clk(clk),.rst_n(rst_n),.audio_req(ar),.audio_lba(32'd11),
  .audio_urgent(1'b0),.video_req(vr),.video_lba(vl),.background_req(1'b0),.background_lba(32'd0),
  .background_start(1'b0),.allow_video(1'b1),.allow_background(1'b0),
  .audio_busy(ab),.video_busy(vb),.audio_valid(av),.video_valid(vv),.audio_done(ad),.video_done(vd),
  .sector_req(sreq),.sector_lba(sl),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
 mv_stream_player #(.FRAME_SECTORS(32)) player(.clk(clk),.rst_n(rst_n),.abort_request(1'b0),
  .request_toggle(trigger),.request_lba(32'd1000),.request_bank(2'd1),.done_toggle(mdone),.failed(failed),
  .write_req(wr),.write_ack(wr),.write_finish_toggle(finish),.write_bank(wb),
  .pixel_valid(pv),.pixel_data(pixel),.sector_req(vr),.sector_lba(vl),.sector_busy(vb),
  .sector_valid(vv),.sector_byte(data),.sector_byte_index(count[8:0]),.sector_done(vd),.sector_error(8'd0));
 always @(posedge clk) if(rst_n) begin
  clock_count=clock_count+1;
  if(ar && !ab) begin
   if(!mux.take_audio) $fatal(1,"real audio producer falsely granted");
   audio_reading<=1;
  end
  if(ad)begin audio_reading<=0;audio_sectors=audio_sectors+1;end
  if(!busy && sreq)begin busy<=1;held<=sl;count<=0;end
  else if(busy)begin
   if(count==512)begin busy<=0;if(held>=1000)video_sectors=video_sectors+1;end
   else count<=count+1'b1;
  end
  if(pv)begin
   if(pixel!==32'hff000000)$fatal(1,"audio bytes entered video writer");
   pixels=pixels+1;if(pixels==8192)finish<=~finish;
  end
  if(audio_sectors>40 && video_sectors==0)$fatal(1,"held audio request starved real MV client");
 end
 initial begin
  #22;rst_n=1;trigger=1;wait(mdone);
  if(failed || video_sectors!=32 || pixels!=8192 || audio_sectors<2)
   $fatal(1,"shared service incomplete audio=%0d video=%0d pixels=%0d",audio_sectors,video_sectors,pixels);
  $display("TEST_PASS closure_mv_service real MV client fair SD progress 32 sectors 8192 pixels");$finish;
 end
 initial begin #10000000;$fatal(1,"shared service timeout");end
endmodule
