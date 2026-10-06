`timescale 1ns/1ps
module tb_mv_linear_write;
reg clk=0;always #5 clk=~clk;
reg rst=1,req=0,linear=1;
wire ack,finish,we;wire[20:0]addr;
integer n=0,mode=0,expected;
frame_fifo_write #(.DYNAMIC_LINEAR(1),.BURST_SIZE(8),.FRAME_WIDTH(8),.FRAME_HEIGHT(4)) dut(
 .rst(rst),.mem_clk(clk),.linear_write(linear),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.App_wr_en(we),.App_wr_addr(addr),
 .write_req(req),.write_req_ack(ack),.write_finish(finish),
 .write_addr_0(21'd1228800),.write_addr_1(21'd1305600),.write_addr_2(21'd1382400),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(21'd32),.rdusedw(10'd40));
always @(posedge clk) if(we) begin
 expected=1228800+(mode==0 ? n : ((3-n/8)*8+n%8));
 if(addr!=expected) $fatal(1,"address %0d expected %0d mode %0d n %0d",addr,expected,mode,n);
 n=n+1;
end
task transfer;
begin
 @(negedge clk);req=1;wait(ack);@(negedge clk);req=0;wait(!ack);
 repeat(4) @(negedge clk);linear=~linear; // input changes after capture must not alter orientation
 wait(finish);@(negedge clk);if(n!=32) $fatal(1,"length");repeat(5) @(negedge clk);
end endtask
initial begin
 #22 rst=0;transfer;mode=1;n=0;linear=0;transfer;
 $display("TEST_PASS mv_linear_write latched orientation contiguous MV legacy BMP flip");$finish;
end
initial begin #100000; $fatal(1,"timeout");end
endmodule
