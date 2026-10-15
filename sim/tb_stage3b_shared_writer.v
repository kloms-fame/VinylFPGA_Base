`timescale 1ns/1ps
module tb_stage3b_shared_writer #(parameter SHORT_ART=0);
 reg sd_clk=0,mem_clk=0,rst_n=0,enable=0,mv_request=0;
 always #5 sd_clk=~sd_clk;
 always #4 mem_clk=~mem_clk;
wire bg_active,bg_req,bg_pixel,bg_sec_req,bg_sec_start,bg_sec_busy,bg_sec_grant,bg_sec_valid,bg_sec_done;
 wire mv_active,mv_req,mv_pixel,mv_sec_req,mv_sec_busy,mv_sec_valid,mv_sec_done,mv_done,mv_failed;
 wire [31:0] bg_data,mv_data,bg_lba,mv_lba;
 wire [20:0] bg_addr;
 wire [5:0] ready;
 wire bg_hold,bg_cancel,bg_hold_mem,bg_cancel_mem;
 wire write_ack,write_finish,write_en,fifo_clear;
 wire [20:0] write_addr;
 wire bg_mem,mv_mem;
 reg finish_toggle=0;
 reg [1:0] mv_bank=0;
 wire sec_req;
 wire [31:0] sec_lba;
 reg sec_busy=0,sec_valid=0,sec_done=0;
 reg [7:0] sec_byte=0;
 reg [8:0] sec_index=0;
 integer adapter_count=0;
 reg [31:0] adapter_lba=0;
 reg adapter_take=0;
 reg [31:0] fifo [0:511];
 integer head=0,tail=0,used=0,total=0,art_words=0,song_words=0,mv_words=0,checks=0;
 reg [31:0] popped;
 wire [9:0] fifo_words=used;
 wire pipeline_valid;
 wire [31:0] pipeline_data;
 media_write_pipeline pipeline(.clk(sd_clk),.rst_n(rst_n),
  .background_owner(bg_active),.mv_owner(mv_active),.background_valid(bg_pixel),
  .mv_valid(mv_pixel),.cover_valid(1'b0),.background_data(bg_data),.mv_data(mv_data),
  .cover_data(32'd0),.pixel_valid(pipeline_valid),.pixel_data(pipeline_data));
 sync_2ff bg_sync(.clk(mem_clk),.rst_n(rst_n),.async_in(bg_active),.sync_out(bg_mem));
 sync_2ff mv_sync(.clk(mem_clk),.rst_n(rst_n),.async_in(mv_active),.sync_out(mv_mem));
 sync_2ff hs(.clk(mem_clk),.rst_n(rst_n),.async_in(bg_hold),.sync_out(bg_hold_mem));
 sync_2ff cs(.clk(mem_clk),.rst_n(rst_n),.async_in(bg_cancel),.sync_out(bg_cancel_mem));
 background_cache_loader #(.FRAME_SECTORS(1)) bg(
  .clk(sd_clk),.rst_n(rst_n),.enable(enable),.base_lba(32'd1000),.song_id(2'd0),
  .art2_supported(1'b0),.art_request_async(1'b0),.art2_request_async(1'b0),.mv_writer_active(mv_active),.invalidate_ack_async(1'b0),
  .write_ack(write_ack),.write_finish_toggle(finish_toggle),.ready_info(ready),
  .write_hold(bg_hold),.write_cancel(bg_cancel),.writer_active(bg_active),.write_req(bg_req),.write_address(bg_addr),
  .pixel_valid(bg_pixel),.pixel_data(bg_data),.sector_req(bg_sec_req),.sector_start(bg_sec_start),.sector_lba(bg_lba),
  .sector_busy(bg_sec_busy),.sector_grant(bg_sec_grant),.sector_valid(bg_sec_valid),.sector_byte(sec_byte),
  .sector_byte_index(sec_index),.sector_done(bg_sec_done),.sector_error(8'd0));
 mv_stream_player #(.FRAME_SECTORS(1)) mv(
  .clk(sd_clk),.rst_n(rst_n),.abort_request(1'b0),.request_toggle(mv_request),
  .request_lba(32'd10000),.request_bank(mv_bank),.done_toggle(mv_done),.failed(mv_failed),
  .writer_active(mv_active),.write_req(mv_req),.write_ack(write_ack && !bg_active),
  .write_finish_toggle(finish_toggle),.pixel_valid(mv_pixel),.pixel_data(mv_data),
  .sector_req(mv_sec_req),.sector_lba(mv_lba),.sector_busy(mv_sec_busy),
  .sector_valid(mv_sec_valid),.sector_byte(sec_byte),.sector_byte_index(sec_index),
  .sector_done(mv_sec_done),.sector_error(8'd0));
 background_sector_mux arb(.clk(sd_clk),.rst_n(rst_n),.audio_req(1'b0),.audio_lba(32'd0),
  .video_req(mv_sec_req),.video_lba(mv_lba),.background_req(bg_sec_req),.background_lba(bg_lba),
  .background_start(bg_sec_start),
  .allow_video(1'b1),.allow_background(1'b1),.video_busy(mv_sec_busy),.video_valid(mv_sec_valid),
  .video_done(mv_sec_done),.background_busy(bg_sec_busy),.background_grant(bg_sec_grant),
  .background_valid(bg_sec_valid),
  .background_done(bg_sec_done),.sector_req(sec_req),.sector_lba(sec_lba),
  .sector_busy(sec_busy),.sector_valid(sec_valid),.sector_done(sec_done));
 wire [20:0] selected_base=bg_mem ? bg_addr : 21'd1228800 + (mv_bank * 21'd256);
 frame_fifo_write #(.DYNAMIC_LINEAR(1),.BURST_SIZE(256)) writer(
  .write_hold(bg_mem && bg_hold_mem),.write_cancel(bg_mem && bg_cancel_mem),.linear_write(bg_active || mv_active),.rst(!rst_n),.mem_clk(mem_clk),
  .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .App_wr_en(write_en),.App_wr_addr(write_addr),
  .write_req(bg_active ? bg_req : mv_req),.write_req_ack(write_ack),.write_finish(write_finish),
  .write_addr_0(selected_base),.write_addr_1(selected_base),.write_addr_2(selected_base),
  .write_addr_3(selected_base),.write_addr_index(2'd0),.write_len(21'd256),
  .fifo_aclr(fifo_clear),.rdusedw(fifo_words));
 task check;
  input ok;
  input [511:0] msg;
  begin checks=checks+1;if(ok!==1'b1) begin $display("FAIL %0s total=%0d addr=%0d",msg,total,write_addr);$finish_and_return(1);end end
 endtask
 // Behavioral dual-clock FIFO, matching ownership and clear signals of top.
 // Clocks have no coincident positive edges, so queue operations are ordered.
 always @(posedge fifo_clear or negedge rst_n) begin head=0;tail=0;used=0;end
 always @(posedge sd_clk) if(rst_n && !fifo_clear && pipeline_valid) begin
  check(used<512,"write FIFO overflow");
  fifo[tail]=pipeline_data;tail=(tail+1)%512;used=used+1;
 end
 always @(posedge mem_clk) if(rst_n) begin
  if(write_finish) finish_toggle<=~finish_toggle;
  if(write_en) begin
   check(used>0,"write FIFO underflow");
   popped=fifo[head];head=(head+1)%512;used=used-1;total=total+1;
   if(write_addr>=1766400) begin
    check(write_addr===1766400+art_words && popped===32'hFF000000,"art chunk protected from pending MV, including padding");art_words=art_words+1;
   end else if(write_addr<1459200) begin
    check(write_addr===1228800+mv_words && popped===32'h0000FF00,"MV owns following transaction");mv_words=mv_words+1;
   end else begin
    check(write_addr===1459200+song_words && popped===32'hFF000000,"song background resumes without contamination");song_words=song_words+1;
   end
  end
 end
 // Adapter byte pacing deliberately leaves gaps while MV is waiting for ACK.
 always @(posedge sd_clk) begin
  adapter_take=sec_req;
  #1;
  sec_valid=0;sec_done=0;
  if(!rst_n) begin sec_busy=0;adapter_count=0;end
  else if(!sec_busy && adapter_take) begin sec_busy=1;adapter_count=0;adapter_lba=sec_lba;end
  else if(sec_busy) begin
   if(adapter_count<((SHORT_ART && adapter_lba==5800)?24:1024)) begin
    if(adapter_count%2==0) begin
     sec_valid=1;sec_index=adapter_count/2;
     sec_byte=(adapter_lba==10000) ? ((sec_index[0]) ? 8'h00:8'h1F) : ((sec_index[0])?8'hF8:8'h00);
    end
    adapter_count=adapter_count+1;
   end else begin sec_done=1;sec_busy=0;end
  end
 end
 initial begin
  repeat(5) @(negedge sd_clk);rst_n=1;enable=1;
  wait(bg.state==5 && bg.byte_count>((SHORT_ART)?4:100));
  @(negedge sd_clk);mv_request=1;
  wait(mv_active);
  check(bg_active,"MV request arrives during BG ownership");
  // Queue a second MV frame while the song-cache sector owns the shared
  // writer. The background sector must finish its SDRAM drain first; then
  // the next MV frame gets a clean FIFO lease with no cross-owner pixels.
  wait(mv_done);
  wait(bg.state==5 && !bg.job_art && bg.byte_count>100);
  @(negedge sd_clk);mv_bank=2'd1;mv_request=~mv_request;
  wait(mv_active);
  check(bg_active,"back-to-back MV request arrives during song-cache ownership");
  wait(mv_done==mv_request);
  wait(ready[2] && ((SHORT_ART) ? !ready[3] : ready[3]));
  repeat(20) @(negedge sd_clk);
  check(total==(SHORT_ART?768:1024) && art_words==(SHORT_ART?0:256) && mv_words==512 && song_words==256 && used==0 && !mv_failed,"back-to-back MV frames preserve shared FIFO ownership and data");
  $display("PASS stage3b shared writer: %0d checks, actual frame_fifo_write, BG/MV collision and FIFO data",checks);$finish;
 end
 initial begin #2000000;$display("FAIL shared writer timeout BG=%0d MV=%0d writer=%0d used=%0d",bg.state,mv.state,writer.state,used);$finish_and_return(1);end
endmodule
