`timescale 1ns/1ps
// 麦克风数字调理链自检：增益、软噪声门、两级低通、4:1 抽取。
// 运行：iverilog -g2005 -o tb_mic.vvp sim/mic_osd_v3/tb_mic_signal_condition.v src/audio/mic_signal_condition.v
//       vvp tb_mic.vvp   ->  期望最后一行 "TB_PASS"
module tb_mic_signal_condition;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #20 clk = ~clk;              // 25 MHz

    reg  [11:0] sample_code  = 12'd2048;
    reg         sample_valid = 1'b0;
    reg  [2:0]  level        = 3'd0;
    wire signed [15:0] mic_sample;
    wire        mic_valid;

    mic_signal_condition dut(
        .clk(clk), .rst_n(rst_n),
        .sample_code(sample_code), .sample_valid(sample_valid),
        .mic_level(level), .mic_sample(mic_sample), .mic_valid(mic_valid));

    integer valid_cnt = 0;
    integer mic_cnt   = 0;
    integer pk_max = 0, pk_min = 0, arm = 0, minc = 0, maxc = 0;

    always @(posedge clk) begin
        if (sample_valid) begin
            valid_cnt <= valid_cnt + 1;
            if (sample_code < minc) minc = sample_code;
            if (sample_code > maxc) maxc = sample_code;
        end
        if (mic_valid) begin
            mic_cnt <= mic_cnt + 1;
            if (arm) begin
                if (mic_sample > pk_max) pk_max = mic_sample;
                if (mic_sample < pk_min) pk_min = mic_sample;
            end
        end
    end

    integer n;
    real ph;
    // 190.8 kS/s 附近的 ADC 采样节拍：每个样本间隔 131 个 25 MHz 周期。
    task drive(input integer amp, input integer freq, input integer nsmp);
        begin
            for (n = 0; n < nsmp; n = n + 1) begin
                ph = 6.283185307 * freq * n / 192000.0;
                sample_code  = 12'd2048 + $rtoi(amp * $sin(ph));
                sample_valid = 1'b1;
                @(posedge clk); #1;
                sample_valid = 1'b0;
                repeat (129) @(posedge clk); #1;
            end
        end
    endtask

    task meas(input integer amp, input integer freq, input integer lvl,
              input integer nsmp, output integer hi, output integer lo);
        begin
            level = lvl[2:0];
            arm = 0; minc = 4095; maxc = 0;
            drive(amp, freq, 12000);            // 让直流跟踪与低通收敛
            pk_max = -40000; pk_min = 40000; arm = 1;
            drive(amp, freq, nsmp);
            arm = 0;
            hi = pk_max; lo = pk_min;
        end
    endtask

    integer a, b, c, d;
    integer errors = 0;
    integer ref200, atten20k;

    initial begin
        rst_n = 0; repeat (10) @(posedge clk); rst_n = 1; repeat (10) @(posedge clk);

        // T1: 0X 档必须完全静音
        meas(500, 1500, 0, 3000, a, b);
        $display("T1 0X amp500       : max=%0d min=%0d", a, b);
        if ((a != 0) || (b != 0)) begin $display("FAIL T1"); errors = errors + 1; end

        // T2: 5X 档 200 码 1.5 kHz -> 约 200*5*16 = 16000
        meas(200, 1500, 5, 3000, a, b);
        $display("T2 5X amp200       : max=%0d min=%0d (expect ~15800)", a, b);
        if ((a < 14000) || (a > 17000) || (b > -14000) || (b < -17000)) begin
            $display("FAIL T2"); errors = errors + 1;
        end

        // T3: 软噪声门必须压住底噪（10 码）
        meas(10, 1500, 5, 3000, a, b);
        $display("T3 gate amp10      : max=%0d min=%0d (expect 0)", a, b);
        if ((a != 0) || (b != 0)) begin $display("FAIL T3"); errors = errors + 1; end

        // T4: 7X 档大信号必须饱和而不是回绕
        meas(2000, 1500, 7, 3000, a, b);
        $display("T4 7X amp2000 clip : max=%0d min=%0d (expect 32767/-32768)", a, b);
        if ((a != 32767) || (b != -32768)) begin $display("FAIL T4"); errors = errors + 1; end

        // T5/T6: 两级低通对 20 kHz 的抑制应优于 20 dB
        meas(400, 200, 5, 3000, a, b);
        $display("T5 200Hz amp400    : max=%0d min=%0d", a, b);
        ref200 = (a > 0) ? a : 1;
        meas(400, 20000, 5, 3000, c, d);
        atten20k = (c * 1000) / ref200;
        $display("T6 20kHz amp400    : max=%0d min=%0d ratio(e-3)=%0d (expect < 100)", c, d, atten20k);
        if (atten20k >= 100) begin $display("FAIL T6"); errors = errors + 1; end

        $display("valid=%0d mic=%0d decim=%0d (expect 4)", valid_cnt, mic_cnt,
                 (mic_cnt != 0) ? (valid_cnt / mic_cnt) : 0);
        if ((mic_cnt == 0) || ((valid_cnt / mic_cnt) != 4)) begin
            $display("FAIL decimation"); errors = errors + 1;
        end

        if (errors == 0) $display("TB_PASS");
        else             $display("TB_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
