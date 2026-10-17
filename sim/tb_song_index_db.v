`timescale 1ns/1ps

// =============================================================================
// S4 回归：song_index_db（INDEX.BIN 流式解析与校验）
//
// 用例（喂入同一份由 tools/vinyl_packer.py 生成的真实 512 字节索引）：
//   1) 合法索引   -> valid=1，曲目 4，封面/音频定位与工具报告一致
//   2) magic 错   -> SIDX_ERR_MAGIC
//   3) 条目被改    -> SIDX_ERR_CRC
//   4) song_count=5 -> SIDX_ERR_COUNT（超限必须拒绝，不得静默越界）
//   5) max_cluster 收紧 -> SIDX_ERR_CLUSTER_RANGE
//   6) 文件流报错  -> SIDX_ERR_STREAM
// =============================================================================
module tb_song_index_db;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg        start = 1'b0;
    reg        in_valid = 1'b0;
    reg [7:0]  in_byte = 8'd0;
    reg        in_done = 1'b0;
    reg [7:0]  in_error = 8'd0;
    reg [31:0] max_cluster = 32'd25;

    wire        busy;
    wire        done;
    wire        valid;
    wire [7:0]  err;
    wire [2:0]  song_count;
    wire [15:0] song_flags;
    wire [63:0] cov0, cov1, cov2, cov3;
    wire [63:0] aud0, aud1, aud2, aud3;

    reg [7:0] blob  [0:511];
    reg [7:0] blob0 [0:511];
    integer errors = 0;
    integer i;
    integer count_case;
    integer fd;
    reg [8*80:1] hex_path;

    song_index_db #(.MAX_SONGS(4)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .in_valid    (in_valid),
        .in_byte     (in_byte),
        .in_done     (in_done),
        .in_error    (in_error),
        .max_cluster (max_cluster),
        .busy        (busy),
        .done        (done),
        .valid       (valid),
        .err         (err),
        .song_count  (song_count),
        .song_flags  (song_flags),
        .song_cover0 (cov0),
        .song_cover1 (cov1),
        .song_cover2 (cov2),
        .song_cover3 (cov3),
        .song_audio0 (aud0),
        .song_audio1 (aud1),
        .song_audio2 (aud2),
        .song_audio3 (aud3)
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

    // 逐字节喂入一份索引；结束后等两拍再返回，便于观察 valid/err 等寄存器
    task feed;
        input [31:0] mc;
        input [7:0]  err_inject;
        begin
            @(negedge clk); start = 1'b1; max_cluster = mc;
            @(negedge clk); start = 1'b0;
            for (i = 0; i < 512; i = i + 1) begin
                @(negedge clk);
                in_valid  = 1'b1;
                in_byte   = blob[i];
            end
            @(negedge clk); in_valid = 1'b0;
            @(negedge clk); in_done = 1'b1; in_error = err_inject;
            @(negedge clk); in_done = 1'b0; in_error = 8'd0;
            // 解析器含"逐拍条目校验"阶段，结束后再等足若干拍
            repeat (14) @(posedge clk); #1;
        end
    endtask

    task restore;
        begin
            for (i = 0; i < 512; i = i + 1) blob[i] = blob0[i];
        end
    endtask

    task update_entries_crc;
        input integer count;
        integer n;
        integer bit_no;
        reg [31:0] crc;
        begin
            crc = 32'hFFFFFFFF;
            for (n = 0; n < count * 64; n = n + 1) begin
                crc = crc ^ {24'd0, blob[64+n]};
                for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                    if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320;
                    else         crc = crc >> 1;
                end
            end
            crc = crc ^ 32'hFFFFFFFF;
            blob[16] = crc[7:0];
            blob[17] = crc[15:8];
            blob[18] = crc[23:16];
            blob[19] = crc[31:24];
        end
    endtask

    initial begin
        hex_path = "sim/s4_fixture/index_only.hex";
        fd = $fopen(hex_path, "r");
        if (fd == 0) begin
            hex_path = "../sim/s4_fixture/index_only.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "s4_fixture/index_only.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "../../sim/s4_fixture/index_only.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            $display("FAIL: 找不到 index_only.hex 夹具");
            $finish;
        end
        $fclose(fd);
        $readmemh(hex_path, blob);
        for (i = 0; i < 512; i = i + 1) blob0[i] = blob[i];

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 1) 合法索引
        restore;
        feed(32'd25, 8'h00);
        check(valid === 1'b1, "合法索引 valid=1");
        check(err === 8'h00, "合法索引 err=0");
        check(song_count === 3'd4, "合法索引曲目数=4");
        check(song_flags === 16'h1113, "song_flags = {1,1,1,3}");
        check(cov0 === {32'd822, 32'd3}, "song0 封面 {bytes=822,cluster=3}");
        check(cov1 === {32'd822, 32'd6}, "song1 封面 cluster=6");
        check(cov2 === {32'd822, 32'd8}, "song2 封面 cluster=8");
        check(cov3 === {32'd822, 32'd10}, "song3 封面 cluster=10");
        check(aud0 === {32'd2048, 32'd12}, "song0 音频 {bytes=2048,cluster=12}");

        // Valid entry counts exercise each exclusive CRC end (128/192/256).
        for (count_case = 1; count_case < 4; count_case = count_case + 1) begin
            restore;
            blob[12] = count_case[7:0];
            blob[13] = 8'd0;
            update_entries_crc(count_case);
            feed(32'd25, 8'h00);
            check(valid === 1'b1 && song_count === count_case[2:0],
                  "valid song_count 1..3 and matching CRC span");
        end

        // 2) magic 错
        restore; blob[0] = blob[0] ^ 8'hFF;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h30, "magic 错 -> 0x30 且 valid=0");
        check(cov0 === 64'd0 && aud0 === 64'd0,
              "默认模块接口在索引无效时继续屏蔽 payload");

        // 3) 条目区被改 -> CRC 错
        restore; blob[64 + 5] = blob[64 + 5] ^ 8'h01;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h34, "条目被改 -> 0x34 CRC 错");

        // 4) song_count 超限
        restore; blob[12] = 8'd5; blob[13] = 8'd0;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h33, "song_count=5 -> 0x33 超限拒绝");

        // Invalid 16-bit counts must not alias through the low three bits of
        // the narrowed CRC end calculation.
        restore; blob[12] = 8'd0; blob[13] = 8'd0;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h33 && dut.crc_calc === 32'hFFFFFFFF,
              "song_count=0 rejected without CRC alias");
        restore; blob[12] = 8'd8; blob[13] = 8'd0;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h33 && dut.crc_calc === 32'hFFFFFFFF,
              "song_count=8 rejected without CRC alias");
        restore; blob[12] = 8'd1; blob[13] = 8'd1;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h33 && dut.crc_calc === 32'hFFFFFFFF,
              "song_count=0x0101 rejected without low-bit alias");
        restore; blob[12] = 8'hFF; blob[13] = 8'hFF;
        feed(32'd25, 8'h00);
        check(valid === 1'b0 && err === 8'h33 && dut.crc_calc === 32'hFFFFFFFF,
              "song_count=0xFFFF rejected without low-bit alias");

        // 5) 簇号越界（收紧 max_cluster）
        restore;
        feed(32'd2, 8'h00);
        check(valid === 1'b0 && err === 8'h35, "簇越界 -> 0x35");

        // 6) 文件流报错
        restore;
        feed(32'd25, 8'h10);
        check(valid === 1'b0 && err === 8'h36, "文件流错误 -> 0x36");

        if (errors == 0)
            $display("TEST_PASS song_index_db_s4");
        else
            $display("FAIL: tb_song_index_db errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_song_index_db timeout");
        $finish;
    end
endmodule
