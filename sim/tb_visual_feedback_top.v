`timescale 1ns/1ps
// Exercise the actual top-level UI/metadata selection and progress connections.
// Vendor clocks and media records are fixtures; the display and CDC are real RTL.
module tb_visual_feedback_top;
 reg clk=0,rst=0,playing=0,grid=0,valid=1;
 reg [1:0] focus=0,selected=0,bank=0;
 reg [31:0] position=0;
 always #5 clk=~clk;
 top dut(.clk(clk),.rst_n(rst),.key3(1'b1),.sw1(1'b1),.sw2(1'b1),.sw3(1'b1),.sw4(1'b1),
 .sd_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
 .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 reg [31:0] duration;
 always @* case(dut.metadata_song_sd)
  0:duration=125*48000;1:duration=62*48000;
  2:duration=5999*48000;3:duration=240*48000;
 endcase
 function [7:0] digit;input integer n;begin
 case(n)0:digit=8'hc0;1:digit=8'hf9;2:digit=8'ha4;3:digit=8'hb0;4:digit=8'h99;
 5:digit=8'h92;6:digit=8'h82;7:digit=8'hf8;8:digit=8'h80;9:digit=8'h90;default:digit=8'hff;endcase
 end endfunction
 task check;input integer seconds,song,fill;reg[63:0]expected;begin
 repeat(600)@(negedge clk);
 expected={digit(seconds/600),digit((seconds/60)%10),8'hbf,digit((seconds%60)/10),digit(seconds%10),8'hff,8'hc0,digit(song+1)};
 if({dut.seg_biz_0,dut.seg_biz_1,dut.seg_biz_2,dut.seg_biz_3,dut.seg_biz_4,dut.seg_biz_5,dut.seg_biz_6,dut.seg_biz_7}!==expected)
  $fatal(1,"FAIL top MM-SS blank NN seconds=%0d song=%0d",seconds,song);
 if(dut.ws_progress_clk!==fill[3:0])$fatal(1,"FAIL top progress expected=%0d got=%0d",fill,dut.ws_progress_clk);
 end endtask
 initial begin
 force dut.sd_card_clk=clk;force dut.ext_mem_clk=clk;force dut.video_clk=clk;
 force dut.sdcard_rst_n=rst;force dut.sd_media_rst_n=rst;force dut.exp_rst_n=rst;
 force dut.video_rst_n=rst;force dut.media_video_rst_n=rst;force dut.mem_rst_n=rst;
 force dut.play_active_sd=playing;force dut.play_sel_song_sd=selected;
 force dut.thumb_mode_sd=grid;force dut.thumb_focus_index_sd=focus;force dut.disp_buf_idx=bank;
 force dut.audio_file_valid=valid;force dut.play_total_samples=duration;force dut.seek_cur_sample_sd=position;
 force dut.board_sw_level_clk=4'b0101; // SW3 on must no longer select E00F0
 force dut.media_err_code=8'h34;force dut.fault_flags_clk=4'hf;
 repeat(4)@(negedge clk);rst=1;
 check(125,0,0);bank=1;check(62,1,0);
 grid=1;focus=2;check(5999,2,0);focus=3;check(240,3,0);
 selected=3;playing=1;position=0;check(0,3,0);
 position=60*48000;check(60,3,2);focus=0;bank=1;check(60,3,2); // pause retains position
 position=180*48000;check(180,3,6); // seek forward
 position=30*48000;check(30,3,1); // backward
 position=0;check(0,3,0);position=240*48000;check(240,3,8);
 playing=0;grid=0;bank=1;check(62,1,0);
 valid=0;check(0,1,0);valid=1;check(62,1,0);
 $display("PASS top browse duration, track number, playback/pause/seek/replay/EOF and exact progress");$finish;
 end
 initial begin #200000;$fatal(1,"FAIL top visual watchdog");end
endmodule
