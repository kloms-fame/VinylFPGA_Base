`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// reset_sync —— 复位同步释放
// 第六讲必做优化一（教程 2.6.1 原样移植）
//
// 外部低有效复位"异步生效、同步释放"：
//   - 复位来了立刻压下去（异步分支），不等时钟；
//   - 复位走了，经两级触发器在本域时钟沿上释放，保证全域寄存器在同一拍
//     离开复位，消除释放瞬间的 recovery/removal 竞争与亚稳态。
// 每个时钟域配一个本模块实例。
// -----------------------------------------------------------------------------
module reset_sync (
    input  wire clk,         // 本时钟域
    input  wire ext_rst_n,   // 外部异步低有效复位
    output wire rst_n_sync   // 本域使用的复位：异步压下、同步释放
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= 1'b1;
            s2 <= s1;
        end
    end

    assign rst_n_sync = s2;

endmodule
