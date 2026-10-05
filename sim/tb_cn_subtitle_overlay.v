`timescale 1ns/1ps

module tb_cn_subtitle_overlay;
    reg         clk;
    reg         rst_n;
    reg         vsync;
    reg         de;
    reg  [9:0]  pixel_x;
    reg  [23:0] rgb_in;
    wire [23:0] rgb_out;
    wire        active;

    integer errors;
    integer line;
    integer current_line;
    integer i;

    vinyl_cn_subtitle_overlay dut (
        .clk(clk),
        .rst_n(rst_n),
        .vsync(vsync),
        .de(de),
        .pixel_x(pixel_x),
        .rgb_in(rgb_in),
        .rgb_out(rgb_out),
        .active(active)
    );

    always #5 clk = ~clk;

    task automatic begin_frame;
        begin
            @(negedge clk);
            vsync = 1'b0;
            de = 1'b0;
            pixel_x = 10'd0;
            repeat (3) @(negedge clk);
            vsync = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic advance_line;
        begin
            @(negedge clk);
            de = 1'b1;
            @(negedge clk);
            de = 1'b0;
            current_line = current_line + 1;
            @(negedge clk);
        end
    endtask

    task automatic advance_to_line;
        input integer target_line;
        begin
            while (current_line < target_line)
                advance_line();
        end
    endtask

    task automatic check_pixel;
        input [9:0]  x;
        input [23:0] expected_rgb;
        input        expected_active;
        begin
            @(negedge clk);
            pixel_x = x;
            #1;
            if (rgb_out !== expected_rgb || active !== expected_active) begin
                $display("FAIL line=%0d x=%0d got=%06h/%0b expected=%06h/%0b",
                         line, x, rgb_out, active, expected_rgb, expected_active);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        vsync = 1'b1;
        de = 1'b0;
        pixel_x = 10'd0;
        rgb_in = 24'h123456;
        errors = 0;
        current_line = 0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        begin_frame();

        advance_to_line(450);
        @(negedge clk);
        de = 1'b1;
        line = current_line;

        // SUBTITLE_X = (640 - 11*18)/2 = 221.
        check_pixel(10'd220, 24'h123456, 1'b0);
        check_pixel(10'd221, 24'h101010, 1'b1);
        check_pixel(10'd418, 24'h101010, 1'b1);
        check_pixel(10'd419, 24'h123456, 1'b0);

        @(negedge clk);
        de = 1'b0;
        current_line = current_line + 1;
        @(negedge clk);

        // Row 1 of glyph 0 "你" has bit 11 set. This maps to x=226.
        advance_to_line(452);
        @(negedge clk);
        de = 1'b1;
        line = current_line;
        check_pixel(10'd226, 24'hFFFFFF, 1'b1);
        @(negedge clk);
        de = 1'b0;
        current_line = current_line + 1;
        @(negedge clk);

        // At line 468 the band is no longer active.
        advance_to_line(468);
        @(negedge clk);
        de = 1'b1;
        line = current_line;
        check_pixel(10'd300, 24'h123456, 1'b0);
        @(negedge clk);
        de = 1'b0;

        if (errors == 0)
            $display("TEST_PASS cn_subtitle_overlay");
        else
            $display("TEST_FAIL cn_subtitle_overlay errors=%0d", errors);

        $finish;
    end
endmodule
