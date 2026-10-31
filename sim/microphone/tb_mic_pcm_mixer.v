`timescale 1ns/1ps
module tb_mic_pcm_mixer;
localparam integer STEP = 8;
localparam integer GMAX = 128;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, in_valid=0, mic_valid=0, mic_enable=0, mute=0, out_ready=1;
reg signed [15:0] in_left=0,in_right=0,mic_sample=0;
reg [7:0] mic_gain_max = GMAX;
wire in_ready,out_valid;
wire signed [15:0] out_left,out_right;
mic_pcm_mixer #(.RAMP_INTERVAL(1)) dut(.*);
integer gain, gnext, i;
reg signed [15:0] mt, last_l, last_r;
reg signed [31:0] el, er;

// Golden model of the microphone term: sat16(mic_sample * gain / 32).
function signed [15:0] mic_term(input signed [15:0] s, input integer g);
  reg signed [31:0] p;
  begin
    p = (s * g) >>> 5;
    if (p > 32'sd32767) p = 32'sd32767;
    else if (p < -32'sd32768) p = -32'sd32768;
    mic_term = p[15:0];
  end
endfunction
function signed [15:0] sat16(input signed [31:0] v);
  begin
    if (v > 32'sd32767) sat16 = 16'sh7fff;
    else if (v < -32'sd32768) sat16 = 16'sh8000;
    else sat16 = v[15:0];
  end
endfunction

task push_check;
  input signed [15:0] l, r, m;
  begin
    @(negedge clk);
    in_valid=1; in_left=l; in_right=r; mic_sample=m;
    gain = dut.mic_gain;
    mt = mic_valid ? mic_term(m, gain) : 16'sd0;
    if (mute) begin el = 0; er = 0; end
    else begin el = l + mt; er = r + mt; end
    if (mic_enable) gnext = ((gain + STEP) > GMAX) ? GMAX : (gain + STEP);
    else gnext = (gain > STEP) ? (gain - STEP) : 0;
    @(posedge clk); #1;
    if (!out_valid || out_left !== sat16(el) || out_right !== sat16(er)) begin
      $display("FAIL gain=%0d exp %0d %0d got %0d %0d", gain, sat16(el), sat16(er), out_left, out_right);
      $fatal(1);
    end
    if (dut.mic_gain !== gnext[7:0]) begin
      $display("FAIL ramp: gain=%0d next exp %0d got %0d", gain, gnext, dut.mic_gain);
      $fatal(1);
    end
    last_l = out_left; last_r = out_right;
    in_valid=0;
  end
endtask

initial begin
  repeat(2) @(posedge clk); @(negedge clk); rst_n=1;
  // Microphone invalid: pure passthrough.
  push_check(16'sd1234,-16'sd2222,16'sd32767);
  @(negedge clk); mic_valid=1; mic_enable=1;
  // Gain ramp 0,8,...,128 with a mid-scale sample: 1024*g/32 = 32*g.
  push_check(16'sd0,16'sd0,16'sd1024);
  for (i=1;i<=16;i=i+1) push_check(16'sd0,16'sd0,16'sd1024);
  // Saturating behaviour at full 4x.
  push_check(16'sd32000,-16'sd32000,16'sd32767);
  push_check(-16'sd32000,16'sd32000,-16'sd32768);
  // Global mute.
  @(negedge clk); mute=1;
  push_check(16'sd1000,-16'sd1000,16'sd0);
  // Backpressure stability: nothing may move while out_ready is low.
  @(negedge clk); mute=0; out_ready=0; in_valid=1; in_left=16'sd1; in_right=16'sd2; mic_sample=16'sd0;
  repeat(4) begin
    @(posedge clk); #1;
    if (!out_valid || in_ready || out_left !== last_l || out_right !== last_r) $fatal(1,"backpressure stability");
  end
  @(negedge clk); in_valid=0; out_ready=1;
  @(posedge clk); #1; if (out_valid) $fatal(1,"held sample did not drain");
  // Ramp down after the microphone is disabled.
  @(negedge clk); mic_enable=0;
  for (i=0;i<17;i=i+1) push_check(16'sd1200,-16'sd1300,16'sd1024);
  push_check(16'sd1200,-16'sd1300,16'sd1024);
  // Invalid microphone sample contributes nothing.
  @(negedge clk); mic_valid=0;
  push_check(16'sd1200,-16'sd1300,16'sd10000);
  @(negedge clk); in_valid=0;
  @(posedge clk); #1; if(out_valid) $fatal(1,"output did not drain");
  $display("PASS mixer ramp gain-law saturation mute backpressure (%0d steps)", i);
  $finish;
end
endmodule
