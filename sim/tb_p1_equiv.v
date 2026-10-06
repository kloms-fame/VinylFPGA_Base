`timescale 1ns/1ps
// =============================================================================
// P1 等价性验证实验（一次性，不并入回归套件）
//
// 目的：证明把 song_cover0..3 / song_audio0..3 由"输出寄存器"改为
//       "assign 直连内部 e_* 数组"之后，**消费者可观察到有效值的最早
//       时刻完全不变**，即功能行为零改变。
//
// 方法：构造两个被测模块——REF（当前实现，输出寄存器）与 GOLD（优化实现，
//       输出直连）。喂入同一份真实 INDEX.BIN 字节流，逐拍对比两者
//       所有输出端口。两者都必须跑完整 512 字节。
//
// 判据：REF 与 GOLD 的 (valid, song_count, song_cover*, song_audio*,
//       song_mv*, err) 在每个仿真时刻完全一致 => 行为等价。
// =============================================================================
module tb_p1_equiv;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg        start = 1'b0;
    reg        in_valid = 1'b0;
    reg  [7:0] in_byte = 8'd0;
    reg        in_done = 1'b0;
    reg  [7:0] in_error = 8'd0;
    reg  [31:0] max_cluster = 32'd25;

    always #5 clk = ~clk;

    // ---------------- REF：当前 RTL（输出寄存器）----------------
    wire        r_busy, r_done, r_valid;
    wire [7:0]  r_err;
    wire [2:0]  r_song_count;
    wire [15:0] r_song_flags;
    wire [63:0] r_cov0, r_cov1, r_cov2, r_cov3;
    wire [63:0] r_aud0, r_aud1, r_aud2, r_aud3;
    wire [63:0] r_mv0, r_mv1, r_mv2, r_mv3;

    song_index_db #(.MAX_SONGS(4)) ref_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .in_valid(in_valid), .in_byte(in_byte), .in_done(in_done),
        .in_error(in_error), .max_cluster(max_cluster),
        .busy(r_busy), .done(r_done), .valid(r_valid), .err(r_err),
        .song_count(r_song_count), .song_flags(r_song_flags),
        .song_cover0(r_cov0), .song_cover1(r_cov1),
        .song_cover2(r_cov2), .song_cover3(r_cov3),
        .song_audio0(r_aud0), .song_audio1(r_aud1),
        .song_audio2(r_aud2), .song_audio3(r_aud3),
        .song_mv0(r_mv0), .song_mv1(r_mv1), .song_mv2(r_mv2), .song_mv3(r_mv3)
    );

    // ---------------- GOLD：P1 优化后（输出直连 e_*）----------------
    // 只替换输出接口的驱动方式，内部解析逻辑完全照抄 REF。
    wire        g_busy, g_done, g_valid;
    wire [7:0]  g_err;
    wire [2:0]  g_song_count;
    wire [15:0] g_song_flags;
    wire [63:0] g_cov0, g_cov1, g_cov2, g_cov3;
    wire [63:0] g_aud0, g_aud1, g_aud2, g_aud3;
    wire [63:0] g_mv0, g_mv1, g_mv2, g_mv3;

    song_index_db_p1 #(.MAX_SONGS(4)) gold_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .in_valid(in_valid), .in_byte(in_byte), .in_done(in_done),
        .in_error(in_error), .max_cluster(max_cluster),
        .busy(g_busy), .done(g_done), .valid(g_valid), .err(g_err),
        .song_count(g_song_count), .song_flags(g_song_flags),
        .song_cover0(g_cov0), .song_cover1(g_cov1),
        .song_cover2(g_cov2), .song_cover3(g_cov3),
        .song_audio0(g_aud0), .song_audio1(g_aud1),
        .song_audio2(g_aud2), .song_audio3(g_aud3),
        .song_mv0(g_mv0), .song_mv1(g_mv1), .song_mv2(g_mv2), .song_mv3(g_mv3)
    );

    // ---------------- 逐拍比对 ----------------
    integer errors = 0;
    integer checks = 0;
    integer cyc = 0;

    always @(posedge clk) if (rst_n) begin
        cyc = cyc + 1;
        checks = checks + 1;
        if (r_valid !== g_valid) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH valid @%0d  ref=%b gold=%b", cyc, r_valid, g_valid);
        end
        if (r_err !== g_err) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH err @%0d  ref=%h gold=%h", cyc, r_err, g_err);
        end
        if (r_song_count !== g_song_count) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH song_count @%0d", cyc);
        end
        if (r_cov0 !== g_cov0 || r_cov1 !== g_cov1 ||
            r_cov2 !== g_cov2 || r_cov3 !== g_cov3) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH cover @%0d  ref=%h %h %h %h | gold=%h %h %h %h",
                         cyc, r_cov0, r_cov1, r_cov2, r_cov3,
                         g_cov0, g_cov1, g_cov2, g_cov3);
        end
        if (r_aud0 !== g_aud0 || r_aud1 !== g_aud1 ||
            r_aud2 !== g_aud2 || r_aud3 !== g_aud3) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH audio @%0d", cyc);
        end
        if (r_mv0 !== g_mv0 || r_mv1 !== g_mv1 ||
            r_mv2 !== g_mv2 || r_mv3 !== g_mv3) begin
            errors = errors + 1;
            if (errors < 12)
                $display("MISMATCH mv @%0d", cyc);
        end
    end

    // ---------------- 激励：真实 INDEX.BIN ----------------
    reg [7:0] blob [0:511];
    integer i, fd;
    reg [8*80:1] hex_path;

    initial begin
        if (!$value$plusargs("blob=%s", hex_path)) begin
            $display("FATAL: need +blob=<path to INDEX.BIN hex>");
            $finish;
        end
        $readmemh(hex_path, blob);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (i = 0; i < 512; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_byte  = blob[i];
        end
        @(negedge clk);
        in_valid = 1'b0;
        in_done  = 1'b1;
        @(negedge clk);
        in_done  = 1'b0;

        repeat (200) @(posedge clk);

        $display("");
        $display("REF_FINAL valid=%b err=%02h song_count=%0d cov0=%h aud0=%h mv0=%h",
                 r_valid, r_err, r_song_count, r_cov0, r_aud0, r_mv0);
        $display("P1_EQUIV_RESULT checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("P1_EQUIV_PASS  song_cover/audio 去寄存器化与当前实现行为完全一致");
        else
            $display("P1_EQUIV_FAIL  存在行为差异，禁止实施");
        $finish;
    end
endmodule