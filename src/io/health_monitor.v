`ifndef EXP_HEALTH_MONITOR_V
`define EXP_HEALTH_MONITOR_V
// Current media error clears on a valid zero code. Independent fault history
// remains until reset; no periodic reporting or UART-only counters are present.
module health_monitor (
 input wire clk, rst_n,
 input wire underrun_pulse, buffer_low, stream_active, video_failed,
 input wire osd_err_valid,
 input wire [7:0] osd_err_code,
 input wire ev_overflow,
 output reg [7:0] err_code,
 output reg [3:0] fault_flags
);
 reg buffer_low_q;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) buffer_low_q <= 1'b0;
  else buffer_low_q <= buffer_low;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) err_code <= 8'd0;
  else if(osd_err_valid) err_code <= osd_err_code;
 end
 // [3:0] = event overflow, video failure, active-stream low buffer, underrun.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) fault_flags <= 4'd0;
  else fault_flags <= fault_flags |
       {ev_overflow, video_failed, buffer_low && !buffer_low_q && stream_active, underrun_pulse};
 end
endmodule
`endif
