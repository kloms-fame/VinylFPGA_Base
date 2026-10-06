`timescale 1ns/1ps
// =============================================================================
// tb_s2_boot_guard —— S2 上电跳过源保护测试
//
// 复现的真实场景：J2 上有拨码停在“0”位（或编码器静止相位为低、按键被按住），
// 上电时 debounce_filter / sync_bit 的初值都是 1，会在消抖时间到后报一次
// “变化”，从而在 ui_event_bus 上产生一次事件。
//
// 期望：这类“上电消抖收敛”不算用户操作，ui_ev_valid 在保护窗内必须为 0；
//       否则 boot_layer 会在上电瞬间被判成“用户跳过”，Logo 直接黑屏。
//
// 说明：为了仿真速度，这里把时钟频率与消抖/保护窗按 1000:1 等比缩小
//       （CLK_FREQ_HZ=50_000，DEBOUNCE_CYCLES=400，保护窗=25000 拍）。
// =============================================================================
module tb_s2_boot_guard;

    localparam integer CLK_HZ     = 50_000;
    localparam integer DEBOUNCE   = 400;      // ≈ 8 ms @50MHz 的 1/1000
    localparam integer AB_STABLE  = 50;
    localparam integer GUARD      = CLK_HZ / 2;   // ≈ 500 ms 的 1/1000

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst_n = 1'b0;
    // J2 输入：按键/按压全部释放(1)；拨码故意让 DIP2/DIP5 停在 0 位
    reg [11:0]  exp_key_n     = 12'hFFF;
    reg [5:0]   exp_dip_n     = 6'b110111;   // bit1=0, bit4=0 → 上电会报变化
    reg         exp_enc1_a    = 1'b1;        // 编码器静止相位：A=0 也常见
    reg         exp_enc1_b    = 1'b0;
    reg         exp_enc1_sw_n = 1'b1;
    reg         exp_enc2_a    = 1'b1;
    reg         exp_enc2_b    = 1'b1;
    reg         exp_enc2_sw_n = 1'b1;
    reg         exp_ir_rx     = 1'b1;
    reg         key1 = 1'b1, key2 = 1'b1, key3 = 1'b1;
    reg         sw1  = 1'b1, sw2  = 1'b1, sw3  = 1'b1, sw4  = 1'b1;

    wire [3:0]  exp_led_n;
    wire        exp_ws2812_data;
    wire [5:0]  exp_ext_o;
    wire        board_buzzer_n;
    wire        uart_tx;
    wire        ui_ev_valid;
    reg         boot_active = 1'b1;

    expansion_integration #(
        .CLK_FREQ_HZ      (CLK_HZ),
        .BAUD_RATE        (115_200),
        .DEBOUNCE_CYCLES  (DEBOUNCE),
        .AB_STABLE_CYCLES (AB_STABLE),
        .IR_CLK_FREQ_HZ   (CLK_HZ),
        .ECHO_ENABLE      (1'b0),
        .BUZZER_ENABLE    (1'b0)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .exp_key_n (exp_key_n), .exp_dip_n (exp_dip_n),
        .exp_enc1_a (exp_enc1_a), .exp_enc1_b (exp_enc1_b), .exp_enc1_sw_n (exp_enc1_sw_n),
        .exp_enc2_a (exp_enc2_a), .exp_enc2_b (exp_enc2_b), .exp_enc2_sw_n (exp_enc2_sw_n),
        .exp_ir_rx (exp_ir_rx),
        .key1 (key1), .key2 (key2), .key3 (key3),
        .sw1 (sw1), .sw2 (sw2), .sw3 (sw3), .sw4 (sw4),
        .exp_led_n (exp_led_n), .exp_ws2812_data (exp_ws2812_data), .exp_ext_o (exp_ext_o),
        .board_buzzer_n (board_buzzer_n), .uart_tx (uart_tx),
        .media_status (24'd0), .ui_ev_valid (ui_ev_valid), .boot_active (boot_active)
    );

    integer guard_pulses = 0;
    integer total_pulses = 0;
    integer cycle_cnt    = 0;

    always @(posedge clk) if (rst_n) begin
        cycle_cnt = cycle_cnt + 1;
        if (ui_ev_valid) begin
            total_pulses = total_pulses + 1;
            if (cycle_cnt < GUARD)
                guard_pulses = guard_pulses + 1;
        end
    end

    initial begin
        repeat (20) @(negedge clk);
        rst_n = 1'b1;

        // 覆盖消抖收敛(≈DEBOUNCE 拍)与整个保护窗
        repeat (GUARD + 4 * DEBOUNCE) @(negedge clk);

        if (guard_pulses != 0)
            $fatal(1, "FAIL power-on settling produced %0d skip event(s) inside guard window (total=%0d)",
                   guard_pulses, total_pulses);
        $display("PASS no power-on skip event inside guard window (cycles=%0d, total=%0d)",
                 cycle_cnt, total_pulses);

        // 保护窗之后，真实用户动作必须仍然能上报（此处用 DIP 之外的事件源验证通路）
        key1 = 1'b0;                       // 按下母板 KEY（会经 board_key_fall_pulse）
        repeat (4 * DEBOUNCE) @(negedge clk);
        if (total_pulses == 0)
            $fatal(1, "FAIL real key press after guard produced no event");
        $display("PASS real key press after guard still reported (total=%0d)", total_pulses);
        $display("TEST_PASS s2_boot_guard");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "FAIL timeout in tb_s2_boot_guard");
    end

endmodule
