`timescale 1ns/1ps
module tb_stage4_cache_transaction;
 reg sd=0,mem=0,rst_n=0,enable=0,invack=0,art=0,art2=0;
 always #5 sd=~sd; always #4 mem=~mem;
 reg busy=0,valid=0,done=0;
 reg [7:0] data=0,error=0;
 reg [8:0] index=0;
 wire [5:0] info;
 wire epoch,owner,req,hold,cancel,pv,sr,ack,finish,app,clear;
 wire [31:0] pixel,lba;
 wire [20:0] address,app_addr;
 wire hold_mem,cancel_mem,owner_mem;
 reg fin_toggle=0;
 wire pipeline_valid;
 wire [31:0] pipeline_data;
 reg [31:0] fifo [0:511];
 integer wp=0,rp=0,total=0,before_count=0,attempt,i;
 reg [20:0] expected_address=0;
 wire [9:0] used=wp-rp;
 background_cache_loader #(.FRAME_SECTORS(2)) loader(
  .clk(sd),.rst_n(rst_n),.enable(enable),.base_lba(32'd1000),.song_id(2'd0),
  .art2_supported(1'b1),.art_request_async(art),.art2_request_async(art2),
  .mv_writer_active(1'b0),.invalidate_ack_async(invack),.write_ack(ack),
  .write_finish_toggle(fin_toggle),.ready_info(info),.invalidate_toggle(epoch),
  .writer_active(owner),.write_req(req),.write_hold(hold),.write_cancel(cancel),
  .write_address(address),.pixel_valid(pv),.pixel_data(pixel),
  .sector_req(sr),.sector_lba(lba),.sector_busy(busy),.sector_grant(busy),.sector_valid(valid),
  .sector_byte(data),.sector_byte_index(index),.sector_done(done),.sector_error(error));
 sync_2ff h(.clk(mem),.rst_n(rst_n),.async_in(hold),.sync_out(hold_mem));
 sync_2ff c(.clk(mem),.rst_n(rst_n),.async_in(cancel),.sync_out(cancel_mem));
 sync_2ff o(.clk(mem),.rst_n(rst_n),.async_in(owner),.sync_out(owner_mem));
 media_write_pipeline pipe(.clk(sd),.rst_n(rst_n),.background_owner(owner),
  .mv_owner(1'b0),.background_valid(pv),.mv_valid(1'b0),.cover_valid(1'b0),
  .background_data(pixel),.mv_data(32'd0),.cover_data(32'd0),
  .pixel_valid(pipeline_valid),.pixel_data(pipeline_data));
 frame_fifo_write #(.DYNAMIC_LINEAR(1),.BURST_SIZE(128)) writer(
  .linear_write(1'b1),.write_hold(owner_mem && hold_mem),
  .write_cancel(owner_mem && cancel_mem),.rst(!rst_n),.mem_clk(mem),
  .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .App_wr_en(app),.App_wr_addr(app_addr),.write_req(req),.write_req_ack(ack),
  .write_finish(finish),.write_addr_0(address),.write_addr_1(21'd0),
  .write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),
  .write_len(21'd256),.fifo_aclr(clear),.rdusedw(used));
 always @(posedge sd) begin
  if(!rst_n || clear) wp=0;
  else if(pipeline_valid) begin
   if(wp-rp>=512) $fatal(1,"write FIFO overflow");
   fifo[wp%512]=pipeline_data;wp=wp+1;
  end
 end
 always @(posedge mem) begin
  if(!rst_n || clear) begin rp=0;expected_address=address;end
  else if(app) begin
   if(hold_mem || cancel_mem) $fatal(1,"unvalidated sector wrote SDRAM");
   if(wp-rp<=0) $fatal(1,"write FIFO underflow");
   if(fifo[rp%512]!==(loader.job_art ? 32'hf800f800 : 32'hff000000)) $fatal(1,"rejected green data escaped ACK FIFO reset");
   if(app_addr!==expected_address) $fatal(1,"noncontiguous chunk address");
   expected_address=expected_address+1;rp=rp+1;total=total+1;
  end
  if(!rst_n) fin_toggle<=0;
  else if(finish) fin_toggle<=!fin_toggle;
 end
 task sector;
 input integer bytes;
 input [31:0] expected_lba;
 input [7:0] err;
 input good;
 begin
  wait(sr);
  if(lba!==expected_lba) $fatal(1,"retry changed LBA %d expected %d",lba,expected_lba);
  @(posedge sd); #1 busy=1;
  wait(req); wait(!req);
  wait(loader.state==5);
  for(i=0;i<bytes;i=i+1) begin
   @(negedge sd); valid=1;index=i;
   data=i%2 ? (good ? 8'hf8 : 8'h07) : (good ? 8'h00 : 8'he0);
  end
  @(negedge sd);valid=0;done=1;error=err;
  @(negedge sd);done=0;error=0;busy=0;
 end
 endtask
 task complete_chunk;
 input integer expected_total;
 begin
  wait(!owner); repeat(5) @(negedge sd);
  if(total!=expected_total) $fatal(1,"wrong committed word count %d expected %d",total,expected_total);
 end
 endtask
 initial begin
  #22 rst_n=1;repeat(8) @(negedge sd);enable=1;
  // Bad short sectors and complete sectors with errors stay in the shared
  // FIFO. No zero padding or any failed pixel is sent to SDRAM.
  sector(12,5800,0,0);
  if(total!=0) $fatal(1,"short sector wrote SDRAM");
  sector(512,5800,0,1);complete_chunk(256);
  sector(512,5801,8'h20,0);
  if(total!=256) $fatal(1,"CRC/error sector wrote SDRAM");
  sector(512,5801,0,1);complete_chunk(512);
  if(!info[3]) $fatal(1,"complete ART1 not published");
  sector(512,1000,0,1);complete_chunk(768);
  sector(512,1001,0,1);complete_chunk(1024);
  if(!info[2]) $fatal(1,"complete song not published");
  art=1;art2=1;repeat(15) @(negedge sd);
  if(!info[3] || epoch) $fatal(1,"ART2 preload must retain ART1 without reader invalidation");
  art2=0;repeat(8) @(negedge sd);art2=1;repeat(8) @(negedge sd);
  if(epoch || total!=1024) $fatal(1,"mode changes must not invalidate immutable artworks");
  invack=epoch;
  sector(512,7000,0,1);complete_chunk(1280);
  sector(512,7001,0,1);complete_chunk(1536);
  if(info[4:3]!==2'b11) $fatal(1,"ART2 tag/ready not published");
  art2=0;repeat(15) @(negedge sd);
  if(req || sr || info[4:3]!=2'b11) $fatal(1,"warm ART1 switch must not reload");
  // Fail ART2 after warming ART1/song. The ready artwork and its physical
  // lane remain intact; exhausted retries must not restart on a mode key.
  enable=0;repeat(10) @(negedge sd);enable=1;
  sector(512,5800,0,1);complete_chunk(1792);
  sector(512,5801,0,1);complete_chunk(2048);
  sector(512,1000,0,1);complete_chunk(2304);
  sector(512,1001,0,1);complete_chunk(2560);
  for(attempt=0;attempt<3;attempt=attempt+1) sector(12,7000,0,0);
  wait(!owner);repeat(25) @(negedge sd);
  if(!info[3] || info[4] || !loader.art2_failed || total!=2560 || req || sr)
   $fatal(1,"failed ART2 must retain ART1/song and stop retrying");
  art2=1;repeat(10) @(negedge sd);art2=0;repeat(10) @(negedge sd);
  if(req || sr || !info[3] || info[4]) $fatal(1,"mode key restarted exhausted ART2");
  // A new media session clears both ready bits. Exhaust ART1 retries and
  // verify cancellation still releases the shared FIFO writer safely.
  enable=0;repeat(10) @(negedge sd);enable=1;
  before_count=total;
  for(attempt=0;attempt<3;attempt=attempt+1) sector(512,5800,8'h20,0);
  if(loader.state!=0 && !cancel) wait(cancel || loader.state==0);
  wait(!owner);repeat(25) @(negedge sd);
  if(total!=before_count || info[3]) $fatal(1,"exhausted sector not safely cancelled");
  // A failed artwork must not prevent the independent song cache advancing.
  enable=0;
  if(!loader.art_failed || writer.state!=0) $fatal(1,"cancel did not release memory writer");
  $display("TEST_PASS stage4 cache FIFO hold retry cancel, immutable ART1/ART2, %d SDRAM words",total);
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout loader=%d writer=%d total=%d",loader.state,writer.state,total);end
endmodule
