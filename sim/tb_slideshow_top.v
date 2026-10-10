`timescale 1ns/1ps

// D1 wiring check: DIP/media/view/count eligibility -> timer -> navigation.
module tb_slideshow_top;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg dip2_enable = 1'b0;
    reg media_ready = 1'b0;
    reg thumbnail_mode = 1'b0;
    reg play_active = 1'b0;
    reg [2:0] image_count = 3'd3;
    reg manual_next = 1'b0;
    reg manual_prev = 1'b0;
    reg choose = 1'b0;
    reg [1:0] chosen = 2'd0;
    reg transition_busy = 1'b0;
    reg transition_commit = 1'b0;
    reg select_ack = 1'b0;
    reg [1:0] displayed = 2'd0;
    integer transition_delay = 0;
    integer transition_count = 0;
    integer i;
    integer expected_display = 3;
    wire eligible = dip2_enable && media_ready && !thumbnail_mode &&
                    !play_active && (image_count > 3'd1);
    wire auto_next;
    wire nav_start;
    wire nav_direction;
    wire select_req;
    wire [1:0] select_index;
    wire nav_busy;

    always #5 clk = ~clk;

    slideshow_controller #(
        .CLK_FREQ_HZ(1000),
        .PERIOD_MS(4)
    ) u_slideshow_controller (
        .clk(clk), .rst_n(rst_n), .enable(eligible),
        .busy(nav_busy), .manual_action(manual_next || manual_prev || choose),
        .auto_next(auto_next)
    );

    cover_navigation u_cover_navigation (
        .clk(clk), .rst_n(rst_n), .ready(media_ready),
        .count(image_count), .displayed(displayed),
        .next_step(manual_next), .prev_step(manual_prev), .auto_next(auto_next),
        .choose(choose), .chosen(chosen), .chosen_direction(1'b1),
        .transition_busy(transition_busy), .transition_commit(transition_commit),
        .select_ack(select_ack), .transition_start(nav_start),
        .direction(nav_direction), .select_req(select_req),
        .select_index(select_index), .busy(nav_busy), .auto_switch_ack()
    );

    // Model the existing transition + select acknowledgement contract.
    always @(posedge clk) begin
        transition_commit <= 1'b0;
        select_ack <= 1'b0;
        if (!rst_n) begin
            transition_busy <= 1'b0;
            displayed <= 2'd0;
            transition_delay <= 0;
            transition_count <= 0;
        end else begin
            if (nav_start) begin
                transition_busy <= 1'b1;
                transition_delay <= 0;
                transition_count <= transition_count + 1;
            end else if (transition_busy) begin
                if (transition_delay == 1) begin
                    transition_busy <= 1'b0;
                    transition_commit <= 1'b1;
                end else
                    transition_delay <= transition_delay + 1;
            end
            if (select_req) begin
                displayed <= select_index;
                select_ack <= 1'b1;
            end
        end
    end

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task wait_transition_count;
        input integer expected;
        integer timeout;
        begin
            timeout = 0;
            while (transition_count < expected && timeout < 80) begin
                tick;
                timeout = timeout + 1;
            end
            if (transition_count != expected)
                $fatal(1, "expected %0d transitions, got %0d", expected, transition_count);
        end
    endtask

    initial begin
        repeat (3) tick;
        rst_n = 1'b1;
        media_ready = 1'b1;
        dip2_enable = 1'b1;
        image_count = 3'd0;
        repeat (8) tick;
        if (transition_count != 0)
            $fatal(1, "slideshow ran with no ready image banks");

        image_count = 3'd1;
        repeat (8) tick;
        if (transition_count != 0)
            $fatal(1, "slideshow ran with only one ready image bank");

        image_count = 3'd4;
        wait_transition_count(1);
        wait (displayed == 2'd1);
        repeat (2) tick;

        thumbnail_mode = 1'b1;
        repeat (8) tick;
        if (transition_count != 1)
            $fatal(1, "slideshow ran in thumbnail selection mode");
        thumbnail_mode = 1'b0;
        play_active = 1'b1;
        repeat (8) tick;
        if (transition_count != 1)
            $fatal(1, "slideshow ran during playback");
        play_active = 1'b0;
        wait_transition_count(2);
        wait (displayed == 2'd2);
        repeat (2) tick;

        // Start a fresh period; manual input on its deadline creates one request.
        wait (nav_busy == 1'b0);
        dip2_enable = 1'b0;
        tick;
        dip2_enable = 1'b1;
        repeat (3) tick;
        manual_next = 1'b1;
        tick;
        manual_next = 1'b0;
        wait_transition_count(3);
        wait (displayed == 2'd3);
        repeat (2) tick;
        if (transition_count != 3)
            $fatal(1, "manual navigation was unexpectedly duplicated");

        // Two ready banks and 100 automatic rotations exercise modulo wrapping.
        image_count = 3'd2;
        expected_display = 0;
        for (i = 0; i < 100; i = i + 1) begin
            wait_transition_count(4 + i);
            expected_display = (expected_display + 1) % 2;
            wait (displayed == expected_display[1:0]);
            wait (nav_busy == 1'b0);
        end

        $display("PASS tb_slideshow_top");
        $finish;
    end
endmodule
