`timescale 1ns/1ps
// Compare the physical pin every clock, including asynchronously interrupted frames.
module tb_ws2812_context_equiv;
    parameter integer PIXELS=8;
    parameter integer REAL_TIMING=0;
    localparam integer LIMIT=REAL_TIMING ? 1500000 : 180000;
    reg clk=0, rst_n=0, enable=0, mode_tgl=0, mute=0;
    reg [7:0] level=0;
    reg [3:0] progress=0;
    wire actual, golden;
    always #10 clk=~clk;
    ws2812_effects #(.PIXEL_COUNT(PIXELS),
        .CLK_FREQ_HZ(REAL_TIMING ? 50000000 : 1000),
        .REFRESH_MS(REAL_TIMING ? 1 : 3),
        .BIT_CYCLES(REAL_TIMING ? 63 : 7),
        .T0H_CYCLES(REAL_TIMING ? 18 : 2),
        .T1H_CYCLES(REAL_TIMING ? 35 : 4),
        .RESET_CYCLES(REAL_TIMING ? 3000 : 5)) dut
        (.clk(clk),.rst_n(rst_n),.enable(enable),.mode_tgl(mode_tgl),
         .level(level),.progress(progress),.mute(mute),.ws_data(actual));
    ws2812_effects_o4 #(.PIXEL_COUNT(PIXELS),
        .CLK_FREQ_HZ(REAL_TIMING ? 50000000 : 1000),
        .REFRESH_MS(REAL_TIMING ? 1 : 3),
        .BIT_CYCLES(REAL_TIMING ? 63 : 7),
        .T0H_CYCLES(REAL_TIMING ? 18 : 2),
        .T1H_CYCLES(REAL_TIMING ? 35 : 4),
        .RESET_CYCLES(REAL_TIMING ? 3000 : 5)) ref_dut
        (.clk(clk),.rst_n(rst_n),.enable(enable),.mode_tgl(mode_tgl),
         .level(level),.progress(progress),.mute(mute),.ws_data(golden));
    integer n, frames=0, black_frames=0, high_samples=0, busy_changes=0;
    integer enable_phase;
    reg [31:0] random_state=32'had681987;
    reg [2:0] modes_seen=0;
    reg [5:0] sectors_seen=0;
    reg mutate;
    initial begin
        mutate=$test$plusargs("MUTATE");
        repeat(3) @(negedge clk);
        rst_n=1;
        for(n=0;n<LIMIT;n=n+1) begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(n%17==0) begin
                level=random_state[7:0];
                progress=random_state[11:8];
                mute=random_state[12] && random_state[13];
                if(dut.busy) busy_changes=busy_changes+1;
            end
            // Includes short off/on pulses during a frame and enough off time for a black frame.
            enable_phase=n%(REAL_TIMING ? 160000 : 9000);
            enable=REAL_TIMING ? !((enable_phase<80) || (enable_phase>=50000 && enable_phase<75000))
                               : !((enable_phase<10) || (enable_phase>=1500 && enable_phase<5000));
            if(n%(REAL_TIMING ? 37000 : 503)==0) mode_tgl=~mode_tgl;
            if(n==(REAL_TIMING ? 650000 : 100000)) rst_n=0;
            if(n==(REAL_TIMING ? 650003 : 100003)) rst_n=1;
            if(rst_n && ref_dut.load_req && !ref_dut.busy) begin
                frames=frames+1;
                modes_seen[ref_dut.mode]=1;
                sectors_seen[ref_dut.hue_sector]=1;
                if(!enable) black_frames=black_frames+1;
            end
            @(posedge clk); #1;
            if((actual ^ (mutate && n==6000)) !== golden || dut.busy !== ref_dut.busy) begin
                $display("FAIL pixel=%0d real=%0d cycle=%0d actual=%b golden=%b busy=%b/%b",PIXELS,REAL_TIMING,n,actual,golden,dut.busy,ref_dut.busy);
                $fatal(1);
            end
            if(actual) high_samples=high_samples+1;
        end
        if(frames<10 || black_frames<3 || high_samples<100 || busy_changes<100 || modes_seen!==3'b111 || (!REAL_TIMING && sectors_seen!==6'b111111)) begin
            $display("FAIL coverage frames=%0d black=%0d high=%0d changes=%0d modes=%b sectors=%b",frames,black_frames,high_samples,busy_changes,modes_seen,sectors_seen);
            $fatal(1);
        end
        $display("PASS WS_CONTEXT pixel=%0d real=%0d clocks=%0d frames=%0d black=%0d high=%0d modes=%b sectors=%b",PIXELS,REAL_TIMING,LIMIT,frames,black_frames,high_samples,modes_seen,sectors_seen);
        $finish;
    end
endmodule
