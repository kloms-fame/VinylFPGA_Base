`timescale 1ns/1ps

module tb_slideshow_controller;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b0;
    reg busy = 1'b0;
    reg manual_action = 1'b0;
    wire auto_next;
    integer i;

    always #5 clk = ~clk;

    slideshow_controller #(
        .CLK_FREQ_HZ(1000),
        .PERIOD_MS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .busy(busy),
        .manual_action(manual_action),
        .auto_next(auto_next)
    );

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task reset_case;
        begin
            rst_n = 1'b0;
            enable = 1'b0;
            busy = 1'b0;
            manual_action = 1'b0;
            repeat (2) tick;
            rst_n = 1'b1;
            tick;
        end
    endtask

    initial begin
        reset_case;

        // One request after exactly one period, then no repeated pulse.
        enable = 1'b1;
        repeat (3) begin
            tick;
            if (auto_next) $fatal(1, "auto_next asserted before the 4-cycle period");
        end
        tick;
        if (!auto_next) $fatal(1, "auto_next missing at the 4-cycle deadline");
        tick;
        if (auto_next) $fatal(1, "auto_next must be a one-cycle pulse");

        // The timer restarts only after the navigation busy interval completes.
        busy = 1'b1;
        tick;
        busy = 1'b0;
        wait (dut.state == 3'd0 && dut.busy_q == 1'b0);
        #1;
        repeat (3) begin
            tick;
            if (auto_next) $fatal(1, "period restarted before transition completion");
        end
        tick;
        if (!auto_next) $fatal(1, "period did not restart after transition completion");

        // An expired period during busy is retained once and emitted when idle.
        reset_case;
        enable = 1'b1;
        busy = 1'b1;
        repeat (5) begin
            tick;
            if (auto_next) $fatal(1, "automatic request fired while busy");
        end
        busy = 1'b0;
        tick;
        tick;
        if (!auto_next) $fatal(1, "busy timeout was not retained as one pending request");

        // A manual step on the deadline wins and starts a fresh full period.
        reset_case;
        enable = 1'b1;
        repeat (3) tick;
        manual_action = 1'b1;
        tick;
        if (auto_next) $fatal(1, "automatic request beat a same-cycle manual step");
        manual_action = 1'b0;
        busy = 1'b1;
        tick;
        busy = 1'b0;
        wait (dut.state == 3'd0 && dut.busy_q == 1'b0);
        #1;
        repeat (3) begin
            tick;
            if (auto_next) $fatal(1, "manual step failed to restart the timer");
        end
        tick;
        if (!auto_next) $fatal(1, "manual step did not start a fresh full period");

        // Disabling the feature clears pending work and starts a fresh period.
        reset_case;
        enable = 1'b1;
        busy = 1'b1;
        repeat (5) tick;
        enable = 1'b0;
        tick;
        busy = 1'b0;
        enable = 1'b1;
        repeat (3) begin
            tick;
            if (auto_next) $fatal(1, "disabled pending request leaked after re-enable");
        end
        tick;
        if (!auto_next) $fatal(1, "re-enabled timer did not start a fresh period");

        $display("PASS tb_slideshow_controller");
        $finish;
    end
endmodule
