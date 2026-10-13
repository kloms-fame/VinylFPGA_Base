`timescale 1ns/1ps
module tb_background_index;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0,iv=0,id=0;
 reg [7:0] ib=0;
 wire valid,done,art2_supported;
 wire [7:0] err;
 wire [31:0] base;
 wire [63:0] cov;
 reg [7:0] blob [0:511];
 integer i;
 song_index_db dut(.clk(clk),.rst_n(rst_n),.start(start),.in_valid(iv),.in_byte(ib),
  .in_done(id),.in_error(8'd0),.max_cluster(32'd25),.valid(valid),.done(done),
  .err(err),.background_base_lba(base),.background_art2_supported(art2_supported),.song_cover0(cov));
 task feed;
 begin
  @(negedge clk); start=1;
  @(negedge clk); start=0;
  for(i=0;i<512;i=i+1) begin @(negedge clk); iv=1;ib=blob[i];end
  @(negedge clk); iv=0;id=1;
  @(negedge clk); id=0;
  repeat(14) @(negedge clk);
 end endtask
 task expect_valid;
 input [31:0] expected;
 input expected_art2;
 begin
  feed;
  if(!valid || err!=0 || cov!=={32'd822,32'd3} || base!==expected || art2_supported!==expected_art2)
   $fatal(1,"extension must preserve legacy index valid=%d err=%d base=%h expected=%h art2=%d expected_art2=%d",valid,err,base,expected,art2_supported,expected_art2);
 end endtask
 task set_base;
 input [31:0] value;
 begin blob[36]=value[7:0];blob[37]=value[15:8];blob[38]=value[23:16];blob[39]=value[31:24];end
 endtask
 initial begin
  $readmemh("sim/s4_fixture/index_only.hex",blob);
  #22 rst_n=1;
  expect_valid(0,0);
  blob[32]="B";blob[33]="G";blob[34]="R";blob[35]="1";
  set_base(32'd123456);
  blob[40]=0;blob[41]=8'h60;blob[42]=8'h09;blob[43]=0;
  blob[44]=5;blob[45]=0;blob[46]=0;blob[47]=0;
  expect_valid(123456,0);
  blob[32]=0;expect_valid(0,0);blob[32]="B";
  blob[41]=0;expect_valid(0,0);blob[41]=8'h60;
  blob[44]=4;expect_valid(0,0);blob[44]=5;
  blob[47]=1;expect_valid(0,0);blob[47]=0;
  set_base(0);expect_valid(0,0);
  set_base(32'hFFFFE88F);expect_valid(32'hFFFFE88F,0);
  set_base(32'hFFFFE890);expect_valid(0,0);
  blob[44]=6;
  set_base(32'd123456);expect_valid(123456,1);
  set_base(32'hFFFFE3DF);expect_valid(32'hFFFFE3DF,1);
  set_base(32'hFFFFE3E0);expect_valid(0,0);
  set_base(32'hFFFFFFFF);expect_valid(0,0);
  set_base(0);expect_valid(0,0);
  blob[44]=7;set_base(32'd123456);expect_valid(0,0);blob[44]=6;
  set_base(32'd123456);
  blob[69]=blob[69]^8'h01;feed;
  if(valid||base!=0||art2_supported||err!=8'h34) $fatal(1,"CRC error must disable extension with whole index");
  $display("TEST_PASS background_index legacy/5-frame/6-frame BGR1 art2 identity invalid layout zero LBA overflow CRC");$finish;
 end
 initial begin #1000000; $fatal(1,"timeout");end
endmodule
