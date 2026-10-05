`timescale 1ns/1ps

// =============================================================================
// 第十三讲移植：KEY1 短按 / 长按判别消抖
//
// 现有工程用 sd_card_bmp.v 内部的 key_press_debounce 处理 KEY1。那个模块在
// “按下”瞬间就发 press_pulse，无法区分短按和长按；第十三讲需要一个进入
// 缩略图视图的入口，又不能在长按时误触发“下一张”，因此这里做一个短按/长按
// 判别版本：
//   - 短按：松开时输出 press_pulse 一拍，语义仍然是原有的“下一张”；
//   - 长按：按住达到 HOLD_MS 时输出 hold_pulse 一拍（用于切换视图），
//           松开时不再输出 press_pulse。
//
// 原有 key_press_debounce（sd_card_bmp.v 内部）保持不动，仍给 KEY2 使用，
// 因此 KEY2 的“短按自动轮播 / 长按上一张”行为完全不变。
// =============================================================================
module key_press_hold #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer HOLD_MS     = 1000
)(
    input  wire clk,
    input  wire rst,               // 高有效复位
    input  wire button_in,         // 低有效按键
    output reg  press_pulse,       // 短按脉冲（松开时一拍）
    output reg  hold_pulse,        // 长按脉冲（达到门限时一拍）
    output reg  button_stable_out  // 1=松开, 0=按下
);
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer HOLD_CYCLES     = (CLK_FREQ_HZ / 1000) * HOLD_MS;

    reg        sync0;
    reg        sync1;
    reg        stable;
    reg        stable_d;
    reg [31:0] deb_cnt;
    reg [31:0] hold_cnt;
    reg        hold_fired;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0             <= 1'b1;
            sync1             <= 1'b1;
            stable            <= 1'b1;
            stable_d          <= 1'b1;
            deb_cnt           <= 32'd0;
            hold_cnt          <= 32'd0;
            hold_fired        <= 1'b0;
            press_pulse       <= 1'b0;
            hold_pulse        <= 1'b0;
            button_stable_out <= 1'b1;
        end else begin
            sync0      <= button_in;
            sync1      <= sync0;
            stable_d   <= stable;
            press_pulse <= 1'b0;
            hold_pulse  <= 1'b0;

            // 1) 普通消抖，确认稳定电平
            if (sync1 == stable) begin
                deb_cnt <= 32'd0;
            end else if (deb_cnt >= (DEBOUNCE_CYCLES - 1)) begin
                deb_cnt           <= 32'd0;
                stable            <= sync1;
                button_stable_out <= sync1;
            end else begin
                deb_cnt <= deb_cnt + 32'd1;
            end

            // 2) 按下沿：清长按状态；稳定按下期间累计长按时间
            if (!stable && stable_d) begin
                hold_cnt   <= 32'd0;
                hold_fired <= 1'b0;
            end else if (!stable) begin
                if (hold_cnt < HOLD_CYCLES)
                    hold_cnt <= hold_cnt + 32'd1;
                if ((hold_cnt == (HOLD_CYCLES - 1)) && !hold_fired) begin
                    hold_fired <= 1'b1;
                    hold_pulse <= 1'b1;
                end
            end

            // 3) 松开沿：没触发过长按才算短按
            if (stable && !stable_d && !hold_fired)
                press_pulse <= 1'b1;
        end
    end

endmodule
