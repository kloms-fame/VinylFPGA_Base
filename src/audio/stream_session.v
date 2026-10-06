`ifndef VINYL_STREAM_SESSION_V
`define VINYL_STREAM_SESSION_V
// SD domain. Stop both FIFO ends, drain the non-preemptible storage transaction,
// and wait for settled metadata before starting a new playback generation.
module stream_session (
 input wire clk, rst_n, requested, restart,
 input wire storage_busy, video_busy, reader_idle,
 output reg enable, output reg start_toggle
);
 reg [1:0] idle_sync;
 reg [4:0] settle;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) idle_sync<=0;
  else idle_sync<={idle_sync[0],reader_idle};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin enable<=0; settle<=0; start_toggle<=0; end
  else if(!requested || restart) begin enable<=0; settle<=0; end
  else if(!enable) begin
   if(storage_busy || video_busy || !idle_sync[1]) settle<=0;
   else if(settle==31) begin enable<=1; start_toggle<=~start_toggle; end
   else settle<=settle+1'b1;
  end
 end
endmodule
`endif
