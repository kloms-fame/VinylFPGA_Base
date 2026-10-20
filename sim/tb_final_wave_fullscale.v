`timescale 1ns/1ps
module tb_final_wave_fullscale;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,vs=1,valid=0; reg signed [15:0] pcm=16'sh8000;
wire [23:0] rgb;reg [9:0] x=66;
promax_audio_waveform #(.DECIMATE(1)) dut(.clk(clk),.rst_n(rst_n),.vsync(vs),.de(1'b1),.rgb_in(24'd0),.pixel_x(x),.enable(1'b1),.pcm_tap_valid(valid),.pcm_tap_left(pcm),.rgb_out(rgb));
initial begin
force dut.line_y=12'd420;
#12 rst_n=1;
@(negedge clk); valid=1;
repeat(32) @(negedge clk);
valid=0; vs=0;
@(negedge clk); vs=1; #1;
$display("PCM=0x8000 abs=%0d displayed=%0d bar_height=%0d peak=%0d peak_height=%0d",dut.sample_abs,dut.selected_sample,dut.bar_height,dut.display_peak,dut.peak_height);
if(dut.selected_sample!==8'd128 || dut.bar_height!==7'd95)
    $fatal(1,"negative fullscale must saturate at 95, got %0d",dut.bar_height);
x=584;#1;
if(dut.peak_height!==7'd95) $fatal(1,"negative fullscale peak must saturate at 95, got %0d",dut.peak_height);
$display("PASS final negative-fullscale bar and peak saturation");
$finish;
end
endmodule
