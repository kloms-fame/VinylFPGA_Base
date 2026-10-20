`timescale 1ns/1ps
module tb_final_axis_lines;
    reg clk=0, rst=1, vs=0, de=0;
    reg [23:0] rgb=0;
    wire user, valid, last;
    wire [23:0] data;
    integer x, line, received=0, last_count=0, sof_count=0;
    always #5 clk=~clk;
    video_rgb_to_axis_640x480 dut(clk,rst,vs,de,rgb,user,valid,last,data);
    always @(posedge clk) begin
        #1;
        if (!rst && valid) begin
            if (data !== received || last !== ((received % 640)==639))
                $fatal(1,"pixel %0d data=%0d TLAST=%b",received,data,last);
            received=received+1;
            if(last) last_count=last_count+1;
            if(user) sof_count=sof_count+1;
        end else if (!rst && (last || user))
            $fatal(1,"sideband outside active video");
    end
    initial begin
        repeat(3) @(negedge clk); rst=0;
        repeat(3) @(negedge clk);
        vs=1; repeat(3) @(negedge clk); vs=0;
        repeat(3) @(negedge clk);
        for(line=0;line<2;line=line+1) begin
            for(x=0;x<640;x=x+1) begin
                de=1; rgb=line*640+x; @(negedge clk);
            end
            de=0; repeat(5) @(negedge clk);
        end
        if(received!=1280 || last_count!=2 || sof_count!=1)
            $fatal(1,"received=%0d EOL=%0d SOF=%0d",received,last_count,sof_count);
        $display("PASS final AXIS: two 640-pixel lines, EOL/data/SOF alignment"); $finish;
    end
endmodule
