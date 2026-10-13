`timescale 1ns/1ps
module tb_s6_video_layer;
reg clk=0; always #20 clk=~clk;
reg rst_n=0,fs=0,play=0,paused=0,restart=0,done=0,raw=0,ev=0;
reg [3:0]code=0;reg [15:0]arg=0;
reg [31:0]ms=0;reg [63:0]meta=0;
reg [1:0] track=0;
reg [1:0]de_pipe=0; wire de=de_pipe[1];reg [9:0]x=0;
wire toggle,req,mv,allowed,visible,preloading;wire[1:0]bank,wb;wire[31:0]lba;wire[23:0]rgb,bypass;
integer y,k,pops=0,shown=0;
ui_event_bridge bridge(.clk(clk),.rst_n(rst_n),.ev_valid(ev),.ev_code(code),.ev_arg(arg),.ev_aux(16'd0),.visual_tgl(toggle));
s6_video_layer dut(.clk(clk),.rst_n(rst_n),.frame_start(fs),.play_active(play),.paused(paused),.restart(restart),
 .diagnostic(1'b0),.transport_ready(1'b1),.track_id(track),.covers_ready(1'b1),.metadata_async(meta),.time_ms(ms),.seek_frame(16'd0),.visual_toggle(toggle),
 .raw_read_en(raw),.out_de(de),.out_x(x),.adjusted_de(de),.adjusted_x(x),
 .rgb_in(24'h123456),.rgb_out(rgb),.mv_read_active(mv),.mv_read_bank(bank),
 .fifo_read_allowed(allowed),.mv_window_visible(visible),.request_toggle(req),.request_lba(lba),.request_bank(wb),
 .mv_preloading(preloading),
 .done_toggle(done),.failed(1'b0));
s6_video_layer #(.ENABLE(0)) rollback(.clk(clk),.rst_n(rst_n),.frame_start(fs),.play_active(play),.paused(paused),.restart(restart),
 .diagnostic(1'b0),.transport_ready(1'b1),.track_id(2'd0),.covers_ready(1'b1),.metadata_async(meta),.time_ms(ms),.seek_frame(16'd0),.visual_toggle(toggle),
 .raw_read_en(raw),.out_de(de),.out_x(x),.adjusted_de(de),.adjusted_x(x),
 .rgb_in(24'h123456),.rgb_out(bypass),.done_toggle(1'b0),.failed(1'b0));
always @(posedge clk) begin
 de_pipe<={de_pipe[0],raw};
 if(!de) x<=0; else x<=x+1'b1;
 if(raw && allowed) pops=pops+1;
 if(de && visible) shown=shown+1;
 if(rst_n && bypass!==24'h123456) $fatal(1,"rollback transparency");
end
task boundary;
begin @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(6) @(negedge clk);end endtask
task event_key;
input [3:0]c;input[15:0]a;
begin @(negedge clk);code=c;arg=a;ev=1;@(negedge clk);ev=0;repeat(6) @(negedge clk);end endtask
initial begin
 #45 rst_n=1;boundary;
 if(rgb!==24'h123456) $fatal(1,"browse pass through");
 play=1;meta={8'd1,8'd10,16'd100,32'd2000};boundary;
 wait(req);boundary;if(!preloading || mv) $fatal(1,"MV first-frame black placeholder");
 event_key(1,7);boundary;if(preloading || mv) $fatal(1,"explicit cover preference must remain visible during loading");
 event_key(1,7);boundary;if(!preloading || mv) $fatal(1,"video preference restores preload black placeholder");
 repeat(8) @(negedge clk);done=req;repeat(8) @(negedge clk);boundary;boundary;boundary;
 if(!mv) $fatal(1,"ready MV must become visible");
 if(preloading) $fatal(1,"ready MV still masked black");
 for(y=0;y<480;y=y+1) begin
  @(negedge clk);raw=1;repeat(640) @(negedge clk);raw=0;repeat(12) @(negedge clk);
 end
 if(pops!=76800 || shown!=76800) $fatal(1,"window dimensions/pop alignment %0d %0d",pops,shown);
 event_key(2,7);boundary;if(!mv) $fatal(1,"KEY08 release must not toggle");
 event_key(1,6);boundary;if(!mv) $fatal(1,"KEY07 must not toggle visual");
 event_key(1,7);if(!mv) $fatal(1,"mode changed midframe");boundary;if(mv) $fatal(1,"KEY08 vinyl");
 event_key(1,7);boundary;if(!mv) $fatal(1,"KEY08 MV");
 // A new song must not retain the preceding song's valid video bank.
 @(negedge clk);track=1;meta={8'd1,8'd10,16'd100,32'd4000};restart=1;done=req;
 repeat(4) @(negedge clk);restart=0;boundary;
 if(mv || !preloading || dut.scheduler.display_valid) $fatal(1,"MV-to-MV must black out the old track");
 wait(req!=done);repeat(8) @(negedge clk);done=req;
 repeat(8) @(negedge clk);boundary;boundary;boundary;
 if(!mv || preloading) $fatal(1,"new track first MV frame not committed");
 // Same-track transport restart/seek preserves its already valid frame.
 @(negedge clk);restart=1;done=req;boundary;
 if(!mv || preloading) $fatal(1,"same-track restart lost retained video");
 @(negedge clk);restart=0;boundary;
 play=0;boundary;if(mv || rgb!==24'h123456) $fatal(1,"exit bypass");
 $display("TEST_PASS s6_video_layer 320x240 FIFO window KEY08 frame boundary rollback");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
