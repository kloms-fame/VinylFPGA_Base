// =============================================================================
// tb_expansion_s1 —— S1 集成层最小冒烟验证
//
// 覆盖：上电横幅 / KEY 消抖边沿 -> 事件 + LED 回显 / DIP 变化事件 /
//       EC1 正交步进 / NEC 红外帧（同一行两个子串）/ 周期状态行。
// 为加快仿真，把消抖/稳定/波特率/周期参数按比例缩小（不改处理顺序）。
//
// 接收侧用"永不阻塞的行环缓冲 + 按行序号轮询匹配"，避免测试台采样速度
// 影响对串口输出的判定。
// =============================================================================
`timescale 1ns/1ps
module tb_expansion_s1;

    localparam integer CLK_NS = 1000;    // 1 MHz
    localparam integer BIT_NS = 10000;   // 100 kbaud @ 1 MHz
    localparam integer NSLOT  = 8;       // 行环缓冲槽位数

    reg clk    = 1'b0;
    reg rst_n  = 1'b0;

    reg [11:0] exp_key_n     = 12'hFFF;
    reg [5:0]  exp_dip_n     = 6'h3F;
    reg        exp_enc1_a    = 1'b1;
    reg        exp_enc1_b    = 1'b1;
    reg        exp_enc1_sw_n = 1'b1;
    reg        exp_enc2_a    = 1'b1;
    reg        exp_enc2_b    = 1'b1;
    reg        exp_enc2_sw_n = 1'b1;
    reg        exp_ir_rx     = 1'b1;
    reg [23:0] media_status = 24'd0;
    reg boot_active = 1'b1;
    reg        tb_sw1        = 1'b1;   // 母板拨码 SW1（用于反馈音检查）

    wire [3:0] exp_led_n;
    wire       exp_ws2812_data;
    wire [5:0] exp_ext_o;
    wire       board_buzzer_n;
    wire       uart_tx;

    integer errors = 0;

    // 串口行环缓冲
    reg [7:0] lines    [0:NSLOT*128-1];
    integer   lens     [0:NSLOT-1];
    integer   slotseq  [0:NSLOT-1];
    integer   wr_slot     = 0;
    integer   wr_len      = 0;
    integer   line_seq    = 0;
    integer   last_checked = 0;
    reg [7:0] rx_byte;
    integer   dbg_i, dbg_s;

    expansion_integration #(
        .CLK_FREQ_HZ      (1_000_000),
        .BAUD_RATE        (100_000),
        .DEBOUNCE_CYCLES  (4),
        .AB_STABLE_CYCLES (2),
        .IR_CLK_FREQ_HZ   (1_000_000),
        .ECHO_ENABLE      (1'b1)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .exp_key_n        (exp_key_n),
        .exp_dip_n        (exp_dip_n),
        .exp_enc1_a       (exp_enc1_a),
        .exp_enc1_b       (exp_enc1_b),
        .exp_enc1_sw_n    (exp_enc1_sw_n),
        .exp_enc2_a       (exp_enc2_a),
        .exp_enc2_b       (exp_enc2_b),
        .exp_enc2_sw_n    (exp_enc2_sw_n),
        .exp_ir_rx        (exp_ir_rx),
        .key1             (1'b1),
        .key2             (1'b1),
        .key3             (1'b1),
        .sw1              (tb_sw1),
        .sw2              (1'b1),
        .sw3              (1'b1),
        .sw4              (1'b1),
        .exp_led_n        (exp_led_n),
        .exp_ws2812_data  (exp_ws2812_data),
        .exp_ext_o        (exp_ext_o),
        .board_buzzer_n   (board_buzzer_n),
        .boot_active      (boot_active),
        .media_status     (media_status),
                              .underrun_pulse   (1'b0),
                              .wav_buffer_low   (1'b0),
                              .wav_stream_active(1'b0),
                              .mv_failed        (1'b0),
                              .osd_err_valid    (1'b0),
                              .osd_err_code     (8'd0),
        .uart_tx          (uart_tx)
    );

    always #(CLK_NS/2) clk = ~clk;

    task uart_recv;
        output [7:0] d;
        integer k;
        begin
            @(negedge uart_tx);
            #(BIT_NS + BIT_NS/2);
            for (k = 0; k < 8; k = k + 1) begin
                d[k] = uart_tx;
                #(BIT_NS);
            end
        end
    endtask

    // 串口行监视器（永不阻塞）
    initial begin
        for (dbg_s = 0; dbg_s < NSLOT; dbg_s = dbg_s + 1) begin
            lens[dbg_s]    = 0;
            slotseq[dbg_s] = 0;
        end
        forever begin
            uart_recv(rx_byte);
            if (rx_byte == 8'h0D) begin
                // CR：等待随后的 LF
            end else if (rx_byte == 8'h0A) begin
                lens[wr_slot]    = wr_len;
                slotseq[wr_slot] = line_seq + 1;
                line_seq         = line_seq + 1;
                $write("RX: ");
                for (dbg_i = 0; dbg_i < wr_len; dbg_i = dbg_i + 1)
                    $write("%c", lines[wr_slot*128 + dbg_i]);
                $write("\n");
                wr_slot = (wr_slot + 1) % NSLOT;
                wr_len  = 0;
            end else if (wr_len < 127) begin
                lines[wr_slot*128 + wr_len] = rx_byte;
                wr_len = wr_len + 1;
            end
        end
    end

    // 在"尚未检查过"的行里按序号从小到大查找同时含 patA（必要时 patB）的一行
    task wait_match;
        input [8*16-1:0] patA;
        input integer    lenA;
        input [8*16-1:0] patB;
        input integer    lenB;
        input [8*24-1:0] msg;
        integer t, s, i, k, f;
        integer best, bestseq;
        reg     okA, okB, found;
        begin
            found = 1'b0;
            t     = 0;
            while (!found && (t < 2000)) begin
                best    = -1;
                bestseq = 32'h7FFFFFFF;
                for (s = 0; s < NSLOT; s = s + 1) begin
                    if ((slotseq[s] > last_checked) && (slotseq[s] < bestseq)) begin
                        bestseq = slotseq[s];
                        best    = s;
                    end
                end

                if (best >= 0) begin
                    okA = 1'b0;
                    okB = 1'b1;
                    for (i = 0; i + lenA <= lens[best]; i = i + 1) begin
                        f = 1;
                        for (k = 0; k < lenA; k = k + 1)
                            if (lines[best*128 + i + k] !== patA[8*(lenA-1-k) +: 8])
                                f = 0;
                        if (f)
                            okA = 1'b1;
                    end
                    if (lenB > 0) begin
                        okB = 1'b0;
                        for (i = 0; i + lenB <= lens[best]; i = i + 1) begin
                            f = 1;
                            for (k = 0; k < lenB; k = k + 1)
                                if (lines[best*128 + i + k] !== patB[8*(lenB-1-k) +: 8])
                                    f = 0;
                            if (f)
                                okB = 1'b1;
                        end
                    end
                    last_checked = bestseq;
                    if (okA && okB)
                        found = 1'b1;
                end else begin
                    #100000;   // 100 us 轮询
                    t = t + 1;
                end
            end

            if (!found) begin
                errors = errors + 1;
                $display("FAIL missing line [%s]", msg);
            end else begin
                $display("PASS line [%s]", msg);
            end
        end
    endtask

    // NEC 红外帧：9ms 引导 + 4.5ms 间隔 + 32 位 LSB-first + 结束标记
    task ir_frame;
        input [31:0] code;
        integer k;
        begin
            exp_ir_rx = 1'b0; #9000000;
            exp_ir_rx = 1'b1; #4500000;
            for (k = 0; k < 32; k = k + 1) begin
                exp_ir_rx = 1'b0; #560000;
                exp_ir_rx = 1'b1;
                if (code[k])
                    #1690000;
                else
                    #560000;
            end
            exp_ir_rx = 1'b0; #560000;
            exp_ir_rx = 1'b1; #2000000;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // 1) 上电横幅
        wait_match("VINYL EXPHUB S1", 15, "", 0, "banner");

        // 1b) 母板拨码 SW1 变化 -> 反馈音（母板 H11 与拓展板 EXT1 同源）
        tb_sw1 = 1'b0;
        repeat (12) @(posedge clk);
        if (board_buzzer_n !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL board SW feedback: buzzer_n=%b", board_buzzer_n);
        end else begin
            $display("PASS board SW feedback tone");
        end

        // 2) KEY04 按下 -> 事件 + LED2 业务动作脉冲（低有效，80 ms）
        //    X1A 起 LED 不再镜像 KEY 电平：LED1=有效红外 / LED2=已接受业务动作 /
        //    LED3=1 Hz 心跳 / LED4=当前故障。
        exp_key_n[3] = 1'b0;
        wait_match("KEY 04 DOWN", 11, "", 0, "key04-down");
        if (exp_led_n[1] !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL led biz pulse on press: exp_led_n=%b", exp_led_n);
        end else begin
            $display("PASS led biz pulse on press");
        end
        // 操作反馈音：母板蜂鸣器（低有效）应进入鸣叫状态，EXT1 同步输出同一波形
        if ((board_buzzer_n !== 1'b0) || (exp_ext_o[0] !== 1'b0)) begin
            errors = errors + 1;
            $display("FAIL buzzer feedback on key press: buzzer_n=%b ext1=%b",
                     board_buzzer_n, exp_ext_o[0]);
        end else begin
            $display("PASS buzzer feedback on key press");
        end

        // 3) KEY04 释放 -> 事件上报；LED2 会在 80 ms 脉冲结束后自动熄灭
        //    （不镜像 KEY 松开本身，避免松开也点亮）
        exp_key_n[3] = 1'b1;
        wait_match("KEY 04 UP", 9, "", 0, "key04-up");
        begin : led_pulse_decay
            integer waited;
            waited = 0;
            // 80 ms 脉冲 @1 MHz -> 需 >= 80000 拍；留足余量到 150 ms
            while ((exp_led_n[1] !== 1'b1) && (waited < 1500)) begin
                #100000;     // 100 us @ 1 MHz
                waited = waited + 1;
            end
            if (exp_led_n[1] !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL led biz pulse stuck on: exp_led_n=%b", exp_led_n);
            end else begin
                $display("PASS led biz pulse self-clears");
            end
        end

        // 4) 另一路按键（KEY07 -> exp_key_n[6]）验证编号映射
        exp_key_n[6] = 1'b0;
        wait_match("KEY 07 DOWN", 11, "", 0, "key07-down");
        exp_key_n[6] = 1'b1;
        wait_match("KEY 07 UP", 9, "", 0, "key07-up");

        // 5) DIP1 变化
        exp_dip_n[0] = 1'b0;
        wait_match("EXPHUB ABSENT", 13, "", 0, "dip1-presence-off");
        wait_match("DIP 1 0", 7, "", 0, "dip1-low");
        exp_dip_n[0] = 1'b1;
        wait_match("EXPHUB PRESENT", 14, "", 0, "dip1-presence-on");
        wait_match("DIP 1 1", 7, "", 0, "dip1-high");

        // 6) EC1 正向一格（11 -> 10 -> 00 -> 01 -> 11）
        exp_enc1_a = 1'b1; exp_enc1_b = 1'b0; repeat (8) @(posedge clk);
        exp_enc1_a = 1'b0; exp_enc1_b = 1'b0; repeat (8) @(posedge clk);
        exp_enc1_a = 1'b0; exp_enc1_b = 1'b1; repeat (8) @(posedge clk);
        exp_enc1_a = 1'b1; exp_enc1_b = 1'b1; repeat (8) @(posedge clk);
        wait_match("ENC1 + 0001", 11, "", 0, "enc1-fwd");

        // 7) NEC 红外实帧（地址 BA / 命令 FF），同一行同时校验码与命令字
        ir_frame(32'hBA45FF00);
        wait_match("IR BA45FF00", 11, "CMD FF", 6, "ir-frame");

        // Runtime diagnostics are transmitted by the FPGA after scan completion.
        media_status = 24'hFF0000;
        wait_match("INFO DONE=1", 11, "PIC=F AUD=1", 11, "media-info");
        wait_match("VERIFY IDX=00", 13, "FS=00 PRES=1", 12, "media-verify-good");
        media_status = 24'hB03400;
        // Drop boot during a pending report: BOOT DONE must not be lost.
        repeat (100) @(posedge clk);
        boot_active = 1'b0;
        wait_match("INFO DONE=1", 11, "PIC=0 AUD=1", 11, "media-info-broken");
        wait_match("VERIFY IDX=34", 13, "FS=00 PRES=1", 12, "media-verify-crc");
        wait_match("BOOT DONE", 9, "", 0, "boot-done-queued");

        // 8) 静止期必须完全无输出（回归原来的周期刷屏问题）
        begin : idle_silence
            integer seq_before;
            seq_before = line_seq;
            #120_000_000;   // 120 ms 仿真：远超过原先周期行的等效间隔
            if (line_seq !== seq_before) begin
                errors = errors + 1;
                $display("FAIL idle flood: %0d unexpected line(s)", line_seq - seq_before);
            end else begin
                $display("PASS idle silent (no periodic flood)");
            end
        end

        // 10) 输出安全态：EXT1 承载反馈音波形，EXT2..EXT6 必须保持 0
        if (exp_ext_o[5:1] !== 5'b00000) begin
            errors = errors + 1;
            $display("FAIL ext_o[5:1] not zero: %b", exp_ext_o);
        end
        // 10b) X1B：WS2812 在"全灭"模式下仍会周期性推一整帧黑色，
        //      因此不能用"恒 0"判定；这里检查数据线不是 X 且在 60 ms 内
        //      至少完成一次黑色帧传输（出现高电平 T0H 脉冲）。
        begin : ws_black_frame
            integer high_seen;
            integer waited;
            high_seen = 0;
            waited = 0;
            if (exp_ws2812_data === 1'bx) begin
                errors = errors + 1;
                $display("FAIL ws2812 is X");
            end else begin
                while ((high_seen == 0) && (waited < 600)) begin
                    #100000;
                    waited = waited + 1;
                    if (exp_ws2812_data === 1'b1)
                        high_seen = 1;
                end
                if (high_seen == 0) begin
                    errors = errors + 1;
                    $display("FAIL ws2812 no black-frame activity in 60 ms");
                end else begin
                    $display("PASS ws2812 black frame transmitted");
                end
            end
        end

        if (errors == 0)
            $display("TEST_PASS expansion_s1_smoke");
        else
            $display("TEST_FAIL expansion_s1_smoke errors=%0d", errors);
        $finish;
    end

    initial begin
        #1200000000;
        $display("TEST_FAIL expansion_s1_smoke watchdog timeout");
        $finish;
    end

endmodule
