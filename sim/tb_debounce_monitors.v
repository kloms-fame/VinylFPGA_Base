`timescale 1ns/1ps
module tb_debounce_monitors;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    reg [24:0] pins=0;
    reg [1:0] ab1=3, ab2=3;
    wire tick;
    wire [24:0] levels;
    wire [11:0] jf,jr;
    wire [5:0] jd;
    wire bf,br;
    wire [3:0] bd;
    wire e1f,e1r,e2f,e2r;
    wire [15:0] c1,c2;
    integer dip_events=0, fall_events=0, rise_events=0, i;
    debounce_tick #(.TICK_CYCLES(7)) timer(clk,rst_n,tick);
    key_dip_monitor #(.DEBOUNCE_CYCLES(21),.DEBOUNCE_TICK_CYCLES(7),.USE_EXTERNAL_TICK(1)) j2(
        .clk(clk),.rst_n(rst_n),.debounce_ce(tick),
        .key_async(pins[11:0]),.dip_async(pins[17:12]),
        .key_level(levels[11:0]),.dip_level(levels[17:12]),
        .key_fall_pulse(jf),.key_rise_pulse(jr),.dip_change_pulse(jd)
    );
    key_dip_monitor #(.KEY_COUNT(1),.DIP_COUNT(4),.DEBOUNCE_CYCLES(21),
        .DEBOUNCE_TICK_CYCLES(7),.USE_EXTERNAL_TICK(1)) board(
        .clk(clk),.rst_n(rst_n),.debounce_ce(tick),
        .key_async(pins[18]),.dip_async(pins[22:19]),
        .key_level(levels[18]),.dip_level(levels[22:19]),
        .key_fall_pulse(bf),.key_rise_pulse(br),.dip_change_pulse(bd)
    );
    encoder_monitor #(.DEBOUNCE_CYCLES(21),.AB_STABLE_CYCLES(2),
        .DEBOUNCE_TICK_CYCLES(7),.USE_EXTERNAL_TICK(1)) enc(
        .clk(clk),.rst_n(rst_n),.debounce_ce(tick),
        .enc1_a_async(ab1[1]),.enc1_b_async(ab1[0]),.enc1_sw_async(pins[23]),
        .enc2_a_async(ab2[1]),.enc2_b_async(ab2[0]),.enc2_sw_async(pins[24]),
        .enc1_count(c1),.enc2_count(c2),
        .enc1_sw_level(levels[23]),.enc2_sw_level(levels[24]),
        .enc1_sw_fall_pulse(e1f),.enc1_sw_rise_pulse(e1r),
        .enc2_sw_fall_pulse(e2f),.enc2_sw_rise_pulse(e2r)
    );
    always @(negedge clk) if(rst_n) begin
        for(i=0;i<6;i=i+1) dip_events=dip_events+jd[i];
        for(i=0;i<4;i=i+1) dip_events=dip_events+bd[i];
        for(i=0;i<12;i=i+1) begin
            fall_events=fall_events+jf[i];
            rise_events=rise_events+jr[i];
        end
        fall_events=fall_events+bf+e1f+e2f;
        rise_events=rise_events+br+e1r+e2r;
    end
    task clocks;
        input integer n;
        begin repeat(n) @(negedge clk); #1; end
    endtask
    task rotate;
        input [1:0] a,b;
        begin ab1=a;ab2=b;clocks(9);end
    endtask
    initial begin
        clocks(4);rst_n=1;
        clocks(50);
        if(levels!==0 || dip_events!=0 || fall_events!=15)
            $fatal(1,"startup convergence/silence failure");
        pins={25{1'b1}};
        clocks(50);
        if(levels!=={25{1'b1}} || dip_events!=10 || rise_events!=15)
            $fatal(1,"simultaneous release failure");
        pins=0;
        // Both buttons settle while quadrature engines rotate in opposite directions.
        rotate(2'b10,2'b01);rotate(2'b00,2'b00);
        rotate(2'b01,2'b10);rotate(2'b11,2'b11);
        clocks(15);
        if(c1!==16'd1 || c2!==16'hffff || levels!==0 || dip_events!=20 || fall_events!=30)
            $fatal(1,"encoder concurrency failure c1=%h c2=%h",c1,c2);
        rotate(2'b01,2'b10);rotate(2'b00,2'b00);
        rotate(2'b10,2'b01);rotate(2'b11,2'b11);
        if(c1!==0 || c2!==0) $fatal(1,"encoder reverse failure");
        // Reset on a shared CE phase that differs from initial startup.
        rst_n=0;clocks(3);dip_events=0;fall_events=0;rise_events=0;rst_n=1;
        clocks(50);
        if(dip_events!=0 || levels!==0) $fatal(1,"reset DIP silence failure");
        $display("PASS 25-channel monitor integration: startup DIP silence, concurrent press/release, EC1/2 opposite rotation and reversal");
        $finish;
    end
endmodule
