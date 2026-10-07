`timescale 1ns/1ps
// =============================================================================
// tb_seg_business_mux —— X1C 数码管业务 mux 仿真
//   参数化节拍：CLK_FREQ_HZ=1_000_000，1 ms = 1000 拍，确定性推进；
//   采样统一在 negedge，避免与 posedge 非阻塞更新竞争。
//   覆盖：MM:SS 计时与饱和方向、未播放曲目号、KEY3 循环显示项、
//         故障页优先且恢复 0 退出、SW3 门控、参数临时值保持、SW1 总熄灭。
// =============================================================================
module tb_seg_business_mux;
    localparam [6:0] BLANK   = 7'b111_1111;
    localparam integer MS    = 1000;          // 1 ms 拍数
    localparam integer SEC   = 1_000 * MS;    // 1 s 拍数

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg display_enable = 1'b1;
    reg mode_tgl = 1'b0;
    reg debug_sw = 1'b0;
    reg [7:0] error_code = 8'd0;
    reg param_valid = 1'b0;
    reg [15:0] param_value = 16'd0;
    reg play_active = 1'b0;
    reg paused = 1'b0;
    reg track_step = 1'b0;
    reg [1:0] song_index = 2'd0;

    wire [7:0] d0, d1, d2, d3, d4, d5;
    integer errors = 0;
    seg_business_mux #(
        .CLK_FREQ_HZ   (1_000_000),
        .PARAM_HOLD_MS (2000)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .display_enable (display_enable),
        .mode_tgl       (mode_tgl),
        .debug_sw       (debug_sw),
        .error_code     (error_code),
        .param_valid    (param_valid),
        .param_value    (param_value),
        .play_active    (play_active),
        .paused         (paused),
        .track_step     (track_step),
        .song_index     (song_index),
        .seg_data_0     (d0),
        .seg_data_1     (d1),
        .seg_data_2     (d2),
        .seg_data_3     (d3),
        .seg_data_4     (d4),
        .seg_data_5     (d5)
    );

    always #500 clk = ~clk;   // 1 MHz：1 拍 = 1 us，1 ms = 1000 拍

    function [6:0] seg_of;
        input [3:0] v;
        begin
            case (v)
                4'h0:    seg_of = 7'b100_0000;
                4'h1:    seg_of = 7'b111_1001;
                4'h2:    seg_of = 7'b010_0100;
                4'h3:    seg_of = 7'b011_0000;
                4'h4:    seg_of = 7'b001_1001;
                4'h5:    seg_of = 7'b001_0010;
                4'h6:    seg_of = 7'b000_0010;
                4'h7:    seg_of = 7'b111_1000;
                4'h8:    seg_of = 7'b000_0000;
                4'h9:    seg_of = 7'b001_0000;
                4'he:    seg_of = 7'b000_0110;
                4'hd:    seg_of = 7'b010_0001;
                default: seg_of = 7'b000_1110;
            endcase
        end
    endfunction

    task check_digit;
        input [7:0] got;
        input [3:0] hex;
        input [255:0] name;
        reg [7:0] want;
        begin
            want = {1'b1, seg_of(hex)};
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%b want=%b", name, got, want);
            end
        end
    endtask

    task check_blank;
        input [7:0] got;
        input [255:0] name;
        begin
            if (got !== {1'b1, BLANK}) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%b want blank", name, got);
            end
        end
    endtask

    // 在 negedge 采样并检查（此时上一拍的组合显示已稳定）
    task sample_all;
        begin
            @(negedge clk);
            #1;
        end
    endtask

    task toggle_mode;
        begin
            @(negedge clk);
            mode_tgl = ~mode_tgl;
            repeat (5) @(posedge clk);
            @(negedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // 1) 未播放：显示曲目编号（song_index=2 -> 3）
        song_index = 2'd2;
        repeat (5) @(posedge clk);
        sample_all;
        check_digit(d5, 4'h3, "idle shows song index");
        check_blank(d4, "idle d4 blank");

        // 2) 播放：1 s 后应为 00:01（play 置位与 ms_div 相位差 <1 ms）
        play_active = 1'b1;
        repeat (SEC + 20) @(posedge clk);
        sample_all;
        check_digit(d0, 4'h0, "MM tens = 0");
        check_digit(d1, 4'h0, "MM ones = 0");
        check_digit(d4, 4'h0, "SS tens = 0");
        check_digit(d5, 4'h1, "SS ones = 1");
        check_blank(d2, "colon d2 blank");
        check_blank(d3, "colon d3 blank");

        // 3) 再走 60 s -> 01:01
        repeat (60 * SEC) @(posedge clk);
        sample_all;
        check_digit(d0, 4'h0, "MM tens = 0 (01:01)");
        check_digit(d1, 4'h1, "MM ones = 1");
        check_digit(d4, 4'h0, "SS tens = 0");
        check_digit(d5, 4'h1, "SS ones = 1");

        // 4) 暂停：计时冻结
        paused = 1'b1;
        repeat (5 * SEC) @(posedge clk);
        sample_all;
        check_digit(d5, 4'h1, "paused freezes SS ones");
        paused = 1'b0;

        // 5) KEY3 -> 曲目编号；再 -> 诊断项（受 SW3 门控）；再 -> MM:SS
        toggle_mode;
        check_digit(d5, 4'h3, "mode1 shows song index");
        toggle_mode;
        debug_sw = 1'b0;
        sample_all;
        check_blank(d5, "mode2 gated by SW3");
        debug_sw = 1'b1;
        repeat (4) @(posedge clk);
        sample_all;
        check_digit(d5, 4'hd, "mode2 debug marker");
        toggle_mode;
        check_digit(d5, 4'h1, "mode0 back to MM:SS");

        // 6) 故障页优先：E + 05，恢复 0 后退出
        error_code = 8'd5;
        repeat (4) @(posedge clk);
        sample_all;
        check_digit(d5, 4'he, "fault marker E");
        check_digit(d4, 4'h0, "fault high nibble");
        check_digit(d3, 4'h5, "fault low nibble");
        check_blank(d0, "fault d0 blank");
        error_code = 8'd0;
        repeat (4) @(posedge clk);
        sample_all;
        check_digit(d5, 4'h1, "fault cleared -> MM:SS");

        // 7) 参数临时值优先于选择项（X5 前路径预验证）
        param_value = 16'h1234;
        param_valid = 1'b1;
        repeat (4) @(posedge clk);
        param_valid = 1'b0;
        sample_all;
        check_digit(d5, 4'h1, "param tens of thousands");
        check_digit(d4, 4'h2, "param thousands");
        check_digit(d3, 4'h3, "param hundreds");
        check_digit(d2, 4'h4, "param tens");
        repeat (2001 * MS + 100) @(posedge clk);   // > 2 s 保持窗
        sample_all;
        check_blank(d2, "param expired -> MM:SS (d2 blank)");

        // 8) SW1 关闭 -> 全灭
        display_enable = 1'b0;
        sample_all;
        check_blank(d0, "SW1 off d0");
        check_blank(d1, "SW1 off d1");
        check_blank(d2, "SW1 off d2");
        check_blank(d3, "SW1 off d3");
        check_blank(d4, "SW1 off d4");
        check_blank(d5, "SW1 off d5");

        if (errors == 0)
            $display("TEST_PASS seg_business_mux");
        else
            $display("TEST_FAIL seg_business_mux errors=%0d", errors);
        $finish;
    end

    initial begin
        #80_000_000_000;
        $display("TEST_FAIL seg_business_mux watchdog");
        $finish;
    end
endmodule
