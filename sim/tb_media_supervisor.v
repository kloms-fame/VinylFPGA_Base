`timescale 1ns/1ps
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
    wire [7:0] media_epoch;
    wire [15:0] cnt_sd_reset;
    wire [15:0] cnt_sector_err;

    integer errors = 0;
    integer i;

    // 用极小参数把毫秒期限映射成少量时钟周期，加速定向仿真：
    // CLK_FREQ_HZ=1000 使 (CLK_FREQ_HZ/1000)=1，于是 MOUNT_TIMEOUT_MS 直接等于周期数。
    media_supervisor #(
        .CLK_FREQ_HZ         (1000),
        .MOUNT_TIMEOUT_MS    (8),
        .SECTOR_TIMEOUT_MS   (1),
        .MOUNT_RETRY_MAX     (3),
        .REMOUNT_COOLDOWN_MS (12),
        .RESET_PULSE_CYCLES  (4)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .media_ready    (media_ready),
        .sector_error   (sector_error),
        .sector_done    (sector_done),
        .sector_busy    (sector_busy),
        .sd_rst_n       (sd_rst_n),
        .media_err_code (media_err_code),
        .media_err_toggle(media_err_toggle),
        .media_epoch    (media_epoch),
        .cnt_sd_reset   (cnt_sd_reset),
        .cnt_sector_err (cnt_sector_err)
    );

    always #5 clk = ~clk;

    task check;
        input cond;
        input [255:0] name;
        begin
            if (!cond) begin
                $display("FAIL: %0s (t=%0t)", name, $time);
                errors = errors + 1;
            end
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
        check(sd_rst_n === 1'b1, "复位释放后 sd_rst_n 为高");
        check(media_err_code === 8'h00, "上电错误码为零");
        check(media_epoch === 8'd0, "上电代次为零");

        // ---- 场景1：挂载成功，不应复位、不报错 ----
        media_ready = 1'b1;
        wait_cycles(30);
        check(media_err_code === 8'h00, "挂载成功错误码保持零");
        check(cnt_sd_reset === 16'd0, "挂载成功不产生复位");
        check(media_epoch === 8'd0, "挂载成功代次不递增");

        // ---- 场景2：无卡持续超时 -> 3 次重试 -> 冷却 -> 第 4 次复位 ----
        media_ready = 1'b0;
        wait (media_epoch == 8'd3);
        check(media_err_code === 8'h01, "挂载超时置 Err-01");
        check(cnt_sd_reset === 16'd3, "三轮重试计数为 3");
        // 3 次重试后应进入冷却，第 4 次复位不应紧随其后。
        wait (media_epoch == 8'd4);
        check(cnt_sd_reset === 16'd4, "冷却后第 4 次复位计数为 4");

        // ---- 场景3：重插恢复 ----
        media_ready = 1'b1;
        wait_cycles(30);
        check(media_epoch === 8'd4, "恢复后不再产生复位");
        check(media_err_code === 8'h01, "错误码保持最近非零(sticky)");

        // ---- 场景4：扇区读超时 -> 立即复位恢复 ----
        sector_done  = 1'b1;
        sector_error = 8'h05;
        wait (sd_rst_n === 1'b0);
        sector_done  = 1'b0;
        sector_error = 8'h00;
        wait (sd_rst_n === 1'b1);
        check(media_err_code === 8'h05, "扇区超时置 Err-05");
        check(media_epoch === 8'd5, "扇区超时复位代次递增");
        check(cnt_sector_err === 16'd1, "扇区错误计数为 1");

        // 场景4 复位后 media_ready 仍为 1，短暂恢复后确认稳定。
        wait_cycles(10);
        check(sd_rst_n === 1'b1, "恢复后复位释放");

        if (errors == 0)
            $display("PASS: media_supervisor");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
