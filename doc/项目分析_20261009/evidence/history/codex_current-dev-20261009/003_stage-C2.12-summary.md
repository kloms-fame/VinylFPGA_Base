# VinylFPGA C2.12 Logo 逐行有效跨度压缩摘要

current_stage: C2.12  
goal: 按资源优化执行方案 Task 12，将开机 Logo 的完整裁剪盒 ROM 改为逐行有效跨度编码，在保持当前 16 色、2 倍显示和像素结果不变的前提下减少 BRAM，并消除原始裁剪盒线性地址乘法。

## confirmed_constraints

- 只修改 Logo 生成器、Logo ROM 和 `boot_layer` 的 Logo 取数接口；不修改顶层端口、SD、音频、MV、歌词、HDMI 主链和 WS2812。
- 保持 134×149、16 色、4 bit 索引、2 倍还原、ROM 同步读一拍和 `boot_layer` 现有输出协议。
- 背景索引为 15；每行记录首个非背景像素、有效跨度长度和压缩数据字偏移；跨度外直接输出背景索引。
- 三个数据 bank 使用 TD 可识别的固定二次幂深度和精确地址位宽：4096、2048、1024 字；当前有效数据共 7055 字。

## artifacts

- `tools/gen_boot_logo.py`：增加逐行有效跨度打包和固定 bank ROM 生成。
- `tools/verify_boot_logo_span.py`：解析生成后的 Verilog 元数据/数据 bank，并对 19966 个存储像素做逐像素比较。
- `src/boot/boot_logo_rom.v`：生成后的 16 色逐行跨度 ROM。
- `src/boot/boot_layer.v`：改为传递 `row_index`、`col_index`、`pixel_valid`，移除 `ly * LOGO_W` 线性地址乘法。
- `sim/tb_boot_s2.v`、`sim/tb_boot_window.v`：沿用现有启动画面与帧边界验收入口。

## verification_evidence

- `python tools/verify_boot_logo_span.py`：`BOOT_LOGO_SPAN_PASS pixels=19966 rows=149 banks=3 words=7055 background=15`。
- `tb_boot_s2`：`TEST_PASS boot_s2_smoke`；Logo 统计 `nonblack=43236 maxlum=592 mid_bright=5932 lower=7676`，与原验收门槛一致。
- `tb_boot_window`：`PASS boot hold/early-skip/no-card timeout at frame boundaries`。
- `tb_s2_boot_guard`：`TEST_PASS s2_boot_guard`。
- SynthPilot 第 24 代：`td_build` 成功到 `opt_gate`。
- 第 24 代 `report_area`：物理 LUT 16829/19600、MSlice 1770/4900、BRAM 49/64、DSP 12/29、寄存器 10890/19600。
- 第 24 代 gate QoR：Setup WNS -9951 ps、TNS -325387 ps、73 个 Setup 违例端点；Hold WNS +471 ps、无 Hold 违例。
- 第 24 代 place/route：place 和 route 均成功；最终 overflow=0、无 multi-drive、无 abnormal timing path；route QoR 为 Setup WNS -9040 ps、TNS -243036 ps、71 个 Setup 违例端点、Hold WNS +34 ps。

## decision

- 通过 RTL、逐像素、综合、布局布线和路由 DRC 基础门禁，可作为 C2.12 候选版本保留。
- 相对 C2.11 第 20 代，物理 LUT 增加 30、MSlice 增加 7、BRAM 减少 1、DSP 减少 1；当前 BRAM 节省有限，但 Logo 线性乘法已删除，route 无资源溢出。
- 当前仍未达到全局 Setup 时序收敛；route 阶段仍有 71 个违例端点，且 TD 报告 1 条时钟使用 local routing 的 `PHY-5079` 严重警告。因此本批次不生成 bit，不宣称可烧录交付。

## blocking_reason

全局 Setup WNS 仍为 -9.040 ns，且存在 1 条时钟 local routing 警告；需要用户人工确认 Logo 显示和当前 route 结果后，再决定是保留 C2.12 继续下一逻辑锥，还是回退到 C2.11 做全局时序优先优化。

## next_action

用户人工验收本摘要对应清单：上电 Logo 完整显示、盒外纯黑、亮部/底部字标、跳过、首图自动交接、无卡超时；确认通过后进入 Task 10 或 Task 13。bit 生成必须等后续物理时序收敛和人工烧录门禁，不在本批次执行。

