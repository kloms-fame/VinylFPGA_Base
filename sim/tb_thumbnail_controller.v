`timescale 1ns/1ps

// 第十五讲回归：缩略图交互控制器。
// 覆盖教程 3.2.3 的 mode/focus/confirm/frame_start/transition_req 行为。
module tb_thumbnail_controller;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        key_right = 1'b0;
    reg        key_left = 1'b0;
    reg        key_confirm = 1'b0;
    reg        key_mode = 1'b0;
    reg  [3:0] image_complete = 4'b1111;
    reg        frame_start = 1'b0;

    wire       view_mode;
    wire [1:0] focus_index;
    wire [1:0] active_index;
    wire       transition_req;

    integer errors = 0;
    integer i;

    thumbnail_controller dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .key_right       (key_right),
        .key_left        (key_left),
        .key_confirm     (key_confirm),
        .key_mode        (key_mode),
        .image_complete  (image_complete),
        .frame_start     (frame_start),
        .view_mode       (view_mode),
        .focus_index     (focus_index),
        .active_index    (active_index),
        .transition_req  (transition_req)
    );

    always #5 clk = ~clk;

    task pulse_key;
        input integer which;
        begin
            @(negedge clk);
            case (which)
                0: key_right   = 1'b1;
                1: key_left    = 1'b1;
                2: key_confirm = 1'b1;
                default: key_mode = 1'b1;
            endcase
            @(posedge clk);
            #1;
            key_right   = 1'b0;
            key_left    = 1'b0;
            key_confirm = 1'b0;
            key_mode    = 1'b0;
            @(negedge clk);
        end
    endtask

    task pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            #1;
            frame_start = 1'b0;
        end
    endtask

    task check_state;
        input        exp_view;
        input [1:0]  exp_focus;
        input [1:0]  exp_active;
        input [8*40:1] name;
        begin
            if (view_mode !== exp_view ||
                focus_index !== exp_focus ||
                active_index !== exp_active) begin
                $display("FAIL: %0s got view=%b focus=%0d active=%0d, expect view=%b focus=%0d active=%0d",
                         name, view_mode, focus_index, active_index,
                         exp_view, exp_focus, exp_active);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        check_state(1'b0, 2'd0, 2'd0, "reset");

        // mode: 全屏 -> 缩略图，transition_req 在 frame_start 单拍输出。
        pulse_key(3);
        check_state(1'b1, 2'd0, 2'd0, "enter thumbnail");
        if (transition_req !== 1'b0) begin
            $display("FAIL: transition_req asserted before frame_start");
            errors = errors + 1;
        end
        pulse_frame_start();
        if (transition_req !== 1'b1) begin
            $display("FAIL: transition_req did not assert at frame_start");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (transition_req !== 1'b0) begin
            $display("FAIL: transition_req was not a single-cycle pulse");
            errors = errors + 1;
        end

        // 右移到边界后循环 0->1->2->3->0。
        for (i = 0; i < 4; i = i + 1) begin
            pulse_key(0);
            if (focus_index !== ((i + 1) & 3)) begin
                $display("FAIL: right wrap step %0d got focus=%0d, expect %0d",
                         i, focus_index, (i + 1) & 3);
                errors = errors + 1;
            end
        end

        // 左移到边界后循环 3->2->1->0->3。
        for (i = 3; i >= 0; i = i - 1) begin
            pulse_key(1);
            if (focus_index !== i[1:0]) begin
                $display("FAIL: left wrap step %0d got focus=%0d", i, focus_index);
                errors = errors + 1;
            end
        end

        // 未加载图片不可确认。当前焦点为 0，右移两次到索引 2。
        pulse_key(0);
        pulse_key(0);
        image_complete = 4'b1011;       // bit2=0
        pulse_key(2);
        check_state(1'b1, 2'd2, 2'd0, "confirm incomplete");

        // 已加载图片确认后 active_index=focus_index，并回到全屏。
        image_complete = 4'b1111;
        pulse_key(0);                   // 焦点 2 -> 3
        pulse_key(2);
        check_state(1'b0, 2'd3, 2'd3, "confirm complete");
        pulse_frame_start();
        if (transition_req !== 1'b1) begin
            $display("FAIL: confirm did not produce frame-bound transition_req");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;

        if (errors == 0)
            $display("PASS: tb_thumbnail_controller all checks passed");
        else
            $display("FAIL: tb_thumbnail_controller errors=%0d", errors);
        $finish;
    end

    initial begin
        #100_000;
        $display("FAIL: tb_thumbnail_controller timeout");
        $finish;
    end
endmodule
