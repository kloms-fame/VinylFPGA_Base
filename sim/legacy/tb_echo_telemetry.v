`timescale 1ns/1ps
// S7-01B：exp_echo_reporter 的 STAT/ERR 串口格式定向验证。
// 独立例化上报器，手动驱动 stat_req / err_req，把 UART 字节流解成文本后
// 校验 "ERR 0A" 与 "STAT ... VER=07010001" 两行格式。
module tb_echo_telemetry;
    localparam integer CLK_NS = 1000;    // 1 MHz
    localparam integer BIT_NS = 10000;   // 100 kbaud @ 1 MHz

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         ev_valid = 1'b0;
    reg  [3:0]  ev_code = 4'd0;
    reg  [15:0] ev_arg = 16'd0;
    reg  [15:0] ev_aux = 16'd0;
    reg         boot_active = 1'b0;
    reg  [23:0] media_status = 24'd0;
    reg         io_ready = 1'b0;
    reg         exp_present = 1'b0;
    reg  [5:0]  dip_state = 6'd0;
    reg         stat_req = 1'b0;
    reg         err_req = 1'b0;
    reg  [7:0]  err_code = 8'd0;
    reg  [15:0] stat_underrun = 16'd1;
    reg  [15:0] stat_buffer_low = 16'd2;
    reg  [15:0] stat_video_fail = 16'd3;
    reg  [15:0] stat_ev_overflow = 16'd4;
    reg  [31:0] fw_version = 32'h0701_0001;

    wire        uart_tx;
    wire        ovf_pulse;

    // 串口字节流收集
    reg  [7:0]  rxbuf [0:4095];
    integer     rxlen = 0;
    reg  [7:0]  rx_byte;
    integer     k;
    integer     errors = 0;

    exp_echo_reporter #(
        .CLK_FREQ_HZ (1_000_000),
        .BAUD_RATE   (100_000),
        .ECHO_ENABLE (1'b1)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .ev_valid   (ev_valid),
        .ev_code    (ev_code),
        .ev_arg     (ev_arg),
        .ev_aux     (ev_aux),
        .boot_active(boot_active),
        .media_status(media_status),
        .io_ready   (io_ready),
        .exp_present(exp_present),
        .dip_state  (dip_state),
        .stat_req   (stat_req),
        .err_req    (err_req),
        .err_code   (err_code),
        .stat_underrun   (stat_underrun),
        .stat_buffer_low (stat_buffer_low),
        .stat_video_fail (stat_video_fail),
        .stat_ev_overflow(stat_ev_overflow),
        .fw_version (fw_version),
        .uart_tx    (uart_tx),
        .ovf_pulse  (ovf_pulse)
    );

    always #(CLK_NS/2) clk = ~clk;

    task uart_recv;
        output [7:0] d;
        integer j;
        begin
            @(negedge uart_tx);
            #(BIT_NS + BIT_NS/2);
            for (j = 0; j < 8; j = j + 1) begin
                d[j] = uart_tx;
                #(BIT_NS);
            end
        end
    endtask

    // 后台字节收集器（永不阻塞）
    initial begin
        forever begin
            uart_recv(rx_byte);
            if (rxlen < 4096) begin
                rxbuf[rxlen] = rx_byte;
                rxlen = rxlen + 1;
            end
        end
    end

    // 在已收到的字节流中查找 ASCII 子串
    function integer find_str;
        input [8*48-1:0] pat;
        input integer    plen;
        integer i, j, f;
        begin
            find_str = 0;
            for (i = 0; i + plen <= rxlen && !find_str; i = i + 1) begin
                f = 1;
                for (j = 0; j < plen; j = j + 1)
                    if (rxbuf[i+j] !== pat[8*(plen-1-j) +: 8])
                        f = 0;
                if (f) find_str = 1;
            end
        end
    endfunction

    task wait_str;
        input [8*48-1:0] pat;
        input integer    plen;
        integer t;
        begin
            t = 0;
            while (!find_str(pat, plen) && t < 2000) begin
                #100000;
                t = t + 1;
            end
            if (find_str(pat, plen))
                $display("PASS line contains [%0s]", pat);
            else begin
                errors = errors + 1;
                $display("FAIL missing line [%0s]", pat);
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        io_ready = 1'b1;
        repeat (10) @(posedge clk);

        // 1) 错误上报：err_code=0x0A
        err_code = 8'h0A;
        err_req = 1'b1; repeat (2) @(posedge clk); err_req = 1'b0;
        wait_str("ERR 0A", 6);

        // 2) 周期遥测：STAT 行包含各计数与版本号
        stat_req = 1'b1; repeat (2) @(posedge clk); stat_req = 1'b0;
        wait_str("STAT UR=0001", 12);
        wait_str("BL=0002", 7);
        wait_str("VF=0003", 7);
        wait_str("OV=0004", 7);
        wait_str("ERR=0A", 6);
        wait_str("VER=07010001", 12);

        if (errors == 0)
            $display("TEST_PASS echo_telemetry");
        else
            $display("TEST_FAIL echo_telemetry errors=%0d", errors);
        $finish;
    end

    initial begin
        #80_000_000;
        $display("TEST_FAIL echo_telemetry watchdog timeout");
        $finish;
    end
endmodule
