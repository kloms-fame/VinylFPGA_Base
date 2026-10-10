# R0 收尾交付与架构决策记录 — 2026-10-08

本次交付状态：**代码修复、回归、签核工具和证据整理完成；R0 物理签核未通过，signed_off=false。**

用户已明确选择“形成当前收尾交付和架构决策报告，暂不继续长时间构建”。因此本轮结束于可追溯的未签核交付，不继续 place/route、bitgen、烧录或 C4 开发。

## 交付范围与输入

- 工作区：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`。
- 分支：`codex/r0-closeout-20261008`，基线 HEAD：`428b77715a32390a7ac3a2e8587db0d802004084`。
- 延续原工作区修改，未覆盖原工程 UCode、资源报告或用户新增文档；未提交混合来源的修改。
- 收尾源码快照：`sim/r0_closeout_target_20261008/build_manifest.json`。
- 快照 dirty hash：`f5d1bb184983b40585f6fb11572ed3fcbced62ac365f72102995d59f86000ef6`。该清单是源码交付快照，不是物理构建签核清单。
- 工作区清单：`sim/r0_closeout_target_20261008/workspace_status.txt`。

## 本轮完成项

- [x] 修复 `fat32_media_loader.v` 扇区仲裁的流水启动窗 owner 重叠风险。
- [x] 修复完成后旧请求重新启动、重复读取旧 LBA 的缺陷。
- [x] 保留请求/LBA 两级寄存、五路优先级和不可抢占的在途事务。
- [x] pending/active 阻止再次授权；物理请求每次 grant 只发一拍；完成后的 cooldown 等待输入快照更新。
- [x] 保持可选端口悬空的原仿真兼容，空闲寄存请求默认确定为 0。
- [x] 新增 `sim/tb_r0_sector_arbitration.v`，纳入后续默认回归列表。
- [x] 补齐资源签核检查：LUT <=16500、BRAM <=60；拒绝把 gate/place 报告签核为 route。
- [x] 修复 Windows PowerShell 5.1 UTF-8 BOM 清单解析。
- [x] QoR 和 area 只选择同阶段报告，拒绝 route QoR 混用 place area。
- [x] 完整构建脚本先检查 gate area；Tcl 在 place 后再次检查 LUT/BRAM/slices，超限即停止，避免昂贵的拥塞 route。
- [x] 完成自动验证与资产验证，并记录明确的未签核结论。

仲裁缺陷证据：修复前，一次 UI 请求实测触发 3 次物理命令、2 次完成；修复后，定向测试确认每次事务恰好一条物理命令，完成和 LBA 配对正确。

## 验证结果

| 验证 | 结果 | 证据 |
|---|---|---|
| 原默认 RTL 回归 | 13/13 PASS | `sim/r0_closeout_final_20261008/results.json` |
| 补充 RTL 回归 | 3/3 PASS | `sim/r0_closeout_target_20261008/results.json` |
| 仲裁新测试 | 5 场景 PASS | `sim/r0_closeout_target_20261008/tb_r0_sector_arbitration.log` |
| 原 FAT32 loader | PASS | 同目录 `tb_fat32_media_loader.log` |
| FAT32 scanner | PASS | 同目录 `tb_fat32_volume_scanner.log` |
| 构建指标单元测试 | 14/14 PASS | `sim/r0_closeout_target_20261008/build_metrics_tests.log` |
| Python 语法检查 | PASS | `py_compile`：collector、timing checker、resource checker |
| 4 曲目 SD/UIRES 镜像 | PASS | `vinyl_packer.py verify`：CRC、连续性、INDEX 绑定 |
| 真实 gate 超限预检 | 按预期拒绝 | 17264 >16500，未启动 place/route |
| 历史 place 超限预检 | 按预期拒绝 | 17856 >16500，slices 99.26% >90% |
| 当前签核结论 | FAIL / 未签核 | 缺最终 route，资源不满足，未生成签核 bit |

新仲裁测试覆盖：单请求准确计数、启动窗不可抢占、五路优先级、连续 UI 不同 LBA、超时仅完成一次。上述 13 项与 3 项补充均为本轮重跑，日志不含 FAIL。默认回归入口今后包含新增仲裁测试，共 14 项。

## 构建证据的适用边界

| 证据 | LUT | REG | BRAM | DSP | 物理状态 |
|---|---:|---:|---:|---:|---|
| 既有 `r0_opt/volume_scanner_fields` | 17196 | 11820 | 58 | 17 | gate，超限 |
| 既有 `r0_opt/arb_prereg` | 17101 | 11853 | 58 | 17 | gate，超限 |
| 既有 `r0_signoff/gate_area_prior` | 17264 | 11985 | 58 | 17 | gate，超限 |
| 本轮中间 `r0_signoff/closeout_gate` | 17110 | 11986 | 58 | 17 | gate，超限；非最终源码 |
| 既有 `r0_signoff/seed5` place | 17856 | 12046 | 58 | 17 | 9727/9800 slices，99.26% |

**不能用 QoR 的 `#luts` 或 area 的 `#Total_luts` 代替 area 利用率行 `#lut ... out of 19600`。** 中间 gate 的 13568 是 LUT 统计口径，真实器件 LUT 利用率为 17110；门禁按后者判定。

