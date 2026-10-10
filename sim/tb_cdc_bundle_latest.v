`timescale 1ns/1ps
module tb_cdc_bundle_latest;
 reg src_clk=0,dst_clk=0,src_rst_n=0,dst_rst_n=0;
 reg [63:0] src_data=0;
 reg src_update=0;
 wire [63:0] dst_data;
 reg [7:0] vol_src=0;
 reg vol_update=0;
 wire [7:0] vol_dst;
 integer i;
 always #5 src_clk=~src_clk;
 always #7 dst_clk=~dst_clk;
 cdc_bundle_latest #(.WIDTH(64)) metadata(
  .src_clk(src_clk),.src_rst_n(src_rst_n),.src_data(src_data),.src_update(src_update),
  .dst_clk(dst_clk),.dst_rst_n(dst_rst_n),.dst_data(dst_data));
 cdc_bundle_latest #(.WIDTH(8)) volume(
  .src_clk(src_clk),.src_rst_n(src_rst_n),.src_data(vol_src),.src_update(vol_update),
  .dst_clk(dst_clk),.dst_rst_n(dst_rst_n),.dst_data(vol_dst));
 task wait_metadata;
  input [63:0] expected;
  integer timeout;
  begin
   timeout=0;
   while(dst_data!==expected && timeout<300) begin @(posedge dst_clk); #1; timeout=timeout+1; end
   if(dst_data!==expected) $fatal(1,"FAIL metadata expected=%h got=%h",expected,dst_data);
  end
 endtask
 task wait_volume;
  input [7:0] expected;
  integer timeout;
  begin
   timeout=0;
   while(vol_dst!==expected && timeout<300) begin @(posedge dst_clk); #1; timeout=timeout+1; end
   if(vol_dst!==expected) $fatal(1,"FAIL volume expected=%h got=%h",expected,vol_dst);
  end
 endtask
 initial begin
  repeat(4) @(posedge src_clk);
  @(negedge src_clk);src_rst_n=1;dst_rst_n=1;
  // First value is transferred as one coherent bundle across unrelated clocks.
  @(negedge src_clk);src_data=64'h010A_0003_1234_5678;vol_src=8'hC8;src_update=1;vol_update=1;
  @(negedge src_clk);src_update=0;vol_update=0;
  wait_metadata(64'h010A_0003_1234_5678);wait_volume(8'hC8);
  // The bundled bus is contractually updated only with an explicit source
  // event; unrelated combinational transitions do not feed a wide comparator.
  @(negedge src_clk);src_data=64'hDEAD_BEEF_0123_4567;vol_src=8'hD0;
  repeat(12) @(negedge src_clk);
  if(dst_data!==64'h010A_0003_1234_5678 || vol_dst!==8'hC8)
   $fatal(1,"FAIL payload changed without src_update");
  @(negedge src_clk);src_data=64'h010A_0003_1234_5678;vol_src=8'hC8;
  // Several source changes while the first transfer/acknowledgment is in flight.
  // Intermediate values may coalesce, but the latest complete value must arrive.
  @(negedge src_clk);src_data=64'h020B_0004_8765_4321;vol_src=8'hD8;src_update=1;vol_update=1;
  @(negedge src_clk);src_data=64'h030C_0005_7654_3210;vol_src=8'hE8;
  @(negedge src_clk);src_data=64'h040D_0006_6543_210F;vol_src=8'hF8;
  @(negedge src_clk);src_update=0;vol_update=0;
  wait_metadata(64'h040D_0006_6543_210F);wait_volume(8'hF8);
  // Reset in the middle of publication; after both sides recover the latest
  // payload must be republished, never a torn mix of pre/post-reset fields.
  @(negedge src_clk);src_data=64'h1122_3344_AABB_CCDD;vol_src=8'h60;src_update=1;vol_update=1;
  @(negedge src_clk);src_update=0;vol_update=0;
  repeat(2) @(posedge dst_clk);
  @(negedge dst_clk);dst_rst_n=0;
  @(negedge src_clk);src_rst_n=0;
  repeat(3) @(posedge dst_clk);
  @(negedge src_clk);src_rst_n=1;
  @(negedge dst_clk);dst_rst_n=1;
  wait_metadata(64'h1122_3344_AABB_CCDD);wait_volume(8'h60);
  // Target-only reset clears its captured payload; source detects readiness
  // recovery and republishes the still-current snapshot.
  @(negedge dst_clk);dst_rst_n=0;
  repeat(2) @(posedge dst_clk);
  @(negedge dst_clk);dst_rst_n=1;
  wait_metadata(64'h1122_3344_AABB_CCDD);wait_volume(8'h60);
  // Source-only reset must also republish the current bundle, including an
  // all-zero value (which otherwise could be mistaken for reset state).
  @(negedge src_clk);src_rst_n=0;
  repeat(3) @(posedge src_clk);
  @(negedge src_clk);src_rst_n=1;
  wait_metadata(64'h1122_3344_AABB_CCDD);wait_volume(8'h60);
  @(negedge src_clk);src_data=0;vol_src=0;src_update=1;vol_update=1;
  @(negedge src_clk);src_update=0;vol_update=0;
  wait_metadata(64'd0);wait_volume(8'd0);
  @(negedge src_clk);src_rst_n=0;
  repeat(3) @(posedge src_clk);
  @(negedge src_clk);src_rst_n=1;
  wait_metadata(64'd0);wait_volume(8'd0);
  @(negedge src_clk);src_data=64'hA55A_1234_89AB_CDEF;vol_src=8'hA5;src_update=1;vol_update=1;
  @(negedge src_clk);src_update=0;vol_update=0;
  wait_metadata(64'hA55A_1234_89AB_CDEF);wait_volume(8'hA5);
  @(negedge src_clk);src_rst_n=0;
  repeat(3) @(posedge src_clk);
  @(negedge src_clk);src_rst_n=1;
  wait_metadata(64'hA55A_1234_89AB_CDEF);wait_volume(8'hA5);
  $display("PASS cdc_bundle_latest coherent payload, coalescing and source/target reset recovery");
  $finish;
 end
 initial begin #30000;$fatal(1,"FAIL watchdog");end
endmodule
