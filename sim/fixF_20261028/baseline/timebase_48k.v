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
// 重播时把时基清零；X2 增加 load/load_sample：Seek 后把时基直接加载到目标
// 样本位置，而不是从 0 重新数起。
// =============================================================================
module timebase_48k (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,   // 48 kHz 单拍（唯一时基源）
    input  wire        running,       // 1=播放中且未暂停
    input  wire        restart,       // 1 拍：清零（切曲/重播）
    input  wire        load,          // 1 拍：加载到 load_sample（X2 Seek）
    input  wire [31:0] load_sample,
    output reg  [31:0] sample_count,
    output reg  [31:0] cur_time_ms,
    output reg  [5:0]  sub_sample
);
    // Exact radix-2 division by 48, one input bit per cycle. The 32-cycle
    // conversion finishes well within one 48-kHz period at video_clk=25 MHz.
    // Count any consumed samples during conversion rather than dropping them.
    reg [31:0] quotient;
    reg [5:0] remainder, steps, pending_samples;
    wire [6:0] shifted = {remainder, quotient[31]};
    wire subtract = shifted >= 7'd48;
    wire [6:0] rem_next = subtract ? shifted - 7'd48 : shifted;
    wire [31:0] quotient_next = {quotient[30:0], subtract};
    wire [6:0] final_sub = rem_next + {1'b0,pending_samples} +
                           ((sample_tick && running) ? 7'd1 : 7'd0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count<=0; cur_time_ms<=0; sub_sample<=0;
            quotient<=0; remainder<=0; steps<=0; pending_samples<=0;
        end else if (load) begin
            sample_count<=load_sample;
            quotient<=load_sample; remainder<=0; steps<=32; pending_samples<=0;
        end else if (restart) begin
            sample_count<=0; cur_time_ms<=0; sub_sample<=0;
            quotient<=0; remainder<=0; steps<=0; pending_samples<=0;
        end else begin
            if (sample_tick && running) sample_count<=sample_count+1'b1;
            if (steps!=0) begin
                quotient<=quotient_next;
                remainder<=rem_next[5:0];
                steps<=steps-1'b1;
                if (sample_tick && running) pending_samples<=pending_samples+1'b1;
                if (steps==1) begin
                    cur_time_ms<=quotient_next + ((final_sub>=48) ? 32'd1 : 32'd0);
                    sub_sample<=(final_sub>=48) ? final_sub-7'd48 : final_sub;
                end
            end else if (sample_tick && running) begin
                if (sub_sample==47) begin
                    sub_sample<=0;cur_time_ms<=cur_time_ms+1'b1;
                end else sub_sample<=sub_sample+1'b1;
            end
        end
    end
endmodule
`endif
