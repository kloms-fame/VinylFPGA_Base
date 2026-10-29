`timescale 1ns/1ps
// Same-edge background reservation and MV start with a phase-shifted SDRAM
// clock. Exercise the actual frame writer and verify both transfer geometries.
module tb_writer_reservation;
 reg sdclk=0,memclk=0,rst=1;
 always #5 sdclk=~sdclk;
 initial begin #2;forever #4 memclk=~memclk;end
 reg mv_active=0,mv_req=0,bg_active=0,bg_req=0,bg_grant=0;
 wire request=bg_active?bg_req:(mv_active?(mv_req&&!bg_grant):1'b0);
 wire [20:0] len=bg_active?21'd256:21'd512;
 wire [20:0] base=bg_active?21'd1000:21'd2000;
 wire ack,done,en;wire [20:0] addr;
 integer written=0,expected;
 frame_fifo_write #(.DYNAMIC_LINEAR(1),.WRITE_V_FLIP(0),.BURST_SIZE(128)) dut(
  .linear_write(1'b1),.write_hold(1'b0),.write_cancel(1'b0),.rst(rst),.mem_clk(memclk),
  .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .O_wr_busy(),.App_wr_en(en),.App_wr_addr(addr),.write_req(request),.write_req_ack(ack),
  .write_finish(done),.write_addr_0(base),.write_addr_1(base),.write_addr_2(base),
  .write_addr_3(base),.write_addr_index(2'd0),.write_len(len),.fifo_aclr(),.rdusedw(10'd400));
 always @(posedge memclk) if(en) begin
  expected=(written<256)?1000+written:2000+written-256;
  if(addr!==expected) $fatal(1,"write owner mismatch word=%0d addr=%0d expected=%0d",written,addr,expected);
  written=written+1;
 end
 initial begin
  repeat(4) @(negedge sdclk);rst=0;
  @(negedge sdclk);bg_grant=1;mv_active=1;mv_req=1;
  repeat(2) @(negedge sdclk);
  if(request) $fatal(1,"MV request exposed while background reserved");
  bg_active=1;bg_req=1;
  wait(ack);@(negedge sdclk);bg_req=0;
  wait(done);@(negedge sdclk);bg_active=0;bg_grant=0;
  wait(!ack);wait(ack);@(negedge sdclk);mv_req=0;
  wait(done);@(negedge sdclk);
  if(written!=768) $fatal(1,"wrong write length %0d",written);
  $display("PASS real writer reservation and geometry 256+512");$finish;
 end
 initial begin #500000;$fatal(1,"writer reservation timeout words=%0d",written);end
endmodule
