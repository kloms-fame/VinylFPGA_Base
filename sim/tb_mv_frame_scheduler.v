`timescale 1ns/1ps
module tb_mv_frame_scheduler;
reg clk=0; always #20 clk=~clk;
reg rst_n=0,fs=0,en=0,pause=0,restart=0,done=0,failed=0;
reg [31:0] ms=0,base=1000;
reg [15:0] seek_frame=16'd0;
wire req,dv,busy; wire [31:0] lba; wire [1:0] wb,db; wire [15:0] frame;
reg [1:0] oldbank; reg [15:0] oldframe; integer n;
mv_frame_scheduler dut(.clk(clk),.rst_n(rst_n),.frame_start(fs),.enable(en),
 .paused(pause),.restart(restart),.time_ms(ms),.start_lba(base),.frame_count(16'd6500),
 .seek_frame(seek_frame),
 .done_toggle(done),.failed(failed),.request_toggle(req),.request_lba(lba),
 .request_bank(wb),.display_valid(dv),.display_bank(db),.display_frame(frame),.waiting(busy));
task tick_frame;
begin @(negedge clk);fs=1;@(negedge clk);fs=0; repeat(4) @(negedge clk);end endtask
task ack_frame;
begin wait(busy);repeat(6) @(negedge clk);done=req;repeat(6) @(negedge clk);end endtask
initial begin
 #45 rst_n=1; @(negedge clk); en=1; tick_frame;
 wait(busy); if(lba!=1000 || wb==db) $fatal(1,"initial command or slot collision");
 ack_frame; if(dv) $fatal(1,"midframe publication"); tick_frame;
 if(!dv || frame!=0) $fatal(1,"first frame");
 wait(busy); if(lba!=1300) $fatal(1,"prefetch next frame");
 ack_frame; tick_frame; if(frame!=0) $fatal(1,"early frame");
 pause=1; ms=100; tick_frame; if(frame!=0) $fatal(1,"pause must freeze");
 pause=0; repeat(10) @(negedge clk); tick_frame; if(frame!=1) $fatal(1,"resume");
 wait(busy); oldbank=db; oldframe=frame;
 ms=500; repeat(20) @(negedge clk); tick_frame;
 if(db!=oldbank || frame!=oldframe) $fatal(1,"underload must freeze");
 ack_frame; tick_frame; wait(busy);
 if(lba!=2500) $fatal(1,"slow reader must catch up to audio time");
 // Cancel an in-flight old-song request. Its completion cannot replace pixels.
 restart=1;ms=0; base=9000; @(negedge clk); restart=0; tick_frame;
 ack_frame; repeat(25) @(negedge clk); tick_frame;
 if(dv) $fatal(1,"stale song published");
 wait(busy); if(lba!=9000) $fatal(1,"new song metadata");
 ack_frame; tick_frame; if(!dv || frame!=0) $fatal(1,"new song start");
 // Ten minute media timeline. Service each requested frame then advance time.
 for(n=1;n<=6000;n=n+1) begin
  wait(busy);
  if(wb==db) $fatal(1,"write/display bank collision");
  ack_frame; ms=n*100; repeat(6) @(negedge clk); tick_frame;
  if(frame!=n) $fatal(1,"timeline drift at %0d got %0d",n,frame);
 end
 // X2: non-zero seek target must position the first requested/displayed frame.
 if(busy) ack_frame;
 en=0; seek_frame=16'd1234; base=20000; ms=0;
 tick_frame;
 restart=1; @(negedge clk); restart=0; en=1;
 repeat(20) @(negedge clk);
 tick_frame; wait(busy);
 if(lba != (20000 + 1234*300))
  $fatal(1,"seek frame LBA mismatch got=%0d want=%0d",lba,20000+1234*300);
 ack_frame; tick_frame;
 if(!dv || frame!=16'd1234) $fatal(1,"seek frame not published");
 ms=123500; wait(busy);
 if(lba != (20000 + 1235*300)) $fatal(1,"post-seek timeline did not continue");
 ack_frame; tick_frame;
 if(frame!=16'd1235) $fatal(1,"post-seek frame drift");
 en=0; tick_frame; if(dv) $fatal(1,"exit must clear at boundary");
 $display("TEST_PASS mv_frame_scheduler pause underload restart seek three slots 600s no drift");$finish;
end
initial begin #100000000; $fatal(1,"timeout");end
endmodule
