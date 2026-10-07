`timescale 1ns/1ps
module tb_lrc_osd_equiv;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, vs=1, de=0, enable=1;
    reg [9:0] pixel_x=0;
    reg [31:0] time_ms=0;
    reg [23:0] rgb_in=0;
    wire [23:0] actual,expected;
    wire hit_actual,hit_expected;
    integer frame=0,y=0,x=0,checks=0,hits=0;
    reg [31:0] line_times[0:8];
    lrc_osd dut(.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.pixel_x(pixel_x),
        .enable(enable),.time_ms(time_ms),.rgb_in(rgb_in),.rgb_out(actual),.hit(hit_actual));
    lrc_osd_o0 reference(.clk(clk),.rst_n(rst_n),.vs(vs),.de(de),.pixel_x(pixel_x),
        .enable(enable),.time_ms(time_ms),.rgb_in(rgb_in),.rgb_out(expected),.hit(hit_expected));
    task compare;
        begin
            if(actual!==expected || hit_actual!==hit_expected)
                $fatal(1,"OSD mismatch frame=%0d y=%0d x=%0d line=%0d actual=%h expected=%h hits=%b/%b",
                    frame,y,x,dut.line_y,actual,expected,hit_actual,hit_expected);
            if(!enable && (actual!==rgb_in || hit_actual!==0))
                $fatal(1,"disabled OSD failed strict bypass");
            checks=checks+1;
        end
    endtask
    always @(posedge clk) if(rst_n) begin
        compare;
        if(hit_actual) hits=hits+1;
        #1;compare;
    end
    initial begin
        line_times[0]=0;line_times[1]=3000;line_times[2]=6500;
        line_times[3]=10000;line_times[4]=13500;line_times[5]=17000;
        line_times[6]=20500;line_times[7]=24000;line_times[8]=27500;
        repeat(4) @(negedge clk);rst_n=1;
        for(frame=0;frame<15;frame=frame+1) begin
            if(frame<9) time_ms=line_times[frame];
            else if(frame==9 || frame==14) time_ms=0;
            else time_ms=30000;
            enable=(frame!=11);
            hits=0;
            @(negedge clk);vs=0;de=0;pixel_x=0;
            repeat(4) @(negedge clk);
            vs=1;
            // Blanking allows the unchanged line-selection FSM to finish.
            repeat(64) @(negedge clk);
            for(y=0;y<525;y=y+1) begin
                for(x=0;x<800;x=x+1) begin
                    @(negedge clk);
                    pixel_x=x;de=(x<640 && y<480);
                    rgb_in=(frame*65536)^(y*1024)^x;
                    if(frame==12) enable=((x%37)!=0);
                    if(frame==13 && y==200 && x==300) time_ms=0;
                end
            end
            @(negedge clk);de=0;
            if(frame!=11 && hits==0) $fatal(1,"empty enabled lyric frame %0d",frame);
            if(frame==11 && hits!=0) $fatal(1,"pause/disable leaked pixels");
            $display("PASS lyric frame=%0d line=%0d hits=%0d",frame,dut.line_sel,hits);
        end
        $display("PASS OSD equivalence: 15 complete 800x525 frames, 9 lyric lines, seek/backwards time, pause and enable toggles; %0d phase comparisons",checks);
        $finish;
    end
endmodule
