`timescale 1ns/1ps

// =============================================================================
// 第十三讲选做件回归：bilinear_8q8（8Q8 定点双线性插值）
//
// 依据教程 3.3.1 节“上板验证”口径：
//   A. wx=0, wy=0  → 输出必须等于 p00（回归基准，同时能抓到 8'd256 截断陷阱）
//   B. wx=wy=128   → 输出等于 4 像素的算术平均（误差 0）
//   C. wx=0, wy=255 → 输出逼近下一行同列像素
//   D. G/B 三通道与 R 通道同构（教程留成 TODO，本工程已补全）
//   E. 权重补数陷阱：inv_wx 在 wx=0 时必须等于 256（而不是 0）
// =============================================================================
module tb_bilinear_8q8;
    reg  [7:0] p00_r=0, p10_r=0, p01_r=0, p11_r=0;
    reg  [7:0] p00_g=0, p10_g=0, p01_g=0, p11_g=0;
    reg  [7:0] p00_b=0, p10_b=0, p01_b=0, p11_b=0;
    reg  [7:0] wx=0, wy=0;

    wire [7:0] out_r, out_g, out_b;

    integer errors = 0;

    bilinear_8q8 dut (
        .p00_r(p00_r), .p10_r(p10_r), .p01_r(p01_r), .p11_r(p11_r),
        .p00_g(p00_g), .p10_g(p10_g), .p01_g(p01_g), .p11_g(p11_g),
        .p00_b(p00_b), .p10_b(p10_b), .p01_b(p01_b), .p11_b(p11_b),
        .wx(wx), .wy(wy),
        .out_r(out_r), .out_g(out_g), .out_b(out_b)
    );

    task check_rgb;
        input [7:0] exp_r;
        input [7:0] exp_g;
        input [7:0] exp_b;
        input [8*24-1:0] tag;
        begin
            #1;
            if (out_r !== exp_r || out_g !== exp_g || out_b !== exp_b) begin
                $display("FAIL: %0s got r=%0d g=%0d b=%0d, expect r=%0d g=%0d b=%0d",
                         tag, out_r, out_g, out_b, exp_r, exp_g, exp_b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // ---------- A. wx=0, wy=0 必须原样输出 p00 ----------
        p00_r = 8'd37;  p10_r = 8'd200; p01_r = 8'd11;  p11_r = 8'd99;
        p00_g = 8'd201; p10_g = 8'd5;   p01_g = 8'd77;  p11_g = 8'd250;
        p00_b = 8'd250; p10_b = 8'd250; p01_b = 8'd0;   p11_b = 8'd1;
        wx = 8'd0; wy = 8'd0;
        check_rgb(8'd37, 8'd201, 8'd250, "wx=0,wy=0 -> p00");

        // ---------- B. wx=wy=128 应为四像素平均 ----------
        // 取 0/100/200/0 使平均值恰为整数 75，可零误差比对
        p00_r = 8'd0;   p10_r = 8'd100; p01_r = 8'd200; p11_r = 8'd0;
        p00_g = 8'd100; p10_g = 8'd0;   p01_g = 8'd0;   p11_g = 8'd200;  // 平均 75
        p00_b = 8'd40;  p10_b = 8'd80;  p01_b = 8'd120; p11_b = 8'd160;  // 平均 100
        wx = 8'd128; wy = 8'd128;
        check_rgb(8'd75, 8'd75, 8'd100, "wx=wy=128 -> 4-pixel average");

        // ---------- C. wx=0, wy=255 逼近下一行同列像素 ----------
        p00_r = 8'd0;   p10_r = 8'd255; p01_r = 8'd255; p11_r = 8'd255;
        p00_g = 8'd0;   p10_g = 8'd0;   p01_g = 8'd255; p11_g = 8'd255;
        p00_b = 8'd0;   p10_b = 8'd0;   p01_b = 8'd0;   p11_b = 8'd0;
        wx = 8'd0; wy = 8'd255;
        // inv_wy = 1：out = row_top[15:8]*1 + row_bottom[15:8]*255，再取高 8 位
        // row_top_r = 0*256 = 0 -> 0；row_bottom_r = 255*256 = 65280 -> [15:8] = 255
        // (0*1 + 255*255) >> 8 = 65025 >> 8 = 254
        // row_top_g = 0；row_bottom_g = 255 -> 254
        // row_top_b = 0；row_bottom_b = 0 -> 0
        check_rgb(8'd254, 8'd254, 8'd0, "wx=0,wy=255 -> near p01");

        // ---------- D. 中值权重下三通道独立正确 ----------
        // wy=0 只走顶行；wx=128 时 row_top[15:8] 正好是 p00/p10 的 50% 截断值
        p00_r = 8'd255; p10_r = 8'd255; p01_r = 8'd0;   p11_r = 8'd0;
        p00_g = 8'd0;   p10_g = 8'd255; p01_g = 8'd0;   p11_g = 8'd0;
        p00_b = 8'd255; p10_b = 8'd0;   p01_b = 8'd0;   p11_b = 8'd0;
        wx = 8'd128; wy = 8'd0;
        // R: (255*128+255*128)>>8 = 255；G: (0+255*128)>>8 = 127；B: (255*128+0)>>8 = 127
        check_rgb(8'd255, 8'd127, 8'd127, "wx=128,wy=0 -> per-channel weighted");

        if (errors == 0)
            $display("PASS: tb_bilinear_8q8 all checks passed");
        else
            $display("FAIL: tb_bilinear_8q8 errors=%0d", errors);

        $finish;
    end
endmodule
