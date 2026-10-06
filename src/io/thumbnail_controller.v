`timescale 1ns/1ps

// =============================================================================
// 第十五讲《缩略图交互选择》：thumbnail_controller
//
// 教程中本课为练习课，完赛工程没有该文件。这里严格采用教程 3.2.2 的
// 参考答案逻辑，不做状态机重构：
//   - view_mode    : 0=全屏，1=缩略图
//   - focus_index  : 2x2 缩略图焦点 0~3
//   - active_index : 确认选中的全屏图片索引
//   - transition_req : 在 frame_start 边界输出一拍，用于触发一次转场
//
// key_left/key_right/key_confirm/key_mode 都是消抖后的单拍脉冲。
// =============================================================================
module thumbnail_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_right,
    input  wire        key_left,
    input  wire        key_confirm,
    input  wire        key_mode,
    input  wire        go_home,
    input  wire [3:0]  image_complete,
    input  wire        frame_start,
    output reg         view_mode,
    output reg  [1:0]  focus_index,
    output reg  [1:0]  active_index,
    output reg         transition_req
);
    reg trans_pend;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            view_mode       <= 1'b0;
            focus_index     <= 2'd0;
            active_index    <= 2'd0;
            transition_req  <= 1'b0;
            trans_pend      <= 1'b0;
        end else begin
            transition_req <= 1'b0;

            if (key_mode) begin
                view_mode <= ~view_mode;
                trans_pend <= 1'b1;
            end

            if (view_mode && key_right) begin
                focus_index <= (focus_index == 2'd3) ? 2'd0 : focus_index + 1'b1;
            end

            if (view_mode && key_left) begin
                focus_index <= (focus_index == 2'd0) ? 2'd3 : focus_index - 1'b1;
            end

            if (key_confirm && image_complete[focus_index]) begin
                active_index <= focus_index;
                view_mode    <= 1'b0;
                trans_pend   <= 1'b1;
            end

            if (frame_start && trans_pend) begin
                transition_req <= 1'b1;
                trans_pend     <= 1'b0;
            end
            // Escape is independent of cover availability and pending display work.
            if (go_home) begin
                view_mode <= 1'b0;
                trans_pend <= 1'b0;
                transition_req <= 1'b0;
            end
        end
    end
endmodule
