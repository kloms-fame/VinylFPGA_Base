`timescale 1ns/1ps

// =============================================================================
// X0R 零行为等价回归：thumbnail_layout
//
// 同时例化：
//   - thumbnail_layout      ：X0R 改写后的当前 RTL
//   - thumbnail_layout_ref  ：S7-03b 快照原 RTL（仅重命名模块名）
// 输入激励分三段：
//   A. 全边界扫描：x=0..704、y=0..524 逐点（覆盖 2/160/320/640 与 2/120/240/480）
//   B. 稀疏全象限：旋转 focus_index / image_complete，覆盖门控与边框语义
//   C. 20 万随机点：12 位全量程随机 x/y/de/focus/image_complete，覆盖截位与越界
// 每个激励点逐拍比对 {thumb_de, source_index, source_x, source_y, focus_border}。
// =============================================================================
module tb_thumbnail_layout_equiv;
    reg         in_de = 1'b0;
    reg  [11:0] pixel_x = 12'd0;
    reg  [11:0] pixel_y = 12'd0;
    reg  [1:0]  focus_index = 2'd0;
    reg  [3:0]  image_complete = 4'b1111;

    wire        d_thumb_de,     d_focus_border;
    wire [1:0]  d_source_index;
    wire [9:0]  d_source_x,     d_source_y;
    wire        r_thumb_de,     r_focus_border;
    wire [1:0]  r_source_index;
    wire [9:0]  r_source_x,     r_source_y;

    thumbnail_layout dut (
        .in_de        (in_de),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (d_thumb_de),
        .source_index (d_source_index),
        .source_x     (d_source_x),
        .source_y     (d_source_y),
        .focus_border (d_focus_border)
    );

    thumbnail_layout_ref ref (
        .in_de        (in_de),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (r_thumb_de),
        .source_index (r_source_index),
        .source_x     (r_source_x),
        .source_y     (r_source_y),
        .focus_border (r_focus_border)
    );

    integer errors = 0;
    integer checks = 0;
    reg [23:0] got;
    reg [23:0] exp;
    reg [31:0] lfsr = 32'h1a2b_3c4d;

    integer ix, iy, n;

    task compare_now;
        begin
            #1;
            checks = checks + 1;
            got = {d_thumb_de, d_source_index, d_source_x, d_source_y, d_focus_border};
            exp = {r_thumb_de, r_source_index, r_source_x, r_source_y, r_focus_border};
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL de=%b x=%0d y=%0d focus=%0d cmp=%b got=%h exp=%h",
                             in_de, pixel_x, pixel_y, focus_index, image_complete, got, exp);
            end
        end
    endtask

    initial begin
        focus_index    = 2'd0;
        image_complete = 4'b1111;

        // ---------- A：边界全域逐点（含缩略图区外与屏幕外） ----------
        for (ix = 0; ix <= 704; ix = ix + 1) begin
            for (iy = 0; iy <= 524; iy = iy + 1) begin
                in_de   = 1'b1;
                pixel_x = ix[11:0];
                pixel_y = iy[11:0];
                compare_now;
            end
        end

        // ---------- B：稀疏全象限，旋转 focus / image_complete ----------
        for (ix = 0; ix <= 704; ix = ix + 3) begin
            for (iy = 0; iy <= 524; iy = iy + 3) begin
                in_de          = 1'b1;
                pixel_x        = ix[11:0];
                pixel_y        = iy[11:0];
                focus_index    = ix[1:0];
                image_complete = iy[3:0];
                compare_now;
            end
        end

        // ---------- C：12 位全量程随机 ----------
        for (n = 0; n < 200000; n = n + 1) begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            pixel_x        = lfsr[11:0];
            pixel_y        = lfsr[23:12];
            focus_index    = lfsr[25:24];
            image_complete = lfsr[29:26];
            in_de          = lfsr[30];
            compare_now;
        end

        if (errors == 0)
            $display("PASS: tb_thumbnail_layout_equiv checks=%0d errors=0", checks);
        else
            $display("FAIL: tb_thumbnail_layout_equiv checks=%0d errors=%0d", checks, errors);
        $finish;
    end
endmodule
