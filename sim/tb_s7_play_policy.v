`timescale 1ns/1ps
module tb_s7_play_policy;
 reg clk=0,rst=0,confirm=0,cf=0,cw=0,ccw=0,mode=0,eof=0,stop=0,lost=0;
 reg [2:0] total=4; reg [1:0] focus=3;
 wire active,paused,step,dir,restart; wire [1:0] song,policy; wire [7:0] vol;
 integer n,restarts=0,steps=0;
 always #5 clk=~clk;
 always @(negedge clk) begin if(restart) restarts=restarts+1; if(step) steps=steps+1; end
 play_ctrl dut(.clk(clk),.rst_n(rst),.song_total(total),.song_confirm(confirm),.focus_index(focus),
 .enc_cw_tgl(cw),.enc_ccw_tgl(ccw),.confirm_tgl(cf),.key_up_tgl(1'b0),.key_down_tgl(1'b0),
 .stop_tgl(1'b0),.stop_request(stop),.media_lost(lost),.stream_end(eof),.end_mode_tgl(mode),
 .end_mode(policy),.restart_request(restart),.play_active(active),.paused(paused),
 .sel_song(song),.volume(vol),.track_step(step),.track_dir(dir));
 task cycles; input integer c; repeat(c) @(negedge clk); endtask
 task start; begin confirm=1;cycles(1);confirm=0;cycles(6);end endtask
 initial begin
 cycles(4);rst=1;cycles(2);total=0;start();
 if(active) $fatal(1,"FAIL no songs cannot start");
 total=4;start();if(!active || song!=3 || paused) $fatal(1,"FAIL start displayed song");
 eof=1;cycles(12);if(!paused || !active || policy!=0) $fatal(1,"FAIL default EOF pauses in PLAY");
 n=restarts;cycles(12);if(n!=restarts) $fatal(1,"FAIL EOF repeated");
 cf=~cf;cycles(8);if(paused || restarts!=n+1) $fatal(1,"FAIL confirm at EOF restarts same song");
 eof=0;cycles(5);mode=~mode;cycles(6);if(policy!=1) $fatal(1,"FAIL repeat mode");
 n=restarts;eof=1;cycles(20);
 if(paused || song!=3 || restarts!=n+1) $fatal(1,"FAIL repeat once");
 eof=0;cycles(5);mode=~mode;cycles(6);eof=1;cycles(10);
 if(song!=0 || paused || steps!=1 || policy!=2) $fatal(1,"FAIL EOF next wraps 4 songs");
 eof=0;cycles(5);cf=~cf;cycles(6);if(!paused) $fatal(1,"FAIL manual pause");
 cw=~cw;cycles(8);if(song!=1 || paused) $fatal(1,"FAIL manual next must restart/unpause");
 ccw=~ccw;cycles(8);if(song!=0) $fatal(1,"FAIL manual previous");
 stop=1;cycles(1);stop=0;cycles(6);if(active) $fatal(1,"FAIL home stops");
 start();lost=1;cycles(6);if(active || paused) $fatal(1,"FAIL media fault stops playback");
 $display("PASS EOF pause/repeat/next, restart, four-song wrap, home/fault");$finish;
 end
 initial begin #20000;$fatal(1,"FAIL watchdog");end
endmodule
