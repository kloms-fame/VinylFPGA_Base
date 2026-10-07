// =============================================================================
// tb_led_business_driver —— X1A 单灯仿真
//   LED1=有效红外脉冲 / LED2=已接受业务动作 / LED3=1 Hz 心跳 / LED4=当前故障，
//   DIP3(en)=0 时组合全灭。为加快仿真把频率/时长按比例缩小。
// =============================================================================
`timescale 1ns/1ps
module tb_led_business_driver;
    localparam integer CLK_NS = 100;     // 10 MHz

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg en = 1'b1;
    reg ir_accepted = 1'b0;
    reg biz_accepted = 1'b0;
    reg fault = 1'b0;

    wire [3:0] led_n;
    integer errors = 0;

    led_business_driver #(
        .CLK_FREQ_HZ  (10_000_000),
        .PULSE_MS     (2),
        .HEARTBEAT_MS (4)          // 半周期 2 ms -> 1 kHz "心跳"，仿真用
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .ir_accepted  (ir_accepted),
        .biz_accepted (biz_accepted),
        .fault        (fault),
        .led_n        (led_n)
    );

    always #(CLK_NS/2) clk = ~clk;

    task expect_bit;
        input [3:0] idx;
        input       val;
        input [255:0] name;
        begin
            if (led_n[idx] !== val) begin
                errors = errors + 1;
                $display("FAIL %0s: led_n=%b (bit%0d expect %b)", name, led_n, idx, val);
            end
        end
    endtask

    task pulse_ir;
        begin
            @(negedge clk);
            ir_accepted = 1'b1;
            @(negedge clk);
            ir_accepted = 1'b0;
        end
    endtask

    task pulse_biz;
        begin
            @(negedge clk);
            biz_accepted = 1'b1;
            @(negedge clk);
            biz_accepted = 1'b0;
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 空闲：只有心跳在动，LED1/2/4 灭
        expect_bit(3'd0, 1'b1, "idle LED1 off");
        expect_bit(3'd1, 1'b1, "idle LED2 off");
        expect_bit(3'd3, 1'b1, "idle LED4 off");

        // 1) 有效红外 -> LED1 亮 2 ms
        pulse_ir;
        repeat (2) @(posedge clk);
        expect_bit(3'd0, 1'b0, "IR pulse lights LED1");
        repeat (25_000) @(posedge clk);      // 10 MHz -> 2.5 ms > PULSE_MS
        expect_bit(3'd0, 1'b1, "IR pulse expires");

        // 2) 已接受业务动作 -> LED2 亮 2 ms
        pulse_biz;
        repeat (2) @(posedge clk);
        expect_bit(3'd1, 1'b0, "biz pulse lights LED2");
        repeat (25_000) @(posedge clk);
        expect_bit(3'd1, 1'b1, "biz pulse expires");

        // 3) 故障保持
        fault = 1'b1;
        repeat (4) @(posedge clk);
        expect_bit(3'd3, 1'b0, "fault holds LED4 on");
        repeat (50_000) @(posedge clk);      // 500 us
        expect_bit(3'd3, 1'b0, "fault still on");
        fault = 1'b0;
        repeat (4) @(posedge clk);
        expect_bit(3'd3, 1'b1, "fault clears LED4");

        // 4) DIP3 关闭 -> 组合全灭（含正在亮的脉冲与心跳）
        pulse_ir;
        repeat (2) @(posedge clk);
        expect_bit(3'd0, 1'b0, "LED1 on before gate");
        en = 1'b0;
        #(CLK_NS/2);
        if (led_n !== 4'hF) begin
            errors = errors + 1;
            $display("FAIL DIP3 gate not dark: led_n=%b", led_n);
        end
        en = 1'b1;
        #(CLK_NS/2);
        repeat (2) @(posedge clk);
        expect_bit(3'd0, 1'b1, "gate re-open clears stale pulse");

        if (errors == 0)
            $display("TEST_PASS led_business_driver");
        else
            $display("TEST_FAIL led_business_driver errors=%0d", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TEST_FAIL led_business_driver watchdog");
        $finish;
    end
endmodule
