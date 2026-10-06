`timescale 1ns/1ps
module tb_s7_switch;
 reg clk=0,pix=0,rst=0,ready=1,nxt=0,prev=0,choose=0;
 reg [1:0] chosen=0,displayed=0,mode=0;
 reg frame=0,ack=0,index_commit=0;
 reg [1:0] pix_bank=0; integer pc=0,i,k; reg dark_seen=0,wipe_seen=0;
 integer page_frames=0,page_checked=0; reg wipe_q=0;
 wire txstart,dir,select_req,busy,txbusy,commit;
 wire [1:0] select_index,kind;wire [7:0] alpha;wire fade,wipe;wire [4:0]ramp;
 always #5 clk=~clk;always #20 pix=~pix;
 always @(negedge pix) begin pc=pc+1;frame=(pc%20==0);end
 always @(posedge pix) begin
  index_commit<=0;
  if(frame && pix_bank!=displayed) begin pix_bank<=displayed;index_commit<=1;end
  if(rst && mode==1 && alpha!=255) $fatal(1,"FAIL page transition darkened the picture");
  if(rst && mode==2 && alpha==0) dark_seen<=1;
  if(rst && mode==1 && wipe) wipe_seen<=1;
  wipe_q<=wipe;
  if(wipe && frame) page_frames=page_frames+1;
  if(wipe_q && !wipe) begin
   if(page_frames!=16) $fatal(1,"FAIL page duration expected 16 frames got %d",page_frames);
   page_checked=page_checked+1;page_frames=0;
  end
 end
 always @(posedge clk) begin
  ack<=0;
  if(select_req && !ack) begin displayed<=select_index;ack<=1;end
 end
 cover_navigation nav(.clk(clk),.rst_n(rst),.ready(ready),.count(3'd4),.displayed(displayed),
 .next_step(nxt),.prev_step(prev),.choose(choose),.chosen(chosen),.chosen_direction(1'b0),.transition_busy(txbusy),
 .transition_commit(commit),.select_ack(ack),.transition_start(txstart),.direction(dir),
 .select_req(select_req),.select_index(select_index),.busy(busy));
 video_fade_transition #(.FADE_FRAMES(16)) fx(.ctrl_clk(clk),.ctrl_rst_n(rst),
 .next_event_in(txstart),.direction_in(dir),.effect_mode(mode),.next_event_out(commit),.fade_busy(txbusy),
 .pix_clk(pix),.pix_rst_n(rst),.player_active(1'b1),.frame_start(frame),.index_commit(index_commit),
 .active_index(pix_bank),.alpha_out(alpha),.fade_active(fade),.wipe_active(wipe),.ramp_out(ramp),.transition_kind(kind));
 task cycles;input integer n;repeat(n) @(negedge clk);endtask
 initial begin
 cycles(4);rst=1;
 for(k=0;k<3;k=k+1) begin
  mode=k;
  for(i=0;i<101;i=i+1) begin nxt=1;cycles(1);nxt=0;cycles(5);end
  wait(!busy);cycles(20);
  if(displayed!==((k+1)%4)) $fatal(1,"FAIL accumulated target mode=%d got=%d",k,displayed);
 end
 if(!dark_seen || !wipe_seen || page_checked==0) $fatal(1,"FAIL effect paths not exercised");
 mode=0;prev=1;cycles(1);prev=0;cycles(1);wait(!busy);cycles(10);
 if(displayed!=2) $fatal(1,"FAIL previous bank");
 chosen=0;choose=1;cycles(1);choose=0;cycles(1);wait(!busy);cycles(10);
 if(displayed!=0) $fatal(1,"FAIL direct bank selection");
 if(dir!=0) $fatal(1,"FAIL direct selection lost requested previous direction");
 $display("PASS 303 rapid steps across three modes, 16-frame page without fade, held bank ACK");$finish;
 end
 initial begin #3000000;$fatal(1,"FAIL transition watchdog busy=%b displayed=%d",busy,displayed);end
endmodule
