`timescale 1ns/1ps

module tb_video_fade_transition;
    reg ctrl_clk = 1'b0;
    reg pix_clk = 1'b0;
    reg ctrl_rst_n = 1'b0;
    reg pix_rst_n = 1'b0;
    reg next_event_in = 1'b0;
    reg bypass_next_event_in = 1'b0;
    reg player_active = 1'b0;
    reg frame_start = 1'b0;
    reg index_commit = 1'b0;
    reg [1:0] active_index = 2'd0;

    wire next_event_out;
    wire fade_busy;
    wire [7:0] alpha_out;
    wire fade_active;
    wire wipe_active;
    wire [4:0] ramp_out;
    wire [1:0] transition_kind;

    wire bypass_next_event_out;
    wire bypass_fade_busy;
    wire [7:0] bypass_alpha_out;
    wire bypass_fade_active;
    wire bypass_wipe_active;
    wire [4:0] bypass_ramp_out;
    wire [1:0] bypass_transition_kind;

    reg [23:0] apply_rgb_in = 24'h80C0FF;
    reg [7:0] apply_alpha = 8'd255;
    reg [7:0] apply_brightness = 8'd255;
    reg apply_wipe_active = 1'b0;
    reg [4:0] apply_wipe_ramp = 5'd0;
    reg [9:0] apply_pixel_x = 10'd0;
    wire [23:0] apply_rgb_out;

    integer frame_count = 0;
    integer errors = 0;
    integer wait_count;

    video_fade_transition #(
        .FADE_FRAMES(4)
    ) dut (
        .ctrl_clk(ctrl_clk),
        .ctrl_rst_n(ctrl_rst_n),
        .next_event_in(next_event_in),
        .next_event_out(next_event_out),
        .fade_busy(fade_busy),
        .pix_clk(pix_clk),
        .pix_rst_n(pix_rst_n),
        .player_active(player_active),
        .frame_start(frame_start),
        .index_commit(index_commit),
        .active_index(active_index),
        .alpha_out(alpha_out),
        .fade_active(fade_active),
        .wipe_active(wipe_active),
        .ramp_out(ramp_out),
        .transition_kind(transition_kind)
    );

    video_fade_transition #(
        .FADE_FRAMES(0)
    ) bypass_dut (
        .ctrl_clk(ctrl_clk),
        .ctrl_rst_n(ctrl_rst_n),
        .next_event_in(bypass_next_event_in),
        .next_event_out(bypass_next_event_out),
        .fade_busy(bypass_fade_busy),
        .pix_clk(pix_clk),
        .pix_rst_n(pix_rst_n),
        .player_active(player_active),
        .frame_start(frame_start),
        .index_commit(index_commit),
        .active_index(active_index),
        .alpha_out(bypass_alpha_out),
        .fade_active(bypass_fade_active),
        .wipe_active(bypass_wipe_active),
        .ramp_out(bypass_ramp_out),
        .transition_kind(bypass_transition_kind)
    );

    video_transition_apply #(
        .WIPE_STEP(40)
    ) apply_dut (
        .rgb_in(apply_rgb_in),
        .alpha(apply_alpha),
        .brightness(apply_brightness),
        .wipe_active(apply_wipe_active),
        .wipe_ramp(apply_wipe_ramp),
        .pixel_x(apply_pixel_x),
        .rgb_out(apply_rgb_out)
    );

    always #5 ctrl_clk = ~ctrl_clk;
    always #20 pix_clk = ~pix_clk;

    // One frame-start pulse every 24 pixel clocks.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            frame_count <= 0;
            frame_start <= 1'b0;
        end else begin
            frame_start <= 1'b0;
            if (frame_count == 23) begin
                frame_count <= 0;
                frame_start <= 1'b1;
            end else begin
                frame_count <= frame_count + 1;
            end
        end
    end

    task ctrl_pulse;
        begin
            @(negedge ctrl_clk);
            next_event_in = 1'b1;
            @(negedge ctrl_clk);
            next_event_in = 1'b0;
        end
    endtask

    task pix_pulse_index;
        input [1:0] idx;
        begin
            @(negedge pix_clk);
            active_index = idx;
            index_commit = 1'b1;
            @(negedge pix_clk);
            index_commit = 1'b0;
        end
    endtask

    task wait_fade_active;
        input expected;
        begin
            wait_count = 0;
            while ((fade_active !== expected) && (wait_count < 5000)) begin
                @(posedge pix_clk);
                wait_count = wait_count + 1;
            end
            if (fade_active !== expected) begin
                $display("FAIL: fade_active timeout, expected %0d", expected);
                errors = errors + 1;
            end
        end
    endtask

    task wait_alpha;
        input [7:0] expected;
        begin
            wait_count = 0;
            while ((alpha_out !== expected) && (wait_count < 5000)) begin
                @(posedge pix_clk);
                wait_count = wait_count + 1;
            end
            if (alpha_out !== expected) begin
                $display("FAIL: alpha timeout, expected %0d got %0d", expected, alpha_out);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Reset both clock domains.
        ctrl_rst_n = 1'b0;
        pix_rst_n = 1'b0;
        repeat (4) @(posedge ctrl_clk);
        ctrl_rst_n = 1'b1;
        pix_rst_n = 1'b1;
        player_active = 1'b1;
        repeat (4) @(posedge pix_clk);

        // Bypass mode must pass the request through and keep alpha full-scale.
        @(negedge ctrl_clk);
        bypass_next_event_in = 1'b1;
        #1;
        if (bypass_next_event_out !== 1'b1 || bypass_alpha_out !== 8'd255) begin
            $display("FAIL: bypass path did not pass request / alpha");
            errors = errors + 1;
        end
        @(negedge ctrl_clk);
        bypass_next_event_in = 1'b0;

        // Manual transition: request -> fade out -> commit -> fade in.
        ctrl_pulse();
        wait_fade_active(1'b1);
        wait_alpha(8'd0);
        wait_count = 0;
        while ((next_event_out !== 1'b1) && (wait_count < 5000)) begin
            @(posedge ctrl_clk);
            wait_count = wait_count + 1;
        end
        if (next_event_out !== 1'b1) begin
            $display("FAIL: manual commit did not reach control domain");
            errors = errors + 1;
        end
        pix_pulse_index(2'd2);
        wait_fade_active(1'b0);
        if (alpha_out !== 8'd255) begin
            $display("FAIL: manual fade-in did not return alpha to 255");
            errors = errors + 1;
        end

        // Automatic slideshow: index commit in IDLE starts a wipe reveal.
        pix_pulse_index(2'd3);
        if (wipe_active !== 1'b1) begin
            $display("FAIL: automatic index commit did not start wipe");
            errors = errors + 1;
        end
        wait_fade_active(1'b0);
        if (wipe_active !== 1'b0) begin
            $display("FAIL: wipe did not finish");
            errors = errors + 1;
        end

        // Pixel-domain arithmetic: alpha and wipe boundary.
        apply_alpha = 8'd255;
        #1;
        if (apply_rgb_out !== 24'h7FBFFE) begin
            $display("FAIL: alpha=255 arithmetic got %h", apply_rgb_out);
            errors = errors + 1;
        end

        // 第十四讲：亮度按教程 2.1 折进转场 alpha。
        apply_brightness = 8'd128;
        #1;
        if (apply_rgb_out !== 24'h40607F) begin
            $display("FAIL: brightness=128 arithmetic got %h", apply_rgb_out);
            errors = errors + 1;
        end
        apply_brightness = 8'd0;
        #1;
        if (apply_rgb_out !== 24'h000000) begin
            $display("FAIL: brightness=0 arithmetic got %h", apply_rgb_out);
            errors = errors + 1;
        end
        apply_brightness = 8'd255;

        apply_alpha = 8'd0;
        #1;
        if (apply_rgb_out !== 24'h000000) begin
            $display("FAIL: alpha=0 arithmetic got %h", apply_rgb_out);
            errors = errors + 1;
        end
        apply_alpha = 8'd255;
        apply_wipe_active = 1'b1;
        apply_wipe_ramp = 5'd1;
        apply_pixel_x = 10'd39;
        #1;
        if (apply_rgb_out !== apply_rgb_in) begin
            $display("FAIL: wipe left side did not show new frame");
            errors = errors + 1;
        end

        apply_brightness = 8'd128;
        #1;
        if (apply_rgb_out !== 24'h40607F) begin
            $display("FAIL: wipe brightness arithmetic got %h", apply_rgb_out);
            errors = errors + 1;
        end
        apply_brightness = 8'd255;

        apply_pixel_x = 10'd40;
        #1;
        if (apply_rgb_out !== 24'h000000) begin
            $display("FAIL: wipe right side was not black");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_video_fade_transition manual/auto/wipe arithmetic");
        else
            $display("FAIL: tb_video_fade_transition errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: tb_video_fade_transition timeout");
        $finish;
    end
endmodule
