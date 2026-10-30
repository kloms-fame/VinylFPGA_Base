# 比赛提交版本验证记录（2026-10-30）

## 版本与验收依据

用户于 2026-10-30 明确确认当前项目已完成人工验收且没有问题。本轮整理针对比赛提交树的工具、仿真、文档和打包，不改变生产 RTL、ROM、引脚、时钟和实现策略，也不自动下载或烧录。

142 个源码/约束与此前验收冻结的输入逐文件核对一致。工程为 TD 6.2.168116 / EG4S20BG256 / top，单 seed 10，59 个源文件/约束条目路径存在。当前 Git 将用户已移走的历史资料作为删除处理，再按当前功能补入精选内容；未将同级 `VinylFPGA_file` 变成新的运行依赖。

已验收输入清单位于 [accepted_inputs.json](verification/accepted_inputs.json)。源码文本的 CRLF/LF 统一后再算哈希，防止不同系统的 Git 换行策略造成误报；同时保留原验收字节哈希供追溯。

## 布线结果与固件身份

| 指标 | 当前实际 Runs |
| --- | --- |
| SWNS | +0.105 ns |
| HWNS | +0.024 ns |
| STNS / HTNS | 0 / 0 ns |
| setup / hold 违例端点 | 0 / 0 |
| 所选 seed | 10 |
| 固件大小 | 684,332 字节 |

本轮 `verify_gui_runs.py` 检查当前完成的阶段、日志、四项时序、route QoR 端点数及 best_result 一致性通过。当前 bit SHA-256 为 `97b370265af7ec7e7b8b4341a88407631722808f434e473d8ba1b4abf11d3863`。此前人工验收冻结 bit 为 `fa994e2a090a845cca6ee70b46c87a29bfa7bc417f45d9228dd8c981f9850ad3`。逐字节比较表明二者只有 ASCII 日期行内 4 个字节不同，配置数据其余部分完全一致；本轮未据此重新生成 bit。

上述数字是当前约束覆盖范围的结果。源码包不包含 Runs；在另一机器上需用对应 TD/器件库重新构建，并核对新的输出。当前工具使用完整报告判定通过，不把历史 seed 编号或 bitgen Success 单独当成时序验收。

## 当前功能回归

精选测试覆盖音频缓存、FAT32、MV、SD 所有权/恢复、seek、歌词、交互、参数及 Flash。当前入口 `run_current_regression.py` 全量包括 **27 项工具测试和 70 个 RTL 测试场景**，亮度/对比度一项内部执行 16,385 组检查。部分场景共享通路，数量不等于独立产品功能数。

分套件结果写入 [current_results.json](verification/current_results.json)。完整编译和执行日志位于本机 `.codex_tmp/contest_submission_20261030/`，不加入 Git。失败、超时或缺少 PASS 会使对应入口返回非零。统一入口亦可在源码 ZIP 解压后的独立目录执行，以检查提交内容是否自足。

可选 ModelSim 的 6 个独立场景由 `verify_finish_modelsim.py` 提供，未包含在全量 Icarus 的 70 场景统计中。实际本轮是否运行及结果见结果 JSON，未执行的检查不记为通过。

## 保留的检查边界

前轮独立 check_timing 的 PLL feedback 2 项、primitive dummy node 3 项、无 input delay 37 项、无 output delay 49 项及 SDRAM 自动约束 abnormal input delay 32 项仍为已知检查范围。PHY-7002（SDRAM 初始位置调整）、PHY-5079（SDRAM 移位时钟本地布线）及部分厂商 IP/HDL 告警并未通过修改约束清除。32 个 SDRAM 条目对应硬 IP DQ 自动约束的 fast/slow 最大 5 ns、最小 1 ns。

人工验收通过不表示所有静态检查项消失。控制仿真也不等于外部 I/O 电气窗口、温压角落、全部卡片与 HDMI 显示设备组合均已测量。生产代码仍保留未被顶层使用的部分官方示例/通用模块，以保持已验收输入身份；没有把它们全部当成当前产品实现。

逐项测试时长、现场设备型号、示波器测量和整卡镜像哈希并未由用户提供，因此不补写为已执行。比赛设备需具备固化上电运行能力；现场建议步骤见 [演示与验收](demo_acceptance.md)。
