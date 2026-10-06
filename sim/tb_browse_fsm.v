`timescale 1ns/1ps

// =============================================================================
// S3 回归：browse_fsm（主界面选歌事件适配层）
//
// 覆盖：
//   1) 全屏态：next->fs_next / prev->fs_prev / confirm->进入缩略图 / mode->切换视图
//   2) 缩略图态：next->焦点+1 / prev->焦点-1 / confirm->确认 / mode->退出视图
//   3) 母板兜底脉冲在全屏/缩略图两种视图下都仍然生效
//   4) J2_BROWSE_ENABLE=0 时事件侧被旁路，母板兜底不受影响（回滚开关）
//
// 事件以"电平翻转"进入（与 ui_event_bridge 一致），本测试台用 100 MHz 单
// 时钟同时驱动两侧，仍能验证 2FF 同步 + 边沿检测只产出单拍脉冲。
// 输出脉冲以计数法核对：目标脉冲恰好 1 拍，其余 5 路均为 0。
// =============================================================================
module tb_browse_fsm;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer errors = 0;

    always #5 clk = ~clk;   // 100 MHz

    // ---------------- J2 enable DUT ----------------
    reg  ev_prev_tgl = 1'b0, ev_next_tgl = 1'b0, ev_confirm_tgl = 1'b0, ev_mode_tgl = 1'b0;
    reg  mb_next = 1'b0, mb_mode = 1'b0, mb_left = 1'b0, mb_confirm = 1'b0;
    reg  view_mode = 1'b0;
    reg  mode_play = 1'b0;
    wire fs_next, fs_prev, thumb_right, thumb_left, thumb_confirm, thumb_mode;

    reg [3:0] c_fs_next, c_fs_prev, c_right, c_left, c_conf, c_mode;

    browse_fsm #(.J2_BROWSE_ENABLE(1'b1)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ev_prev_tgl    (ev_prev_tgl),
        .ev_next_tgl    (ev_next_tgl),
        .ev_confirm_tgl (ev_confirm_tgl),
        .ev_mode_tgl    (ev_mode_tgl),
        .mb_next        (mb_next),
        .mb_mode        (mb_mode),
        .mb_left        (mb_left),
        .mb_confirm     (mb_confirm),
        .view_mode      (view_mode),
        .mode_play      (mode_play),
        .fs_next        (fs_next),
        .fs_prev        (fs_prev),
        .thumb_right    (thumb_right),
        .thumb_left     (thumb_left),
        .thumb_confirm  (thumb_confirm),
        .thumb_mode     (thumb_mode)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (fs_next)       c_fs_next <= c_fs_next + 1'b1;
            if (fs_prev)       c_fs_prev <= c_fs_prev + 1'b1;
            if (thumb_right)   c_right   <= c_right   + 1'b1;
            if (thumb_left)    c_left    <= c_left    + 1'b1;
            if (thumb_confirm) c_conf    <= c_conf    + 1'b1;
            if (thumb_mode)    c_mode    <= c_mode    + 1'b1;
        end
    end

    // ---------------- J2 disabled DUT (rollback switch) ----------------
    reg  off_prev_tgl = 1'b0, off_next_tgl = 1'b0, off_confirm_tgl = 1'b0, off_mode_tgl = 1'b0;
    reg  off_mb_next = 1'b0, off_mb_mode = 1'b0, off_mb_left = 1'b0, off_mb_confirm = 1'b0;
    reg  off_view_mode = 1'b0;
    wire off_fs_next, off_fs_prev, off_right, off_left, off_conf, off_mode;
    reg [3:0] o_fs_next, o_fs_prev, o_right, o_left, o_conf, o_mode;

    browse_fsm #(.J2_BROWSE_ENABLE(1'b0)) dut_off (
        .clk            (clk),
        .rst_n          (rst_n),
        .ev_prev_tgl    (off_prev_tgl),
        .ev_next_tgl    (off_next_tgl),
        .ev_confirm_tgl (off_confirm_tgl),
        .ev_mode_tgl    (off_mode_tgl),
        .mb_next        (off_mb_next),
        .mb_mode        (off_mb_mode),
        .mb_left        (off_mb_left),
        .mb_confirm     (off_mb_confirm),
        .view_mode      (off_view_mode),
        .mode_play      (1'b0),
        .fs_next        (off_fs_next),
        .fs_prev        (off_fs_prev),
        .thumb_right    (off_right),
        .thumb_left     (off_left),
        .thumb_confirm  (off_conf),
        .thumb_mode     (off_mode)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (off_fs_next) o_fs_next <= o_fs_next + 1'b1;
            if (off_fs_prev) o_fs_prev <= o_fs_prev + 1'b1;
            if (off_right)   o_right   <= o_right   + 1'b1;
            if (off_left)    o_left    <= o_left    + 1'b1;
            if (off_conf)    o_conf    <= o_conf    + 1'b1;
            if (off_mode)    o_mode    <= o_mode    + 1'b1;
        end
    end

    task clear_counts;
        begin
            c_fs_next = 0; c_fs_prev = 0; c_right = 0;
            c_left = 0; c_conf = 0; c_mode = 0;
        end
    endtask

    task clear_off_counts;
        begin
            o_fs_next = 0; o_fs_prev = 0; o_right = 0;
            o_left = 0; o_conf = 0; o_mode = 0;
        end
    endtask

    task check_pulses;
        input [5:0] exp;                 // {fs_next,fs_prev,right,left,conf,mode}
        input [8*28:1] name;
        reg [5:0] got;
        begin
            got = {c_fs_next[0], c_fs_prev[0], c_right[0], c_left[0], c_conf[0], c_mode[0]};
            if (got !== exp) begin
                $display("FAIL: %0s pulses=%b expect=%b", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // 触发一路事件（电平翻转）并核对输出脉冲分布
    task fire_event;
        input [1:0] which;               // 0=prev 1=next 2=confirm 3=mode
        input [5:0] exp;
        input [8*28:1] name;
        begin
            clear_counts;
            @(negedge clk);
            case (which)
                2'd0: ev_prev_tgl    = ~ev_prev_tgl;
                2'd1: ev_next_tgl    = ~ev_next_tgl;
                2'd2: ev_confirm_tgl = ~ev_confirm_tgl;
                default: ev_mode_tgl = ~ev_mode_tgl;
            endcase
            repeat (12) @(posedge clk);
            check_pulses(exp, name);
        end
    endtask

    // 触发母板兜底脉冲（sd 域单拍）
    task fire_mpulse;
        input [1:0] which;               // 0=mb_next 1=mb_mode 2=mb_left 3=mb_confirm
        input [5:0] exp;
        input [8*28:1] name;
        begin
            clear_counts;
            @(negedge clk);
            case (which)
                2'd0: mb_next    = 1'b1;
                2'd1: mb_mode    = 1'b1;
                2'd2: mb_left    = 1'b1;
                default: mb_confirm = 1'b1;
            endcase
            @(posedge clk);
            @(negedge clk);
            mb_next = 1'b0; mb_mode = 1'b0; mb_left = 1'b0; mb_confirm = 1'b0;
            repeat (4) @(posedge clk);
            check_pulses(exp, name);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ---- 全屏态 ----
        view_mode = 1'b0;
        fire_event(2'd1, 6'b100000, "fullscreen next event");
        fire_event(2'd0, 6'b010000, "fullscreen prev event");
        fire_event(2'd2, 6'b000001, "fullscreen confirm enters grid");
        fire_event(2'd3, 6'b000001, "fullscreen mode toggles grid");
        fire_mpulse(2'd0, 6'b100000, "fullscreen mb_next fallback");
        fire_mpulse(2'd1, 6'b000001, "fullscreen mb_mode fallback");

        // ---- 缩略图态 ----
        view_mode = 1'b1;
        repeat (2) @(posedge clk);
        fire_event(2'd1, 6'b001000, "thumbnail next = focus right");
        fire_event(2'd0, 6'b000100, "thumbnail prev = focus left");
        fire_event(2'd2, 6'b000010, "thumbnail confirm");
        fire_event(2'd3, 6'b000001, "thumbnail mode toggles grid");
        fire_mpulse(2'd0, 6'b001000, "thumbnail mb_next fallback");
        fire_mpulse(2'd2, 6'b000100, "thumbnail mb_left fallback");
        fire_mpulse(2'd3, 6'b000010, "thumbnail mb_confirm fallback");
        fire_mpulse(2'd1, 6'b000001, "thumbnail mb_mode fallback");

        // KEY7 must enter the grid on the same event that exits playback.
        view_mode = 1'b0;
        mode_play = 1'b1;
        fire_event(2'd3, 6'b000001, "playing KEY7 enters grid once");
        fire_event(2'd1, 6'b000000, "playing navigation stays gated");
        mode_play = 1'b0;

        // ---- 回滚开关：J2_BROWSE_ENABLE=0 ----
        off_view_mode = 1'b0;
        clear_off_counts;
        @(negedge clk);
        off_next_tgl = ~off_next_tgl;
        repeat (12) @(posedge clk);
        if ({o_fs_next[0], o_fs_prev[0], o_right[0], o_left[0], o_conf[0], o_mode[0]} !== 6'b000000) begin
            $display("FAIL: disabled J2 path still produced an event pulse");
            errors = errors + 1;
        end
        clear_off_counts;
        @(negedge clk);
        off_mb_next = 1'b1;
        @(posedge clk);
        @(negedge clk);
        off_mb_next = 1'b0;
        repeat (4) @(posedge clk);
        if ({o_fs_next[0], o_fs_prev[0], o_right[0], o_left[0], o_conf[0], o_mode[0]} !== 6'b100000) begin
            $display("FAIL: disabled J2 path broke motherboard fallback");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS browse_fsm_s3_smoke");
        else
            $display("FAIL: tb_browse_fsm errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000;
        $display("FAIL: tb_browse_fsm timeout");
        $finish;
    end
endmodule
