`timescale 1ns/1ps
module tb_s7_recovery_clear;
 reg clk=0,rst=0,ready=0;
 wire reset_n; wire [7:0] error; wire toggle;
 always #5 clk=~clk;
 media_supervisor #(.CLK_FREQ_HZ(2000),.MOUNT_TIMEOUT_MS(8),
 .REMOUNT_COOLDOWN_MS(12),.RESET_PULSE_CYCLES(4)) dut(
 .clk(clk),.rst_n(rst),.mount_error(8'd0),.media_ready(ready),.sector_error(8'd0),
 .sector_done(1'b0),.sector_busy(1'b0),.sd_rst_n(reset_n),
 .media_err_code(error),.media_err_toggle(toggle));
 initial begin
 repeat(4) @(negedge clk); rst=1;
 wait(!reset_n); wait(reset_n); ready=1;
 repeat(8) @(negedge clk);
 if(error!==0) $fatal(1,"FAIL successful remount must clear active error, got %h",error);
 $display("PASS recovery clears active error"); $finish;
 end
 initial begin #10000; $fatal(1,"FAIL watchdog"); end
endmodule
