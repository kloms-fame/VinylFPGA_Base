`timescale 1ns/1ps

module tb_hdmi_pcm_audio_bridge;
    reg         clk;
    reg         rst_n;
    reg [1:0]   media_id;
    reg [7:0]   volume;
    wire        audio_valid;
    wire signed [23:0] audio_left;
    wire signed [23:0] audio_right;
    wire        sample_overflow;
    wire        contract_error;
    wire        blip_active;

    integer valid_count;
    integer amplitude_error;
    integer channel_error;
    integer contract_error_seen;
    reg     count_enable;

    hdmi_pcm_audio_bridge #(
        .CLOCK_HZ  (25_000_000),
        .SAMPLE_HZ (48_000)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .media_id        (media_id),
        .volume          (volume),
        .audio_valid     (audio_valid),
        .audio_left      (audio_left),
        .audio_right     (audio_right),
        .sample_overflow (sample_overflow),
        .contract_error  (contract_error),
        .blip_active     (blip_active)
    );

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        media_id      = 2'd0;
        volume        = 8'd200;
        valid_count   = 0;
        amplitude_error = 0;
        channel_error = 0;
        contract_error_seen = 0;
        count_enable  = 1'b0;
    end

    always #20 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && count_enable && audio_valid)
            valid_count = valid_count + 1;

        if (rst_n && audio_valid) begin
            // 16bit PCM 左移 8bit 后，±10000 对应 24bit 的 ±2,560,000。
            if (audio_left > 24'sd3000000 || audio_left < -24'sd3000000) begin
                if (amplitude_error < 5)
                    $display("amplitude sample: left=%0d right=%0d time=%0t", audio_left, audio_right, $time);
                amplitude_error = amplitude_error + 1;
            end
            if (audio_left !== audio_right) begin
                if (channel_error < 5)
                    $display("channel sample: left=%0d right=%0d time=%0t", audio_left, audio_right, $time);
                channel_error = channel_error + 1;
            end
        end

        if (rst_n && contract_error)
            contract_error_seen = contract_error_seen + 1;
    end

    initial begin
        #200;
        rst_n = 1'b1;

        // 跳过首图提交前的准备时间，统计 100ms 内的有效音频样本数。
        #200000;
        count_enable = 1'b1;
        #100000000;
        count_enable = 1'b0;

        if (valid_count < 4790 || valid_count > 4810) begin
            $display("FAIL: 48kHz sample count mismatch, valid_count=%0d (expect 4800)", valid_count);
            $finish;
        end
        if (amplitude_error != 0) begin
            $display("FAIL: PCM amplitude error count=%0d", amplitude_error);
            $finish;
        end
        if (channel_error != 0) begin
            $display("FAIL: PCM channel error count=%0d", channel_error);
            $finish;
        end
        if (contract_error_seen != 0) begin
            $display("FAIL: PCM contract error count=%0d", contract_error_seen);
            $finish;
        end
        if (sample_overflow != 1'b0) begin
            $display("FAIL: tone source overflow asserted");
            $finish;
        end

        // 切图后应触发 1.5kHz 提示音。
        media_id = 2'd1;
        repeat (10) @(posedge clk);
        if (!blip_active) begin
            $display("FAIL: media_id change did not trigger blip");
            $finish;
        end

        $display("PASS: 48kHz PCM count=%0d, amplitude/error checks clean, blip active", valid_count);
        $finish;
    end
endmodule
