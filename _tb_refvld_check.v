`define SDR_CLK_PERIOD        1000000000/125000000
`define ROW_WIDTH             11
`define SELF_REFRESH_INTERVAL 64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)
module tb_refvld;
  reg clk=0; reg Rst=1; reg Sdr_ref_ack=0; reg Sdr_rw_vld=0; reg init_done=0;
  always #4 clk=~clk;
  reg [13:0] init_cnt=0; reg ref_req=0; reg ref_vld=0; reg [19:0] ack_sft=0;
  reg init_vld=0; reg [31:0] init_cnt32=0; reg init_en=0;
  integer ref_pulses=0; integer refvld_high=0;
  // init_vld 明文逻辑
  always @(posedge clk) begin
    init_cnt32[0]<=init_en; init_cnt32[31:1]<=init_cnt32[30:0];
    if(init_cnt32[30]||Rst) init_vld<=1'b0; else if(init_cnt32[0]) init_vld<=1'b1;
  end
  always @(posedge clk) begin
    if(Rst||!init_done) init_cnt<=14'd0;
    else if(init_cnt==`SELF_REFRESH_INTERVAL) init_cnt<=14'd0;
    else init_cnt<=init_cnt+1'b1;
    if(Rst) ack_sft<=0; else begin ack_sft[0]<=Sdr_ref_ack; ack_sft[19:1]<=ack_sft[18:0]; end
    if(Rst) begin ref_req<=0; ref_vld<=0; end
    else begin
      if(init_cnt==(`SELF_REFRESH_INTERVAL-10)&&!Sdr_ref_ack) ref_req<=1'b1; else ref_req<=1'b0;
      if(Sdr_ref_ack&&~Sdr_rw_vld) ref_vld<=1'b1; else if(ack_sft[19]) ref_vld<=1'b0;
    end
    if(ref_req) ref_pulses=ref_pulses+1;
    if(init_vld||ref_vld) refvld_high=refvld_high+1;
  end
  wire Sdr_ref_req = ref_req | 1'b0;   // App_ref_req 在 sdram.v 中硬接 1'b0
  wire Sdr_init_ref_vld = init_vld || ref_vld;
  initial begin
    #1000 Rst=0; #2000 init_en=1; #3000 init_en=0; #5000 init_done=1;
    // 正常工作 5ms，模拟 Sdr_ref_ack 恒为0（因从不发刷新请求）
    #5000000;
    $display("=========== 5ms 正常工作窗口 ===========");
    $display("Sdr_ref_req  发出次数 = %0d  <== 给 SDRAM 的刷新命令数", ref_pulses);
    $display("Sdr_init_ref_vld 为高周期数 = %0d  <== 上次修复依赖的'刷新窗口'信号", refvld_high);
    $display("init_cnt 当前值 = %0d (SELF_REFRESH_INTERVAL=%0d)", init_cnt, `SELF_REFRESH_INTERVAL);
    $display("init_vld=%b ref_vld=%b -> Sdr_init_ref_vld=%b", init_vld, ref_vld, Sdr_init_ref_vld);
    $display("推论：~Sdr_init_ref_vld 恒为 %b，即上次修复的 ctrl_quiet 中该项永不生效", ~Sdr_init_ref_vld);
    $finish;
  end
endmodule
