`timescale 1ns/1ps
module tb_mv_stream_player;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,req=0,ack=0,fin=0,busy=0,valid=0,done=0;
reg [7:0] data=0,error=0; reg [8:0] idx=0;
wire complete,failed,active,wr_req,pv,sr;
wire [31:0] pd,lba; wire [1:0] bank;
integer pixels=0,i,s;
mv_stream_player #(.FRAME_SECTORS(2)) dut(.clk(clk),.rst_n(rst_n),
 .request_toggle(req),.request_lba(32'd2000),.request_bank(2'd2),
 .done_toggle(complete),.failed(failed),.writer_active(active),.write_req(wr_req),
 .write_ack(ack),.write_finish_toggle(fin),.write_bank(bank),.pixel_valid(pv),.pixel_data(pd),
 .sector_req(sr),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),
 .sector_byte(data),.sector_byte_index(idx),.sector_done(done),.sector_error(error));
always @(posedge clk) if(pv) begin
 pixels=pixels+1;
 if(pd!==32'hff000000) $fatal(1,"RGB565 LE red expansion");
end
task handshake;
begin wait(wr_req); repeat(5) @(negedge clk); ack=1; wait(!wr_req);
 repeat(6) @(negedge clk); ack=0; end endtask
task sector;
input integer size;
begin
 wait(sr); @(posedge clk); #1 busy=1; @(negedge clk);
 for(i=0;i<size;i=i+1) begin
  idx=i; data=i%2 ? 8'hf8 : 8'h00; valid=1;
  @(negedge clk); valid=0; @(negedge clk);
 end
 done=1; @(negedge clk); done=0;busy=0;
end endtask
initial begin
 #22 rst_n=1; #8 req=1; handshake;
 wait(sr); if(lba!=2000 || bank!=2) $fatal(1,"command mailbox");
 sector(512); wait(sr); if(lba!=2001) $fatal(1,"sector increment"); sector(512);
 repeat(20) @(negedge clk);
 if(complete || pixels!=512) $fatal(1,"published before SDRAM drain");
 fin=1; wait(complete); if(failed) $fatal(1,"valid frame failed");
 wait(!active); repeat(10) @(negedge clk); req=0; handshake;
 // Short sector must never be published as a complete frame.
 sector(12); wait(!complete); repeat(10) @(negedge clk);
 if(!failed) $fatal(1,"truncation status must remain stable for CDC");
 $display("TEST_PASS mv_stream_player RGB565 exact pixels drain truncation CDC"); $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
