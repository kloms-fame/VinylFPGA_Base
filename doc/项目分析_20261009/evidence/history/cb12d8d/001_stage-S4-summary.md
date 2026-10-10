# VinylFPGA TD 工程修复与构建摘要

- `current_stage`: TD project creation / full build verification
- `goal`: 修复 `prj/VinylFPGA.al` 的 SDRAM 源文件组织，使工程可在 TD 6.2.1 中打开并完整编译到 bitstream。
- `confirmed_constraints`: EG4 / EG4S20BG256；顶层 `top`；主时钟 `clk` 50 MHz；使用 `constraints/pin.adc` 与 `constraints/timing.sdc`；PLL、FIFO、HDMI 加密核保持原文件不变。
- `artifacts`: `prj/VinylFPGA.al`、`src/SD/sdram.v`、`prj/VinylFPGA.bit`。
- `decision`: SynthPilot 已完成 `elaborate -> opt_rtl -> opt_gate -> place -> route -> timing -> bitgen`，所有阶段无错误，允许作为可编译 TD 工程使用。
- `blocking_reason`: 无编译阻塞。最终时序中的 SDRAM 相移时钟 setup 负裕量与官方 `lab_ex5_i2s` 参考工程结果一致，未通过伪约束或修改 PLL 的方式掩盖。
- `next_action`: 在 TD GUI 中打开 `prj/VinylFPGA.al`，按正常 Compile/Run 流程重新生成 GUI run 产物；下载后的板级 HDMI、TF 卡与 SDRAM 功能仍需实板验证。

## 根因与最小修复

1. `src/SD/sdram.v` 未被列入 `VinylFPGA.al`，导致顶层 `U3` 被视为黑盒。
2. `sdr_as_ram.enc.v`、`sdr_init_ref.enc.v`、`sdr_wrrd.enc.v` 被错误标记为 `AutoExcluded`。
3. `src/SD/sdram.v` 首行存在多余的 `global_def.v` 文本。

本次仅修复上述工程入口问题，没有修改应用逻辑、PLL 参数、FIFO 参数、HDMI 加密核或 SDRAM 控制算法。

## 2026-10-03 SynthPilot 验证

- 工程打开：成功分析 36 个源文件。
- 综合：`opt_gate` 成功。
- 物理实现：place、route 成功。
- bitstream：`prj/VinylFPGA.bit`，629624 字节。
- 构建错误：0。
- 资源摘要：LUT 4028/19600，REG 3790/19600，BRAM 20/64，PLL 3/4。
