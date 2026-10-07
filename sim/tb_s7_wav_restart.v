`timescale 1ns/1ps
module tb_s7_wav_restart;
 reg clk=0,pix=0,rst=0,requested=0,restart=0;
 reg[31:0]target=100;
 reg busy=0,valid=0,done=0;reg[7:0]data=0,error=0;reg[8:0]idx=0;
 reg inject_error=0;
 wire enable,toggle,idle,req,sv,active,eof,consumed;wire[31:0]lba,count;
 wire signed[15:0]sample;
 reg[31:0]served=0;integer phase=0,byte_no=0,pc=0,n;
 reg tick=0;integer first_seen=0;
 always #5 clk=~clk;always #19 pix=~pix;
 always @(negedge pix)begin pc=pc+1;tick=(pc%8==0);end
 stream_session session(.clk(clk),.rst_n(rst),.requested(requested),.restart(restart),
 .storage_busy(busy),.video_busy(1'b0),.reader_idle(idle),.enable(enable),.start_toggle(toggle));
 wav_stream_player dut(.wr_clk(clk),.wr_rst_n(rst),.play_enable(enable),.start_lba(target),
 .total_sectors(32'd2),.valid_samples(32'd512),.sd_req(req),.sd_lba(lba),.sd_busy(busy),.sd_valid(valid),
 .sd_byte(data),.sd_byte_index(idx),.sd_done(done),.sd_error(error),
 .rd_clk(pix),.rd_rst_n(rst),.sample_tick(tick),.sample_ready(1'b1),
 .sample_out(sample),.sample_valid(sv),.sample_counter(count),.stream_active(active),.stream_end(eof),
 .reader_idle(idle),.sample_consumed(consumed),.buffer_low(),.underrun_pulse(),
 .skip_samples(8'd0),.sample_base(32'd0));
 always @(posedge clk) begin
  valid<=0;done<=0;
  if(!rst)begin phase<=0;busy<=0;byte_no<=0;end
  else case(phase)
   0:if(req && !busy)begin phase<=1;busy<=1;error<=0;end
   1:begin served<=lba;byte_no<=0;phase<=2;end
   2:if(byte_no<512)begin
    valid<=1;idx<=byte_no;data<=byte_no[0]?served[7:0]:(byte_no>>1);byte_no<=byte_no+1;
   end else begin done<=1;error<=inject_error?8'h05:8'd0;phase<=3;end
   3:begin busy<=0;phase<=0;end
  endcase
 end
 always @(negedge pix) if(rst && sv && count==1) begin
  if(sample!=={target[7:0],8'd0}) $fatal(1,"FAIL stale/new first sample %h expected %h",sample,{target[7:0],8'd0});
  first_seen=first_seen+1;
 end
 initial begin
 repeat(5)@(negedge clk);rst=1;requested=1;
 // Cancel after samples started, and again while a later sector is outstanding.
 for(n=0;n<10;n=n+1)begin
  wait(count>=8);wait(busy && byte_no>=17 && byte_no<500);
  @(negedge clk);target=target+8;restart=1;
  @(negedge clk);restart=0;
  wait(!enable);wait(enable);
  wait(count==1);repeat(10)@(negedge pix);
 end
 wait(eof);if(count!=512)$fatal(1,"FAIL restarted stream length");
 inject_error=1;@(negedge clk);restart=1;target=target+8;
 @(negedge clk);restart=0;wait(!enable);wait(enable);wait(done);
 repeat(1000)@(negedge pix);
 if(eof || active)$fatal(1,"FAIL read failure mislabeled successful EOF");
 if(first_seen<10)$fatal(1,"FAIL restarts not observed");
 $display("PASS ten in-flight restarts, first-sample LBA scoreboard, successful drain vs error EOF");$finish;
 end
 initial begin #10000000;$fatal(1,"FAIL restart watchdog");end
endmodule
