`timescale 1ns/1ps

module tb_osd_overlay;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         vsync = 1'b1;
    reg         de = 1'b0;
    reg  [9:0]  pixel_x = 10'd0;
    reg  [23:0] rgb_in = 24'h123456;
    reg  [1:0]  active_index = 2'd0;
    reg         auto_enabled = 1'b0;
    reg  [7:0]  error_code = 8'h00;
    reg  [7:0]  brightness = 8'd255;
    reg  [7:0]  contrast = 8'd128;
    reg         menu_active = 1'b0;

    wire [23:0] rgb_out;
    wire        de_out;
    wire        osd_active;

    integer errors = 0;
    integer line;
    integer x;

    osd_overlay_24 #(
        .OSD_X(8),
        .OSD_Y(8)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .vsync        (vsync),
        .de           (de),
        .rgb_in       (rgb_in),
        .pixel_x      (pixel_x),
        .active_index (active_index),
        .auto_enabled (auto_enabled),
        .error_code   (error_code),
        .brightness   (brightness),
        .contrast     (contrast),
        .menu_active  (menu_active),
        .rgb_out      (rgb_out),
        .de_out       (de_out),
        .osd_active   (osd_active)
    );

    always #5 clk = ~clk;

    task expect_rgb;
        input [23:0] expected;
        begin
            if (rgb_out !== expected) begin
                $display("FAIL: pixel_x=%0d line=%0d got=%06h expected=%06h",
                         pixel_x, line, rgb_out, expected);
                errors = errors + 1;
            end
        end
    endtask

    task begin_frame;
        input [1:0]  idx;
        input        auto_mode;
        input [7:0]  err;
        begin
            @(negedge clk);
            vsync = 1'b0;
            de = 1'b0;
            pixel_x = 10'd0;
            active_index = idx;
            auto_enabled = auto_mode;
            error_code = err;
            repeat (2) @(negedge clk);
            vsync = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task render_frame;
        input        do_checks;
        input [23:0] osd_color;
        begin
            for (line = 0; line < 9; line = line + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    @(negedge clk);
                    pixel_x = x[9:0];
                    de = 1'b1;
                    #1;

                    if (do_checks && (line == 8)) begin
                        case (x)
                            7:  begin expect_rgb(24'h123456); end
                            10: begin expect_rgb(osd_color); end
                            13: begin expect_rgb(24'h123456); end
                            16: begin expect_rgb(auto_enabled ? 24'h123456 : osd_color); end
                            17: begin expect_rgb(osd_color); end
                            24: begin expect_rgb(osd_color); end
                            28: begin expect_rgb(osd_color); end
                            default: ;
                        endcase
                    end
                end

                @(negedge clk);
                de = 1'b0;
                pixel_x = 10'd0;
                @(negedge clk);
            end
        end
    endtask

    task render_menu_frame;
        begin
            for (line = 0; line < 25; line = line + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    @(negedge clk);
                    pixel_x = x[9:0];
                    de = 1'b1;
                    #1;

                    if (line == 24) begin
                        case (x)
                            8:  begin expect_rgb(24'hFFFF00); end
                            12: begin expect_rgb(24'h123456); end
                            17: begin expect_rgb(24'hFFFF00); end
                            25: begin expect_rgb(24'hFFFF00); end
                            33: begin expect_rgb(24'hFFFF00); end
                            41: begin expect_rgb(24'hFFFF00); end
                            48: begin expect_rgb(24'hFFFF00); end
                            56: begin expect_rgb(24'h123456); end
                            default: ;
                        endcase
                    end
                end

                @(negedge clk);
                de = 1'b0;
                pixel_x = 10'd0;
                @(negedge clk);
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // 正常状态：图片1 + 手动E + 错误码00，OSD为黄色，区域外透传。
        begin_frame(2'd0, 1'b0, 8'h00);
        render_frame(1'b1, 24'hFFFF00);

        // 错误状态：图片3 + 自动A + 错误码44，OSD为红色，区域外仍透传。
        begin_frame(2'd2, 1'b1, 8'h44);
        render_frame(1'b1, 24'hFF4444);

        // 菜单状态：第二行显示亮度AB、对比度CD；字形内部为黄色，空白处透传。
        @(negedge clk);
        brightness = 8'hab;
        contrast = 8'hcd;
        menu_active = 1'b1;
        begin_frame(2'd0, 1'b0, 8'h00);
        render_menu_frame;
        menu_active = 1'b0;

        // 消隐期不得叠加OSD。
        @(negedge clk);
        de = 1'b0;
        pixel_x = 10'd0;
        #1;
        if (de_out !== 1'b0 || osd_active !== 1'b0 || rgb_out !== rgb_in) begin
            $display("FAIL: blanking output mismatch");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_osd_overlay all checks passed");
        else
            $display("FAIL: tb_osd_overlay errors=%0d", errors);

        $finish;
    end
endmodule
