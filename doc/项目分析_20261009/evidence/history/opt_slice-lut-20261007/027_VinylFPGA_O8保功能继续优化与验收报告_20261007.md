# VinylFPGA O8 保功能继续优化与验收报告

日期：2026-10-07。工程入口：`prj/VinylFPGA.al`；器件：EG4S20BG256；工作分支：`opt/slice-lut-20261007`。

本轮从已通过实现并下载的 `6ffce23`（O12345_r4_20261007）继续优化。最终候选 `O8_r2_20261007` 已完成综合、布局布线、时序检查、bit 生成及 JTAG SRAM 下载。最终 Slice 7735（78.93%），LUT 14254，比上一轮分别减少 111 和 296；不新增功能裁剪，不修改时钟和时序例外。

## 本轮改动及取舍

1. `src/io/ir_nec_decoder.v`：按包含饱和端点的参数上界计算计数器位宽。默认的 low_cnt、low_width、high_cnt 从各 32 位变为 20、20、19 位；保留原饱和、复位、阈值和事件周期。常量函数使用无符号 32 位输入，保留原比较语义；零值至少分配 1 位。
2. `src/io/ws2812_effects.v`：用 33 位冻结的灯效上下文代替整帧像素寄存器，在原 load 接受边沿锁存模式、颜色、幅度、进度与跑马位置，按当前像素生成 GRB。发送中输入变化只影响下一帧。灯效精度、串行脉宽、刷新控制及关闭补黑保留。
3. `src/io/ws2812_driver.v`：新增可选 STREAMING 模式供 effects 使用；默认值 0 保留原整帧输入行为。串行状态机不变。新增端口用于当前像素数据和索引。

蜂鸣器参数计数器缩位实测仅少 6 LUT、REG 不变；quadrature_decoder 缩位没有面积收益。两项均恢复到 `6ffce23`，没有把源码声明位数减少计作资源收益。实验源码作为 `.v.txt` 归档，不参与工程。

## SynthPilot MCP 模块测量

开发前已获取 `https://www.synthpilot.dev/llms.txt` 用法说明。使用 SynthPilot MCP 独立综合各模块，基线来自 O12345_r4，实验来自 O8_r1。每次使用新的 TD 会话状态，并核对实际综合结果及报告中的 top。

| 模块 | 原 LUT → 实验 LUT | 原 REG → 实验 REG | 最终采用 |
|---|---:|---:|---|
| ir_nec_decoder | 679 → 455 | 173 → 136 | 是 |
| ws2812_effects | 615 → 295 | 231 → 116 | 是 |
| buzzer_feedback | 246 → 240 | 74 → 74 | 否 |
| quadrature_decoder | 106 → 106 | 42 → 42 | 否 |

这些是独立模块 top、默认 auto 映射、无 ADC/SDC 的面积筛选结果，不能相加作为整机收益，也不能作为整机时序签核。一次非空会话错误后产生的旧 top 报告 `o8_baseline_ir_20261007.area` 已明确排除；正确红外基线是 `o8_baseline_ir_unit_20261007.area`。8 份有效报告及调用输出保存在附件。

## 整机最终实现

使用 TD 6.2.168116、area_prior、seed5，保留 107 个源码/约束文件的哈希快照。最终源码、约束、文件集合与快照一致；当前 `.al` 路径展开后与快照一致。原生构建进程退出 0，包含 VERIFIED_ROUND_COMPLETE，日志无 ERROR/FATAL。

| 指标 | 上一轮 O12345_r4 | 本轮 O8_r2 | 本轮变化 |
|---|---:|---:|---:|
| 最终 Slice | 7846 / 9800（80.06%） | 7735 / 9800（78.93%） | −111 |
| 最终 LUT | 14550 / 19600 | 14254 / 19600（72.72%） | −296 |
| 最终 REG | 9514 | 9366 | −148 |
| BRAM9K | 42 / 64 | 42 / 64 | 0 |
| DSP | 15 / 29 | 15 / 29 | 0 |
| Setup WNS | +0.158 ns | +0.132 ns | 均通过 |
| Hold WNS | +0.030 ns | +0.027 ns | 均通过 |
| Setup / Hold TNS | 0 / 0 | 0 / 0 | 均通过 |
| Setup / Hold 违规端点 | 0 / 0 | 0 / 0 | 均通过 |

原生 gate 阶段 LUT 14051 → 13761，REG 9439 → 9291；上表为布局布线及 Hold 修复后的最终数值。两种统计口径分开记录。

当前剩余 2065 Slice、5346 LUT、22 块 BRAM9K。相对最初 `533f605` 的 9504 Slice、17839 LUT，累计减少 1769 Slice、3585 LUT。本轮已低于原计划的 7834 Slice 保守预算目标，但这不代表尚未实现的后续功能已经验收。

最终六个时钟频率不变，50 MHz 域 Setup WNS +3.275 ns，覆盖新增 WS2812 组合渲染所在时钟域；100 MHz 域 +0.132 ns，125 MHz SDRAM 域 +0.215 ns。slow/fast 检查通过，STA 覆盖率 99.95%，结论适用于当前约束。

约束检查 no clock、invalid constraint、combinational loops、no path constraints 均为 0。历史 dummy node=3、PLL/clock buffer 检查项=2、no input delay=33、no output delay=38 等边界仍存在，没有将其宣称为零警告或所有板外接口均全约束。按高效增量要求，仅执行通过的 seed5，不重复综合或 seed7。