中间 gate 启动于 16:13:09（北京时间），最终的空闲请求确定值兼容修复随后进入源码。因此清单中的 loader SHA-256 为 `d138421bde31ab81de1a0b0e389761b21a63025688763acbe5f387e9677fbb78`，交付源码为 `db4f8279857cd2a1d29f9d9fc41372234a92b1c5a44b6f947a91ac697bc7ec26`。该 gate 仅作为中间资源失败证据，**不能用于最终源码签核**。遵照用户停止长构建的选择，未再次综合最终修复。

历史 seed5 place：Setup WNS +0.108 ns、Setup TNS 0、Setup 违例 0；Hold WNS -0.011 ns、Hold TNS -0.121 ns、Hold 违例 11。route 日志停止在拥塞消除过程，未生成最终 route QoR、pr.db 或签核 bit。place 的 setup 正裕量不能替代 route 签核。

继承的时钟约束未修改。报告列出的频率为 clk 50 MHz、SD 100 MHz、视频 25 MHz、外存/移位时钟 125 MHz、HDMI 串行 125 MHz。既有 SDRAM 位置不满足约束的 PHY-7002 告警仍需独立解决；未增加 false path 来隐藏同域路径。

## 架构决策交付

方案的资源门限仍未满足；多轮结构优化与综合策略试验并未留下可放行的物理实现。按当前方案应先作架构取舍，再继续 C4。

| 后续方向 | 收益 | 代价与进入条件 |
|---|---|---|
| 保留器件与全部功能，集中优化主要模块 | 保持现有验收语义 | 需要新的模块级资源目标、等价测试和完整物理构建，不能承诺短时收敛 |
| 保留器件，精简非核心常驻显示 | 有机会较快释放布局余量 | 需要用户确认具体功能取舍；UART 已常量关闭、诊断模式已常量关闭，不能把这些再次计为面积收益 |
| 使用更大器件 | 获得明确容量余量 | 涉及板卡、引脚、IP 和时钟迁移，独立立项 |

已保存 hierarchy，便于后续从真实大模块入手：媒体 loader、UI asset loader、expansion integration、HDMI wrapper。只删除文件名或换 seed 无法证明减少器件利用率。当前保留全部功能，不擅自删除显示或改变硬门限。

## 未完成项及后续最小入口

- [ ] 最终源码重新 gate，达到 LUT <=16500、BRAM <=60。
- [ ] place/route 达到 slices <=90%，Setup/Hold WNS >=0、TNS=0、0 违例、0 overflow。
- [ ] 签核 bit、哈希、JTAG 和原功能板级冒烟。

R0-A 的本轮工具补洞完成；R0-B/R0-C 保持未放行。后续决定继续开发时，从当前分支和源码清单开始，先解决资源取舍，再重新运行完整门禁。不得复用本次中间 gate 或历史 place 宣称最终源码通过。

## 资产和中间产物哈希

- UIRES.BIN：`96fbd93b6586a4475dcb58c6e43c35342fc82edcb0cd79b8ab48be2ed38ef679`。
- card_UIRES.img：`322fecc8fec57066f66b4016cc41f1961c2b8ecd68d07d050268f8251edf3e38`。
- 中间 gate DB（未签核）：`6e056ba55e2a5b195ca150afff727f69de8b7d71781be479cbadabb41d1553cb`。
- 机器哈希清单：`sim/r0_closeout_target_20261008/artifact_hashes.json`。

本次交付不含新签核 bit，无烧录、串口或人工画面/音频通过声明。
