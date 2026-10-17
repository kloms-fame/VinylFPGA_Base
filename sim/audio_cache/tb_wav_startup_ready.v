`timescale 1ns/1ps
module tb_wav_startup_ready;
    reg wr_clk=0,rd_clk=0;
    always #5 wr_clk=~wr_clk;
    always #20 rd_clk=~rd_clk;
    reg rst_n=0,enable=0,hold_second=0;
    reg [31:0] sectors=2,valid_samples=257,sample_base=10000;
    reg [7:0] skip=255;
    wire req,ready,consumed,ended,idle;
    wire [31:0] lba,count;
    wire signed [15:0] sample;
    wire sample_valid,underrun;
    reg raw_busy=0,raw_valid=0,raw_done=0;
    reg [7:0] raw_byte=0;
    reg [8:0] raw_index=0;
    integer cursor=0,issued=0,sector_number=0,rd_cycles=0;
    integer observed=0,expected=255,test_number=1,first_sector_done=0;
    reg tick=0;
    wav_stream_player dut (
        .wr_clk(wr_clk),.wr_rst_n(rst_n),.play_enable(enable),
        .start_lba(32'd100),.total_sectors(sectors),.valid_samples(valid_samples),.skip_samples(skip),
        .sd_req(req),.sd_lba(lba),.sd_busy(raw_busy || (hold_second && issued>0)),
        .sd_valid(raw_valid),.sd_byte(raw_byte),.sd_byte_index(raw_index),.sd_done(raw_done),.sd_error(8'd0),
        .rd_clk(rd_clk),.rd_rst_n(rst_n),.sample_tick(tick),.sample_out(sample),.sample_valid(sample_valid),
        .sample_ready(ready),.startup_ready(ready),.sample_counter(count),.stream_active(),.stream_end(ended),
        .reader_idle(idle),.sample_consumed(consumed),.buffer_low(),.sample_base(sample_base),.underrun_pulse(underrun));
    always @(negedge rd_clk) begin
        rd_cycles=rd_cycles+1;
        tick=(rd_cycles%8)==0;
    end
    always @(posedge wr_clk) begin
        raw_valid<=0;raw_done<=0;
        if (!enable) begin
            raw_busy<=0;cursor=0;issued=0;
        end else if(req && !raw_busy && !(hold_second && issued>0)) begin
            raw_busy<=1;sector_number=issued;issued=issued+1;cursor=0;
        end else if(raw_busy) begin
            if(cursor==512) begin
                raw_busy<=0;raw_done<=1;
                if(issued==1) first_sector_done=1;
            end else begin
                raw_valid<=1;raw_index<=cursor;
                raw_byte <= (cursor%2)==0 ? (sector_number*256+cursor/2)&255 : (sector_number*256+cursor/2)>>8;
                cursor=cursor+1;
            end
        end
    end
    always @(posedge rd_clk) begin
        if(rst_n && consumed) begin
            #1;
            if(sample!==expected[15:0]) $fatal(1,"test%0d sample%0d got%0d expected%0d",test_number,observed,sample,expected);
            observed=observed+1;expected=expected+1;
        end else #1;
        if(rst_n && underrun) $fatal(1,"test%0d false startup/seek underrun",test_number);
    end
    task stop_session;
        begin
            @(negedge wr_clk);enable=0;
            repeat(12) @(negedge rd_clk);
            if(ready || !idle) $fatal(1,"startup latch did not clear on stop");
            observed=0;first_sector_done=0;
        end
    endtask
    task wait_end;
        input integer n;
        integer cycles;
        begin
            cycles=0;
            while(!ended && cycles<20000) begin @(negedge rd_clk);cycles=cycles+1;end
            if(!ended || observed!=n) $fatal(1,"test%0d EOF count %0d expected%0d",test_number,observed,n);
        end
    endtask
    initial begin
        repeat(5) @(negedge wr_clk);
        rst_n=1;enable=1;hold_second=1;
        wait(first_sector_done);
        repeat(100) @(negedge rd_clk);
        if(ready || observed!=0 || count!=sample_base)
            $fatal(1,"seek255 opened startup gate with only one usable FIFO sample");
        hold_second=0;
        wait_end(257);
        $display("PASS seek255 holds until enough PCM samples, no false underrun, ordered257 samples");
        stop_session;
        test_number=2;sectors=1;valid_samples=6;skip=250;expected=250;sample_base=20000;enable=1;
        wait_end(6);
        $display("PASS short EOF releases startup with6 samples below256 threshold");
        stop_session;
        test_number=3;sectors=1;valid_samples=256;skip=0;expected=0;sample_base=0;enable=1;
        wait_end(256);
        $display("PASS normal startup ordered256 samples; stop clears readiness");
        stop_session;
        $display("PASS tb_wav_startup_ready");
        $finish;
    end
    initial begin #3000000;$fatal(1,"Global timeout");end
endmodule
