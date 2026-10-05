`define SDR_CLK_PERIOD 1000000000/125000000
`define ROW_WIDTH 11
`define SELF_REFRESH_INTERVAL 64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)
`define FIXED_INTERVAL 64000000/(`SDR_CLK_PERIOD)/2**(`ROW_WIDTH)
module macro_check;
  initial begin
    $display("SDR_CLK_PERIOD            = %0d", `SDR_CLK_PERIOD);
    $display("SELF_REFRESH_INTERVAL     = %0d  <== 工程/官方实际值", `SELF_REFRESH_INTERVAL);
    $display("FIXED (加括号后)          = %0d  <== 设计意图值", `FIXED_INTERVAL);
    $display("14bit wrap of INT-10      = %0d", `SELF_REFRESH_INTERVAL - 10);
    $display("14bit mask of (INT-10)    = %0d", (`SELF_REFRESH_INTERVAL - 10) & 14'h3FFF);
    $finish;
  end
endmodule
