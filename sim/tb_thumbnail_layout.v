`timescale 1ns/1ps

// =============================================================================
// 第十三讲回归：thumbnail_layout（教程原样移植件，纯组合）
//
// 逐条验证教程 2.5 / 3.2 节写死的映射关系：
//   A. 2x2 象限 -> source_index（左上0 右上1 左下2 右下3）
//   B. 局部坐标 -> 最近邻源坐标（source_x = local_x*4，source_y = local_y*4）
//   C. 焦点边框：只画在 focus_index 对应格子最外圈 2 像素
//   D. image_complete 门控：未加载完成的格子不出 thumb_de
//   E. 屏幕范围内但落在缩略图区之外（x>=320 或 y>=240）不显示
//   F. in_de=0 或超出 640x480 一律不显示
// =============================================================================
module tb_thumbnail_layout;
    reg         in_de = 1'b0;
    reg  [11:0] pixel_x = 12'd0;
    reg  [11:0] pixel_y = 12'd0;
    reg  [1:0]  focus_index = 2'd0;
    reg  [3:0]  image_complete = 4'b1111;

    wire        thumb_de;
    wire [1:0]  source_index;
    wire [9:0]  source_x;
    wire [9:0]  source_y;
    wire        focus_border;

    integer errors = 0;

    thumbnail_layout #(
        .DISPLAY_WIDTH  (640),
        .DISPLAY_HEIGHT (480),
        .THUMB_WIDTH    (160),
        .THUMB_HEIGHT   (120)
    ) dut (
        .in_de        (in_de),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (thumb_de),
        .source_index (source_index),
        .source_x     (source_x),
        .source_y     (source_y),
        .focus_border (focus_border)
    );

    // 期望值检查：坐标映射（不含边框）
    task check_map;
        input [11:0] x;
        input [11:0] y;
        input [1:0]  exp_idx;
        input [9:0]  exp_sx;
        input [9:0]  exp_sy;
        begin
            in_de = 1'b1;
            pixel_x = x;
            pixel_y = y;
            #1;
            if (thumb_de !== 1'b1 ||
                source_index !== exp_idx ||
                source_x !== exp_sx ||
                source_y !== exp_sy) begin
                $display("FAIL: map(%0d,%0d) got de=%b idx=%0d sx=%0d sy=%0d, expect de=1 idx=%0d sx=%0d sy=%0d",
                         x, y, thumb_de, source_index, source_x, source_y,
                         exp_idx, exp_sx, exp_sy);
                errors = errors + 1;
            end
        end
    endtask

    // 期望值检查：不显示
    task check_blank;
        input [11:0] x;
        input [11:0] y;
        input        de_in;
        begin
            in_de = de_in;
            pixel_x = x;
            pixel_y = y;
            #1;
            if (thumb_de !== 1'b0 || focus_border !== 1'b0) begin
                $display("FAIL: blank(%0d,%0d,de=%b) got de=%b border=%b, expect 0/0",
                         x, y, de_in, thumb_de, focus_border);
                errors = errors + 1;
            end
        end
    endtask

    // 期望值检查：焦点边框
    task check_border;
        input [11:0] x;
        input [11:0] y;
        input [1:0]  focus;
        input        exp_border;
        begin
            focus_index = focus;
            in_de = 1'b1;
            pixel_x = x;
            pixel_y = y;
            #1;
            if (thumb_de !== 1'b1 || focus_border !== exp_border) begin
                $display("FAIL: border(%0d,%0d,focus=%0d) got de=%b border=%b, expect de=1 border=%b",
                         x, y, focus, thumb_de, focus_border, exp_border);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        focus_index = 2'd0;
        image_complete = 4'b1111;

        // ---------- A + B：四个象限的坐标映射 ----------
        check_map(12'd10,  12'd20,  2'd0, 10'd40,  10'd80);   // 左上
        check_map(12'd165, 12'd30,  2'd1, 10'd20,  10'd120);  // 右上
        check_map(12'd10,  12'd130, 2'd2, 10'd40,  10'd40);   // 左下
        check_map(12'd200, 12'd150, 2'd3, 10'd160, 10'd120);  // 右下
        // 格子边界值：x=159/160、y=119/120 的归属
        check_map(12'd159, 12'd119, 2'd0, 10'd636, 10'd476);
        check_map(12'd160, 12'd119, 2'd1, 10'd0,   10'd476);
        check_map(12'd159, 12'd120, 2'd2, 10'd636, 10'd0);
        check_map(12'd160, 12'd120, 2'd3, 10'd0,   10'd0);

        // ---------- C：焦点边框（2 像素） ----------
        check_border(12'd0,   12'd20,  2'd0, 1'b1);  // 左边
        check_border(12'd1,   12'd20,  2'd0, 1'b1);  // 左边第 2 列
        check_border(12'd2,   12'd20,  2'd0, 1'b0);  // 左边之外
        check_border(12'd20,  12'd0,   2'd0, 1'b1);  // 上边
        check_border(12'd20,  12'd2,   2'd0, 1'b0);  // 上边之外
        check_border(12'd20,  12'd118, 2'd0, 1'b1);  // 下边
        check_border(12'd20,  12'd117, 2'd0, 1'b0);  // 下边之外
        check_border(12'd158, 12'd20,  2'd0, 1'b1);  // 右边
        check_border(12'd157, 12'd20,  2'd0, 1'b0);  // 右边之外
        check_border(12'd20,  12'd20,  2'd1, 1'b0);  // 焦点不是这个格子
        check_border(12'd160, 12'd20,  2'd1, 1'b1);  // 焦点是这个格子的左边框

        // ---------- D：image_complete 门控 ----------
        focus_index = 2'd0;
        image_complete = 4'b0001;
        check_map(12'd10, 12'd20, 2'd0, 10'd40, 10'd80);   // bank0 已就绪
        check_blank(12'd165, 12'd30, 1'b1);                // bank1 未就绪
        check_blank(12'd10,  12'd130, 1'b1);               // bank2 未就绪
        image_complete = 4'b1111;

        // ---------- E：缩略图区之外（屏幕内） ----------
        check_blank(12'd320, 12'd0,   1'b1);   // 右半屏留空
        check_blank(12'd639, 12'd239, 1'b1);
        check_blank(12'd0,   12'd240, 1'b1);   // 下半屏留空
        check_blank(12'd319, 12'd479, 1'b1);

        // ---------- F：in_de=0 与超范围 ----------
        check_blank(12'd10,  12'd20,  1'b0);
        check_blank(12'd640, 12'd0,   1'b1);
        check_blank(12'd0,   12'd480, 1'b1);

        if (errors == 0)
            $display("PASS: tb_thumbnail_layout all checks passed");
        else
            $display("FAIL: tb_thumbnail_layout errors=%0d", errors);

        $finish;
    end
endmodule