## 仿真与审查

| 验证入口 | 结果 | 覆盖与边界 |
|---|---|---|
| `tools/verify_s7_acceptance.py` | 47/47 PASS | 当前最终源码的媒体、显示、SD、输入、歌词、元数据等主回归 |
| `tools/verify_x1x2_repair.py --label o8_final` | 5/5 PASS | 输入、时间基准、MV 保持、数码管、灯效 |
| `tools/verify_ws2812_context.py` | 10/10 PASS | 5 组 effects 等价、5 组 driver 默认整帧/流式/旧版对比 |
| `tools/verify_counter_r5.py` | 实验 33/33 PASS | 8 组最终保留的 IR 配置；25 组已撤回的蜂鸣器实验配置 |

WS 共 254 万周期对比：effects 222 万、driver 32 万。覆盖像素数 1/3/8/16、全模式、缩参全色相、忙时更新、重复 load、关闭补黑、快速重新使能、复位。真实 8 灯串行时序为 50 MHz 下 63/18/35/3000 周期；该用例将 REFRESH_MS 缩短为 1 以提高验证效率，不是默认 20 ms 下的长时间板测。单采样反转的故障注入成功触发 FAIL，失败证据单独标注保存。

IR 验证频率为 50000000、123457、10000、23273、42667、1000、1、0 Hz；默认参数 15394780 周期，包含有效码、重复码、无效脉冲、饱和恢复、阈值边界与随机复位。23273/42667 配置分别验证低/高计数器饱和上界恰为 256 的端点位宽。蜂鸣器 25 项通过属于 O8_r1 实验，不计入最终采用优化的验证收益。

更新 `sim/tb_x1x2_lights.v`，通过实际串行脉宽解码验证输出，并按 load 时刻独立建立期望帧，保留原功能断言，避免依赖已删除的私有 frame_rgb/pixel_mem 实现。旧 `tb_ws2812_x1.v` 的固定绿色预期早于本轮基线且未被现有工具入口引用，本轮未使用它替代当前规格。

独立审查已检查上下文采样边沿、busy/IDLE 对齐、像素索引切换、关闭补黑、计数器端点及 legacy 来源，无阻塞问题。其要求确认的 WS 渲染组合路径已由本轮最终 50 MHz 时序报告覆盖。

## 固件与下载

2026-10-07 19:20 完成 bit 生成和安路 Allink JTAG SRAM 下载。bitgen、setup_debugger、export_bitgen_param 均完成，生成 `.bit`、`top_inst.bid`、`.bitgen_param.f`；自定义 Tcl 流程以 VERIFIED_BITGEN_COMPLETE 作为阶段完成标记，不依赖 GUI run 的 `.bitgen.end.f`。

下载日志包含 EG4S20BG256 型号识别、PRG-2014 Chip validation success、program/download 命令正常完成及 VERIFIED_SRAM_DOWNLOAD_COMPLETE。进程退出 0，bit 生成与下载日志无 ERROR/FATAL。

- 便捷固件：`prj/VinylFPGA_O8_20261007.bit`。
- 原始固件：`prj/resource_opt_verified_20261005/O8_r2_20261007/VinylFPGA_optimized.bit`。
- 发布信息：`prj/VinylFPGA_O8_20261007.release.json`。
- 大小：643592 字节。
- SHA256：`d2c374cdbd47bca5a8eeb59d323efa48d82c814dfbc88cd1321fe14a87d573a5`。
- 下载方式：SRAM，掉电不保留；未写 Flash。上一轮固件仍保留。

已完成工具级构建及实际下载，未进行显示器/扬声器人工观察、长时间播放与物理热插拔验收。当前 UART 静默，未把串口无输出当成功能板验。

## 复现、证据与后续优化空间

原始快照及数据库保存在 `prj/resource_opt_verified_20261005/`，小型原始报告和测试输出归档在同目录下的 `O8继续优化验收附件_20261007/`。`comparison.json` 中旧基线 matches_current_inputs=false 是预期结果，本轮候选为 true。

```powershell
$env:PATH = 'D:/iverilog/bin;' + $env:PATH
python tools/verify_s7_acceptance.py
python tools/verify_ws2812_context.py
python tools/verify_counter_r5.py
python tools/verify_x1x2_repair.py --label MY_NEW_LABEL
python tools/resource_opt_round.py MY_NEW_ROUND
python tools/build_verified_round.py MY_NEW_ROUND --seed 5 --map-mode area_prior
python tools/release_verified_round.py MY_NEW_ROUND --program-sram --allink
```

重新运行 counter 工具会验证当前已恢复的蜂鸣器与其基线一致，不等同于重新运行已撤回的实验；实验源码另行归档供复核。重新构建必须使用新轮次名，避免覆盖已有发布证据。源码可通过本轮 Git 提交或基线 `6ffce23` 回退；回退源码后应使用对应固件。

后续仍可研究 FAT/index/metadata 存储和多路选择结构，但涉及访问时序与存储架构，应单独进行小范围原型、模块面积测量及媒体回归。当前不缩小 FIFO，不删除显示或媒体功能，也不凭代码外观估计收益。本轮以两项经等价验证且具有整机净收益的改动收尾。
