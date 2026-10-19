`timescale 1ns/1ps
// Real cache/staging/DMA + sector arbitration. Synthetic card and SDRAM model.
// One abstract SD tick represents 0.533333 us of service budget: 10,000 ticks
// per 512-byte PCM sector = 96,000 B/s. HDL clocks are accelerated; this does
// not claim wall-clock simulation or a particular physical card's throughput.
module tb_audio_mv_slow_window;
 parameter REGRESSED_POLICY=0;
 localparam SECTOR_PERIOD=10000;
 localparam NORMAL_SECTORS=1400;
 localparam SLOW_TICKS=9187500; // 4.9 s in the abstract service budget.
 reg sd_clk=0,mem_clk=0;
 always #5 sd_clk=~sd_clk;
 always #4 mem_clk=~mem_clk;
 reg rst_n=0,enabled=0,playing=0,client_req=0;
 wire cb,cv,cd,cache_ready,cache_low,cache_critical;
 wire [7:0] byte_data,ce;wire [8:0] byte_index;
 wire audio_req,audio_busy,audio_valid,audio_done,video_busy;
 wire raw_req;wire [31:0] audio_lba,raw_lba;
 reg raw_busy=0,raw_valid=0,raw_done=0;
 reg [31:0] held_lba=0;reg [8:0] raw_index=0;reg [7:0] raw_byte=0;
 integer raw_cursor=0,token_wait=0;
 integer ticks=0,start_tick=0,slow_start_tick=0,recovery_start_tick=0,video_at_recovery=0;
 integer issued=0,completed=0,expected_index=0,deadline=0;
 integer audio_sectors=0,video_sectors=0,min_reserve=1008,reserve_before_slow=0;
 reg slow_started=0,recovery_started=0,underflow=0;
 wire in_slow=slow_started && ticks-slow_start_tick<SLOW_TICKS;
 wire strict_audio=REGRESSED_POLICY ? cache_critical : 1'b1;
 wire allow_video=REGRESSED_POLICY ? 1'b1 : !cache_low;
 wire lock,owner,mwe,mre;wire [20:0] mwa,mra;wire [31:0] mwd;wire [3:0] mask;
 reg [7:0] memory[0:524287];
 reg [11:0] returns=0;reg [7:0] return_data[0:11];
 integer j;
 audio_prefetch_sdram cache(
  .sd_clk(sd_clk),.sd_rst_n(rst_n),.mem_clk(mem_clk),.mem_rst_n(rst_n),
  .source_ready(1'b1),.enable(enabled),.start_lba(32'd100),.total_sectors(32'd10000),
  .client_req(client_req),.client_busy(cb),.client_valid(cv),.client_byte(byte_data),
  .client_byte_index(byte_index),.client_done(cd),.client_error(ce),
  .raw_req(audio_req),.raw_lba(audio_lba),.raw_busy(audio_busy),.raw_valid(audio_valid),
  .raw_byte(raw_byte),.raw_byte_index(raw_index),.raw_done(audio_done),.raw_error(8'd0),
  .playback_ready(cache_ready),.prefetch_low(cache_low),.prefetch_critical(cache_critical),.session_busy(),
  .video_read_busy(1'b0),.video_write_busy(1'b0),.controller_busy(1'b0),.refresh_active(1'b0),
  .mem_read_valid(returns[11]),.mem_read_data({24'd0,return_data[11]}),
  .access_lock(lock),.read_owner(owner),.mem_wr_en(mwe),.mem_wr_addr(mwa),
  .mem_wr_data(mwd),.mem_wr_mask(mask),.mem_rd_en(mre),.mem_rd_addr(mra));
 background_sector_mux mux(.clk(sd_clk),.rst_n(rst_n),.audio_req(audio_req),.audio_lba(audio_lba),
  .audio_urgent(strict_audio),.video_req(playing),.video_lba(32'h100000),
  .background_req(1'b0),.background_lba(32'd0),.background_start(1'b0),
  .allow_video(allow_video),.allow_background(1'b0),.audio_busy(audio_busy),.video_busy(video_busy),
  .audio_valid(audio_valid),.audio_done(audio_done),.video_valid(),.video_done(),
  .background_busy(),.background_grant(),.background_valid(),.background_done(),
  .sector_req(raw_req),.sector_lba(raw_lba),
  .sector_busy(raw_busy),.sector_valid(raw_valid),.sector_done(raw_done));
 always @(posedge mem_clk) begin
  returns<={returns[10:0],mre};
  if(mre) return_data[0]<=memory[mra];
  for(j=1;j<12;j=j+1)return_data[j]<=return_data[j-1];
  if(mwe)begin
   if(mask!==4'b1110)$fatal(1,"PCM mask changed");
   memory[mwa]<=mwd[7:0];
  end
 end
 always @(posedge sd_clk) begin
  ticks=ticks+1;raw_valid<=0;raw_done<=0;
  if(!rst_n)raw_busy<=0;
  else if(!raw_busy && raw_req)begin
   raw_busy<=1;held_lba<=raw_lba;raw_cursor=0;
   token_wait=playing ? (in_slow ? 26750 : 512) : 0;
   if(raw_lba==32'h100000)video_sectors=video_sectors+1;
   else audio_sectors=audio_sectors+1;
  end else if(raw_busy)begin
   if(token_wait>0)token_wait=token_wait-1;
   else if(raw_cursor==512)begin raw_done<=1;raw_busy<=0;end
   else begin
    raw_valid<=1;raw_index<=raw_cursor;raw_byte<=held_lba*7+raw_cursor*13;
    raw_cursor=raw_cursor+1;
   end
  end
  if(rst_n && cv)begin
   if(byte_index!==expected_index[8:0] || byte_data!==(((100+completed)*7+expected_index*13)&255))
    $fatal(1,"PCM order/content mismatch at sector %0d byte %0d",completed,expected_index);
   expected_index=expected_index+1;
  end
  if(rst_n && cd)begin
   if(ce!=0 || expected_index!=512)$fatal(1,"cache error=%h bytes=%0d",ce,expected_index);
   completed=completed+1;expected_index=0;
  end
 end
 always @(negedge sd_clk)if(playing)begin
  if(client_req && !cb)client_req=0;
  if(cache.occupied<min_reserve)min_reserve=cache.occupied;
  if(ticks>=deadline)begin
   if(completed!=issued)begin
    underflow=1;
    $display("BUDGET_UNDERRUN policy=%0d sectors=%0d occupied=%0d slow_elapsed_ticks=%0d",REGRESSED_POLICY,completed,cache.occupied,ticks-slow_start_tick);
    $fatal(1,"audio deadline missed under MV + slow-card service");
   end
   issued=issued+1;client_req=1;deadline=deadline+SECTOR_PERIOD;
  end
  if(!slow_started && completed>=NORMAL_SECTORS)begin
   slow_started=1;slow_start_tick=ticks;reserve_before_slow=cache.occupied;
   $display("BEFORE_SLOW policy=%0d occupied=%0d audio_sectors=%0d video_sectors=%0d",REGRESSED_POLICY,cache.occupied,audio_sectors,video_sectors);
  end
  if(slow_started && !recovery_started && ticks-slow_start_tick>=SLOW_TICKS)begin
   if(video_sectors<100 || completed<NORMAL_SECTORS+918)$fatal(1,"stress did not exercise service budget");
   if(!REGRESSED_POLICY && reserve_before_slow<950)$fatal(1,"stable reserve not maintained");
   recovery_started=1;recovery_start_tick=ticks;video_at_recovery=video_sectors;
   $display("SLOW_COMPLETE policy=%0d completed=%0d occupied=%0d",REGRESSED_POLICY,completed,cache.occupied);
  end
  if(recovery_started && cache.occupied>=960 && video_sectors>video_at_recovery)begin
   $display("TEST_PASS audio_mv_slow_window policy=%0d completed=%0d reserve_before=%0d minimum=%0d recovery_ticks=%0d MV_resumed=1",REGRESSED_POLICY,completed,reserve_before_slow,min_reserve,ticks-recovery_start_tick);
   $finish;
  end
  if(recovery_started && ticks-recovery_start_tick>200*SECTOR_PERIOD)
   $fatal(1,"audio reserve/MV service did not recover after slow window");
 end
 initial begin
  repeat(5)@(negedge sd_clk);rst_n=1;enabled=1;
  wait(cache.occupied==1008);@(negedge sd_clk);
  playing=1;start_tick=ticks;deadline=ticks+SECTOR_PERIOD;
 end
 initial begin #400000000;$fatal(1,"service budget simulation timeout");end
endmodule
