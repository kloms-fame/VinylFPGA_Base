`timescale 1ns/1ps
// Independent elapsed-clock reference checks every output and every pulse.
module debounce_case #(
    parameter PERIOD = 7,
    parameter TICKS = 3,
    parameter CHANNELS = 25,
    parameter ALL_PHASES = 1
)(output reg done = 0);
    reg clk = 0;
    always begin
        #10;
        if (done) wait (!done);
        clk = ~clk;
    end
    reg rst_n = 0;
    reg [CHANNELS-1:0] pins = {CHANNELS{1'b1}};
    wire tick;
    wire [CHANNELS-1:0] level, fall_pulse, rise_pulse;
    debounce_tick #(.TICK_CYCLES(PERIOD)) timer(clk, rst_n, tick);
    debounce_bank #(.CHANNELS(CHANNELS), .STABLE_TICKS(TICKS)) dut(
        .clk(clk), .rst_n(rst_n), .tick_ce(tick), .async_in(pins),
        .level(level), .fall_pulse(fall_pulse), .rise_pulse(rise_pulse)
    );

    reg [CHANNELS-1:0] meta = {CHANNELS{1'b1}};
    reg [CHANNELS-1:0] synced = {CHANNELS{1'b1}};
    reg [CHANNELS-1:0] expected = {CHANNELS{1'b1}};
    reg [CHANNELS-1:0] expected_fall = 0, expected_rise = 0;
    integer start_cycle [0:CHANNELS-1];
    integer cycle = 0, last_tick = -1, checks = 0;
    integer i, phase, phase_count;
    reg [CHANNELS-1:0] old_meta;

    always @(posedge clk) begin
        cycle = cycle + 1;
        expected_fall = 0;
        expected_rise = 0;
        if (!rst_n) begin
            meta = {CHANNELS{1'b1}};
            synced = {CHANNELS{1'b1}};
            expected = {CHANNELS{1'b1}};
            last_tick = -1;
            for (i = 0; i < CHANNELS; i = i+1)
                start_cycle[i] = -1;
        end else begin
            if (tick) begin
                if (last_tick >= 0 && cycle-last_tick != PERIOD)
                    $fatal(1, "tick interval mismatch P=%0d", PERIOD);
                last_tick = cycle;
            end
            for (i = 0; i < CHANNELS; i = i+1) begin
                if (synced[i] == expected[i])
                    start_cycle[i] = -1;
                else if (tick && start_cycle[i] < 0)
                    start_cycle[i] = cycle;
                else if (tick && cycle-start_cycle[i] >= PERIOD*TICKS) begin
                    expected[i] = synced[i];
                    expected_fall[i] = !synced[i];
                    expected_rise[i] = synced[i];
                    start_cycle[i] = -1;
                end
            end
            old_meta = meta;
            meta = pins;
            synced = old_meta;
        end
        #1;
        checks = checks + 1;
        if (level !== expected || fall_pulse !== expected_fall || rise_pulse !== expected_rise)
            $fatal(1, "reference mismatch P=%0d T=%0d cycle=%0d level=%h want=%h fall=%h want=%h rise=%h want=%h",
                   PERIOD,TICKS,cycle,level,expected,fall_pulse,expected_fall,rise_pulse,expected_rise);
    end

    task clocks;
        input integer n;
        integer k;
        begin
            for (k=0; k<n; k=k+1) @(negedge clk);
        end
    endtask

    task reset;
        begin
            rst_n = 0;
            clocks(3);
            rst_n = 1;
        end
    endtask

    initial begin
        clocks(2);
        phase_count = ALL_PHASES ? PERIOD : 3;
        // Every relative phase in scaled models; real 8 ms checks phases 0,1,P-1.
        for (phase=0; phase<phase_count; phase=phase+1) begin
            pins = {CHANNELS{1'b1}};
            reset;
            clocks(ALL_PHASES ? phase : ((phase==2) ? PERIOD-1 : phase));
            pins = 0;
            clocks(PERIOD*TICKS + PERIOD + 5);
            if (level !== {CHANNELS{1'b0}}) $fatal(1, "held press failed");
            pins = {CHANNELS{1'b1}};
            clocks(PERIOD*TICKS + PERIOD + 5);
            if (level !== {CHANNELS{1'b1}}) $fatal(1, "held release failed");
        end

        // Inputs held low at reset must still converge with initial level high.
        pins = 0;
        reset;
        clocks(PERIOD*TICKS + PERIOD + 5);
        if (level !== {CHANNELS{1'b0}}) $fatal(1, "held-at-reset failed");
        pins = {CHANNELS{1'b1}};
        clocks(PERIOD*TICKS + PERIOD + 5);

        if (TICKS > 1 && PERIOD > 3) begin
            // Two subthreshold pulses cannot be accumulated into a press.
            pins = 0;
            clocks(PERIOD*TICKS-2);
            pins = {CHANNELS{1'b1}};
            clocks(4);
            pins = 0;
            clocks(PERIOD*TICKS-2);
            pins = {CHANNELS{1'b1}};
            clocks(PERIOD*TICKS + PERIOD + 5);
            if (level !== {CHANNELS{1'b1}}) $fatal(1, "short pulses accepted");

            // A single synchronized high cycle entirely between CE pulses
            // cancels channel 0, while all other channels continue independently.
            pins = 0;
            clocks(PERIOD*TICKS-PERIOD);
            while (!tick) @(negedge clk);
            clocks(1);
            pins[0] = 1;
            clocks(1);
            pins[0] = 0;
            clocks(PERIOD*TICKS + PERIOD + 5);
            if (level !== {CHANNELS{1'b0}}) $fatal(1, "glitch recovery failed");
        end

        // Repeated noise on channel 0 must not starve all other channels.
        pins = {CHANNELS{1'b1}};
        clocks(PERIOD*TICKS + PERIOD + 5);
        pins = 0;
        repeat (PERIOD*TICKS + PERIOD + 5) begin
            pins[0] = ~pins[0];
            clocks(1);
        end
        if (level[CHANNELS-1:1] !== {(CHANNELS-1){1'b0}})
            $fatal(1, "independent channels starved");
        pins = 0;
        clocks(PERIOD*TICKS + PERIOD + 5);
        $display("PASS debounce P=%0d T=%0d channels=%0d phases=%0d checked_clocks=%0d",
                 PERIOD,TICKS,CHANNELS,phase_count,checks);
        done = 1;
    end
endmodule

module tb_debounce_bank;
    wire a,b,c,d;
    debounce_case #(.PERIOD(7), .TICKS(3)) scaled(a);
    debounce_case #(.PERIOD(5), .TICKS(1)) threshold_one(b);
    debounce_case #(.PERIOD(1), .TICKS(1)) tick_one(c);
    debounce_case #(.PERIOD(5000), .TICKS(80), .CHANNELS(3), .ALL_PHASES(0)) real_8ms(d);
    initial begin
        wait(a && b && c && d);
        $display("PASS shared debounce: all phases, 25 channels, 8 ms, glitches, reset, threshold 1");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "debounce timeout");
    end
endmodule
