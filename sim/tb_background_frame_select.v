`timescale 1ns/1ps
module tb_background_frame_select;
    reg clk=0,rst_n=0,frame_start=0,enable=1;
    always #20 clk=~clk;
    reg [1:0] mode=1,song_id=0;
    // {epoch,art2_tag,art_ready,song_ready,song_id}
    reg [5:0] ready_info=6'b001100;
    wire active,epoch;
    wire [20:0] base;
    integer checks=0;
    background_frame_select dut(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .enable(enable),.mode(mode),.song_id(song_id),.ready_info(ready_info),
        .image_active(active),.epoch(epoch),.base(base));
    task check;
        input ok;
        begin checks=checks+1;if(ok!==1'b1) begin $display("FAIL selector check %0d",checks);$finish_and_return(1);end end
    endtask
    task frame;
        begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;@(negedge clk);end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        frame;check(active && base==1459200 && !epoch);
        ready_info=6'b101101;song_id=1;
        repeat(5) @(negedge clk);check(active && !epoch);
        frame;check(!active && epoch); // ready data still needs one gray frame
        frame;check(active && base==1459200);
        ready_info[2]=0;frame;check(!active);
        ready_info[2]=1;song_id=2;frame;check(!active);
        song_id=1;frame;check(active);
        mode=2;frame;check(active && base==1766400);
        mode=3;frame;check(!active); // slot is still tagged as first art
        ready_info[4]=1;
        repeat(5) @(negedge clk);check(!active);
        frame;check(active && base==1766400);
        mode=2;frame;check(!active); // slot now holds second art
        ready_info[4]=0;frame;check(active);
        ready_info[3]=0;frame;check(!active);
        ready_info[3]=1;ready_info[5]=0;frame;check(!active && !epoch);
        frame;check(active && !epoch);
        enable=0;frame;check(!active);
        enable=1;mode=0;frame;check(!active);
        mode=3;ready_info[4]=1;frame;check(active);
        rst_n=0;@(negedge clk);check(!active && !epoch && base==0);
        $display("PASS background_frame_select: %0d checks, frame commit epoch gray barrier art identity modes 0/1/2/3",checks);$finish;
    end
endmodule
