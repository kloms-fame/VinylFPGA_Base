# 版本验证记录（2026-10-31 麦克风 / OSD MIC 版本）

## 版本与验收依据

2026-10-30 用户确认 `fe383ab` 已完成人工验收。2026-10-31 在该基线上新增扩展板麦克风采集、降噪（两级低通 + 软噪声门）、OSD 第 6 页 `MIC` 音量档位（0X/4X/5X/6X/7X，默认 5X）与 Flash 掉电保存，详见 [麦克风与 OSD MIC 页](mic_osd.md)。

本版 144 个源码/约束输入已重新逐文件签署哈希，工程为 TD 6.2.168116 / EG4S20BG256 / top，原生 MultiSeed 选中 seed 18，61 个源文件/约束条目路径存在。2026-10-30 的旧签收哈希保留在 Git 历史（`fde3af1` 之前）中，可用于追溯基线输入。

已验收输入清单位于 [accepted_inputs.json](verification/accepted_inputs.json)。源码文本的 CRLF/LF 统一后再算哈希，防止不同系统的 Git 换行策略造成误报；同时保留原验收字节哈希供追溯。

## 布线结果与固件身份

| 指标 | 当前实际 Runs |
| --- | --- |
| SWNS | +0.218 ns |
| HWNS | +0.030 ns |
| STNS / HTNS | 0 / 0 ns |
| setup / hold 违例端点 | 0 / 0 |
| 所选 seed | 18 |
| #slices | 9,380（95.71%，mslice 4,690 / 4,900） |
| 固件大小 | 684,332 字节 |
| 固件 SHA-256 | `a220d57ba6a4ec0b56e8d9ea1a5798ff329112a922ee90669d6f98d4398f1464` |

本版由仓库自带的官方收尾流程 `tools/build_closeout.ps1` 构建（TD GUI 引擎 + `prj/VinylFPGA.al` + MultiSeed），日志打印 `CLOSEOUT_BUILD_TIMING_PASSED`，流内执行了 `fix_hold`；随后 `tools/verify_gui_runs.py` 复检阶段、日志、四项时序、route QoR 端点数和 best_result 一致性，退出码 0。综合后面积为 LUT 17,570/19,600（89.64%）、Reg 12,218、BRAM 55/64、DSP 10/29、ADC 1/1，比基线 `fe383ab` 少 289 LUT 与 8 个 BRAM。

上一版（seed 10）的 bit SHA-256 为 `97b370265af7ec7e7b8b4341a88407631722808f434e473d8ba1b4abf11d3863`，2026-10-30 人工验收冻结 bit 为 `fa994e2a090a845cca6ee70b46c87a29bfa7bc417f45d9228dd8c981f9850ad3`；本版包含麦克风相关 RTL 与 seed 变更，属于新的实现结果，不能与之逐字节等同。

上述数字是当前约束覆盖范围的结果。源码包不包含 Runs；在另一机器上需用对应 TD/器件库重新构建，并核对新的输出。当前工具使用完整报告判定通过，不把历史 seed 编号或 bitgen Success 单独当成时序验收。

## 当前功能回归

精选测试覆盖音频缓存、FAT32、MV、SD 所有权/恢复、seek、歌词、交互、参数及 Flash。当前入口 `run_current_regression.py` 全量包括 **27 项工具测试和 70 个 RTL 测试场景**，亮度/对比度一项内部执行 16,385 组检查。部分场景共享通路，数量不等于独立产品功能数。

本版另加两个自校验测试台，不计入上述统计：`sim/mic_osd_v3/tb_mic_signal_condition.v`（档位增益、门限、饱和、20 kHz 抑制、4:1 抽取）与 `sim/mic_osd_v3/tb_ui_mic_params.v`（6 页轮转、MIC 档位循环与回绕）。两者均以 `TB_PASS` 结尾，运行命令见 `sim/mic_osd_v3/README.md`。

分套件结果写入 [current_results.json](verification/current_results.json)。完整编译和执行日志位于本机 `.codex_tmp/contest_submission_20261030/`，不加入 Git。失败、超时或缺少 PASS 会使对应入口返回非零。统一入口亦可在源码 ZIP 解压后的独立目录执行，以检查提交内容是否自足。

可选 ModelSim 的 6 个独立场景由 `verify_finish_modelsim.py` 提供，未包含在全量 Icarus 的 70 场景统计中。实际本轮是否运行及结果见结果 JSON，未执行的检查不记为通过。

## 保留的检查边界

前轮独立 check_timing 的 PLL feedback 2 项、primitive dummy node 3 项、无 input delay 37 项、无 output delay 49 项及 SDRAM 自动约束 abnormal input delay 32 项仍为已知检查范围。PHY-7002（SDRAM 初始位置调整）、PHY-5079（SDRAM 移位时钟本地布线）及部分厂商 IP/HDL 告警并未通过修改约束清除。32 个 SDRAM 条目对应硬 IP DQ 自动约束的 fast/slow 最大 5 ns、最小 1 ns。

人工验收通过不表示所有静态检查项消失。控制仿真也不等于外部 I/O 电气窗口、温压角落、全部卡片与 HDMI 显示设备组合均已测量。生产代码仍保留未被顶层使用的部分官方示例/通用模块，以保持已验收输入身份；没有把它们全部当成当前产品实现。

逐项测试时长、现场设备型号、示波器测量和整卡镜像哈希并未由用户提供，因此不补写为已执行。比赛设备需具备固化上电运行能力；现场建议步骤见 [演示与验收](demo_acceptance.md)。
