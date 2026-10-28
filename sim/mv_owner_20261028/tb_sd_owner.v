`timescale 1ns/1ps
module tb_sd_owner;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 reg areq=0,mreq=0,pause=0,abort=0;
 reg [31:0] alba=32'd500;
 wire init,cs,rd,rdvalid,rdend,absy,aval,adone;
 wire [31:0] rdaddr;
 wire [7:0] rddata,abyte,aerr,mdata,merr;
 wire [8:0] aidx;
 wire mvalid,msdone,mdone,mactive,cmd17idle,grant;
 integer which=0,abytes=0,mbytes=0,asecs=0,msecs=0;
 reg [7:0] expected;
 sd_sector_adapter #(.SECTOR_TIMEOUT_CYCLES(30000)
`ifdef FIXE
  ,.USE_BUS_GRANT(1'b1)
`endif
 ) adapter(
  .clk(clk),.rst_n(!rst),.sector_req(areq),.sector_lba(alba),
  .sector_busy(absy),.sector_valid(aval),.sector_byte(abyte),
  .sector_byte_index(aidx),.sector_done(adone),.sector_error(aerr),
  .sd_sec_read(rd),.sd_sec_read_addr(rdaddr),.sd_sec_read_data_valid(rdvalid),
  .sd_sec_read_data(rddata),.sd_sec_read_end(rdend)
`ifdef FIXE
  ,.bus_grant(grant)
`endif
 );
 sd_card_top #(.SPI_LOW_SPEED_DIV(0)) dut(
  .clk(clk),.rst(rst),.SD_nCS(cs),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
  .sd_init_done(init),.sd_sec_read(rd),.sd_sec_read_addr(rdaddr),
  .sd_sec_read_data(rddata),.sd_sec_read_data_valid(rdvalid),.sd_sec_read_end(rdend),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end(),
  .mv_burst_req(mreq),.mv_burst_lba(32'd1000),.mv_burst_len(8'd8),
  .mv_burst_pause(pause),.mv_burst_abort(abort),.mv_burst_valid(mvalid),
  .mv_burst_data(mdata),.mv_burst_sector_done(msdone),.mv_burst_done(mdone),
  .mv_burst_error(merr),.mv_burst_active(mactive),.mv_cmd17_idle(cmd17idle)
`ifdef FIXE
  ,.sd_bus_grant(grant)
`endif
 );
`ifndef FIXE
 assign grant=1'b1;
`endif
 always @(posedge clk) if(!rst) begin
  if(aval) begin
   if(abyte !== (alba[7:0]^aidx[7:0])) $fatal(1,"audio byte mismatch");
   abytes=abytes+1;
  end
  if(adone) begin
   if(aerr && which!=6) $fatal(1,"AUDIO_TIMEOUT err=%02x rd=%b idle=%b mv=%b effective=%b tmo=%d",aerr,rd,cmd17idle,mactive,dut.sd_sec_read_eff,adapter.tmo_cnt);
   if(abytes!=512 && which!=6) $fatal(1,"audio length %0d",abytes);
   asecs=asecs+1;abytes=0;
  end
  if(mvalid) begin
   expected=(8'he8+msecs[7:0])^mbytes[7:0];
   if(mdata!==expected) $fatal(1,"MV mismatch sec=%d idx=%d got=%h expected=%h",msecs,mbytes,mdata,expected);
   mbytes=mbytes+1;
  end
  if(msdone) begin
   if(mbytes!=512) $fatal(1,"MV length %d",mbytes);
   msecs=msecs+1;mbytes=0;
  end
  if(mdone && merr) $fatal(1,"MV error %h",merr);
 end
 reg [4:0] prev=0;
 always @(negedge clk) if(!rst && prev!={rd,cmd17idle,mreq,mactive,dut.sd_sec_read_eff}) begin
  $display("EVENT t=%0t rd=%b idle=%b mvreq=%b mvactive=%b effective=%b grant=%b timeout=%0d",$time,rd,cmd17idle,mreq,mactive,dut.sd_sec_read_eff,grant,adapter.tmo_cnt);
  prev={rd,cmd17idle,mreq,mactive,dut.sd_sec_read_eff};
 end
 task audio_request;
 begin @(negedge clk);areq=1;@(negedge clk);areq=0;end
 endtask
 initial begin
  if(!$value$plusargs("CASE=%d",which)) which=0;
  repeat(10) @(negedge clk);rst=0;
  wait(cmd17idle);repeat(8) @(negedge clk);
  case(which)
   0: begin // Audio already in flight: MV cannot take its command/ack.
    audio_request();wait(!cmd17idle);@(negedge clk);mreq=1;
   end
   1: begin // Adapter has a pending request at the exact MV arrival edge.
    audio_request();mreq=1;
   end
   2: begin // Wait exceeds adapter watchdog; waiting must not count.
    dut.spi_master_m0.token_delay=40000;
    mreq=1;wait(mactive);audio_request();repeat(35000) @(negedge clk);
`ifdef FIXE
    if(adapter.tmo_cnt!=0) $fatal(1,"watchdog counts before grant");
`endif
    pause=0;
   end
   3: begin // CMD12 must ignore MISO during command and its stuff byte.
    dut.spi_master_m0.strict_stop=1;mreq=1;
   end
   4: begin // Abort during a block must finish block and then stop.
    mreq=1;wait(mvalid);repeat(100) @(negedge clk);abort=1;
   end
   5: begin // Reset during data: no stuck CS / owner.
    mreq=1;wait(mvalid);@(negedge clk);rst=1;mreq=0;
    repeat(4) @(negedge clk);if(!cs) $fatal(1,"reset kept CS low");
    rst=0;wait(cmd17idle);audio_request();wait(asecs==1);
    $display("PASS reset_during_data");$finish;
   end
   6: begin // A card that never returns a data token must still timeout.
    dut.spi_master_m0.token_delay=100000;audio_request();
    wait(adone);if(aerr!=8'h05) $fatal(1,"missing watchdog");
    $display("PASS granted_timeout");$finish;
   end
   7: begin // Full bridge must yield a paused burst to pending audio.
    mreq=1;wait(msdone);@(negedge clk);pause=1;audio_request();
   end
  endcase
  wait(mdone);if(!cs) $fatal(1,"CS_NOT_RELEASED_AFTER_CMD12");
  @(negedge clk);mreq=0;abort=0;
  repeat(12) @(negedge clk);
  if(which<=2 || which==7) wait(asecs==1);
  if(which==7 && msecs!=1) $fatal(1,"pause did not yield at block boundary");
  if(which!=4 && which!=7 && msecs!=8) $fatal(1,"bad burst length %0d",msecs);
  if(dut.spi_master_m0.cmd12_count!=1) $fatal(1,"missing CMD12");
  $display("PASS sd_owner case=%0d audio=%0d mv=%0d",which,asecs,msecs);$finish;
 end
 initial begin repeat(200000) @(posedge clk);$fatal(1,"TEST_TIMEOUT case=%d mvsecs=%d audio=%d",which,msecs,asecs);end
endmodule
