`timescale 1ns/1ps
// Exercise the actual header comparator registers at the existing byte
// positions. This local arithmetic check supplements streamed integration.
module tb_closure_header_compare;
 reg clk=0,rst=1;
 reg [31:0] offset=0,bytes=0;
 reg [5:0] position=49;
 integer i,checks=0;
 reg expected;
 always #5 clk=~clk;
 fat32_media_loader dut(.clk(clk),.rst(rst),.sd_init_done(1'b1));
 task check_pair;
  begin
   position=49;expected=(offset>=32'd54 && offset<bytes);
   @(negedge clk);position=51;
   @(negedge clk);
   if(dut.header_offset_ok!==expected) $fatal(1,"offset comparison %h < %h",offset,bytes);
   checks=checks+1;
  end
 endtask
 initial begin
  repeat(3) @(negedge clk);rst=0;
  force dut.load_state=dut.LD_HEADER;
  force dut.streamer_valid=1'b1;
  force dut.header_byte_cnt=position;
  force dut.data_offset=offset;
  force dut.file_len=bytes;
  offset=53;bytes=54;check_pair;
  offset=54;bytes=54;check_pair;
  offset=54;bytes=55;check_pair;
  offset=32'h0000ffff;bytes=32'h00010000;check_pair;
  offset=32'h00010000;bytes=32'h0000ffff;check_pair;
  offset=32'hffffffff;bytes=32'hffffffff;check_pair;
  offset=32'hfffffffe;bytes=32'hffffffff;check_pair;
  for(i=0;i<10000;i=i+1) begin offset=$random;bytes=$random;check_pair;end
  $display("PASS header offset split comparison %0d vectors",checks);$finish;
 end
endmodule
