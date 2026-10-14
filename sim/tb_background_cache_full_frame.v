`timescale 1ns/1ps
module tb_background_cache_full_frame;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,enable=0,ack=0,fin=0,busy=0,valid=0,done=0;
 reg [7:0] byte_value=0;
 reg [8:0] index=0;
 wire [5:0] info;
 wire active,wr,pv,sr,start;
 wire [20:0] address;
 wire [31:0] pd,lba;
 integer frame,chunk,i,pixels=0;
 background_cache_loader dut(.clk(clk),.rst_n(rst_n),.enable(enable),
  .base_lba(32'd1000),.song_id(2'd0),.art2_supported(1'b0),.art_request_async(1'b0),.art2_request_async(1'b0),.mv_writer_active(1'b0),.invalidate_ack_async(1'b0),
  .write_ack(ack),.write_finish_toggle(fin),.ready_info(info),.invalidate_toggle(),
  .writer_active(active),.write_req(wr),.write_address(address),.pixel_valid(pv),.pixel_data(pd),
  .sector_req(sr),.sector_start(start),.sector_lba(lba),.sector_busy(busy),.sector_grant(busy),.sector_valid(valid),
  .sector_byte(byte_value),.sector_byte_index(index),.sector_done(done),.sector_error(8'd0));
 always @(posedge clk) if(pv) begin
  pixels=pixels+1;
  if(pd!==32'h00ff0000) $fatal(1,"full frame RGB565 green expansion");
 end
 initial begin
  #22 rst_n=1; @(negedge clk);enable=1;
  for(frame=0;frame<2;frame=frame+1) begin
   for(chunk=0;chunk<1200;chunk=chunk+1) begin
    wait(sr);
    if(lba!==(frame==0?32'd5800:32'd1000)+chunk)
      $fatal(1,"full-frame sector frame=%d chunk=%d",frame,chunk);
    @(posedge clk); #1 busy=1;
    wait(wr);
    if(address!==(frame==0?21'd1766400:21'd1459200)+chunk*256)
      $fatal(1,"full-frame SDRAM chunk address frame=%d chunk=%d",frame,chunk);
    @(negedge clk);ack=1;wait(!wr);repeat(3) @(negedge clk);ack=0;
    wait(dut.state==5); wait(start);
    for(i=0;i<512;i=i+1) begin
     @(negedge clk);valid=1;index=i;byte_value=i%2?8'h07:8'he0;
    end
    @(negedge clk);valid=0;done=1;
    @(negedge clk);done=0;busy=0;
    wait(dut.state==7);
    if((frame==0 && info[3]) || (frame==1 && info[2]))
      $fatal(1,"frame ready before all 1200 chunks complete");
    @(negedge clk);fin=!fin;wait(!active);repeat(3) @(negedge clk);
   end
   if(frame==0 && !info[3]) $fatal(1,"full art frame not ready");
   if(frame==1 && !info[2]) $fatal(1,"full song frame not ready");
  end
  if(pixels!=614400 || info[3:0]!=4'b1100) $fatal(1,"full frame count/tags");
  $display("TEST_PASS background_cache_full_frame 2400 sectors 614400 pixels exact slots boundaries");$finish;
 end
 initial begin #20000000; $fatal(1,"timeout");end
endmodule
