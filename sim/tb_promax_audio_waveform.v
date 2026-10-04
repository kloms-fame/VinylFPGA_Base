`timescale 1ns/1ps

module tb_promax_audio_waveform;
    reg clk = 0;
    reg rst_n = 0;
    reg vsync = 1;
    reg de = 0;
    reg [9:0] pixel_x = 0;
    reg enable = 1;
    reg pcm_tap_valid = 0;
    reg signed [15:0] pcm_tap_left = 16'sd0;
    wire [23:0] rgb_out;
    wire waveform_active;
    reg [23:0] observed;

    promax_audio_waveform #(
        .WAVE_X(64),
        .WAVE_Y(376),
        .WAVE_WIDTH(512),
        .WAVE_HEIGHT(96),
        .DECIMATE(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .vsync(vsync),
        .de(de),
        .rgb_in(24'h000000),
        .pixel_x(pixel_x),
        .enable(enable),
        .pcm_tap_valid(pcm_tap_valid),
        .pcm_tap_left(pcm_tap_left),
        .rgb_out(rgb_out),
        .waveform_active(waveform_active)
    );

    always #5 clk = ~clk;
    integer i;
    integer line;

    task push_sample;
        input signed [15:0] value;
        begin
            pcm_tap_left = value;
            pcm_tap_valid = 1'b1;
            @(posedge clk);
            pcm_tap_valid = 1'b0;
        end
    endtask

    task run_frame;
        input integer sample_value;
        begin
            // VSYNC low starts a new frame.
            @(negedge clk);
            vsync = 1'b0;
            @(posedge clk);
            repeat (2) @(posedge clk);
            @(negedge clk);
            vsync = 1'b1;

            // Feed enough PCM samples for all 32 bars.
            for (i = 0; i < 64; i = i + 1)
                push_sample(sample_value);

            for (line = 0; line < 480; line = line + 1) begin
                de = 1'b1;
                for (i = 0; i < 640; i = i + 1) begin
                    pixel_x = i[9:0];
                    @(posedge clk);
                    if (line == 411 && i == 66)
                        observed = rgb_out;
                end
                de = 1'b0;
                @(posedge clk);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        run_frame(16'sd32767);
        run_frame(16'sd32767);

        // At the second frame start the first captured bank is displayed.
        if (!dut.display_valid) begin
            $display("FAIL: display_valid was not asserted");
            $finish;
        end

        if (observed != 24'hff3040) begin
            $display("FAIL: expected a colored upward bar pixel, observed %h", observed);
            $finish;
        end

        if (dut.DISPLAY_HEIGHT != 95) begin
            $display("FAIL: expected a 95-pixel drawable waveform height");
            $finish;
        end

        $display("PASS: taller colored waveform bars and peak meter are active");
        $finish;
    end
endmodule
