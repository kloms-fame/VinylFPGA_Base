`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// sync_2ff —— 单比特电平两级同步器
// 第六讲优化二配套（教程 2.6.2 原样移植）
//
// 用于把 Sdr_init_done 这类"单比特、慢变"电平从 ext_mem_clk 域同步到
// sd_card_clk 域。
// 合同边界：只适用于单比特慢变信号；多位总线禁止逐位 2FF。
// RESET_VAL：复位输出电平，按信号空闲态选择。
// -----------------------------------------------------------------------------
module sync_2ff #(
    parameter RESET_VAL = 1'b0   // 复位输出电平=信号空闲态
)(
    input  wire clk,       // 目的时钟域
    input  wire rst_n,     // 目的域低有效复位
    input  wire async_in,  // 异步输入（源域电平）
    output wire sync_out   // 目的域同步后的电平
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= RESET_VAL;
            s2 <= RESET_VAL;
        end else begin
            s1 <= async_in;
            s2 <= s1;
        end
    end

    assign sync_out = s2;

endmodule
