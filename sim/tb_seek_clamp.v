`timescale 1ns/1ps
// Check the complete signed clamp range, including values above 32 bits.
module tb_seek_clamp;
    reg clk=0, rst_n=0;
    reg signed [36:0] sample;
    reg [31:0] limit_value;
    reg signed [36:0] expected;
    integer i, checks=0;
    always #5 clk=~clk;
    seek_controller dut(
        .clk(clk),.rst_n(rst_n),.play_active(1'b0),.cur_sample(32'd0),
        .total_samples(32'd0),.clear_pulse(1'b0),
        .seek_fwd5_tgl(1'b0),.seek_bwd5_tgl(1'b0),
        .seek_fwd2_tgl(1'b0),.seek_bwd2_tgl(1'b0),.replay_tgl(1'b0),
        .target_sample(),.restart_req());
    task check;
        input signed [36:0] value;
        input [31:0] bound;
        begin
            sample=value; limit_value=bound;
            if(value < 0) expected=0;
            else if(value > $signed({5'd0,bound})) expected=$signed({5'd0,bound});
            else expected=value;
            #1;
            if(dut.clamped !== expected)
                $fatal(1,"clamp sample=%h limit=%h got=%h expected=%h",value,bound,dut.clamped,expected);
            checks=checks+1;
        end
    endtask
    initial begin
        force dut.sum_reg=sample;
        force dut.lim_reg=limit_value;
        check(37'sd0,32'd0);
        check(37'sd1,32'd0);
        check(-37'sd1,32'd0);
        check(37'sd0,32'hffffffff);
        check(37'sh0ffffffff,32'hffffffff);
        check(37'sh100000000,32'hffffffff);
        check(37'sh00000ffff,32'h00010000);
        check(37'sh000010000,32'h0000ffff);
        check(37'sh080000000,32'h7fffffff);
        check(-37'sh100000000,32'hffffffff);
        check(37'sh0fffffffff,32'hffffffff);
        check(37'sh1000000000,32'hffffffff);
        for(i=0;i<20000;i=i+1) begin
            limit_value=$random;
            check($signed({5'd0,limit_value}),limit_value);
            check($signed({5'd0,limit_value})+37'sd1,limit_value);
            check($signed({5'd0,limit_value})-37'sd1,limit_value);
            check(-37'sd1,limit_value);
            check(37'sh100000000,limit_value);
            check({$random,$random},limit_value);
        end
        $display("PASS seek signed clamp %0d boundary/random checks",checks);
        $finish;
    end
endmodule
