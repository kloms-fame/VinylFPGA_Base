`timescale 1ns/1ps

module tb_subtitle_replace;
    reg src_clk = 1'b0;
    reg video_clk = 1'b0;
    reg rst_n = 1'b0;
    reg rx_valid = 1'b0;
    reg [7:0] rx_data = 8'd0;

    wire glyph_we;
    wire [9:0] glyph_waddr;
    wire [15:0] glyph_wdata;
    wire text_we;
    wire [5:0] text_waddr;
    wire [4:0] text_wdata;
    wire commit_toggle;
    wire commit_bank;
    wire [5:0] commit_length;

    wire [5:0] text_raddr;
    wire [4:0] text_rdata;
    wire [9:0] glyph_raddr;
    wire [15:0] glyph_rdata;
    wire [23:0] rgb_out;
    wire de_out;
    wire vs_out;
    wire active;

    reg vsync = 1'b1;
    reg de = 1'b0;
    reg [9:0] pixel_x = 10'd0;
    reg [23:0] rgb_in = 24'h123456;
    integer line = 0;
    integer errors = 0;
    integer i;

    subtitle_ascii_parser parser (
        .clk(src_clk), .rst_n(rst_n), .rx_valid(rx_valid), .rx_data(rx_data),
        .glyph_we(glyph_we), .glyph_waddr(glyph_waddr), .glyph_wdata(glyph_wdata),
        .text_we(text_we), .text_waddr(text_waddr), .text_wdata(text_wdata),
        .commit_toggle(commit_toggle), .commit_bank(commit_bank),
        .commit_length(commit_length)
    );

    subtitle_glyph_ram glyph_ram (
        .wr_clk(src_clk), .wr_en(glyph_we), .wr_addr(glyph_waddr),
        .wr_data(glyph_wdata), .rd_clk(video_clk), .rd_addr(glyph_raddr),
        .rd_data(glyph_rdata)
    );

    subtitle_text_ram text_ram (
        .wr_clk(src_clk), .wr_en(text_we), .wr_addr(text_waddr),
        .wr_data(text_wdata), .rd_addr(text_raddr), .rd_data(text_rdata)
    );

    dynamic_cn_subtitle_overlay #(
        .H_ACTIVE(640), .V_ACTIVE(480), .CELL_W(18), .CELL_H(18),
        .SUBTITLE_Y(450)
    ) overlay (
        .src_clk(src_clk), .src_rst_n(rst_n),
        .commit_toggle(commit_toggle), .commit_bank(commit_bank),
        .commit_length(commit_length),
        .video_clk(video_clk), .video_rst_n(rst_n), .vsync(vsync), .de(de),
        .pixel_x(pixel_x), .rgb_in(rgb_in),
        .text_raddr(text_raddr), .text_rdata(text_rdata),
        .glyph_raddr(glyph_raddr), .glyph_rdata(glyph_rdata),
        .rgb_out(rgb_out), .de_out(de_out), .vs_out(vs_out), .active(active)
    );

    always #10 src_clk = ~src_clk;
    always #20 video_clk = ~video_clk;

    task send_char;
        input [7:0] value;
        begin
            @(negedge src_clk);
            rx_data = value;
            rx_valid = 1'b1;
            @(negedge src_clk);
            rx_valid = 1'b0;
        end
    endtask

    task send_string;
        input [8*160-1:0] value;
        input integer length;
        integer j;
        begin
            for (j = 0; j < length; j = j + 1)
                send_char(value[(length - 1 - j) * 8 +: 8]);
        end
    endtask

    task begin_frame;
        begin
            @(negedge video_clk);
            vsync = 1'b0;
            repeat (3) @(negedge video_clk);
            vsync = 1'b1;
            repeat (3) @(negedge video_clk);
            line = 0;
        end
    endtask

    task advance_line;
        begin
            @(negedge video_clk);
            pixel_x = 10'd0;
            de = 1'b1;
            @(negedge video_clk);
            de = 1'b0;
            line = line + 1;
            @(negedge video_clk);
        end
    endtask

    task advance_to_line;
        input integer target;
        begin
            while (line < target)
                advance_line();
        end
    endtask

    task check_pixel;
        input integer y;
        input [9:0] x;
        input [23:0] expected_rgb;
        input expected_active;
        begin
            advance_to_line(y);
            @(negedge video_clk);
            pixel_x = x;
            de = 1'b1;
            @(posedge video_clk);
            #1;
            if ((rgb_out !== expected_rgb) ||
                (active !== expected_active) ||
                (de_out !== 1'b1)) begin
                $display("FAIL y=%0d x=%0d rgb=%06h active=%0b expected=%06h/%0b",
                         y, x, rgb_out, active, expected_rgb, expected_active);
                errors = errors + 1;
            end
            @(negedge video_clk);
            de = 1'b0;
            @(negedge video_clk);
        end
    endtask

    initial begin
        repeat (5) @(negedge src_clk);
        rst_n = 1'b1;
        repeat (5) @(negedge src_clk);

        // First line: every row has the leftmost pixel set.
        send_string("@G,00,8000800080008000800080008000800080008000800080008000800080008000\n", 71);
        send_string("@A,00\n", 6);
        send_string("@T\n", 3);
        repeat (10) @(negedge video_clk);
        begin_frame();

        advance_to_line(451);
        check_pixel(451, 10'd312, 24'hFFFFFF, 1'b1);
        check_pixel(451, 10'd311, 24'h101010, 1'b1);
        begin_frame();

        // Replace with every row using bit 14.
        send_string("@C\n", 3);
        send_string("@G,00,4000400040004000400040004000400040004000400040004000400040004000\n", 71);
        send_string("@A,00\n", 6);
        send_string("@T\n", 3);
        repeat (10) @(negedge video_clk);
        begin_frame();

        advance_to_line(451);
        check_pixel(451, 10'd312, 24'h101010, 1'b1);
        check_pixel(451, 10'd313, 24'hFFFFFF, 1'b1);

        if (errors == 0)
            $display("TEST_PASS subtitle_replace");
        else
            $display("TEST_FAIL subtitle_replace errors=%0d", errors);
        $finish;
    end
endmodule
