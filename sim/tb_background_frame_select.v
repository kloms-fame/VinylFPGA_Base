`timescale 1ns/1ps
module tb_background_frame_select;
    reg clk=0,rst_n=0,frame_start=0,enable=1;
    always #20 clk=~clk;
    reg [1:0] mode=1,song_id=0;
    reg [4:0] ready_info=5'b01100;
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
        frame;check(active && base==1459200);
        ready_info=5'b11001;song_id=1;
        repeat(5) @(negedge clk);check(active && !epoch);
        frame;check(!active && epoch);
        ready_info=5'b11101;frame;check(active);
        song_id=2;frame;check(!active);
        mode=2;frame;check(active && base==1766400);
        enable=0;frame;check(!active);
        enable=1;mode=3;frame;check(!active);
        mode=0;frame;check(!active);
        rst_n=0;@(negedge clk);check(!active && !epoch);
        $display("PASS background_frame_select: %0d checks",checks);$finish;
    end
endmodule
