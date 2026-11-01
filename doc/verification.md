# 比赛提交版本验证记录（2026-11-01）

## 版本与验收范围

当前源码冻结版本为 `mic-followvol-v1.0`，工程为 TD 6.2.168116 / EG4S20BG256 / `top` / seed 15。[提交输入清单](verification/accepted_inputs.json)逐文件记录 145 个 `src`/`constraints` 输入和 63 个主工程条目；`verify_submission.py` 同时核对主工程哈希、seed、相对路径和文档链接。源码文本按 CRLF 转 LF 后计算哈希，避免 Windows 与 Linux 签出产生无意义差异。

2026-10-30 的人工验收只覆盖此前的 seed 10 主线。之后加入的麦克风跟随音量版本不能自动继承该结论。本轮完成的是当前源码身份、数字回归和打包检查，不是 seed 15 的模拟输入、音质、供电或整机固化验收。

## 构建与固件身份

| 指标 | `mic-followvol-v1.0` 发布证据 |
| --- | --- |
| SWNS | +0.060 ns |
| HWNS | +0.021 ns |
| STNS / HTNS | 0 / 0 ns |
| setup / hold 违例端点 | 0 / 0 |
| 所选 seed | 15 |
| 固件大小 | 684,332 字节 |
| 规范固件 SHA-256 | `12888BE734514BCE75FBF16651CACA2C2E680833A75909AD35F90CC582C4B2F8` |

规范固件以发布时独立归档的 `稳定固件_麦克风跟随VOL_seed15_12888BE7.bit` 为准，不随源码 ZIP 分发。`prj/VinylFPGA_Runs/best_result/` 是可重建的本机构建候选；检查到的一次候选与规范 bit 仅相差 3 个日期头字节，但这不能替代实际文件哈希和配置数据核对。交付时必须以赛事附件中的实际文件为准。

`verify_gui_runs.py` 只接受已完成的 MultiSeed 输出，要求存在 `.multiSeed.end.f`、seed 的 place/route/bitgen 完成标记、时序报告、route QoR 和一致的 best_result。缺少完成标记时应重新完成 TD 构建；不得把进行中的 Runs、历史 seed 编号或 bitgen 单步 Success 写成当前时序签核。源码包本身不含 Runs，详见[构建说明](build.md)。

## 当前功能回归

全量入口 `python -X utf8 tools/run_current_regression.py` 于 2026-11-01 实际返回退出码 0，包含 **27 项工具测试和 75 个 RTL 测试场景**。亮度/对比度套件内部另执行 16,385 组检查。场景共享部分通路，因此数量不代表 75 个完全独立的系统功能。

| 测试集合 | 场景数 | 结果 |
| --- | ---: | --- |
| Python 工具测试 | 27 | PASS |
| 收尾集成 RTL | 10 | PASS |
| 麦克风数字通路 | 5 | PASS |
| 音频、FAT32 与媒体 | 32 | PASS |
| SD 所有权与恢复 | 11 | PASS |
| seek 集成 | 2 | PASS |
| 歌词与交互 | 8 | PASS |
| 提示音与 Flash | 6 | PASS |
| 亮度与对比度算术 | 1 | PASS |

分套件结果和日志哈希写入 [current_results.json](verification/current_results.json)。本轮证据目录为 `.codex_tmp/regression_20261101_200949/`，不加入 Git。统一入口在失败、超时或缺少 PASS 时返回非零；完整日志保留在每个套件子目录。

## 检查边界

本轮没有重新执行 ModelSim、TD 全构建、烧录或现场人工验收。Icarus 控制模型只能验证数字接口与调度行为，不能覆盖模拟麦克风偏置、噪声、音质、GPIO 供电、外部 I/O 电气窗口、温压角落、全部卡片与 HDMI 设备组合。历史 `check_timing` 项和 partial Runs 也不能替代当前 seed 15 的完整时序报告。

麦克风上板前必须按[硬件接入说明](microphone_bringup.md)完成供电、偏置和输入幅度实测。比赛设备仍需按[演示与验收](demo_acceptance.md)确认同一镜像的断电上电启动、完整媒体和固化状态。
