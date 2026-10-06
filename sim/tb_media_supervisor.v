`timescale 1ns/1ps
// S7-02 media_supervisor 定向验证：挂载看门狗（超时/重试/恢复）与扇区事务
// 看门狗（读超时立即复位）。用极小参数把毫秒期限映射成少量时钟周期加速。
// 本测试不依赖内部遥测，通过 sd_rst_n 下降沿计数观测复位（黑盒口径）。
module tb_media_supervisor;
    reg clk = 0;
    reg rst_n = 0;
    reg media_ready = 0;
    reg [7:0] sector_error = 0;
    reg sector_done = 0;
    reg sector_busy = 0;

    wire sd_rst_n;
    wire [7:0] media_err_code;
    wire media_err_toggle;

    integer errors = 0;
    integer check_id = 0;
    integer i;
    integer saved_cnt;
    integer rst_fall_cnt = 0;
    reg sd_rst_n_prev = 0;

    // CLK_FREQ_HZ=2000 -> 预分频 PRE_DIV=2，即 1ms=2 周期：
    // 挂载期限 8ms=16 周期、冷却 12ms=24 周期、复位脉冲 4 周期。
    media_supervisor #(
        .CLK_FREQ_HZ         (2000),
        .MOUNT_TIMEOUT_MS    (8),
        .MOUNT_RETRY_MAX     (3),
        .REMOUNT_COOLDOWN_MS (12),
        .RESET_PULSE_CYCLES  (4)
    ) dut (.mount_error(8'd0),
        .clk            (clk),
        .rst_n          (rst_n),
        .media_ready    (media_ready),
        .sector_error   (sector_error),
        .sector_done    (sector_done),
        .sector_busy    (sector_busy),
        .sd_rst_n       (sd_rst_n),
        .media_err_code (media_err_code),
        .media_err_toggle(media_err_toggle)
    );

    always #5 clk = ~clk;

    // 统计 sd_rst_n 下降沿（复位脉冲开始）。
    always @(posedge clk) begin
        sd_rst_n_prev <= sd_rst_n;
        if (rst_n && sd_rst_n_prev && !sd_rst_n)
            rst_fall_cnt = rst_fall_cnt + 1;
    end

    task check;
        input cond;
        input [255:0] name;
        begin
            if (!cond) begin
                $display("FAIL[%0d]: %0s (t=%0t)", check_id, name, $time);
                errors = errors + 1;
            end
            check_id = check_id + 1;
        end
    endtask

    task wait_cycles;
        input integer n;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    initial begin
        wait_cycles(5);
        rst_n = 1;
        wait_cycles(3);
        check(sd_rst_n === 1'b1, "reset-released sd_rst_n high");
        check(media_err_code === 8'h00, "boot err zero");

        // ---- 场景1：挂载成功，不应复位、不报错 ----
        media_ready = 1'b1;
        wait_cycles(40);
        check(media_err_code === 8'h00, "mount-ok err zero");
        check(rst_fall_cnt === 0, "mount-ok no reset");

        // ---- 场景2：无卡持续超时 -> Err-01，并持续重试复位 ----
        media_ready = 1'b0;
        wait (rst_fall_cnt >= 2);
        check(media_err_code === 8'h01, "mount-timeout Err-01");
        check(rst_fall_cnt >= 2, "mount-timeout repeated reset");

        // ---- 场景3：重插恢复，复位停止 ----
        media_ready = 1'b1;
        wait (sd_rst_n === 1'b1);
        wait_cycles(40);
        check(media_err_code === 8'h00, "active error clear after recovery");
        saved_cnt = rst_fall_cnt;
        wait_cycles(40);
        check(rst_fall_cnt === saved_cnt, "recovery stops reset");

        // ---- 场景4：扇区读超时 -> 立即复位恢复 ----
        sector_done  = 1'b1;
        sector_error = 8'h05;
        wait (sd_rst_n === 1'b0);
        sector_done  = 1'b0;
        sector_error = 8'h00;
        wait (sd_rst_n === 1'b1);
        check(media_err_code === 8'h05, "sector-timeout Err-05");
        wait_cycles(10);
        check(sd_rst_n === 1'b1, "sector-recovery reset released");

        if (errors == 0)
            $display("PASS: media_supervisor");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
