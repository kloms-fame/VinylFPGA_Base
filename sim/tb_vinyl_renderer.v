`timescale 1ns/1ps

// =============================================================================
// S6 回归：黑胶视觉层
//   1) 盘外像素原样透传（不遮挡封面/背景）
//   2) 盘内确实画出盘面；盘心有标签色；盘面非纯黑（有纹路）
//   3) 相位改变 -> 高光位置改变（证明"在转"）
//   4) enable=0 / de=0 时完全不覆盖
// =============================================================================
module tb_vinyl_renderer;
    reg clk = 1'b0, rst_n = 1'b0;
    reg de = 1'b0;
    reg [9:0] px = 10'd0, py = 10'd0;
    reg [7:0] phase = 8'd0;
    reg enable = 1'b1;
    wire [23:0] rgb_out;
    wire        hit;
    integer errors = 0;

    localparam [23:0] CX = 24'h111111;
    localparam integer CX_P = 320, CY_P = 206;

    vinyl_renderer dut (
        .clk(clk), .rst_n(rst_n), .de(de), .pixel_x(px), .pixel_y(py),
        .phase(phase), .enable(enable), .rgb_in(CX), .rgb_out(rgb_out), .hit(hit)
    );

    always #5 clk = ~clk;

    task check;
        input cond;
        input [8*56:1] name;
        begin
            if (!cond) begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    task at;
        input integer x, y;
        begin
            @(negedge clk); px = x[9:0]; py = y[9:0]; de = 1'b1;
            @(negedge clk);
        end
    endtask

    integer x, y, nonblack, label_px, hit_px;
    integer phase0_nonblack;
    reg [23:0] sample_a, sample_b;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 1) 盘外（屏幕角）必须透传
        at(5, 5);
        check(hit === 1'b0 && rgb_out === CX, "盘外像素原样透传");
        at(635, 475);
        check(hit === 1'b0, "右下角在盘外");

        // 2) 扫盘面：统计点亮数/标签/非黑
        hit_px = 0; nonblack = 0; label_px = 0;
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                px = x[9:0]; py = y[9:0]; de = 1'b1;
                #1;
                if (hit) begin
                    hit_px = hit_px + 1;
                    if (rgb_out !== 24'h0A0A0C) nonblack = nonblack + 1;
                    if (rgb_out === 24'hB23A2E) label_px = label_px + 1;
                end
            end
        end
        check(hit_px > 60000, "盘面点亮像素数量级正确（半径约 148）");
        check(nonblack > 5000, "盘面有纹路/标签/高光，不是纯黑");
        check(label_px > 4000, "盘心标签色存在");

        // 3) 相位变化 -> 高光位置变化
        phase = 8'd0;
        at(CX_P + 64, CY_P);
        sample_a = rgb_out;
        phase = 8'd128;                 // 转 180 度
        at(CX_P + 64, CY_P);
        sample_b = rgb_out;
        check(sample_a !== sample_b, "相位改变后同一像素颜色变化（高光在转）");

        // 4) enable/de 关闭时不覆盖
        enable = 1'b0;
        at(CX_P, CY_P);
        check(hit === 1'b0 && rgb_out === CX, "enable=0 不覆盖");
        enable = 1'b1; de = 1'b0;
        check(hit === 1'b0, "de=0 不覆盖");

        if (errors == 0)
            $display("TEST_PASS vinyl_renderer_s6");
        else
            $display("FAIL: tb_vinyl_renderer errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: tb_vinyl_renderer timeout");
        $finish;
    end
endmodule
