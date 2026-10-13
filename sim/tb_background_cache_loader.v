`timescale 1ns/1ps
module tb_background_cache_loader;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,enable=0,mv=0,invack=0,ack=0,fin=0,busy=0,valid=0,done=0;
 reg [31:0] base=0;
 reg [1:0] song=0;
 reg [7:0] data=0,error=0;
 reg [8:0] idx=0;
 wire [5:0] info;
 wire inv,active,wr,pv,sr;
 wire [20:0] address;
 wire [31:0] pd,lba;
 integer pixels=0,padded=0,i;
 reg pad_allowed=0;
 reg epoch_saved;
 background_cache_loader #(.FRAME_SECTORS(2)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.base_lba(base),.song_id(song),
  .art2_supported(1'b0),.art_request_async(1'b0),.art2_request_async(1'b0),.mv_writer_active(mv),.invalidate_ack_async(invack),.write_ack(ack),
  .write_finish_toggle(fin),.ready_info(info),.invalidate_toggle(inv),
  .writer_active(active),.write_req(wr),.write_address(address),
  .pixel_valid(pv),.pixel_data(pd),.sector_req(sr),.sector_lba(lba),
  .sector_busy(busy),.sector_valid(valid),.sector_byte(data),.sector_byte_index(idx),
  .sector_done(done),.sector_error(error));
 always @(posedge clk) if(pv) begin
  if(!active) $fatal(1,"pixel outside writer ownership");
  pixels=pixels+1;
  if(pd===32'd0 && pad_allowed) padded=padded+1;
  else if(pd!==32'hff000000) $fatal(1,"RGB565 LE red expansion");
 end
 task handshake;
 input [20:0] expected;
 begin
  wait(wr); if(address!==expected) $fatal(1,"chunk address got %d expected %d",address,expected);
  repeat(4) @(negedge clk); ack=1;
  wait(!wr); repeat(4) @(negedge clk); ack=0;
 end endtask
 task sector;
 input integer size;
 input [31:0] expected_lba;
 input [7:0] error_value;
 begin
  wait(sr); if(lba!==expected_lba) $fatal(1,"wrong sector LBA %d",lba);
  @(posedge clk); #1 busy=1;
  for(i=0;i<size;i=i+1) begin
   @(negedge clk); idx=i; data=i%2 ? 8'hf8 : 8'h00; valid=1;
  end
  @(negedge clk); valid=0; done=1; error=error_value;
  @(negedge clk); done=0;busy=0;error=0;
 end endtask
 task finish_chunk;
 begin
  wait(dut.state==7 || dut.state==9);
  repeat(8) @(negedge clk);
  if(!active) $fatal(1,"writer ownership released before SDRAM completion");
  fin=!fin;
  wait(!active); repeat(3) @(negedge clk);
 end endtask
 initial begin
  #22 rst_n=1; repeat(10) @(negedge clk);
  if(wr||sr||info[3:2]) $fatal(1,"old card must remain idle");
  base=1000; enable=1;
  handshake(21'd1766400); sector(512,5800,0);
  mv=1; finish_chunk;
  repeat(10) @(negedge clk);
  if(active||wr||sr||info[3]) $fatal(1,"MV priority/early art ready");
  mv=0; handshake(21'd1766656); sector(512,5801,0);
  if(info[3]) $fatal(1,"art published before final SDRAM drain");
  finish_chunk; if(!info[3]) $fatal(1,"art not ready after complete frame");
  handshake(21'd1459200); sector(512,1000,0); finish_chunk;
  handshake(21'd1459456); sector(512,1001,0);
  if(info[2]) $fatal(1,"song published before write finish");
  finish_chunk;
  if(info[3:0]!==4'b1100 || pixels!=1024) $fatal(1,"initial frame tags/count");
  @(negedge clk); song=1; repeat(5) @(negedge clk);
  epoch_saved=inv;
  if(info[2] || !inv) $fatal(1,"song ready not invalidated");
  song=2; repeat(5) @(negedge clk); song=3; repeat(5) @(negedge clk);
  if(inv!==epoch_saved || wr||sr) $fatal(1,"pending epochs must coalesce and block overwrite");
  invack=inv; handshake(21'd1459200); sector(512,4600,0);
  // Mid-job switch: complete old chunk, never publish its frame.
  song=2; repeat(5) @(negedge clk); finish_chunk;
  repeat(10) @(negedge clk);
  if(info[2] || wr||sr) $fatal(1,"obsolete song/ACK gate");
  invack=inv;
  handshake(21'd1459200); sector(512,3400,0); finish_chunk;
  handshake(21'd1459456); sector(512,3401,0); finish_chunk;
  if(info[3:0]!==4'b1110) $fatal(1,"latest song tag/art persistence");
  song=1; repeat(5) @(negedge clk); invack=inv;
  pad_allowed=1;
  handshake(21'd1459200); sector(12,2200,0);
  handshake(21'd1459200); sector(12,2200,0);
  handshake(21'd1459200); sector(12,2200,0); finish_chunk;
  if(padded!=0 || info[2]) $fatal(1,"short sector must cancel without padding or publishing");
  repeat(30) @(negedge clk); if(wr||sr||active) $fatal(1,"failed song must not immediately retry");
  // New song clears failure; explicit adapter error also drains and blocks retry.
  song=0; repeat(5) @(negedge clk); invack=inv;
  handshake(21'd1459200); sector(512,1000,8'h20);
  handshake(21'd1459200); sector(512,1000,8'h20);
  handshake(21'd1459200); sector(512,1000,8'h20); finish_chunk;
  repeat(30) @(negedge clk); if(wr||sr||active||info[2]) $fatal(1,"SD error publication/retry");
  $display("TEST_PASS background_cache_loader pixels addresses priority epoch coalescing drain short error");
  $finish;
 end
 initial begin #1000000; $fatal(1,"timeout state=%d",dut.state); end
endmodule
