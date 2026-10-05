`timescale 1ns/1ps

// =============================================================================
// SDRAM 只读口换手开关（第十三讲新增，供缩略图取像复用唯一的一路读口）
//
// 背景：本工程 SDRAM 控制器只有一路 App_rd_en/App_rd_addr 只读口，原本由
// frame_read_write（内部 frame_fifo_read）独占。缩略图视图需要按坐标随机取像，
// 必须与整帧顺序读取共用这一路读口。
//
// 设计边界（“高危链路尽量不动”）：
//   - 不修改 frame_read_write / frame_fifo_read / sdram 内部任何一行；
//   - 全屏模式（mode_active=0）下本模块是纯组合直通：
//       app_rd_en   = frw_rd_en
//       app_rd_addr = frw_rd_addr
//       frw_rd_valid = sdr_rd_en
//     没有额外打拍、没有额外延迟，对现有显示链路是零影响；
//   - 只有进入缩略图视图时才把读口交给按坐标取像一侧。
//
// 换手隔离窗：
//   两种视图切换时，先在当前占用方“连续静默” QUIET_CYCLES 个 mem 时钟之后
//   才切换归属。控制器单次读延迟只有十几拍，连续 64 拍没有新请求即可保证在途
//   读全部返回原归属，不会出现“跨模式串一个像素”。
//
//   - 全屏 → 缩略图：顶层先把帧读请求/读使能关掉，帧读 FIFO 填满后
//     frame_fifo_read 停在 S_CHECK_FIFO，frw_rd_en 拉低，本模块等满静默窗后
//     交给缩略图取像；
//   - 缩略图 → 全屏：顶层先把缩略图 mem_enable 关掉（mem_idle=0 时天然关掉），
//     thumb_rd_req 拉低，等满静默窗后交还帧读。
// =============================================================================
module sdram_rd_arbiter #(
    parameter integer ADDR_WIDTH   = 21,
    parameter integer QUIET_CYCLES = 64,   // 换手前当前占用方需连续静默的周期数
    parameter integer SYNC_STAGES  = 2
) (
    input  wire                    clk,             // ext_mem_clk
    input  wire                    rst,             // 高有效复位

    input  wire                    view_mode_req,   // 来自 video 域（异步电平，1=缩略图）

    // frame_read_write 侧
    input  wire                    frw_rd_en,
    input  wire [ADDR_WIDTH-1:0]   frw_rd_addr,
    output wire                    frw_rd_valid,    // 回到 frame_read_write 的 Sdr_rd_en

    // 缩略图取像侧
    input  wire                    thumb_rd_req,
    input  wire [ADDR_WIDTH-1:0]   thumb_rd_addr,
    output wire                    thumb_rd_valid,
    output wire [31:0]             thumb_rd_dout,

    // 到 sdram U3
    output wire                    app_rd_en,
    output wire [ADDR_WIDTH-1:0]   app_rd_addr,
    input  wire                    sdr_rd_en,       // U3 的 Sdr_rd_en
    input  wire [31:0]             sdr_rd_dout,     // U3 的 Sdr_rd_dout

    // 状态输出
    output reg                     mode_active,     // 1=缩略图取像占用读口
    output wire                    mem_idle         // 1=无待切换（换手窗口已结束）
);

    reg [SYNC_STAGES-1:0] vm_sync;
    reg [31:0]            quiet_cnt;

    wire vm_level  = vm_sync[SYNC_STAGES-1];
    wire pending   = (vm_level != mode_active);
    // 当前占用方的请求（组合）
    wire owner_req = mode_active ? thumb_rd_req : frw_rd_en;

    // 换手窗口内 mem_idle=0，两侧的请求闸门都会被顶层关掉
    assign mem_idle = ~pending;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vm_sync     <= {SYNC_STAGES{1'b0}};
            quiet_cnt   <= 32'd0;
            mode_active <= 1'b0;
        end else begin
            vm_sync <= {vm_sync[SYNC_STAGES-2:0], view_mode_req};

            if (!pending) begin
                quiet_cnt <= 32'd0;
            end else if (!owner_req) begin
                if (quiet_cnt >= (QUIET_CYCLES - 1)) begin
                    quiet_cnt   <= 32'd0;
                    mode_active <= vm_level;      // 静默窗结束才切换归属
                end else begin
                    quiet_cnt <= quiet_cnt + 32'd1;
                end
            end else begin
                quiet_cnt <= 32'd0;              // 占用方还在发请求，重新计时
            end
        end
    end

    // 读请求：全屏模式下就是 frame_read_write 的纯组合直通；
    // 缩略图模式下交给按坐标取像一侧。
    assign app_rd_en   = mode_active ? thumb_rd_req  : frw_rd_en;
    assign app_rd_addr = mode_active ? thumb_rd_addr : frw_rd_addr;

    // 读回数据：按当前归属分发。换手只在静默窗之后发生，因此在途数据一定
    // 回到“发起它的那一侧”。
    //
    // 注意：Sdr_rd_en 与 Sdr_rd_dout 是“同拍有效”的（原工程直接把这两根线
    // 接到 rfifo 的 we/di）。所以两侧的数据都必须与各自的 valid 同拍输出，
    // 这里绝不能再给 thumb 数据打一拍，否则会整体错位一个像素。
    assign frw_rd_valid   = mode_active ? 1'b0 : sdr_rd_en;
    assign thumb_rd_valid = mode_active ? sdr_rd_en : 1'b0;
    assign thumb_rd_dout  = sdr_rd_dout;

endmodule
