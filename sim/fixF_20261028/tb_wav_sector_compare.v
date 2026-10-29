`timescale 1ns/1ps
module tb_wav_sector_compare;
 reg [31:0] read_count=0, total=0;
 integer i;
 wav_stream_player dut(.total_sectors(total));
 task check;
 begin
  #1;
  if (dut.sectors_complete !== (read_count >= total))
   $fatal(1,"sector comparison mismatch read=%h total=%h",read_count,total);
 end
 endtask
 initial begin
  force dut.sectors_read = read_count;
  read_count=32'h0000ffff; total=32'h00010000; check;
  read_count=32'h00010000; total=32'h0000ffff; check;
  read_count=32'hffffffff; total=32'hffffffff; check;
  read_count=0; total=0; check;
  for(i=0;i<10000;i=i+1) begin read_count=$random; total=$random; check; end
  $display("PASS sector comparator boundaries and 10000 random pairs");
  $finish;
 end
endmodule
