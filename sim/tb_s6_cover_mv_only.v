`timescale 1ns/1ps
module tb_s6_cover_mv_only;
reg clk=0;
always #20 clk=~clk;
reg rst_n=0, frame_start=0, play_active=0, adjusted_de=0;
reg [9:0] adjusted_x=0;
wire [23:0] rgb_out;
wire mv_read_active, fifo_read_allowed, mv_window_visible;
wire [1:0] mv_read_bank, request_bank;
wire request_toggle;
wire [31:0] request_lba;

s6_video_layer dut(
 .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.play_active(play_active),
 .paused(1'b0),.restart(1'b0),.diagnostic(1'b0),.transport_ready(1'b0),
 .covers_ready(1'b1),.metadata_async(64'd0),.time_ms(32'd0),.seek_frame(16'd0),
 .visual_toggle(1'b0),.raw_read_en(1'b0),.out_de(1'b0),.out_x(10'd176),
 .adjusted_de(adjusted_de),.adjusted_x(adjusted_x),
 .rgb_in(24'h123456),.rgb_out(rgb_out),.mv_read_active(mv_read_active),
 .mv_read_bank(mv_read_bank),.fifo_read_allowed(fifo_read_allowed),
 .mv_window_visible(mv_window_visible),.request_toggle(request_toggle),
 .request_lba(request_lba),.request_bank(request_bank),
 .done_toggle(1'b0),.failed(1'b0));

task tick;
begin @(negedge clk); end
endtask

task frame_boundary;
begin
 @(negedge clk); frame_start=1;
 @(negedge clk); frame_start=0;
 tick;
end
endtask

integer y;
initial begin
 repeat(2) tick;
 rst_n=1;
 frame_boundary;
 play_active=1;
 frame_boundary;

 // Reach the old renderer's center coordinate using the same DE line counter
 // cadence as the production adjusted video stream.
 for(y=0;y<184;y=y+1) begin
   adjusted_de=1; tick;
   adjusted_de=0; tick;
 end
 adjusted_x=176;
 adjusted_de=1;
 #1;
 if(rgb_out!==24'h123456)
   $fatal(1,"FAIL current cover pixel was obscured at old vinyl center: %h",rgb_out);
 if(mv_read_active)
   $fatal(1,"FAIL unavailable MV must remain in static image mode");
 $display("TEST_PASS s6 current image visible at former vinyl center, MV unavailable fallback");
 $finish;
end

initial begin #1000000; $fatal(1,"FAIL timeout"); end
endmodule
