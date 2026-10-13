`timescale 1ns/1ps
module tb_media_write_pipeline;
 reg clk=0,rst_n=0,bg=0,mv=0,bv=0,vv=0,cv=0;
 reg [31:0] bd=0,vd=0,cd=0;
 wire valid;
 wire [31:0] data;
 reg expect_valid;
 reg [31:0] expect_data;
 integer i;
 always #5 clk=~clk;
 media_write_pipeline dut(.clk(clk),.rst_n(rst_n),.background_owner(bg),.mv_owner(mv),
  .background_valid(bv),.mv_valid(vv),.cover_valid(cv),.background_data(bd),
  .mv_data(vd),.cover_data(cd),.pixel_valid(valid),.pixel_data(data));
 initial begin
  repeat(3) @(negedge clk);rst_n=1;
  for(i=0;i<4096;i=i+1) begin
   @(negedge clk);{bg,mv,bv,vv,cv}=i[4:0];bd=32'hB0000000+i;vd=32'hD0000000+i;cd=32'hC0000000+i;
   expect_valid=bg?bv:mv?vv:cv;expect_data=bg?bd:mv?vd:cd;
   @(posedge clk);#1;
   if(valid!==expect_valid || data!==expect_data) $fatal(1,"token mismatch %d",i);
  end
  @(negedge clk);rst_n=0;#1;if(valid!==0 || data!==0) $fatal(1,"reset token");
  $display("PASS media_write_pipeline 4096 tokens, owner priority and reset");$finish;
 end
endmodule
