`timescale 1ns/1ps
// Real WAV player and MV producer share a byte-paced SD service. One video
// sector has an extra 1 ms token delay; check every consumed PCM sample.
module tb_mv_audio_shared;
reg sdclk=0;always #5 sdclk=~sdclk;
reg pixclk=0;always #20 pixclk=~pixclk;
reg rst_n=0,play=0,mreq=0,busy=0,fin=0;
reg[31:0] held_lba=0;reg[9:0] byte_count=0;reg[16:0]delay_count=0;
wire[8:0]idx=byte_count[8:0];
wire valid=busy && delay_count==0 && byte_count<512;
wire done=busy && delay_count==0 && byte_count==512;
reg[15:0]sample_div=0;reg tick=0;
wire ar,ab,av,ad,vr,vb,vv,vd,sreq;wire[31:0]al,vl,sl;
wire low,active,ended,sample_valid,mdone,mfailed,wr,wp;wire signed[15:0]sample;
wire[31:0]counter,pixel;wire[1:0]wbank;wire[31:0]sample_number=(held_lba-100)*256+(idx>>1);
wire[7:0]b=(held_lba>=1000) ? (idx[0]?8'hf8:8'd0) : (idx[0]?sample_number[15:8]:sample_number[7:0]);
integer last=0,pixels=0,video_sectors=0;reg[1:0]low_sync=3;
always @(posedge pixclk) begin
 if(!rst_n) begin sample_div<=0;tick<=0;end
 else begin
  tick<=0;
  if(sample_div==520) begin sample_div<=0;tick<=1;end
  else sample_div<=sample_div+1'b1;
 end
end
always @(posedge sdclk) low_sync<={low_sync[0],low};
wav_stream_player #(.ADDR_WIDTH(10)) audio(.wr_clk(sdclk),.wr_rst_n(rst_n),.play_enable(play),
 .start_lba(32'd100),.total_sectors(32'd4),.sd_req(ar),.sd_lba(al),.sd_busy(ab),.sd_valid(av),
 .sd_byte(b),.sd_byte_index(idx),.sd_done(ad),.sd_error(8'd0),.rd_clk(pixclk),.rd_rst_n(rst_n),
 .sample_tick(tick),.sample_out(sample),.sample_valid(sample_valid),.sample_ready(1'b1),
 .sample_counter(counter),.stream_active(active),.stream_end(ended),.buffer_low(low));
mv_sector_mux mux(.clk(sdclk),.rst_n(rst_n),.audio_req(ar),.audio_lba(al),.video_req(vr),.video_lba(vl),
 .allow_video(!low_sync[1]),.audio_busy(ab),.video_busy(vb),.audio_valid(av),.video_valid(vv),
 .audio_done(ad),.video_done(vd),.sector_req(sreq),.sector_lba(sl),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
mv_stream_player #(.FRAME_SECTORS(20)) video(.clk(sdclk),.rst_n(rst_n),.request_toggle(mreq),
 .request_lba(32'd1000),.request_bank(2'd1),.done_toggle(mdone),.failed(mfailed),.write_req(wr),.write_ack(wr),
 .write_finish_toggle(fin),.write_bank(wbank),.pixel_valid(wp),.pixel_data(pixel),.sector_req(vr),.sector_lba(vl),
 .sector_busy(vb),.sector_valid(vv),.sector_byte(b),.sector_byte_index(idx),.sector_done(vd),.sector_error(8'd0));
always @(posedge sdclk) begin
 if(!busy && sreq) begin
  busy<=1;held_lba<=sl;byte_count<=0;
  delay_count<=(sl==1000) ? 100000 : 35;
  if(sl>=1000) video_sectors<=video_sectors+1;
 end else if(busy) begin
  if(delay_count!=0) delay_count<=delay_count-1'b1;
  else if(byte_count==512) busy<=0;
  else begin byte_count<=byte_count+1'b1;delay_count<=35;end
 end
 if(wp) begin
  pixels=pixels+1;
  if(pixel!==32'hff000000) $fatal(1,"video got audio bytes");
  if(pixels==5120)fin<=~fin;
 end
end
always @(negedge pixclk) if(sample_valid && play) begin
 if(counter>last) begin
  if(counter!=last+1 || sample!==(counter-1)) $fatal(1,"PCM ordering %0d sample %0d",counter,sample);
  last=counter;
 end else if(last>0 && last<1024) $fatal(1,"audio underflow during video transfer");
end
initial begin
 #83 rst_n=1;play=1;
 wait(counter==100);@(negedge sdclk);mreq=1;
 wait(counter==1024);repeat(8) @(negedge pixclk);
 if(video_sectors==0 || pixels==0 || mfailed) $fatal(1,"no concurrent video progress");
 $display("TEST_PASS mv_audio_shared 1024 ordered PCM samples concurrent video extra 1ms token delay");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
