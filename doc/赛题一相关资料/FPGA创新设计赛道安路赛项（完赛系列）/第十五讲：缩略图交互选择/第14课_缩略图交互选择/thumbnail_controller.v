// thumbnail_controller.v —— 第14课练习骨架（完赛工程未实现）
module thumbnail_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_right,   // 消抖后单拍：焦点右移
    input  wire        key_left,    // 消抖后单拍：焦点左移
    input  wire        key_confirm, // 消抖后单拍：选中当前焦点
    input  wire        key_mode,    // 消抖后单拍：全屏/缩略图切换
    input  wire [3:0]  image_complete,
    input  wire        frame_start, // 帧边界
    output reg         view_mode,   // 0=全屏 1=缩略图
    output reg [1:0]   focus_index,
    output reg [1:0]   active_index,
    output reg         transition_req
);
    // 复位初值：全屏、焦点0、当前图0
    // TODO(学员完成1)：key_mode 翻转 view_mode，并产生一个周期 transition_req
    // TODO(学员完成2)：只有 view_mode==1（缩略图）时才响应方向键：
    //     key_right -> focus_index+1，到 2'd3 后 wrap 回 2'd0；
    //     key_left  -> focus_index-1，到 2'd0 后 wrap 回 2'd3；
    //     全屏模式下方向键留给上一张/下一张，不动 focus_index。
    // TODO(学员完成3)：key_confirm 时 active_index = focus_index；view_mode=0(全屏)；transition_req=1。
    //     （注意：focus_index 指向的图若未加载，应忽略或提示，可用 image_complete[focus_index] 判断）
    // TODO(学员完成4)：以上寄存器变化在 frame_start 锁存/生效，避免一帧内坐标切换撕裂；
    //     transition_req 是单拍脉冲，拍宽1拍后自动拉低。
endmodule
