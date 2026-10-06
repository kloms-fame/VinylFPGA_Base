`timescale 1ns/1ps

// =============================================================================
// S3 集成冒烟：真实 J2 物理输入 -> 选曲控制脉冲
//
// 链路：exp_enc*/exp_key_n
//         -> expansion_io_hub（同步/消抖/正交解码）
//         -> ui_event_bus（统一事件编码）
//         -> ui_event_bridge（clk 域选曲事件解码 -> 电平翻转）
//         -> browse_fsm（sd 域同步/边沿 -> 控制脉冲）
//
// 目的：证明"EC1 旋转/方向键驱动当前封面选择"在真实输入驱动下整链打通，
// 而不只是 browse_fsm 单模块成立。消抖/正交稳定常数在本测试台按比例缩小，
// 只影响仿真时长，不影响方向判定与事件语义。
// =============================================================================
module tb_s3_browse_integration;
    localparam integer DEBOUNCE_CYCLES  = 40;
    localparam integer AB_STABLE_CYCLES = 40;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer errors = 0;

    always #5 clk = ~clk;   // 100 MHz

    // ---- J2 物理输入 ----
    reg [11:0] exp_key_n = 12'hFFF;
    reg [5:0]  exp_dip_n = 6'h01;
    reg        exp_enc1_a = 1'b1;
    reg        exp_enc1_b = 1'b1;
    reg        exp_enc1_sw_n = 1'b1;
    reg        exp_enc2_a = 1'b1, exp_enc2_b = 1'b1, exp_enc2_sw_n = 1'b1;
    reg        exp_ir_rx = 1'b1;
    reg        key1 = 1'b1, key2 = 1'b1, key3 = 1'b1;
    reg        sw1 = 1'b1, sw2 = 1'b1, sw3 = 1'b1, sw4 = 1'b1;

    wire [3:0]  exp_led_n;
    wire        exp_ws2812_data;
    wire [5:0]  exp_ext_o;
    wire        board_buzzer_n;
    wire        uart_tx;
    wire        ui_ev_valid;
    wire        ui_event_valid;
    wire [3:0]  ui_event_code;
    wire [15:0] ui_event_arg;
    wire [15:0] ui_event_aux;

    expansion_integration #(
        .CLK_FREQ_HZ      (2_000_000),
        .BAUD_RATE        (115_200),
        .DEBOUNCE_CYCLES  (DEBOUNCE_CYCLES),
        .AB_STABLE_CYCLES (AB_STABLE_CYCLES),
        .IR_CLK_FREQ_HZ   (2_000_000),
        .ECHO_ENABLE      (1'b0),
        .BUZZER_ENABLE    (1'b0)
    ) u_exp (
        .clk             (clk),
        .rst_n           (rst_n),
        .exp_key_n       (exp_key_n),
        .exp_dip_n       (exp_dip_n),
        .exp_enc1_a      (exp_enc1_a),
        .exp_enc1_b      (exp_enc1_b),
        .exp_enc1_sw_n   (exp_enc1_sw_n),
        .exp_enc2_a      (exp_enc2_a),
        .exp_enc2_b      (exp_enc2_b),
        .exp_enc2_sw_n   (exp_enc2_sw_n),
        .exp_ir_rx       (exp_ir_rx),
        .key1            (key1),
        .key2            (key2),
        .key3            (key3),
        .sw1             (sw1),
        .sw2             (sw2),
        .sw3             (sw3),
        .sw4             (sw4),
        .exp_led_n       (exp_led_n),
        .exp_ws2812_data (exp_ws2812_data),
        .exp_ext_o       (exp_ext_o),
        .board_buzzer_n  (board_buzzer_n),
        .uart_tx         (uart_tx),
        .ui_ev_valid     (ui_ev_valid),
        .boot_active     (1'b0),
        .media_status    (24'd0),
        .ui_event_valid  (ui_event_valid),
        .ui_event_code   (ui_event_code),
        .ui_event_arg    (ui_event_arg),
        .ui_event_aux    (ui_event_aux)
    );

    wire ev_prev_tgl, ev_next_tgl, ev_confirm_tgl, ev_mode_tgl;

    ui_event_bridge u_bridge (
        .clk         (clk),
        .rst_n       (rst_n),
        .ev_valid    (ui_event_valid),
        .ev_code     (ui_event_code),
        .ev_arg      (ui_event_arg),
        .ev_aux      (ui_event_aux),
        .prev_tgl    (ev_prev_tgl),
        .next_tgl    (ev_next_tgl),
        .confirm_tgl (ev_confirm_tgl),
        .mode_tgl    (ev_mode_tgl)
    );

    reg  view_mode = 1'b0;
    wire fs_next, fs_prev, thumb_right, thumb_left, thumb_confirm, thumb_mode;

    browse_fsm #(.J2_BROWSE_ENABLE(1'b1)) u_browse (
        .clk            (clk),
        .rst_n          (rst_n),
        .ev_prev_tgl    (ev_prev_tgl),
        .ev_next_tgl    (ev_next_tgl),
        .ev_confirm_tgl (ev_confirm_tgl),
        .ev_mode_tgl    (ev_mode_tgl),
        .mb_next        (1'b0),
        .mb_mode        (1'b0),
        .mb_left        (1'b0),
        .mb_confirm     (1'b0),
        .view_mode      (view_mode),
        .mode_play      (1'b0),
        .fs_next        (fs_next),
        .fs_prev        (fs_prev),
        .thumb_right    (thumb_right),
        .thumb_left     (thumb_left),
        .thumb_confirm  (thumb_confirm),
        .thumb_mode     (thumb_mode)
    );

    reg [4:0] c_next, c_prev, c_right, c_left, c_conf, c_mode;
    always @(posedge clk) begin
        if (rst_n) begin
            if (fs_next)       c_next <= c_next + 1'b1;
            if (fs_prev)       c_prev <= c_prev + 1'b1;
            if (thumb_right)   c_right <= c_right + 1'b1;
            if (thumb_left)    c_left <= c_left + 1'b1;
            if (thumb_confirm) c_conf <= c_conf + 1'b1;
            if (thumb_mode)    c_mode <= c_mode + 1'b1;
        end
    end

    task clear_counts;
        begin c_next=0; c_prev=0; c_right=0; c_left=0; c_conf=0; c_mode=0; end
    endtask

    // 正交一圈：顺时针(dir=0/next) 用 11->10->00->01->11；逆时针(dir=1/prev) 反向。
    task quad_turn;
        input dir;                 // 0=顺时针(下一张)，1=逆时针(上一张)
        begin
            if (!dir) begin
                exp_enc1_a=1'b1; exp_enc1_b=1'b0; settle();
                exp_enc1_a=1'b0; exp_enc1_b=1'b0; settle();
                exp_enc1_a=1'b0; exp_enc1_b=1'b1; settle();
                exp_enc1_a=1'b1; exp_enc1_b=1'b1; settle();
            end else begin
                exp_enc1_a=1'b0; exp_enc1_b=1'b1; settle();
                exp_enc1_a=1'b0; exp_enc1_b=1'b0; settle();
                exp_enc1_a=1'b1; exp_enc1_b=1'b0; settle();
                exp_enc1_a=1'b1; exp_enc1_b=1'b1; settle();
            end
        end
    endtask

    task settle;
        begin repeat (AB_STABLE_CYCLES + 6) @(posedge clk); end
    endtask

    task key_press;
        input integer idx;
        begin
            @(negedge clk); exp_key_n[idx] = 1'b0;
            repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);
            repeat (14) @(posedge clk);
            @(negedge clk); exp_key_n[idx] = 1'b1;
            repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);
        end
    endtask

    task enc_sw_press;
        begin
            @(negedge clk); exp_enc1_sw_n = 1'b0;
            repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);
            repeat (14) @(posedge clk);
            @(negedge clk); exp_enc1_sw_n = 1'b1;
            repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);
        end
    endtask

    task check;
        input [4:0] en, ep, er, el, ec, em;
        input [8*30:1] name;
        begin
            // 事件链总延迟 = 正交稳定 + bus 打拍 + bridge 打拍 + fsm 3 级同步 + 输出，
            // 统一在这里等足，避免把本拍脉冲算到下一次动作的窗口里。
            repeat (30) @(posedge clk);
            if ({c_next,c_prev,c_right,c_left,c_conf,c_mode} !== {en,ep,er,el,ec,em}) begin
                $display("FAIL: %0s got {next,prev,right,left,conf,mode}={%0d,%0d,%0d,%0d,%0d,%0d}",
                         name, c_next, c_prev, c_right, c_left, c_conf, c_mode);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (6) @(posedge clk);
        exp_enc1_a = 1'b1; exp_enc1_b = 1'b1;
        repeat (AB_STABLE_CYCLES + 6) @(posedge clk);

        repeat (DEBOUNCE_CYCLES + AB_STABLE_CYCLES + 24) @(posedge clk);

        // ---- 全屏态：EC1 旋转直接切换封面 ----
        view_mode = 1'b0;
        clear_counts; quad_turn(1'b0); check(5'd1,5'd0,5'd0,5'd0,5'd0,5'd0, "fullscreen EC1 CW -> next");
        clear_counts; quad_turn(1'b1); check(5'd0,5'd1,5'd0,5'd0,5'd0,5'd0, "fullscreen EC1 CCW -> prev");
        clear_counts; enc_sw_press();   check(5'd0,5'd0,5'd0,5'd0,5'd0,5'd1, "fullscreen EC1 press -> enter grid");

        // ---- 缩略图态：EC1/方向键移动焦点、EC1/KEY02 确认 ----
        view_mode = 1'b1;
        repeat (4) @(posedge clk);
        clear_counts; quad_turn(1'b0); check(5'd0,5'd0,5'd1,5'd0,5'd0,5'd0, "thumbnail EC1 CW -> focus right");
        clear_counts; quad_turn(1'b1); check(5'd0,5'd0,5'd0,5'd1,5'd0,5'd0, "thumbnail EC1 CCW -> focus left");
        clear_counts; enc_sw_press();   check(5'd0,5'd0,5'd0,5'd0,5'd1,5'd0, "thumbnail EC1 press -> confirm");
        clear_counts; key_press(0);     check(5'd0,5'd0,5'd0,5'd1,5'd0,5'd0, "KEY01(left) -> focus left");
        clear_counts; key_press(2);     check(5'd0,5'd0,5'd1,5'd0,5'd0,5'd0, "KEY03(right) -> focus right");
        clear_counts; key_press(1);     check(5'd0,5'd0,5'd0,5'd0,5'd1,5'd0, "KEY02(mid) -> confirm");
        clear_counts; key_press(6);     check(5'd0,5'd0,5'd0,5'd0,5'd0,5'd1, "KEY07 -> toggle grid");

        // ---- 回到全屏：KEY04(上)/KEY05(下) 方向键也能切封面 ----
        view_mode = 1'b0;
        repeat (4) @(posedge clk);
        clear_counts; key_press(4);     check(5'd1,5'd0,5'd0,5'd0,5'd0,5'd0, "KEY05(down) -> next");
        clear_counts; key_press(3);     check(5'd0,5'd1,5'd0,5'd0,5'd0,5'd0, "KEY04(up) -> prev");

        if (errors == 0)
            $display("TEST_PASS s3_browse_integration");
        else
            $display("FAIL: tb_s3_browse_integration errors=%0d", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL: tb_s3_browse_integration timeout");
        $finish;
    end
endmodule
