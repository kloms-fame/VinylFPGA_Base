`timescale 1ns/1ps

// 第十四讲回归：亮度/对比度像素模块
//   A. brightness=255、contrast=128 必须逐位旁路；
//   B. contrast=0 必须把所有通道压到中间灰 0x80；
//   C. contrast=255 必须拉伸并正确饱和；
//   D. 亮度=0 必须为黑。
module tb_brightness_contrast_adjust;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         in_de = 1'b0;
    reg  [23:0] rgb_in = 24'd0;
    reg  [7:0]  brightness = 8'd255;
    reg  [7:0]  contrast = 8'd128;

    wire        out_de;
    wire [23:0] rgb_out;
    integer errors = 0;
    integer i;

    brightness_contrast_adjust dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_de      (in_de),
        .rgb_in     (rgb_in),
        .brightness (brightness),
        .contrast   (contrast),
        .out_de     (out_de),
        .rgb_out    (rgb_out)
    );

    always #5 clk = ~clk;

    task apply_one;
        input [23:0] rgb;
        input [7:0]  b;
        input [7:0]  c;
        input [23:0] expected;
        begin
            @(negedge clk);
            rgb_in     = rgb;
            brightness = b;
            contrast   = c;
            in_de      = 1'b1;
            @(posedge clk);
            #1;
            if (!out_de || rgb_out !== expected) begin
                $display("FAIL: rgb=%06h b=%0d c=%0d got=%06h expected=%06h",
                         rgb, b, c, rgb_out, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // A. 默认参数逐位旁路
        apply_one(24'h00_00_00, 8'd255, 8'd128, 24'h00_00_00);
        apply_one(24'hff_ff_ff, 8'd255, 8'd128, 24'hff_ff_ff);
        apply_one(24'h12_34_56, 8'd255, 8'd128, 24'h12_34_56);
        apply_one(24'hff_00_aa, 8'd255, 8'd128, 24'hff_00_aa);

        // B. contrast=0 -> 每通道中灰 0x80
        apply_one(24'h12_34_56, 8'd255, 8'd0, 24'h80_80_80);
        apply_one(24'hff_ff_ff, 8'd255, 8'd0, 24'h80_80_80);

        // C. contrast=255 -> 以 128 为中心拉伸并饱和
        apply_one(24'h00_00_00, 8'd255, 8'd255, 24'h00_00_00);
        apply_one(24'h80_80_80, 8'd255, 8'd255, 24'h80_80_80);
        apply_one(24'hff_ff_ff, 8'd255, 8'd255, 24'hff_ff_ff);
        apply_one(24'h40_c0_80, 8'd255, 8'd255, 24'h00_ff_80);

        // D. brightness=0 -> 黑
        apply_one(24'h12_34_56, 8'd0, 8'd128, 24'h00_00_00);

        // E. 消隐期 DE 必须跟随输入
        @(negedge clk);
        in_de = 1'b0;
        @(posedge clk);
        #1;
        if (out_de !== 1'b0) begin
            $display("FAIL: out_de should be low in blanking");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_brightness_contrast_adjust all checks passed");
        else
            $display("FAIL: tb_brightness_contrast_adjust errors=%0d", errors);

        $finish;
    end
endmodule
