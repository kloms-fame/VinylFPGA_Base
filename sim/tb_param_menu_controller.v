`timescale 1ns/1ps

// 第十四讲回归：组合键参数菜单控制器
module tb_param_menu_controller;
    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  key1_n = 1'b1;
    reg  key2_n = 1'b1;

    wire        key1_out_n;
    wire        key2_out_n;
    wire [7:0]  cfg_brightness;
    wire [7:0]  cfg_contrast;
    wire        cfg_update_valid;
    wire        menu_event;
    wire [1:0]  menu_kind;
    wire [3:0]  menu_level;
    wire        menu_active;

    integer errors = 0;

    param_menu_controller #(
        .CLK_FREQ_HZ     (1_000_000),
        .DEBOUNCE_MS     (1),
        .COMBO_HOLD_MS   (2),
        .LONG_HOLD_MS    (3),
        .MENU_TIMEOUT_MS (10)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .key1_n           (key1_n),
        .key2_n           (key2_n),
        .key1_out_n       (key1_out_n),
        .key2_out_n       (key2_out_n),
        .cfg_brightness   (cfg_brightness),
        .cfg_contrast     (cfg_contrast),
        .cfg_update_valid (cfg_update_valid),
        .menu_event       (menu_event),
        .menu_kind        (menu_kind),
        .menu_level       (menu_level),
        .menu_active      (menu_active)
    );

    always #500 clk = ~clk;  // 1 MHz

    task press_combo_enter;
        begin
            key1_n = 1'b0;
            key2_n = 1'b0;
            #2_200_000;
            key1_n = 1'b1;
            key2_n = 1'b1;
            #1_200_000;
        end
    endtask

    task press_key1_short;
        begin
            key1_n = 1'b0;
            #1_800_000;
            key1_n = 1'b1;
            #1_200_000;
        end
    endtask

    task press_key2_short;
        begin
            key2_n = 1'b0;
            #1_800_000;
            key2_n = 1'b1;
            #1_200_000;
        end
    endtask

    task press_key1_long;
        begin
            key1_n = 1'b0;
            #4_500_000;
            key1_n = 1'b1;
            #1_200_000;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // 菜单外 KEY1 直通，不能吞掉原有下一张按键。
        key1_n = 1'b0;
        #2_500;
        if (key1_out_n !== 1'b0 || key2_out_n !== 1'b1) begin
            $display("FAIL: KEY1 passthrough broken");
            errors = errors + 1;
        end
        key1_n = 1'b1;
        #1_200_000;

        // 组合键进入菜单，参数给默认值。
        press_combo_enter;
        if (!menu_active || cfg_brightness !== 8'd255 || cfg_contrast !== 8'd128) begin
            $display("FAIL: menu entry/default values wrong (active=%b b=%0d c=%0d)",
                     menu_active, cfg_brightness, cfg_contrast);
            errors = errors + 1;
        end

        // KEY1 短按：亮度 255 -> 0（5 档循环）
        press_key1_short;
        if (cfg_brightness !== 8'd0) begin
            $display("FAIL: brightness short press got %0d expected 0", cfg_brightness);
            errors = errors + 1;
        end

        // KEY2 短按：对比度 128 -> 192
        press_key2_short;
        if (cfg_contrast !== 8'd192) begin
            $display("FAIL: contrast short press got %0d expected 192", cfg_contrast);
            errors = errors + 1;
        end

        // KEY1 长按：亮度 0 -> 255（0 档向下一档回绕）
        press_key1_long;
        if (cfg_brightness !== 8'd255) begin
            $display("FAIL: brightness long press got %0d expected 255", cfg_brightness);
            errors = errors + 1;
        end

        // 菜单内两个按键输出必须保持松开态，不能泄漏给原链路。
        key1_n = 1'b0;
        #2_500;
        if (key1_out_n !== 1'b1) begin
            $display("FAIL: menu leaked KEY1 to original chain");
            errors = errors + 1;
        end
        key1_n = 1'b1;
        #1_200_000;

        // 组合键退出菜单
        press_combo_enter;
        if (menu_active) begin
            $display("FAIL: combo did not exit menu");
            errors = errors + 1;
        end

        // 菜单自动超时退出
        press_combo_enter;
        if (!menu_active) begin
            $display("FAIL: re-entry failed");
            errors = errors + 1;
        end
        #11_000_000;
        if (menu_active) begin
            $display("FAIL: menu timeout did not fire");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_param_menu_controller all checks passed");
        else
            $display("FAIL: tb_param_menu_controller errors=%0d", errors);

        $finish;
    end

    initial begin
        #60_000_000;
        $display("FAIL: tb_param_menu_controller timeout");
        $finish;
    end
endmodule
