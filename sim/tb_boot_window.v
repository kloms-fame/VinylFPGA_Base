`timescale 1ns/1ps
module tb_boot_window;
reg clk=0,rst_n=0,vs=1,skip=0;
always #5 clk=~clk;
integer n=0;
always @(negedge clk) begin n=n+1; vs=(n%10!=0); end
wire hold_active,timeout_active,skip_active;
boot_layer #(.CLK_FREQ_HZ(1000),.HOLD_MS(60),.TIMEOUT_MS(80),.SKIP_MIN_MS(40)) hold_dut
(.clk(clk),.rst_n(rst_n),.vs(vs),.de(1'b0),.pixel_x(10'd0),.skip_toggle(1'b0),.first_image_ready(1'b1),.boot_active(hold_active));
boot_layer #(.CLK_FREQ_HZ(1000),.HOLD_MS(60),.TIMEOUT_MS(80),.SKIP_MIN_MS(40)) timeout_dut
(.clk(clk),.rst_n(rst_n),.vs(vs),.de(1'b0),.pixel_x(10'd0),.skip_toggle(1'b0),.first_image_ready(1'b0),.boot_active(timeout_active));
boot_layer #(.CLK_FREQ_HZ(1000),.HOLD_MS(60),.TIMEOUT_MS(80),.SKIP_MIN_MS(40)) skip_dut
(.clk(clk),.rst_n(rst_n),.vs(vs),.de(1'b0),.pixel_x(10'd0),.skip_toggle(skip),.first_image_ready(1'b1),.boot_active(skip_active));
initial begin
 repeat(4) @(negedge clk);rst_n=1;
 repeat(5) @(negedge clk);skip=1;
 repeat(30) @(negedge clk);
 if(!hold_active || !skip_active || !timeout_active) $fatal(1,"FAIL boot minimum window");
 repeat(20) @(negedge clk);
 if(!hold_active || skip_active || !timeout_active) $fatal(1,"FAIL skip/frame boundary window");
 repeat(20) @(negedge clk);
 if(hold_active || !timeout_active) $fatal(1,"FAIL first-image hold duration");
 repeat(20) @(negedge clk);
 if(timeout_active) $fatal(1,"FAIL no-card timeout did not exit");
 $display("PASS boot hold/early-skip/no-card timeout at frame boundaries");$finish;
end
endmodule
