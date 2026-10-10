# VinylFPGA C2.7 动态歌词显示提交摘要

current_stage: C2.7
goal: 在不复制字库和不改变视频节拍的前提下，将 UIRES 缓存的当前歌词行字形接入既有 lrc_osd 像素路径。

implementation:
- `src/display/lrc_osd.v` 增加 `dynamic_enable` 和 `dynamic_glyphs` 接口；动态开启时从缓存行的 16 个字形槽选字，关闭时继续使用原内置静态行表。
- `src/top_tf_hdmi_audio.v` 将 `lrc_cache` 的当前行字形读口连接到 lrc_osd；动态使能受播放态、UIRES valid、时间定位 valid 和诊断模式共同门控。
- `sim/tb_lrc_dynamic_select.v` 覆盖动态字形产生有效像素命中；原 `tb_lrc_osd_equiv` 保持 15 帧等价回归。

resource_evidence:
- SynthPilot 第 13 代 `opt_gate` 通过。
- LUT 16877/19600（86.11%），MSlice 1792/4900（36.57%），BRAM 50/64（78.12%），寄存器 10864/19600（55.43%）。
- 相对 C2.6 增加的 BRAM 主要来自实际使用 `lrc_cache` 行字形读口；未复制第二套字库或增加额外像素流水。

verification_boundary:
- 已通过动态行选择定向仿真、原有 15 帧 OSD 等价回归和 SynthPilot `opt_gate`。
- 门级 Setup WNS 约 -10.431 ns，TNS -317.227 ns，73 个 Setup 违例；Hold WNS 0.471 ns，无 Hold 违例。
- 当前未执行 place/route/bit，也未进行本阶段板级人工验收；不得据此生成或宣称可烧录 bit。

next_action: 先人工验收 UIRES 正常/缺失/损坏、切曲、暂停和 Seek 下的动态回退行为；然后针对 BRAM/LUT 和门级 Setup 违例做物理实现前优化，只有 route 时序和资源通过后才执行 bitgen。
