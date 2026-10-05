`define SDR_CLK_PERIOD       1000000000/125000000
`define ROW_WIDTH            11
`define SELF_REFRESH_INTERVAL 64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)
// 修复候选：给 SDR_CLK_PERIOD 加括号
`define SDR_CLK_PERIOD_FIX   (1000000000/125000000)
`define INTERVAL_FIX         64000000/`SDR_CLK_PERIOD_FIX/2**(`ROW_WIDTH)

module tb_ref_check;
  reg clk=0; reg Rst=1; reg Sdr_ref_ack=0; reg Sdr_rw_vld=0;
  always #4 clk = ~clk;                 // 125MHz -> 8ns
  always @(posedge clk) Sdr_ref_ack <= 1'b0;   // 无刷新请求则无 ack

  // ==== 复刻 sdr_init_ref 明文逻辑：工程当前宏 ====
  reg init_done=0;
  reg [31:0] sdr_init_cnt=0; reg sdr_init_en=0;
  reg [13:0] init_cnt=0; reg ref_req=0; reg ref_vld=0;
  reg [19:0] sdr_ref_ack_sft=0;
  integer cur_ref_pulses=0;
  always @(posedge clk) begin
    sdr_init_cnt[0] <= sdr_init_en; sdr_init_cnt[31:1] <= sdr_init_cnt[30:0];
    if (Rst) init_cnt <= 14'd0;
    else if (!init_done) init_cnt <= 14'd0;
    else if (init_cnt == `SELF_REFRESH_INTERVAL) init_cnt <= 14'd0;
    else init_cnt <= init_cnt + 1'b1;
    if (Rst) sdr_ref_ack_sft <= 0;
    else begin sdr_ref_ack_sft[0] <= Sdr_ref_ack; sdr_ref_ack_sft[19:1] <= sdr_ref_ack_sft[18:0]; end
    if (Rst) begin ref_req <= 0; ref_vld <= 0; end
    else begin
      if (init_cnt == (`SELF_REFRESH_INTERVAL-10) && !Sdr_ref_ack) ref_req <= 1'b1;
      else ref_req <= 1'b0;
      if (Sdr_ref_ack && ~Sdr_rw_vld) ref_vld <= 1'b1;
      else if (sdr_ref_ack_sft[19]) ref_vld <= 1'b0;
    end
    if (ref_req) cur_ref_pulses = cur_ref_pulses + 1;
  end

  // ==== 复刻：加括号修复后的宏 ====
  reg [13:0] init_cnt_f=0; reg ref_req_f=0;
  integer fix_ref_pulses=0;
  always @(posedge clk) begin
    if (Rst || !init_done) init_cnt_f <= 14'd0;
    else if (init_cnt_f == `INTERVAL_FIX) init_cnt_f <= 14'd0;
    else init_cnt_f <= init_cnt_f + 1'b1;
    if (Rst) ref_req_f <= 1'b0;
    else if (init_cnt_f == (`INTERVAL_FIX-10)) ref_req_f <= 1'b1;
    else ref_req_f <= 1'b0;
    if (ref_req_f) fix_ref_pulses = fix_ref_pulses + 1;
  end

  initial begin
    $display("SDR_CLK_PERIOD(工程) = %0d", `SDR_CLK_PERIOD);
    $display("SELF_REFRESH_INTERVAL(工程) = %0d", `SELF_REFRESH_INTERVAL);
    $display("INTERVAL_FIX(加括号) = %0d  -> 刷新周期 = %0d ns", `INTERVAL_FIX, `INTERVAL_FIX*8);
    #1000; Rst = 0;
    #5000; init_done = 1;         // 模拟初始化完成，进入正常工作
    #2000000;                    // 观察 2ms（= 250000 个 125MHz 周期）
    $display("---------- 2ms 观察窗口结果 ----------");
    $display("init_cnt      (工程) = %0d", init_cnt);
    $display("ref_req 脉冲数(工程) = %0d   <== SDRAM 自动刷新命令数", cur_ref_pulses);
    $display("init_cnt_f  (修复后) = %0d", init_cnt_f);
    $display("ref_req 脉冲数(修复) = %0d", fix_ref_pulses);
    $display("SDRAM 规格要求：每 15.625us 至少 1 次刷新；2ms 内应 >= %0d 次", 2000000/15625);
    $finish;
  end
endmodule
