`timescale 1ns/1ps
// Integration: encoder seek -> controller -> drained restart -> actual PCM data.
module tb_seek_pcm_session;
 reg sdclk=0, pixclk=0, rst=0, forward=0, backward=0;
 always #5 sdclk=~sdclk;
 always #20 pixclk=~pixclk;
 wire [31:0] target;
 wire restart, enabled, toggle, idle;
 reg [31:0] base_lba=10000, total=480000, current=50000;
 reg [31:0] start_lba=0, sectors=0, samples=0;
 reg [7:0] skip=0;
 seek_controller #(.BUSY_HOLD(20'd100)) seek(.clk(sdclk),.rst_n(rst),.play_active(1'b1),
  .cur_sample(current),.total_samples(total),.clear_pulse(1'b0),
  .seek_fwd5_tgl(1'b0),.seek_bwd5_tgl(1'b0),.seek_fwd2_tgl(forward),.seek_bwd2_tgl(backward),.replay_tgl(1'b0),
  .target_sample(target),.restart_req(restart));
 always @(posedge sdclk) begin
  start_lba <= base_lba + (target >> 8);
  sectors <= 32'd1875 - (target >> 8);
  samples <= total - target;
  skip <= target[7:0];
 end
 wire sd_req, sd_busy, sd_valid, sd_done, consumed;
 wire [31:0] sd_lba;
 wire [7:0] sd_byte;
 wire [8:0] sd_idx;
 reg [31:0] target1=0,target2=0;
 always @(posedge pixclk) begin target1<=target; target2<=target1; end
 reg [2:0] card_state=0;
 reg [8:0] idx=0;
 reg [31:0] sample_id=0;
 assign sd_busy=(card_state!=0);
 assign sd_valid=(card_state==2);
 assign sd_done=(card_state==3);
 assign sd_idx=idx;
 assign sd_byte=idx[0] ? sample_id[15:8] : sample_id[7:0];
 always @(posedge sdclk) begin
  if (!rst) begin card_state<=0; idx<=0; sample_id<=0; end
  else case(card_state)
   0: if(sd_req) card_state<=1;
   1: begin sample_id<=(sd_lba-base_lba)*256; idx<=0; card_state<=2; end
   2: begin idx<=idx+1'b1; if(idx[0]) sample_id<=sample_id+1'b1; if(idx==511) card_state<=3; end
   3: card_state<=0;
  endcase
 end
 stream_session sess(.clk(sdclk),.rst_n(rst),.requested(1'b1),.restart(restart),
  .storage_busy(sd_busy),.video_busy(1'b0),.reader_idle(idle),.enable(enabled),.start_toggle(toggle));
 wire signed [15:0] pcm;
 wire valid;
 reg [9:0] div=0; reg tick=0;
 always @(posedge pixclk) begin tick<=0; if(div==519) begin div<=0; tick<=1; end else div<=div+1'b1; end
 wav_stream_player wav(.wr_clk(sdclk),.wr_rst_n(rst),.play_enable(enabled),.start_lba(start_lba),
  .total_sectors(sectors),.valid_samples(samples),.skip_samples(skip),.sd_req(sd_req),.sd_lba(sd_lba),
  .sd_busy(sd_busy),.sd_valid(sd_valid),.sd_byte(sd_byte),.sd_byte_index(sd_idx),.sd_done(sd_done),.sd_error(8'd0),
  .rd_clk(pixclk),.rd_rst_n(rst),.sample_tick(tick),.sample_out(pcm),.sample_valid(valid),.sample_ready(1'b1),
  .sample_counter(),.stream_active(),.stream_end(),.reader_idle(idle),.sample_consumed(consumed),
  .startup_ready(),.buffer_low(),.sample_base(target2),.underrun_pulse());
 initial begin
  repeat(5) @(negedge sdclk); rst=1;
  wait(enabled); repeat(2000) @(negedge sdclk);
  forward=~forward;
  wait(restart); wait(!enabled); wait(enabled);
  if(target!==146000) $fatal(1,"wrong target %0d",target);
  if(start_lba!==10000+(146000/256) || skip!==(146000%256)) $fatal(1,"wrong sector/offset");
  wait(consumed); @(posedge pixclk); #1;
  if(pcm !== (146000 & 16'hffff)) $fatal(1,"first PCM %0d expected %0d",pcm,146000 & 16'hffff);
  $display("PASS encoder seek target=%0d LBA=%0d offset=%0d first_pcm=%0d",target,start_lba,skip,pcm);
  @(negedge sdclk); current=146000; backward=~backward;
  wait(restart); wait(!enabled); wait(enabled);
  if(target!==50000) $fatal(1,"wrong reverse target %0d",target);
  if(start_lba!==10000+(50000/256) || skip!==(50000%256)) $fatal(1,"wrong reverse sector/offset");
  wait(consumed); @(posedge pixclk); #1;
  if(pcm !== (50000 & 16'hffff)) $fatal(1,"reverse first PCM %0d expected %0d",pcm,50000);
  $display("PASS reverse seek target=%0d LBA=%0d offset=%0d first_pcm=%h",target,start_lba,skip,pcm);
  $finish;
 end
 initial begin #10000000; $fatal(1,"seek PCM timeout"); end
endmodule
