`timescale 1ns/1ps
module tb_closure_write_geometry #(parameter WIDTH=640, HEIGHT=4, BURST=128);
 localparam [20:0] WORDS=WIDTH*HEIGHT;
 reg clk=0,rst=1,req=0;
 always #4 clk=~clk;
 wire ack,done,en;
 wire [20:0] addr;
 integer words=0,expected;
 frame_fifo_write #(.DYNAMIC_LINEAR(1),.WRITE_V_FLIP(1),.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.BURST_SIZE(BURST)) dut(
  .linear_write(1'b0),.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
  .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .App_wr_en(en),.App_wr_addr(addr),.write_req(req),.write_req_ack(ack),.write_finish(done),
  .write_addr_0(21'd1000),.write_addr_1(21'd1000),.write_addr_2(21'd1000),.write_addr_3(21'd1000),
  .write_addr_index(2'd0),.write_len(WORDS),.rdusedw(10'd400));
 always @(posedge clk) if(en) begin
  expected=1000+(HEIGHT-1-words/WIDTH)*WIDTH+words%WIDTH;
  if(addr!==expected || words>=WIDTH*HEIGHT) $fatal(1,"flip address width%0d word%0d got%0d expected%0d",WIDTH,words,addr,expected);
  words=words+1;
 end
 initial begin
  repeat(4) @(negedge clk);rst=0;req=1;
  wait(ack);@(negedge clk);req=0;
  wait(done);@(negedge clk);
  if(words!=WIDTH*HEIGHT) $fatal(1,"write count");
  $display("PASS write geometry WIDTH%0d HEIGHT%0d words%0d",WIDTH,HEIGHT,words);$finish;
 end
 initial begin #1000000;$fatal(1,"write geometry timeout");end
endmodule
