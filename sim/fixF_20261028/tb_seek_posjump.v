`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_seek_posjump —— 位置跳变（Seek / 切歌）在 video 域的完整链路回归
//
// 复现的真实链路（与 top_tf_hdmi_audio.v 同构）：
//   seek_controller 在 sd 域同拍改 target_sample + 拉 restart_req
//     -> stream_session 停/启一次，start_toggle 翻转
//     -> play_track_restart_vid 单拍（seek 与切歌共用这一条脉冲）
//     -> timebase_48k(.restart, .load) + s6_video_layer(.restart, .seek_frame)
//
// 判据：
//   Seek 后 lyric_time_ms == target/48，MV target_frame == target/4800；
//   切歌后二者归零；跳变之后 1000 拍内 target_frame 不得自增（next_time 必须同步重装）。
// -----------------------------------------------------------------------------
module tb_seek_posjump;
reg clk = 0, rst_n = 0;
always #20 clk = ~clk;                     // 25 MHz video_clk

reg frame_start=0, play_active=0, paused=0, diagnostic=0;
reg transport_ready=1, covers_ready=1;
reg [63:0] metadata_async=64'd0;
reg [1:0]  track_id=2'd0;
reg visual_toggle=0, raw_read_en=0, out_de=0, adjusted_de=0;
reg [9:0]  out_x=10'd0, adjusted_x=10'd0;
reg [23:0] rgb_in=24'd0;
reg done_toggle=0, failed=0;
wire [23:0] rgb_out;
wire mv_read_active;
wire [1:0]  mv_read_bank;
wire fifo_read_allowed, mv_window_visible, request_toggle;
wire [31:0] request_lba;
wire [1:0]  request_bank;

// ---- sd 域目标 + video 域 2FF（top_tf_hdmi_audio.v:1396-1404）----
reg [31:0] target_sd=0, target_v1=0, target_v2=0;
always @(posedge clk or negedge rst_n)
  if(!rst_n) begin target_v1<=0; target_v2<=0; end
  else begin target_v1<=target_sd; target_v2<=target_v1; end

// ---- 目标样本/4800 串行定位器（top_tf_hdmi_audio.v:1408-1427 逐行同构）----
reg [31:0] seek_frame_rem=0, seek_frame_target_d=0;
reg [19:0] seek_frame_calc_reg=0;
reg        seek_frame_busy=0;
wire [31:0] seek_frame_rem_next = seek_frame_rem - 32'd4800;
wire [15:0] seek_frame_vid = (seek_frame_calc_reg > 20'h0FFFF) ? 16'hFFFF :
                             seek_frame_calc_reg[15:0];
always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
    seek_frame_rem<=0; seek_frame_target_d<=0; seek_frame_calc_reg<=0; seek_frame_busy<=0;
  end else if (target_v2 != seek_frame_target_d) begin
    seek_frame_target_d <= target_v2;
    seek_frame_rem      <= target_v2;
    seek_frame_calc_reg <= 20'd0;
    seek_frame_busy     <= (target_v2 >= 32'd4800);
  end else if (seek_frame_busy) begin
    if (seek_frame_rem >= 32'd4800) begin
      seek_frame_rem      <= seek_frame_rem_next;
      seek_frame_calc_reg <= seek_frame_calc_reg + 1'b1;
    end else begin
      seek_frame_busy <= 1'b0;
    end
  end
end

// ---- 48 kHz tick（25 MHz / 48000 = 520.8）----
reg sample_tick = 0;
integer tick_cnt = 0;
always @(posedge clk) begin
  if (tick_cnt == 520) begin tick_cnt <= 0; sample_tick <= 1'b1; end
  else begin tick_cnt <= tick_cnt + 1; sample_tick <= 1'b0; end
end
// ---- 视频帧起始（缩比：5000 拍 = 200 us）----
integer fs_cnt = 0;
always @(posedge clk) begin
  if (fs_cnt == 4999) begin fs_cnt <= 0; frame_start <= 1'b1; end
  else begin fs_cnt <= fs_cnt + 1; frame_start <= 1'b0; end
end

// ---- 时基。load = restart | 目标变化（修复后的顶层接法）----
reg  [31:0] target_q = 0;
wire        target_changed = (target_v2 != target_q);
always @(posedge clk or negedge rst_n)
  if(!rst_n) target_q <= 32'd0; else target_q <= target_v2;
reg  restart = 0;
wire [31:0] lyric_time_ms, lyric_sample_count;
timebase_48k u_timebase (
  .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick), .running(play_active & ~paused),
  .restart(restart), .load(restart | target_changed), .load_sample(target_v2),
  .sample_count(lyric_sample_count), .cur_time_ms(lyric_time_ms), .sub_sample()
);

s6_video_layer #(.ENABLE(1)) u_s6 (
  .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .play_active(play_active),
  .paused(paused), .restart(restart), .diagnostic(diagnostic),
  .transport_ready(transport_ready), .covers_ready(covers_ready),
  .metadata_async(metadata_async), .track_id(track_id),
  .time_ms(lyric_time_ms), .seek_frame(seek_frame_vid), .visual_toggle(visual_toggle),
  .raw_read_en(raw_read_en), .out_de(out_de), .out_x(out_x),
  .adjusted_de(adjusted_de), .adjusted_x(adjusted_x), .rgb_in(rgb_in), .rgb_out(rgb_out),
  .mv_read_active(mv_read_active), .mv_read_bank(mv_read_bank),
  .fifo_read_allowed(fifo_read_allowed), .mv_window_visible(mv_window_visible),
  .request_toggle(request_toggle), .request_lba(request_lba), .request_bank(request_bank),
  .done_toggle(done_toggle), .failed(failed)
);

integer errors = 0;
// 定位器推进期间（seek_moving）不得发出任何帧请求：中途帧会以旧位置闪一帧，
// 这正是"seek 后画面从头开始"的第二条路径，必须由 invalidating/can_issue 挡住。
reg        req_prev = 0;
reg [31:0] req_lba_last = 0;
integer    moving_requests = 0;
// 写入完成模型：每个请求 40 拍后 done_toggle 翻转，释放 busy，使后续请求得以继续
// （否则 busy 永远为 1，seek 之后根本不会再发请求，观测不到"是否从中途发出"）。
reg [7:0] done_cnt = 0;
always @(posedge clk) begin
  if (!rst_n) begin done_cnt <= 0; done_toggle <= 0; end
  else if (request_toggle != req_prev) done_cnt <= 8'd40;
  else if (done_cnt != 0) begin
    done_cnt <= done_cnt - 1;
    if (done_cnt == 1) done_toggle <= ~done_toggle;
  end
end
always @(posedge clk) begin
  if (rst_n && (request_toggle != req_prev)) begin
    req_lba_last <= request_lba;
    if (u_s6.scheduler.seek_moving) moving_requests = moving_requests + 1;
  end
  req_prev <= request_toggle;
end
task chk_time(input [31:0] exp, input [8*24-1:0] name);
begin
  if (lyric_time_ms > exp + 2 || lyric_time_ms + 2 < exp) begin
    $display("FAIL %0s time_ms=%0d exp=%0d", name, lyric_time_ms, exp);
    errors = errors + 1;
  end else $display("PASS %0s time_ms=%0d (exp %0d)", name, lyric_time_ms, exp);
end
endtask
task chk_frame(input [15:0] exp, input [8*24-1:0] name);
begin
  if (u_s6.scheduler.target_frame !== exp) begin
    $display("FAIL %0s target_frame=%0d exp=%0d", name, u_s6.scheduler.target_frame, exp);
    errors = errors + 1;
  end else $display("PASS %0s target_frame=%0d", name, u_s6.scheduler.target_frame);
end
endtask
task chk_req(input [15:0] exp_frame, input [8*24-1:0] name);
begin
  // 请求会带 1 帧前瞻，因此只要求"落在目标帧或其之后"，绝不允许落在中途的早帧。
  if ((req_lba_last - 32'd1000) / 32'd300 < exp_frame) begin
    $display("FAIL %0s request frame %0d < seek frame %0d", name,
             (req_lba_last - 32'd1000) / 32'd300, exp_frame);
    errors = errors + 1;
  end else $display("PASS %0s request frame %0d >= seek frame %0d", name,
                    (req_lba_last - 32'd1000) / 32'd300, exp_frame);
end
endtask
task pos_jump(input [31:0] tgt);
begin
  @(negedge clk); target_sd = tgt;
  repeat (20) @(negedge clk);
  restart = 1'b1; @(negedge clk); restart = 1'b0;
  repeat (300) @(posedge clk);
end
endtask

initial begin
  metadata_async = {8'd1, 8'd10, 16'd300, 32'd1000};   // version1 / 10fps / 300帧 / lba1000
  play_active = 1'b1; covers_ready = 1'b1; transport_ready = 1'b1;
  #100 rst_n = 1'b1;
  repeat (50) @(posedge clk);

  // 1) 从 0 起播后 seek 到 3000 ms（frame 30）
  $display("--- step1: seek to 3000 ms (frame 30) ---");
  pos_jump(32'd144000);
  chk_time(32'd3000, "seek3000 time");
  chk_frame(16'd30, "seek3000 frame");
  chk_req(16'd30, "seek3000 request not from mid-relocation");
  repeat (1000) @(posedge clk);
  chk_frame(16'd30, "seek3000 frame stable");

  // 2) 再 seek 到 6000 ms（frame 60）——向后跳
  $display("--- step2: seek to 6000 ms (frame 60) ---");
  pos_jump(32'd288000);
  chk_time(32'd6000, "seek6000 time");
  chk_frame(16'd60, "seek6000 frame");
  chk_req(16'd60, "seek6000 request not from mid-relocation");
  repeat (1000) @(posedge clk);
  chk_frame(16'd60, "seek6000 frame stable");

  // 3) 切歌：target 归零 + track_id 变化 + restart（与 play_ctrl 的 seek_clear 同拍起效）
  $display("--- step3: track change -> 0 ---");
  track_id = 2'd1;
  pos_jump(32'd0);
  chk_time(32'd0, "track time");
  chk_frame(16'd0, "track frame");
  repeat (1000) @(posedge clk);
  chk_frame(16'd0, "track frame stable");

  if (moving_requests != 0) begin
    $display("FAIL issued %0d frame requests while the seek target was still moving",
             moving_requests);
    errors = errors + 1;
  end else $display("PASS no frame request during seek relocation");
  if (errors == 0) $display("RESULT PASS");
  else $fatal(1, "RESULT FAIL errors=%0d", errors);
  $finish;
end
endmodule
