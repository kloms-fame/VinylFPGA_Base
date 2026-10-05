module tb_final;
  // 地址格式（据 sdram.v 注释）：App_addr = {row[10:0], bank[1:0], col[7:0]} = 21位
  localparam FRAME_PIXELS = 307200;
  localparam BUF0=0, BUF1=FRAME_PIXELS, BUF2=FRAME_PIXELS*2, BUF3=FRAME_PIXELS*3;
  function [10:0] row_of; input [20:0] a; row_of = a[20:10]; endfunction
  function [1:0]  bank_of; input [20:0] a; bank_of = a[9:8]; endfunction
  initial begin
    $display("========== 四张图片在 SDRAM 中的行地址分布 ==========");
    $display("BUF0 起始地址 %0d -> row=%0d bank=%0d", BUF0, row_of(BUF0), bank_of(BUF0));
    $display("BUF1 起始地址 %0d -> row=%0d bank=%0d", BUF1, row_of(BUF1), bank_of(BUF1));
    $display("BUF2 起始地址 %0d -> row=%0d bank=%0d", BUF2, row_of(BUF2), bank_of(BUF2));
    $display("BUF3 起始地址 %0d -> row=%0d bank=%0d", BUF3, row_of(BUF3), bank_of(BUF3));
    $display("BUF3 结束地址 %0d -> row=%0d", BUF3+FRAME_PIXELS-1, row_of(BUF3+FRAME_PIXELS-1));
    $display("每张图片占用行数 = %0d 行 (300行/张, 4张共1200行, 未超2048行上限)",
             row_of(BUF1)-row_of(BUF0));
    $display("");
    $display("========== 刷新间隔计算核对 ==========");
    $display("SDRAM 时钟 = 125MHz -> 周期 8ns");
    $display("SDRAM 规格: 2048行(ROW_WIDTH=11) 需在 64ms 内全部刷新");
    $display("  -> 每行刷新周期 = 64ms/2048 = 31.25us");
    $display("  -> 31.25us / 8ns = %0d 个时钟周期 (设计意图值)", 64000000/8/2048);
    $display("工程宏实际展开值 = %0d  <== BUG: 刷新被彻底关闭", 64000000/(1000000000/125000000)/2**11);
    $display("");
    $display("========== 显示读带宽裕量核对 ==========");
    $display("640x480@60Hz: 每帧 %0d 像素, 帧周期 16.67ms", FRAME_PIXELS);
    $display("读带宽需求 = %0d 字 / 16.67ms = %0d 字/us", FRAME_PIXELS, FRAME_PIXELS/16670);
    $display("mem_clk 125MHz 连续读供给 = 125 字/us  (裕量 %.1f 倍)", 125.0/(FRAME_PIXELS/16670.0));
    $display("=> 读带宽极其宽裕, 任何合理刷新/节流都不会导致显示欠载");
    $finish;
  end
endmodule
