`timescale 1ns/1ps
module tb_playback_progress;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg vs = 1'b1;
    reg [31:0] elapsed_samples = 32'd0;
    reg [31:0] total_samples = 32'd0;
    wire [8:0] progress_fill;
    wire [39:0] elapsed_time_ascii;
    wire [47:0] remaining_time_ascii;
    wire [39:0] total_time_ascii;
    wire time_known;

    integer cycles;
    integer minute_value;
    integer failures = 0;
    reg [63:0] elapsed_clamped;
    reg [63:0] elapsed_seconds;
    reg [63:0] total_seconds;
    reg [63:0] remaining_seconds;
    reg [63:0] elapsed_minutes;
    reg [63:0] total_minutes;
    reg [63:0] remaining_minutes;
    reg [63:0] expected_progress;
    reg [39:0] expected_elapsed_ascii;
    reg [47:0] expected_remaining_ascii;
    reg [39:0] expected_total_ascii;

    playback_progress dut (
        .clk(clk), .rst_n(rst_n), .vs(vs),
        .elapsed_samples(elapsed_samples), .total_samples(total_samples),
        .progress_fill(progress_fill), .elapsed_time_ascii(elapsed_time_ascii),
        .remaining_time_ascii(remaining_time_ascii), .total_time_ascii(total_time_ascii),
        .time_known(time_known)
    );

    always #5 clk = ~clk;

    function [7:0] ascii_digit;
        input [63:0] value;
        begin ascii_digit = 8'd48 + value[7:0]; end
    endfunction

    task calculate_expected;
        reg [63:0] elapsed_min_display;
        reg [63:0] total_min_display;
        reg [63:0] remaining_min_display;
        reg [63:0] elapsed_sec_display;
        reg [63:0] total_sec_display;
        reg [63:0] remaining_sec_display;
        begin
            elapsed_clamped = (elapsed_samples > total_samples)
                            ? {32'd0, total_samples} : {32'd0, elapsed_samples};
            expected_progress = (elapsed_clamped * 64'd320) / total_samples;
            if (expected_progress > 64'd320) expected_progress = 64'd320;

            elapsed_seconds = elapsed_clamped / 64'd48000;
            total_seconds = {32'd0, total_samples} / 64'd48000;
            remaining_seconds = (total_seconds > elapsed_seconds)
                              ? total_seconds - elapsed_seconds : 64'd0;

            elapsed_minutes = elapsed_seconds / 64'd60;
            total_minutes = total_seconds / 64'd60;
            remaining_minutes = remaining_seconds / 64'd60;
            elapsed_min_display = (elapsed_minutes > 64'd99) ? 64'd99 : elapsed_minutes;
            total_min_display = (total_minutes > 64'd99) ? 64'd99 : total_minutes;
            remaining_min_display = (remaining_minutes > 64'd99) ? 64'd99 : remaining_minutes;
            elapsed_sec_display = elapsed_seconds % 64'd60;
            total_sec_display = total_seconds % 64'd60;
            remaining_sec_display = remaining_seconds % 64'd60;

            if (elapsed_min_display < 10)
                expected_elapsed_ascii = {ascii_digit(elapsed_min_display), 8'h3A,
                    ascii_digit(elapsed_sec_display / 10), ascii_digit(elapsed_sec_display % 10), 8'h20};
            else
                expected_elapsed_ascii = {ascii_digit(elapsed_min_display / 10),
                    ascii_digit(elapsed_min_display % 10), 8'h3A,
                    ascii_digit(elapsed_sec_display / 10), ascii_digit(elapsed_sec_display % 10)};

            if (remaining_min_display < 10)
                expected_remaining_ascii = {8'h20, 8'h2D, ascii_digit(remaining_min_display), 8'h3A,
                    ascii_digit(remaining_sec_display / 10), ascii_digit(remaining_sec_display % 10)};
            else
                expected_remaining_ascii = {8'h2D, ascii_digit(remaining_min_display / 10),
                    ascii_digit(remaining_min_display % 10), 8'h3A,
                    ascii_digit(remaining_sec_display / 10), ascii_digit(remaining_sec_display % 10)};

            expected_total_ascii = {ascii_digit(total_min_display / 10),
                ascii_digit(total_min_display % 10), 8'h3A,
                ascii_digit(total_sec_display / 10), ascii_digit(total_sec_display % 10)};
        end
    endtask

    task run_case;
        input [8*32-1:0] label_text;
        input [31:0] elapsed_value;
        input [31:0] total_value;
        integer i;
        begin
            rst_n = 1'b0;
            vs = 1'b1;
            elapsed_samples = elapsed_value;
            total_samples = total_value;
            repeat (3) @(posedge clk);
            #1 rst_n = 1'b1;
            @(negedge clk) vs = 1'b0;
            @(posedge clk); #1;

            if (total_value == 0) begin
                if (time_known !== 1'b0 || progress_fill !== 9'd0 ||
                    elapsed_time_ascii !== {8'h2D,8'h2D,8'h3A,8'h2D,8'h2D} ||
                    remaining_time_ascii !== {8'h20,8'h2D,8'h2D,8'h3A,8'h2D,8'h2D} ||
                    total_time_ascii !== {8'h2D,8'h2D,8'h3A,8'h2D,8'h2D}) begin
                    $display("FAIL %0s: zero-total invalid output", label_text);
                    failures = failures + 1;
                end else begin
                    $display("PASS %0s: zero-total invalid output", label_text);
                end
            end else begin
                cycles = 0;
                while ((time_known !== 1'b1) && (cycles < 600)) begin
                    @(posedge clk); #1;
                    cycles = cycles + 1;
                end
                if (time_known !== 1'b1) begin
                    $display("FAIL %0s: formatter timeout after %0d clocks", label_text, cycles);
                    failures = failures + 1;
                end else begin
                    if (cycles != 279) begin
                        $display("FAIL %0s: update latency expected 279 clocks got %0d",
                            label_text, cycles);
                        failures = failures + 1;
                    end
                    calculate_expected();
                    if (progress_fill !== expected_progress[8:0]) begin
                        $display("FAIL %0s: progress expected %0d got %0d", label_text,
                            expected_progress, progress_fill);
                        failures = failures + 1;
                    end
                    if (elapsed_time_ascii !== expected_elapsed_ascii) begin
                        $display("FAIL %0s: elapsed expected %h got %h", label_text,
                            expected_elapsed_ascii, elapsed_time_ascii);
                        failures = failures + 1;
                    end
                    if (remaining_time_ascii !== expected_remaining_ascii) begin
                        $display("FAIL %0s: remaining expected %h got %h", label_text,
                            expected_remaining_ascii, remaining_time_ascii);
                        failures = failures + 1;
                    end
                    if (total_time_ascii !== expected_total_ascii) begin
                        $display("FAIL %0s: total expected %h got %h", label_text,
                            expected_total_ascii, total_time_ascii);
                        failures = failures + 1;
                    end
                    $display("PASS %0s: latency=%0d progress=%0d elapsed=%h remaining=%h total=%h",
                        label_text, cycles, progress_fill, elapsed_time_ascii,
                        remaining_time_ascii, total_time_ascii);
                end
            end
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        run_case("zero_total", 32'd0, 32'd0);
        run_case("minute_0", 32'd0, 32'd48000);
        run_case("minute_1", 32'd48000, 32'd120000);
        run_case("minute_59_boundary", 32'd1799 * 32'd48000, 32'd3600 * 32'd48000);
        run_case("minute_99_boundary", 32'd5940 * 32'd48000, 32'd6000 * 32'd48000);
        run_case("minute_100_clamp", 32'd6000 * 32'd48000, 32'd6060 * 32'd48000);
        run_case("elapsed_over_total", 32'hFFFFFFFF, 32'd300 * 32'd48000);
        run_case("maximum_sample_count", 32'hFFFFFFFF, 32'hFFFFFFFF);
        for (minute_value = 0; minute_value < 100; minute_value = minute_value + 1)
            run_case("exhaustive_minute", minute_value * 2880000, 101 * 2880000);
        if (failures != 0) begin
            $display("FAIL tb_playback_progress failures=%0d", failures);
            $fatal(1);
        end
        $display("PASS tb_playback_progress");
        $finish;
    end
endmodule
