`timescale 1ns/1ps
// Real command + SPI state machines with an ideal card response byte model.
// Measures transport ceiling, NOT physical SD-card latency or sustained IO.
module tb_mv_bandwidth;
reg clk=0;always #5 clk=~clk;
reg rst=1,cmd_req=0,rd_req=0;
wire ca,ra,valid,sreq,sack,ncs;wire[15:0]div;wire[7:0]di;
wire[7:0]response=(dut.state==6) ? 8'hfe : ((dut.state==4 && dut.byte_cnt>=6) ? 8'h00 : 8'hff);
integer cycles=0,start_cycle,bytes=0,n,total;
always @(posedge clk) cycles=cycles+1;
always @(posedge clk) if(valid) bytes=bytes+1;
sd_card_cmd dut(.sys_clk(clk),.rst(rst),.spi_clk_div(16'd0),.cmd_req(cmd_req),.cmd_req_ack(ca),
 .cmd(48'h1100001000ff),.cmd_r1(8'd0),.cmd_data_len(16'd0),
 .block_read_req(rd_req),.block_read_valid(valid),.block_read_req_ack(ra),
 .block_write_req(1'b0),.block_write_data(8'd0),.nCS_ctrl(ncs),.clk_div(div),
 .spi_wr_req(sreq),.spi_wr_ack(sack),.spi_data_in(di),.spi_data_out(response));
spi_master spi(.sys_clk(clk),.rst(rst),.MISO(1'b1),.CPOL(1'b1),.CPHA(1'b1),
 .nCS_ctrl(ncs),.clk_div(div),.wr_req(sreq),.wr_ack(sack),.data_in(di));
initial begin
 #22 rst=0;wait(dut.state==1);@(negedge clk);start_cycle=cycles;
 for(n=0;n<8;n=n+1) begin
  cmd_req=1;wait(ca);@(negedge clk);cmd_req=0;wait(dut.state==1);
  @(negedge clk);rd_req=1;wait(ra);@(negedge clk);rd_req=0;wait(dut.state==1);@(negedge clk);
 end
 total=cycles-start_cycle;
 if(bytes!=4096) $fatal(1,"bytes %0d",bytes);
 $display("TRANSPORT_BYTES=%0d CYCLES=%0d BYTES_PER_SECOND=%0f",bytes,total,bytes*100000000.0/total);
 if(bytes*100000000.0/total<1632000.0) $fatal(1,"transport below MV10fps plus PCM budget");
 $display("TEST_PASS mv_bandwidth ideal card transport budget");$finish;
end
initial begin #10000000; $fatal(1,"timeout");end
endmodule
