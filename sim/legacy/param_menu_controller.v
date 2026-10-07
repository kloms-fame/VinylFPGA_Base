`timescale 1ns/1ps

// =============================================================================
// 第十四讲：亮度/对比度参数菜单控制器
//
// 教程的真实完赛模块使用 KEY4 单击调音量、长按调轮播周期；本工程只有
// KEY1/KEY2 两个物理按键，因此教程 2.4 明确允许“用组合键”完成参数入口。
// 本模块保留教程的“消抖 + 按住计时 + 松开分支 + case LUT”思路，做成：
//
//   KEY1 + KEY2 同时按住 1s 后松开：进入 / 退出参数菜单
//   菜单内 KEY1 短按：亮度 +1 档；KEY1 长按：亮度 -1 档
//   菜单内 KEY2 短按：对比度 +1 档；KEY2 长按：对比度 -1 档
//   菜单内 10s 无操作：自动退出
//
// 组合键按下期间，两路输出都强制为高（松开态），所以原有 KEY1 下一张 /
// 缩略图长按和 KEY2 自动轮播 / 上一张不会看到这次组合按压。菜单外本模块
// 对两路按键是透明直通，原有功能保持不变。
// =============================================================================
module param_menu_controller #(
    parameter integer CLK_FREQ_HZ      = 100_000_000,
    parameter integer DEBOUNCE_MS      = 20,
    parameter integer COMBO_HOLD_MS    = 1000,
    parameter integer LONG_HOLD_MS     = 1000,
    parameter integer MENU_TIMEOUT_MS  = 10000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key1_n,
    input  wire        key2_n,

    // 送给原有按键链路（低有效，菜单/组合键期间强制为高）
    output wire        key1_out_n,
    output wire        key2_out_n,

    output reg  [7:0]  cfg_brightness,
    output reg  [7:0]  cfg_contrast,
    output reg         cfg_update_valid,
    output reg         menu_event,
    output reg  [1:0]  menu_kind,     // 0 = brightness, 1 = contrast
    output reg  [3:0]  menu_level,
    output reg         menu_active
);
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COMBO_CYCLES    = (CLK_FREQ_HZ / 1000) * COMBO_HOLD_MS;
    localparam integer LONG_CYCLES     = (CLK_FREQ_HZ / 1000) * LONG_HOLD_MS;
    localparam integer TIMEOUT_CYCLES  = (CLK_FREQ_HZ / 1000) * MENU_TIMEOUT_MS;

    localparam integer BRIGHT_STEPS = 5;
    localparam integer CONTRAST_STEPS = 5;

    // TD 不认 initial 初始化的 ROM 数组，档位表继续使用教程中的 case 函数。
    function [7:0] brightness_lut;
        input [3:0] level;
        begin
            case (level)
                4'd0:    brightness_lut = 8'd0;
                4'd1:    brightness_lut = 8'd64;
                4'd2:    brightness_lut = 8'd128;
                4'd3:    brightness_lut = 8'd192;
                default: brightness_lut = 8'd255;
            endcase
        end
    endfunction

    function [7:0] contrast_lut;
        input [3:0] level;
        begin
            case (level)
                4'd0:    contrast_lut = 8'd0;
                4'd1:    contrast_lut = 8'd64;
                4'd2:    contrast_lut = 8'd128;
                4'd3:    contrast_lut = 8'd192;
                default: contrast_lut = 8'd255;
            endcase
        end
    endfunction

    function [3:0] brightness_level;
        input [7:0] value;
        begin
            case (value)
                8'd0:   brightness_level = 4'd0;
                8'd64:  brightness_level = 4'd1;
                8'd128: brightness_level = 4'd2;
                8'd192: brightness_level = 4'd3;
                default: brightness_level = 4'd4;
            endcase
        end
    endfunction

    function [3:0] contrast_level;
        input [7:0] value;
        begin
            case (value)
                8'd0:   contrast_level = 4'd0;
                8'd64:  contrast_level = 4'd1;
                8'd128: contrast_level = 4'd2;
                8'd192: contrast_level = 4'd3;
                default: contrast_level = 4'd4;
            endcase
        end
    endfunction

    // 两级同步 + 20ms 消抖
    reg [1:0] key1_sync;
    reg [1:0] key2_sync;
    reg       key1_raw;
    reg       key2_raw;
    reg       key1_stable;
    reg       key2_stable;
    // 100MHz、20ms 消抖需要 2_000_000 个周期，20 位计数器最大只能到
    // 1_048_575，会导致 stable 状态永远无法更新。这里必须使用 32 位。
    reg [31:0] key1_deb_cnt;
    reg [31:0] key2_deb_cnt;

    // 组合键判定与菜单内按住计时
    reg [31:0] combo_cnt;
    reg        combo_long;
    reg [31:0] key1_hold_cnt;
    reg [31:0] key2_hold_cnt;
    reg        key1_long;
    reg        key2_long;
    reg        menu_entry_lock;
    reg [31:0] menu_idle_cnt;
    reg [3:0]  lvl_next;

    wire combo_pressed = (key1_sync[1] == 1'b0) && (key2_sync[1] == 1'b0);
    wire key1_pressed  = (key1_stable == 1'b0);
    wire key2_pressed  = (key2_stable == 1'b0);

    // 组合键期间和菜单期间都将原有按键链路置为松开，避免误触发。
    assign key1_out_n = (combo_pressed || menu_active) ? 1'b1 : key1_sync[1];
    assign key2_out_n = (combo_pressed || menu_active) ? 1'b1 : key2_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_sync        <= 2'b11;
            key2_sync        <= 2'b11;
            key1_raw         <= 1'b1;
            key2_raw         <= 1'b1;
            key1_stable      <= 1'b1;
            key2_stable      <= 1'b1;
            key1_deb_cnt     <= 32'd0;
            key2_deb_cnt     <= 32'd0;
            combo_cnt        <= 32'd0;
            combo_long       <= 1'b0;
            key1_hold_cnt    <= 32'd0;
            key2_hold_cnt    <= 32'd0;
            key1_long        <= 1'b0;
            key2_long        <= 1'b0;
            menu_entry_lock  <= 1'b0;
            menu_idle_cnt    <= 32'd0;
            cfg_brightness   <= 8'd255;
            cfg_contrast     <= 8'd128;
            cfg_update_valid <= 1'b0;
            menu_event       <= 1'b0;
            menu_kind        <= 2'd0;
            menu_level       <= 4'd4;
            menu_active      <= 1'b0;
        end else begin
            cfg_update_valid <= 1'b0;
            menu_event       <= 1'b0;

            key1_sync <= {key1_sync[0], key1_n};
            key2_sync <= {key2_sync[0], key2_n};

            // 普通按键消抖
            if (key1_sync[1] != key1_raw) begin
                if (key1_deb_cnt >= DEBOUNCE_CYCLES - 1) begin
                    key1_raw    <= key1_sync[1];
                    key1_stable <= key1_sync[1];
                    key1_deb_cnt <= 32'd0;
                end else begin
                    key1_deb_cnt <= key1_deb_cnt + 1'b1;
                end
            end else begin
                key1_deb_cnt <= 32'd0;
            end

            if (key2_sync[1] != key2_raw) begin
                if (key2_deb_cnt >= DEBOUNCE_CYCLES - 1) begin
                    key2_raw    <= key2_sync[1];
                    key2_stable <= key2_sync[1];
                    key2_deb_cnt <= 32'd0;
                end else begin
                    key2_deb_cnt <= key2_deb_cnt + 1'b1;
                end
            end else begin
                key2_deb_cnt <= 32'd0;
            end

            // 组合键按住计时：达到门限后只置标记，松开时统一切换菜单。
            if (combo_pressed) begin
                if (combo_cnt < COMBO_CYCLES)
                    combo_cnt <= combo_cnt + 1'b1;
                if (combo_cnt >= COMBO_CYCLES)
                    combo_long <= 1'b1;
            end else begin
                if (combo_long) begin
                    menu_active  <= ~menu_active;
                    menu_entry_lock <= ~menu_active;
                    menu_event   <= 1'b1;
                    menu_kind    <= 2'd0;
                    menu_level   <= brightness_level(cfg_brightness);
                end
                combo_cnt  <= 32'd0;
                combo_long <= 1'b0;
            end

            // 菜单内按键短按/长按分支。长按只在松开时执行一次，避免重复。
            if (menu_active && !combo_pressed && !menu_entry_lock) begin
                if (key1_pressed) begin
                    if (key1_hold_cnt < LONG_CYCLES)
                        key1_hold_cnt <= key1_hold_cnt + 1'b1;
                    if (key1_hold_cnt >= LONG_CYCLES)
                        key1_long <= 1'b1;
                end else begin
                    if (key1_long) begin
                        lvl_next = brightness_level(cfg_brightness);
                        lvl_next = (lvl_next == 4'd0) ? BRIGHT_STEPS-1 : lvl_next - 1'b1;
                        cfg_brightness   <= brightness_lut(lvl_next);
                        cfg_update_valid <= 1'b1;
                        menu_event       <= 1'b1;
                        menu_kind        <= 2'd0;
                        menu_level       <= lvl_next;
                    end else if (key1_hold_cnt > 0) begin
                        lvl_next = brightness_level(cfg_brightness);
                        lvl_next = (lvl_next == BRIGHT_STEPS-1) ? 4'd0 : lvl_next + 1'b1;
                        cfg_brightness   <= brightness_lut(lvl_next);
                        cfg_update_valid <= 1'b1;
                        menu_event       <= 1'b1;
                        menu_kind        <= 2'd0;
                        menu_level       <= lvl_next;
                    end
                    key1_hold_cnt <= 32'd0;
                    key1_long     <= 1'b0;
                end

                if (key2_pressed) begin
                    if (key2_hold_cnt < LONG_CYCLES)
                        key2_hold_cnt <= key2_hold_cnt + 1'b1;
                    if (key2_hold_cnt >= LONG_CYCLES)
                        key2_long <= 1'b1;
                end else begin
                    if (key2_long) begin
                        lvl_next = contrast_level(cfg_contrast);
                        lvl_next = (lvl_next == 4'd0) ? CONTRAST_STEPS-1 : lvl_next - 1'b1;
                        cfg_contrast     <= contrast_lut(lvl_next);
                        cfg_update_valid <= 1'b1;
                        menu_event       <= 1'b1;
                        menu_kind        <= 2'd1;
                        menu_level       <= lvl_next;
                    end else if (key2_hold_cnt > 0) begin
                        lvl_next = contrast_level(cfg_contrast);
                        lvl_next = (lvl_next == CONTRAST_STEPS-1) ? 4'd0 : lvl_next + 1'b1;
                        cfg_contrast     <= contrast_lut(lvl_next);
                        cfg_update_valid <= 1'b1;
                        menu_event       <= 1'b1;
                        menu_kind        <= 2'd1;
                        menu_level       <= lvl_next;
                    end
                    key2_hold_cnt <= 32'd0;
                    key2_long     <= 1'b0;
                end

                // 菜单无操作自动退出，避免一直吞掉原有按键。
                if (key1_pressed || key2_pressed || key1_hold_cnt != 0 || key2_hold_cnt != 0)
                    menu_idle_cnt <= 32'd0;
                else if (menu_idle_cnt < TIMEOUT_CYCLES)
                    menu_idle_cnt <= menu_idle_cnt + 1'b1;
                else begin
                    menu_active  <= 1'b0;
                    menu_event   <= 1'b1;
                    menu_idle_cnt <= 32'd0;
                end
            end else if (menu_active && combo_pressed) begin
                // 菜单内再次双键长按用于退出；组合键按住期间不能累计成
                // KEY1/KEY2 的长按，否则松开后会误把亮度/对比度减一档。
                key1_hold_cnt <= 32'd0;
                key2_hold_cnt <= 32'd0;
                key1_long     <= 1'b0;
                key2_long     <= 1'b0;
                menu_idle_cnt <= 32'd0;
            end else if (menu_active && menu_entry_lock) begin
                // 进入菜单时组合键的消抖状态还会保持“按下”约 20ms，
                // 必须等两键都回到稳定松开后再开始识别菜单按键。
                key1_hold_cnt <= 32'd0;
                key2_hold_cnt <= 32'd0;
                key1_long     <= 1'b0;
                key2_long     <= 1'b0;
                menu_idle_cnt <= 32'd0;
                if (key1_stable && key2_stable)
                    menu_entry_lock <= 1'b0;
            end else begin
                key1_hold_cnt <= 32'd0;
                key2_hold_cnt <= 32'd0;
                key1_long     <= 1'b0;
                key2_long     <= 1'b0;
                menu_idle_cnt <= 32'd0;
            end
        end
    end
endmodule
