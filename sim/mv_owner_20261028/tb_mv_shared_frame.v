`timescale 1ns/1ps
// Real player + bridge + SD owners + command engine. Only SPI bytes and
// SDRAM writer completion are modeled. Validate every pixel in three frames,
// concurrent audio, inter-frame drain, cancellation, and changing frame LBA.
module tb_mv_shared_frame;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 reg request_toggle=0,write_ack=0,finish=0,stop=0,allow=1;
 reg [31:0] request_lba=1000;
 wire writer,write_req,pv,done,failed,req,busy,valid,sdone;
 wire [31:0] pixels,lba;
 wire [7:0] byte_data,error;
 wire [8:0] bi;
 wire br,ba,bv,bsd,bd,bp,bs,cs,idle,init,grant;
 wire [31:0] blba;
 wire [7:0] blen,bdata,berror;
 reg ar=0;
 wire ab,rd,rv,re,adone;
 wire [31:0] raddr;
 wire [7:0] rdata,aerror;
 integer frame=0,count=0,total=0,asecs=0,frames_done=0;
 integer realtime_mode=0,cycles=0,start_cycle=0,audio_period=5000;
 always @(posedge clk) cycles=cycles+1;
 integer idx,sec;
 reg [7:0] lo,hi;
 reg [15:0] rgb;
 reg [31:0] expect_pixel;
 mv_stream_player player(.clk(clk),.rst_n(!rst),.abort_request(stop),
  .request_toggle(request_toggle),.request_lba(request_lba),.request_bank(2'd1),
  .done_toggle(done),.failed(failed),.writer_active(writer),.write_req(write_req),
  .write_ack(write_ack),.write_finish_toggle(finish),.write_bank(),
  .pixel_valid(pv),.pixel_data(pixels),.sector_req(req),.sector_lba(lba),
  .sector_busy(busy),.sector_valid(valid),.sector_byte(byte_data),
  .sector_byte_index(bi),.sector_done(sdone),.sector_error(error));
 mv_sd_burst bridge(.clk(clk),.rst_n(!rst),.abort(1'b0),.allow(allow),
  .stream_active(writer),.sector_req(req),.sector_lba(lba),.sector_busy(busy),
  .sector_valid(valid),.sector_byte(byte_data),.sector_byte_index(bi),
  .sector_done(sdone),.sector_error(error),.burst_req(br),.burst_lba(blba),
  .burst_len(blen),.burst_pause(bp),.burst_active(ba),.burst_valid(bv),
  .burst_data(bdata),.burst_sector_done(bsd),.burst_done(bd),
  .burst_error(berror),.burst_stop(bs),.debug_buf_count());
 sd_card_top #(.SPI_LOW_SPEED_DIV(0)) dut(.clk(clk),.rst(rst),
  .SD_nCS(cs),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.sd_init_done(init),
  .sd_sec_read(rd),.sd_sec_read_addr(raddr),.sd_sec_read_data(rdata),
  .sd_sec_read_data_valid(rv),.sd_sec_read_end(re),.sd_sec_write(1'b0),
  .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),
  .sd_sec_write_end(),.mv_burst_req(br),.mv_burst_lba(blba),.mv_burst_len(blen),
  .mv_burst_pause(bp),.mv_burst_abort(bs),.mv_burst_valid(bv),
  .mv_burst_data(bdata),.mv_burst_sector_done(bsd),.mv_burst_done(bd),
  .mv_burst_error(berror),.mv_burst_active(ba),.mv_cmd17_idle(idle),
  .sd_bus_grant(grant));
 sd_sector_adapter #(.SECTOR_TIMEOUT_CYCLES(30000),.USE_BUS_GRANT(1)) audio(
  .clk(clk),.rst_n(!rst),.bus_grant(grant),.sector_req(ar),.sector_lba(32'd500),
  .sector_busy(ab),.sector_valid(),.sector_byte(),.sector_byte_index(),
  .sector_done(adone),.sector_error(aerror),.sd_sec_read(rd),
  .sd_sec_read_addr(raddr),.sd_sec_read_data_valid(rv),.sd_sec_read_data(rdata),.sd_sec_read_end(re));
 always @(posedge clk) if(!rst) begin
  if(valid && player.state!=3'd4) $fatal(1,"UNREQUESTED_BANK_OUTPUT state=%d lba=%d",player.state,lba);
  if(adone) begin if(aerror) $fatal(1,"audio error %h",aerror);asecs=asecs+1;end
  if(bd && berror) $fatal(1,"burst error %h",berror);
  if(pv) begin
   idx=(count%256)*2;sec=count/256;
   lo=(request_lba+sec)^idx;hi=(request_lba+sec)^(idx+1);
   rgb={hi,lo};
   expect_pixel={rgb[15:11],rgb[15:13],rgb[10:5],rgb[10:9],rgb[4:0],rgb[4:2],8'd0};
   if(pixels!==expect_pixel) $fatal(1,"pixel mismatch frame=%d pixel=%d got=%h exp=%h",frame,count,pixels,expect_pixel);
   count=count+1;total=total+1;
  end
 end
 initial begin // SDRAM writer handshake and completion.
  forever begin
   wait(write_req);repeat(3) @(negedge clk);write_ack=1;
   wait(!write_req);@(negedge clk);write_ack=0;
   wait(count==76800 || stop);
   if(!stop) begin repeat(10) @(negedge clk);finish=!finish;end
   wait(!writer);@(negedge clk);
  end
 end
 initial begin // Realistic PCM sector demand, independent of MV progress.
  wait(init);repeat(20) @(negedge clk);
  forever begin
   if(!ab) begin ar=1;@(negedge clk);ar=0;end
   repeat(audio_period) @(negedge clk);
  end
 end
 initial begin
  repeat(10) @(negedge clk);rst=0;wait(idle);
  if($test$plusargs("REALTIME")) begin
   realtime_mode=1;audio_period=533333;dut.spi_master_m0.byte_delay=34;
  end
  dut.spi_master_m0.strict_stop=1;
  for(frame=0;frame<3;frame=frame+1) begin
   start_cycle=cycles;
   count=0;request_lba=(frame==1)?9000:1000+frame*300;request_toggle=!request_toggle;
   wait(writer);wait(done==request_toggle);@(negedge clk);
   if(failed || count!=76800) $fatal(1,"frame failed count=%d",count);
   frames_done=frames_done+1;
   if(realtime_mode && cycles-start_cycle>10000000) $fatal(1,"10FPS_DEADLINE_MISSED");
   $display("FRAME_CYCLES %0d",cycles-start_cycle);
   $display("FRAME_PASS frame=%d pixels=%d audio=%d",frame,count,asecs);
   // Writer may remain draining while the two speculative banks fill.
   repeat(realtime_mode ? 200000 : 10000) @(negedge clk);
   if(ba) $fatal(1,"MV holds bus between frames pause=%b count=%d",bp,bridge.buf_count);
   if(realtime_mode) repeat(10000000-(cycles-start_cycle)) @(negedge clk);
  end
  if(!realtime_mode) begin
   // Abort during READ, then restart a different song immediately after the
   // player reports completion. No frame-gap delay to hide stale-bank races.
   frame=3;count=0;request_lba=13000;request_toggle=!request_toggle;
   wait(writer);wait(count>=1000);@(negedge clk);stop=1;
   wait(done==request_toggle);@(negedge clk);stop=0;
   count=0;request_lba=20000;request_toggle=!request_toggle;
   wait(writer);wait(done==request_toggle);@(negedge clk);
   if(failed || count!=76800) $fatal(1,"rapid abort/restart failed");
   $display("PASS rapid_abort_restart noncontiguous LBA 13000->20000 pixels=%d",count);
  end
  if(asecs<3) $fatal(1,"audio starved");
  $display("PASS shared_frames frames=%d first_three_frames_sectors=900 total_pixels=%d audio=%d",frames_done,total,asecs);$finish;
 end
 initial begin repeat(40000000) @(posedge clk);$fatal(1,"FRAME_TEST_TIMEOUT frame=%d count=%d req=%b busy=%b full=%b br=%b ba=%b pause=%b",frame,count,req,busy,bridge.full,br,ba,bp);end
endmodule
