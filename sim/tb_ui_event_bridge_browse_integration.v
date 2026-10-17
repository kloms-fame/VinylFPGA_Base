`timescale 1ns/1ps

module tb_ui_event_bridge_browse_integration;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ev_valid = 1'b0;
    reg [3:0] ev_code = 4'd0;
    reg [15:0] ev_arg = 16'd0;
    reg [15:0] ev_aux = 16'd0;
    reg mode_play = 1'b0;

    wire prev_tgl, next_tgl, confirm_tgl, mode_tgl, home_tgl;
    wire play_start, play_stop, fs_next, fs_prev;
    integer starts = 0;
    integer stops = 0;
    integer nexts = 0;
    integer prevs = 0;

    always #5 clk = ~clk;

    ui_event_bridge u_bridge (
        .clk(clk), .rst_n(rst_n), .ev_valid(ev_valid),
        .ev_code(ev_code), .ev_arg(ev_arg), .ev_aux(ev_aux),
        .prev_tgl(prev_tgl), .next_tgl(next_tgl), .confirm_tgl(confirm_tgl),
        .mode_tgl(mode_tgl), .home_tgl(home_tgl)
    );

    browse_fsm #(.J2_BROWSE_ENABLE(1'b1)) u_browse (
        .clk(clk), .rst_n(rst_n),
        .ev_prev_tgl(prev_tgl), .ev_next_tgl(next_tgl),
        .ev_confirm_tgl(confirm_tgl), .ev_mode_tgl(mode_tgl),
        .ev_home_tgl(home_tgl), .mode_play(mode_play),
        .fs_next(fs_next), .fs_prev(fs_prev),
        .play_start(play_start), .play_stop(play_stop)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (play_start) starts = starts + 1;
            if (play_stop) stops = stops + 1;
            if (fs_next) nexts = nexts + 1;
            if (fs_prev) prevs = prevs + 1;
        end
    end

    task clear_counts;
        begin starts = 0; stops = 0; nexts = 0; prevs = 0; end
    endtask

    task send_key;
        input [15:0] index;
        begin
            @(negedge clk);
            ev_valid = 1'b1;
            ev_code = 4'd1; // EV_KEY_DOWN
            ev_arg = index;
            @(negedge clk);
            ev_valid = 1'b0;
            ev_code = 4'd0;
            ev_arg = 16'd0;
            repeat (12) @(posedge clk);
        end
    endtask

    task expect_counts;
        input integer exp_start;
        input integer exp_stop;
        input integer exp_next;
        input integer exp_prev;
        input [8*40-1:0] label;
        begin
            if ({starts, stops, nexts, prevs} !==
                {exp_start, exp_stop, exp_next, exp_prev})
                $fatal(1, "FAIL %0s got start/stop/next/prev=%0d/%0d/%0d/%0d",
                       label, starts, stops, nexts, prevs);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        clear_counts(); send_key(16'd0); expect_counts(0, 0, 0, 1, "KEY01 -> previous");
        clear_counts(); send_key(16'd2); expect_counts(0, 0, 1, 0, "KEY03 -> next");
        clear_counts(); send_key(16'd1); expect_counts(1, 0, 0, 0, "KEY02 -> start");

        mode_play = 1'b1;
        clear_counts(); send_key(16'd6); expect_counts(0, 1, 0, 0, "KEY07 -> stop");
        mode_play = 1'b0;
        clear_counts(); send_key(16'd10); expect_counts(0, 1, 0, 0, "KEY11 -> home stop");

        $display("TEST_PASS ui_event_bridge to browse_fsm integration");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL watchdog");
    end
endmodule
