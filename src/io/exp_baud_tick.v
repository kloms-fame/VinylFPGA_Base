`ifndef EXP_EXP_BAUD_TICK_V
`define EXP_EXP_BAUD_TICK_V
// =============================================================================
// exp_baud_tick —— 波特率节拍发生器（移植自 J2 标定工程 baud_tick.v）
//
// 与 J2 标定工程逐字一致的算法，仅把模块改名为 exp_ 前缀，避免与后续
// 主链路串口模块重名。默认 50 MHz / 115200 8N1。
// =============================================================================
module exp_baud_tick #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick
);
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    reg [31:0] baud_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 32'd0;
            tick     <= 1'b0;
        end else if (baud_cnt == CLKS_PER_BIT - 1) begin
            baud_cnt <= 32'd0;
            tick     <= 1'b1;
        end else begin
            baud_cnt <= baud_cnt + 1'b1;
            tick     <= 1'b0;
        end
    end
endmodule
`endif
