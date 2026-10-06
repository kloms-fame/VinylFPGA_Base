`timescale 1ns/1ps
module tb_mv_index;
`include "sim/s6_20261006/mv_expected.vh"
reg clk=0;always #5 clk=~clk;
reg rst_n=0,start=0,v=0,done=0;reg [7:0] b=0;reg [7:0] mem[0:511];
wire valid;wire [7:0]err;wire [63:0]mv;wire[15:0]flags;integer i;
integer fd;
reg [8*160-1:0] v1path,v2path;
song_index_db dut(.clk(clk),.rst_n(rst_n),.start(start),.in_valid(v),.in_byte(b),.in_done(done),
 .in_error(8'd0),.max_cluster(32'd1101),.valid(valid),.err(err),.song_mv0(mv),.song_flags(flags));
task feed;
begin
 @(negedge clk); start=1;@(negedge clk);start=0;
 for(i=0;i<512;i=i+1) begin v=1;b=mem[i];@(negedge clk);end
 v=0;done=1;@(negedge clk);done=0;repeat(15) @(negedge clk);
end endtask
initial begin
 #22 rst_n=1;
 v2path="sim/s6_20261006/index_v2.hex";v1path="sim/s6_20261006/index_v1.hex";
 fd=$fopen(v2path,"r");
 if(!fd) begin v2path="../../sim/s6_20261006/index_v2.hex";v1path="../../sim/s6_20261006/index_v1.hex";end
 else $fclose(fd);
 $readmemh(v2path,mem);feed;
 if(!valid || mv!==EXPECTED_MV || !flags[3]) $fatal(1,"v2 PC/RTL metadata mismatch");
 $readmemh(v1path,mem);feed;
 if(!valid || mv!=0 || flags[3]) $fatal(1,"legacy v1 must not activate reserved bytes");
 $readmemh(v2path,mem);mem[120]=mem[120]^1;feed;
 if(valid || mv!=0 || err!=8'h34) $fatal(1,"MV metadata must be protected by entry CRC");
 $display("TEST_PASS mv_index v2 metadata v1 compatibility CRC rejection");$finish;
end
initial begin #100000; $fatal(1,"timeout");end
endmodule
