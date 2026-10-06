`ifndef VINYL_MEDIA_PROBE_V
`define VINYL_MEDIA_PROBE_V
// Lowest priority read-only CMD17 on LBA 0 after one second without client IO.
// A probe owns the whole sector; bytes/done never leak into WAV/MV clients.
module media_probe #(
 parameter integer IDLE_CYCLES=100_000_000
)(
 input wire clk,rst_n,ready,
 input wire client_req, input wire [31:0] client_lba,
 output wire client_busy,client_valid,client_done,
 output wire card_req, output wire [31:0] card_lba,
 input wire card_busy,card_valid,card_done
);
 localparam W=(IDLE_CYCLES<2)?1:$clog2(IDLE_CYCLES);
 reg [W-1:0] count;
 reg probing,issued;
 wire take_probe=ready && count==IDLE_CYCLES-1 && !client_req && !card_busy && !probing;
 // Only registered ownership drives busy. The upstream mux qualifies its
 // request with !busy; including take_probe here creates a combinational loop.
 // A client granted on the same edge waits behind this single probe sector.
 assign client_busy=card_busy || probing;
 assign client_valid=card_valid && !probing;
 assign client_done=card_done && !probing;
 assign card_req=probing ? !issued : client_req;
 assign card_lba=probing ? 32'd0 : client_lba;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) count<=0;
  else if(!ready || card_done || client_req) count<=0;
  else if(count!=IDLE_CYCLES-1) count<=count+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin probing<=0; issued<=0; end
  else if(take_probe) begin probing<=1; issued<=0; end
  else if(probing) begin
   if(card_done) begin probing<=0; issued<=0; end
   else if(!card_busy) issued<=1;
  end
 end
endmodule
`endif
