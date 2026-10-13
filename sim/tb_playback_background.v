`timescale 1ns/1ps

module tb_playback_background;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_start = 1'b0;
    reg enable = 1'b1;
    reg cycle_toggle_async = 1'b0;
    reg [9:0] pixel_x = 10'd176;
    reg [9:0] pixel_y = 10'd168;
    wire [1:0] mode_frame;
    wire [23:0] background_rgb;
    integer x;
    integer y;
    integer lowest;
    integer highest;
    integer checks = 0;

    playback_background dut (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .enable(enable), .cycle_toggle_async(cycle_toggle_async),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .mode_frame(mode_frame), .background_rgb(background_rgb)
    );

    always #20 clk = ~clk;

    task expect_mode;
        input [1:0] expected;
        begin
            if (mode_frame !== expected) begin
                $display("FAIL mode: actual=%0d expected=%0d time=%0t",
                    mode_frame, expected, $time);
                $finish_and_return(1);
            end
            checks = checks + 1;
        end
    endtask

    task cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    // Offset the 50 MHz source event from both edges of the 25 MHz video clock.
    task key_event;
        begin
            @(negedge clk);
            #7;
            cycle_toggle_async = ~cycle_toggle_async;
            cycles(6);
        end
    endtask

    task commit_frame;
        input [1:0] expected;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            #1;
            expect_mode(expected);
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    task expect_pixel;
        input [9:0] px;
        input [9:0] py;
        input [23:0] expected;
        begin
            pixel_x = px;
            pixel_y = py;
            #1;
            if (background_rgb !== expected) begin
                $display("FAIL pixel (%0d,%0d): actual=%h expected=%h",
                    px, py, background_rgb, expected);
                $finish_and_return(1);
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        #1;
        expect_mode(2'd0);
        cycles(2);
        @(negedge clk);
        rst_n = 1'b1;
        cycles(3);

        // An event outside blanking remains pending until the next frame.
        key_event;
        expect_mode(2'd0);
        cycles(5);
        expect_mode(2'd0);
        commit_frame(2'd1);
        expect_pixel(10'd176, 10'd168, 24'h808080);

        // Two independent debounced events before a frame must both count.
        key_event;
        key_event;
        expect_mode(2'd1);
        commit_frame(2'd3);
        expect_pixel(10'd0, 10'd0, 24'h08080C);
        expect_pixel(10'd1023, 10'd1023, 24'h08080C);

        // Verify every visible mode and the modulo-four wrap.
        key_event;
        commit_frame(2'd0);
        key_event;
        commit_frame(2'd1);
        expect_pixel(10'd176, 10'd168, 24'h808080);
        key_event;
        commit_frame(2'd2);
        expect_pixel(10'd176, 10'd168, 24'h808080);
        key_event;
        commit_frame(2'd3);
        key_event;
        commit_frame(2'd0);

        // Assert frame_start on the exact edge that consumes a synced event.
        @(negedge clk);
        #7;
        cycle_toggle_async = ~cycle_toggle_async;
        wait (dut.cycle_event === 1'b1);
        @(negedge clk);
        frame_start = 1'b1;
        @(posedge clk);
        #1;
        expect_mode(2'd1);
        @(negedge clk);
        frame_start = 1'b0;
        cycles(3);

        // Disabled events are consumed, never replayed when playback returns.
        @(negedge clk);
        enable = 1'b0;
        key_event;
        key_event;
        commit_frame(2'd1);
        if (dut.cycle_sync_history !== cycle_toggle_async) begin
            $display("FAIL synchronizer stopped while disabled");
            $finish_and_return(1);
        end
        @(negedge clk);
        enable = 1'b1;
        cycles(4);
        commit_frame(2'd1);

        // Re-enter playback again without resetting the selected mode.
        @(negedge clk);
        enable = 1'b0;
        cycles(4);
        @(negedge clk);
        enable = 1'b1;
        commit_frame(2'd1);

        // Return to gray and check range/channel consistency for every pixel.
        key_event;
        key_event;
        key_event;
        commit_frame(2'd0);
        expect_pixel(10'd176, 10'd168, 24'h808080);
        expect_pixel(10'd0, 10'd0, 24'h767676);
        expect_pixel(10'd639, 10'd479, 24'h696969);
        lowest = 255;
        highest = 0;
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                pixel_x = x;
                pixel_y = y;
                #1;
                if (background_rgb[23:16] < 105 ||
                    background_rgb[23:16] > 128 ||
                    background_rgb[23:16] !== background_rgb[15:8] ||
                    background_rgb[15:8] !== background_rgb[7:0]) begin
                    $display("FAIL visible gray range at (%0d,%0d): %h",
                        x, y, background_rgb);
                    $finish_and_return(1);
                end
                if (background_rgb[7:0] < lowest)
                    lowest = background_rgb[7:0];
                if (background_rgb[7:0] > highest)
                    highest = background_rgb[7:0];
            end
        end
        if (lowest != 105 || highest != 128) begin
            $display("FAIL observed range=%0d..%0d", lowest, highest);
            $finish_and_return(1);
        end

        // The full ten-bit coordinate domain also cannot wrap below zero.
        for (y = 0; y < 1024; y = y + 1) begin
            for (x = 0; x < 1024; x = x + 1) begin
                pixel_x = x;
                pixel_y = y;
                #1;
                if (background_rgb[7:0] < 66 || background_rgb[7:0] > 128) begin
                    $display("FAIL underflow at (%0d,%0d): %h", x, y,
                        background_rgb);
                    $finish_and_return(1);
                end
            end
        end

        // Reset clears an active non-default selection and pending source state.
        key_event;
        key_event;
        key_event;
        commit_frame(2'd3);
        @(negedge clk);
        rst_n = 1'b0;
        cycle_toggle_async = 1'b0;
        #1;
        expect_mode(2'd0);
        expect_pixel(10'd176, 10'd168, 24'h808080);
        cycles(2);
        @(negedge clk);
        rst_n = 1'b1;
        cycles(6);
        commit_frame(2'd0);
        $display("PASS playback_background: %0d explicit checks, all 307200 visible pixels, all 1048576 coordinate pairs", checks);
        $finish_and_return(0);
    end

    initial begin
        #2000000;
        $display("FAIL timeout");
        $finish_and_return(1);
    end
endmodule
