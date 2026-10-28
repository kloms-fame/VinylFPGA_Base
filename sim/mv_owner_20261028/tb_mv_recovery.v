`timescale 1ns/1ps
module tb_mv_recovery;
 reg clk=0,rst=1,mreq=0,rd=0;
 always #5 clk=~clk;
 wire media_rst_n,init,cs,mdone,mactive,re,rv,grant;
 wire [7:0] merr,media_error;
 integer which=0,saved_cmd12=0,saved_error=0,bytes=0;
 wire fault=mdone && merr!=0;
 sd_card_top #(.SPI_LOW_SPEED_DIV(0),.MV_TIMEOUT_CYCLES(2000)) dut(
  .clk(clk),.rst(rst || !media_rst_n),
  .SD_nCS(cs),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.sd_init_done(init),
  .sd_sec_read(rd),.sd_sec_read_addr(32'd500),.sd_sec_read_data(),
  .sd_sec_read_data_valid(rv),.sd_sec_read_end(re),.sd_sec_write(1'b0),
  .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end(),
  .mv_burst_req(mreq),.mv_burst_lba(32'd1000),.mv_burst_len(8'd8),
  .mv_burst_pause(1'b0),.mv_burst_abort(1'b0),.mv_burst_valid(),.mv_burst_data(),
  .mv_burst_sector_done(),.mv_burst_done(mdone),.mv_burst_error(merr),
  .mv_burst_active(mactive),.mv_cmd17_idle(),.sd_bus_grant(grant));
 media_supervisor #(.CLK_FREQ_HZ(100000),.RESET_PULSE_CYCLES(8)) supervisor(
  .clk(clk),.rst_n(!rst),.media_ready(init),.mount_error(8'd0),
  .sector_error(merr),.sector_done(fault),.sector_busy(1'b0),
  .sd_rst_n(media_rst_n),.media_err_code(media_error),.media_err_toggle());
 always @(posedge clk) if(rv) bytes=bytes+1;
 initial begin
  if(!$value$plusargs("CASE=%d",which)) which=0;
  repeat(10) @(negedge clk);rst=0;wait(dut.cmd17_idle);
  case(which)
   0: dut.spi_master_m0.token_delay=10000;
   1: dut.spi_master_m0.stall_op=18;
   2: dut.spi_master_m0.stall_op=12;
  endcase
  @(negedge clk);mreq=1;wait(mdone);
  saved_error=merr;saved_cmd12=dut.spi_master_m0.cmd12_count;
  if(which==0 && saved_cmd12!=1) $fatal(1,"data timeout skipped CMD12");
  if(which==2 && saved_error!=8'h08) $fatal(1,"missing stop timeout");
  if(saved_error==0) $fatal(1,"missing MV error");
  @(negedge clk);mreq=0;
  wait(!media_rst_n);@(negedge clk);if(!cs) $fatal(1,"reset CS low");
  dut.spi_master_m0.stall_op=-1;dut.spi_master_m0.token_delay=0;
  wait(media_rst_n);wait(dut.cmd17_idle);
  if(dut.owner!=2'd0) $fatal(1,"owner stuck after media reset owner=%d",dut.owner);
  @(negedge clk);rd=1;wait(re);@(negedge clk);rd=0;
  if(bytes!=512) $fatal(1,"audio did not recover %d",bytes);
  $display("PASS mv_recovery case=%d error=%h CMD12=%d",which,saved_error,saved_cmd12);$finish;
 end
 initial begin repeat(30000) @(posedge clk);$fatal(1,"recovery timeout case=%d",which);end
endmodule
