`timescale 1ns/1ps
// Protocol model, not a model of analog conversion or converter noise.
module EG_PHY_ADC #(parameter CH5="DISABLE", VREF="DISABLE") (
    input clk, pd, input [2:0] s, input soc,
    output reg eoc, output reg [11:0] dout
);
    reg [4:0] countdown;
    reg [11:0] next_code;
    initial begin countdown=0; next_code=0; eoc=0; dout=0; end
    always @(posedge clk or posedge pd) begin
        if (pd) begin countdown<=0; next_code<=0; eoc<=0; dout<=0; end
        else begin
            eoc <= 0;
            if (soc) begin
                if (countdown != 0 || s != 5 || CH5 != "ENABLE" || VREF != "ENABLE") $fatal(1,"invalid ADC request");
                countdown <= 16;
            end else if (countdown != 0) begin
                countdown <= countdown - 1'b1;
                if (countdown == 1) begin eoc<=1; dout<=next_code; next_code<=next_code+1'b1; end
            end
        end
    end
endmodule

module tb_mic_adc_capture;
    reg clk=0, rst_n=0;
    wire [11:0] sample_code;
    wire sample_valid;
    integer count=0, cycles=0, last_cycle=0;
    mic_adc_capture dut(.clk(clk),.rst_n(rst_n),.sample_code(sample_code),.sample_valid(sample_valid));
    always #20 clk=~clk;
    always @(negedge clk) if (rst_n) begin
        cycles=cycles+1;
        if (sample_valid) begin
            if (sample_code !== (count & 12'hfff)) $fatal(1,"incorrect conversion %d %d",count,sample_code);
            if (count > 0 && (cycles-last_cycle < 172 || cycles-last_cycle > 174))
                $fatal(1,"unexpected sample interval %d",cycles-last_cycle);
            last_cycle=cycles;
            count=count+1;
        end
    end
    initial begin
        repeat (4) @(negedge clk); rst_n=1;
        repeat (50000) @(negedge clk);
        if (count != 287 && count != 288) $fatal(1,"bad sample rate %d", count);
        rst_n=0; repeat (4) @(negedge clk);
        if (sample_valid || sample_code) $fatal(1,"bad reset");
        $display("PASS ADC capture: %0d conversions, cadence and reset",count);
        $finish;
    end
endmodule
