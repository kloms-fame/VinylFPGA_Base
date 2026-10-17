`timescale 1ns/1ps
module tb_quadrature_decoder_area;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [1:0] ab = 2'b11;
    wire step_pulse;
    wire direction;
    wire [15:0] count;
    integer pulse_count = 0;
    reg pulse_seen = 1'b0;

    always #5 clk = ~clk;

    quadrature_decoder #(.STABLE_CYCLES(2)) dut (
        .clk(clk), .rst_n(rst_n), .a_async(ab[1]), .b_async(ab[0]),
        .step_pulse(step_pulse), .direction(direction), .count(count)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            pulse_count = 0;
            pulse_seen = 1'b0;
        end else begin
            if (step_pulse) begin
                if (pulse_seen)
                    $fatal(1, "step_pulse lasted more than one cycle");
                pulse_count = pulse_count + 1;
            end
            pulse_seen = step_pulse;
        end
    end

    task wait_clocks;
        input integer cycles;
        integer n;
        begin
            for (n = 0; n < cycles; n = n + 1)
                @(negedge clk);
            #1;
        end
    endtask

    task apply_state;
        input [1:0] next_state;
        begin
            ab = next_state;
            wait_clocks(8);
        end
    endtask

    task positive_turn;
        begin
            apply_state(2'b10);
            apply_state(2'b00);
            apply_state(2'b01);
            apply_state(2'b11);
        end
    endtask

    task positive_turn_from_10;
        begin
            apply_state(2'b00);
            apply_state(2'b01);
            apply_state(2'b11);
            apply_state(2'b10);
        end
    endtask

    task negative_turn_from_11;
        begin
            apply_state(2'b01);
            apply_state(2'b00);
            apply_state(2'b10);
            apply_state(2'b11);
        end
    endtask

    task negative_turn_from_10;
        begin
            apply_state(2'b11);
            apply_state(2'b01);
            apply_state(2'b00);
            apply_state(2'b10);
        end
    endtask

    initial begin
        wait_clocks(4);
        rst_n = 1'b1;
        wait_clocks(8);

        // A short synchronized contact glitch must not complete a step.
        ab = 2'b10;
        wait_clocks(1);
        ab = 2'b11;
        wait_clocks(10);
        if (count !== 16'd0 || pulse_count != 0)
            $fatal(1, "short glitch changed encoder count or pulsed");

        positive_turn();
        if (count !== 16'd1 || direction !== 1'b0 || pulse_count != 1)
            $fatal(1, "positive cycle failed count=%h dir=%b pulses=%0d", count, direction, pulse_count);

        negative_turn_from_11();
        if (count !== 16'd0 || direction !== 1'b1 || pulse_count != 2)
            $fatal(1, "negative cycle failed count=%h dir=%b pulses=%0d", count, direction, pulse_count);

        // Reach three positive quarter steps, then reject a two-bit jump.
        apply_state(2'b10);
        apply_state(2'b00);
        apply_state(2'b01);
        apply_state(2'b10);
        if (count !== 16'd0 || pulse_count != 2)
            $fatal(1, "illegal two-bit jump changed count or pulsed");

        // The legal sequence after recovery still completes exactly once.
        apply_state(2'b00);
        apply_state(2'b01);
        apply_state(2'b11);
        apply_state(2'b10);
        if (count !== 16'd1 || pulse_count != 3)
            $fatal(1, "post-error recovery failed count=%h pulses=%0d", count, pulse_count);

        // Verify both 16-bit wrap directions without altering production ports.
        dut.count = 16'hffff;
        positive_turn_from_10();
        if (count !== 16'd0 || pulse_count != 4)
            $fatal(1, "positive count wrap failed count=%h pulses=%0d", count, pulse_count);

        dut.count = 16'd0;
        negative_turn_from_10();
        if (count !== 16'hffff || pulse_count != 5)
            $fatal(1, "negative count wrap failed count=%h pulses=%0d", count, pulse_count);

        wait_clocks(4);
        if (step_pulse !== 1'b0)
            $fatal(1, "step_pulse did not return low");
        $display("PASS quadrature decoder: debounce glitch, both directions, invalid transition recovery, one-cycle pulses, 16-bit wrap");
        $finish;
    end
endmodule
