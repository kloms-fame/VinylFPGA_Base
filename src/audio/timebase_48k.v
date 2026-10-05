`timescale 1ns/1ps
`ifndef EXP_TIMEBASE_48K_V
`define EXP_TIMEBASE_48K_V
// =============================================================================
// timebase_48k —— S5：全工程唯一的 48 kHz 毫秒时基
//
// 输入就是既有 wav_sample_tick（video_clk 25 MHz 上的 48 kHz 分数节拍），
// 所以"只允许一个 48 kHz 源"这条约束天然成立：歌词、进度、任何时间量都只认
// 这里输出的 cur_time_ms，不再各自计数。
//
//   sample_tick && running  -> sample_count++、sub_sample 0..47 循环
//   每 48 个样本             -> cur_time_ms++（48 kHz / 1000 = 48 样本/毫秒）
//
// running=0（暂停/未播放）时全部冻结，歌词与音频同步停止；restart 用于切曲/
// 重播时把时基清零。
// =============================================================================
module timebase_48k (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,   // 48 kHz 单拍（唯一时基源）
    input  wire        running,       // 1=播放中且未暂停
    input  wire        restart,       // 1 拍：清零（切曲/重播）
    output reg  [31:0] sample_count,
    output reg  [31:0] cur_time_ms,
    output reg  [5:0]  sub_sample
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count <= 32'd0;
            cur_time_ms  <= 32'd0;
            sub_sample   <= 6'd0;
        end else if (restart) begin
            sample_count <= 32'd0;
            cur_time_ms  <= 32'd0;
            sub_sample   <= 6'd0;
        end else if (sample_tick && running) begin
            sample_count <= sample_count + 32'd1;
            if (sub_sample == 6'd47) begin
                sub_sample  <= 6'd0;
                cur_time_ms <= cur_time_ms + 32'd1;
            end else begin
                sub_sample <= sub_sample + 6'd1;
            end
        end
    end
endmodule
`endif
