# X0R 基线补证、IO 审计和零行为减负最终报告

日期：2026-10-07

工程根：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`

报告状态：**收尾版，资源准入未通过，X1 暂缓**

## 1. 执行摘要

X0R 已完成基线身份、IO 约束、资源时序、告警和仿真回归的证据整理。固定基线可以生成 bit、下载到 `EG4S20BG256` 并完成 SRAM 下载校验，但最小冒烟中的板级功能验收尚未执行。

最终判定：

1. **综合、布局布线、时序检查和固定基线 bitgen 有效。**
2. **固定基线 bit 具备可生成、可下载证据，但不等于 HDMI/音频/SD/SDRAM 板级功能全部通过。**
3. **X0R 资源门禁未通过。** 目标为 `Slices <= 8232`（84%），固定基线为 `8412`（85.84%），R1 为 `8433`，R2 为 `8463`。
4. **R1/R2 未发布，也未生成新 bit。** 当前唯一固定交付 bit 仍是 `S7_03b_key07_key11_20261006_s7` 基线归档。
5. **X1 因资源准入阻塞。** 在没有新的资源下降方案和完整回归前，不进入 X1 业务扩展。
6. S6 和 S7-03b 已由用户确认验收完成；本报告不重复验收，也不把 KEY07/KEY11 重新列入测试矩阵。

## 2. 固定基线身份

| 项目 | 值 |
|---|---|
| 快照 | `prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7` |
| 顶层 | `top` |
| 器件 | `EG4S20BG256` |
| 工具 | TD `6.2.168116` |
| bit 归档 | `doc/开发资料/拓展功能开发/X0R_20261007_evidence/baseline_archive/VinylFPGA_optimized.bit` |
| bit 大小 | 641264 字节 |
| bit SHA256 | `23fd3bb166f7627ad9fd43759081ca6202644380400208658eee661bb542cac6` |
| bitgen 证据 | `baseline_archive/release_bitgen.log`，`VERIFIED_BITGEN_COMPLETE` |
| 下载证据 | `baseline_archive/release_download.log`，`VERIFIED_SRAM_DOWNLOAD_COMPLETE` |
| 下载器件 | `PRG-2014 : Chip validation success: EG4S20BG256` |

下载日志中曾出现一条 `Error @ mpsse.cpp:90 : device not found`，随后同一流程完成器件校验和 SRAM 下载，并以 `VERIFIED_SRAM_DOWNLOAD_COMPLETE` 结束。该条应按 JTAG 初始枚举的瞬时错误记录，而不是隐藏；它不改变最终下载成功结论，也不能被扩展解释为板级功能通过。

固定 bit 与归档清单：

```powershell
cd D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA
Get-FileHash -Algorithm SHA256 `
  .\doc\开发资料\拓展功能开发\X0R_20261007_evidence\baseline_archive\VinylFPGA_optimized.bit
```

期望值：

```text
23FD3BB166F7627AD9FD43759081CA6202644380400208658EEE661BB542CAC6
```

## 3. 资源利用率

| 版本 | LUT | FF | BRAM9K | DSP | Slices | Slices 占比 | 资源门禁 |
|---|---:|---:|---:|---:|---:|---:|---|
| 固定基线 S7-03b | 15733 | 9699 | 40 | 15 | 8412 | 85.84% | 未通过 |
| X0R R1 缩略图实验 | 15677 | 9687 | 40 | 15 | 8433 | 86.05% | 未通过 |
| X0R R2 启动字段实验 | 15724 | 9687 | 40 | 15 | 8463 | 86.36% | 未通过 |

资源结论：

- X0R 资源门禁为 `Slices <= 8232`，即不超过 84%。
- 固定基线已超出 84% 门禁，R1/R2 也没有下降穿越门禁。
- R1 比固定基线少 56 LUT、少 12 FF，但 Slices 反而增加 21；R2 比固定基线少 9 LUT、少 12 FF，但 Slices 增加 51。
- 该现象说明当前实验没有实际缓解布局密度，不能用 LUT/FF 的局部下降宣称资源治理成功。
- 固定基线其他资源为：LUT 80.27%、FF 49.48%、BRAM9K 62.50%、DSP 51.72%。

发布策略：

- R1/R2 仅保留为失败实验证据，不发布。
- 不为 R1/R2 生成 bit。
- 不把 R1/R2 资源数字混入固定基线发布结论。

## 4. 时序收敛

| 版本 | Setup WNS | Setup TNS | Hold WNS | Hold TNS | Setup 违例端点 | Hold 违例端点 |
|---|---:|---:|---:|---:|---:|---:|
| 固定基线 | +114 ps | 0 | +3 ps | 0 | 0 | 0 |
| R1 | +123 ps | 0 | +4 ps | 0 | 0 | 0 |
| R2 | +147 ps | 0 | +3 ps | 0 | 0 | 0 |

固定基线片内时序结论：

- Setup 和 Hold 均为非负，TNS 为 0，违例端点为 0。
- 固定基线各时钟 Fmax：`sd_card_clk` 101.153 MHz、`video_clk` 34.257 MHz、`clk` 59.751 MHz、`ext_mem_clk` 135.999 MHz、`hdmi_5x_clk` 256.345 MHz。
- 片内 STA 通过不等于外部接口时序已量化。`sd_miso`、SD SPI 输出、HDMI TMDS、HDMI DDC 和 SDRAM 板级时钟质量仍需人工验收。

## 5. IO 与约束审计

审计报告：

- `X0R_20261007_evidence/X0R_io_constraint_audit_20261007.md`

关键结论：

1. 130 个物理 pad 全部由 `71` 个顶层逻辑端口、`55` 个 SDRAM 硬核派生 pad 和 `4` 个 HDMI 差分负端解释。
2. 方向闭合为 `INPUT 35 + OUTPUT 62 + INOUT 33 = 130`，物理位置 130 个唯一。
3. `final.constraints` 中 `no clock`、`invalid constraint`、组合环、`no path`、软 FIFO 例外和 shadowed exception 均为 0。
4. `dummy node = 3`，属于工具内部未连接端或闲置 pad，不构成组合环。
5. PLL 检查项 2 表示两个 PLL 实例通过，不是两条错误。
6. `no input delay = 35`、`no output delay = 36` 是既有约束策略。没有板级走线延迟、源同步窗口和负载数据前，不补造 IO delay。
7. 本轮未修改 `pin.adc` 和 `timing.sdc`。

需保留的接口级风险：

- `sd_miso`：SPI 回读缺少量化输入延迟。
- `sd_dclk/sd_mosi`：SPI 输出缺少量化输出延迟。
- HDMI TMDS：已有 `set_max_delay 8 ns -datapath_only`，但仍需显示器实测。
- HDMI DDC：低风险 I2C，但需确认目标显示器是否使用 EDID。
- SDRAM：地址、数据和时钟完整性依赖长时间板级运行。

## 6. 告警审计

详细报告：

- `X0R_20261007_evidence/X0R_warning_audit_20261007.md`

固定基线 `native_build.log` 统计：

- 可计 `WARNING`：67 条。
- 其中 `CRITICAL-WARNING`：5 条。
- 另有 3 条同类告警折叠提示 `Similar messages will be suppressed`。
- `compile_manifest.json` 中错误/致命行：0。

高关注项：

1. `HDL-5007` 中 `24 -> 21` 的 SDRAM 地址/长度位宽差异是真实契约风险，当前缺少显式地址范围断言；本轮保留，需后续治理。
2. `PHY-7002`：SDRAM 初始位置被工具移动，工具合法化后仍完成全流程。
3. `PHY-5079`：1 条时钟网使用本地路由。
4. `USR-6135`：两个 PLL 的反馈路径补偿延迟不可完全预测，来自既有 IP 配置。
5. `HDL-5369`：缩略图布局有锁存推断，但最终 RTL 报告 `#LATCH = 0`，属于低风险清理项。
6. SD 写路径未连接对应当前只读业务，不构成本轮主链路阻断。

## 7. 仿真与回归验证

本轮已完成的验证：

| 验证 | 结果 | 说明 |
|---|---|---|
| `python tools/verify_resource_opt.py` | PASS | 资源优化回归全部通过 |
| `python tools/test_vinyl_packer.py` | 22/22 PASS | 媒体打包与边界回归 |
| `python tools/verify_s0_s5_fixes.py` | PASS | S0-S5 修复回归 |
| S7 定向 HIL/仿真 | PASS | health monitor、echo telemetry、WAV underrun、SD 超时、媒体监督、恢复清理、WAV 重启 |
| 四 bank / SD / SDRAM arbiter | PASS | 四 bank 调度、扇区适配器、SDRAM 读写仲裁 |
| 缩略图链路 | PASS | 布局、控制器、视图读取、FIFO 突发和空弹保护 |

验证边界：

- 以上是仿真/回归证据，不是板级验收。
- `tb_echo_telemetry` 与 `tb_health_monitor` 仍使用手工旧版本号 `32'h0701_0001`，当前 `expansion_integration.v` 的 `FW_VERSION = 32'h0703_0002`。这只能证明格式和状态转移，不能证明真实构建版本号已绑定到仿真夹具。
- 更厚的 UART 遥测字段尚未实现，详见第 8 节。

## 8. 未完成与残余风险

以下项目必须在新一轮功能开发前明确，不应在收尾报告中写成已完成：

1. **板级最小冒烟未执行。** 未对归档 bit 完成 HDMI 首图、WAV 连续播放、SD 插拔恢复、物理极性和 SDRAM 长时间运行的人工验收。
2. **遥测缺口未实现。** 当前 `health_monitor` 只有 `underrun`、`buffer_low`、`video_fail`、`ev_overflow`、`err_code`；`exp_echo_reporter` 的 STAT 只有 `UR`、`BL`、`VF`、`OV`、`ERR`、`VER`。缺少 SD 超时/重试、最大扇区等待、最低 FIFO 水位、MV missed-deadline 和最近错误等字段。
3. **`UR=0005` 未定性。** 尚不能判定为启动瞬态、切换/重缓冲停顿还是稳定播放中的真实欠载；不得自行豁免。
4. **版本绑定不完整。** 顶层集成版本为 `32'h0703_0002`，但相关旧测试台仍为 `32'h0701_0001`。
5. **资源门禁失败。** X0R 未能把 Slices 降到 84% 以下，R1/R2 实验均未发布。
6. **SDRAM 地址截断未治理。** 24 位地址/长度到 21 位形式端口的高 3 位缺少显式范围证明。
7. **外部接口时序未量化。** SD SPI、HDMI TMDS/DDC 和 SDRAM 需要板级或示波器证据。
8. **X0R 多 seed 放行条件未完成。** 执行方案要求至少 seed 7 和一个替代 seed 达到 Setup/Hold 非负、TNS=0、违例端点=0。固定基线是历史通过快照，不能替代 X0R 的候选减负版本多 seed 复验；R1/R2 已在资源门禁处停止，未进入发布级多 seed 放行。

## 9. 改动范围与理由

本轮业务 RTL 无 diff：

```text
git diff --name-only -- src constraints
```

结果为空。`pin.adc`、`timing.sdc` 未修改。

本轮唯一代码型改动是测试契约文件 `tools/verify_resource_opt.py`，修改理由：

1. 旧逐拍参考台复位后 `sd_lba` 为 `X`，不能作为当前时序优化实现的金标准。
2. 当前实现比旧参考多一拍 `WS_DONE` 调度。
3. S7-02 后 SD 错误进入故障静默，旧参考要求排空到 EOF，与新行为冲突。

新测试仍严格检查样本顺序、计数、排空、停止态不得发 `sd_req` 以及非控制流的请求到 LBA 握手；控制流用例改为验证故障静默和恢复。

## 10. 发布与准入结论

| 项目 | 结论 |
|---|---|
| 固定基线综合 | 通过 |
| 固定基线布局布线 | 通过 |
| 固定基线片内时序 | 通过，Setup/Hold 均非负，TNS 0 |
| 固定基线 bitgen | 通过，已生成 bit |
| 固定基线 SRAM 下载 | 通过，`EG4S20BG256` |
| X0R 资源门禁 | **未通过** |
| R1/R2 发布 | **不发布** |
| X1 准入 | **阻塞，等待资源治理和板级验收** |
| 板级功能验收 | **未执行** |

最终交付物：

- 固定基线 bit：`X0R_20261007_evidence/baseline_archive/VinylFPGA_optimized.bit`
- IO 与约束审计：`X0R_io_constraint_audit_20261007.md`
- 告警审计：`X0R_warning_audit_20261007.md`
- 资源对比：`round_compare_R1_R2.md`
- 本报告：`X0R_board_and_build_baseline_20261007.md`

## 11. 人工验收清单

本节是对固定基线 bit 的 X0R 发布前冒烟，不是重新打开 S6 或 S7-03b 验收。用户已确认 S6 和 S7-03b 验收完成；KEY07/KEY11 不重复测试，只在记录中保留“用户已确认”状态。

### 11.1 交付身份

- [ ] 校验固定 bit SHA256 等于 `23fd3bb166f7627ad9fd43759081ca6202644380400208658eee661bb542cac6`。
- [ ] 只在固定 bit 上执行本清单，不使用未发布的 R1/R2。
- [ ] 记录下载工具版本、板卡器件和下载结果。

### 11.2 最小板级冒烟

- [ ] 上电后 HDMI 首图/开机 Logo 正常，无黑屏、花屏、撕裂。
- [ ] 播放一张已知 WAV，确认音频连续、无爆音、无死锁。
- [ ] 插入/拔出 SD 卡，确认媒体恢复进入和退出，UART 出现 `STAT/ERR` 变化。
- [ ] 数码管扫描正常，无错位、重影或亮度异常。
- [ ] UART 115200 8N1 可接收版本 banner 和状态输出。
- [ ] 失败时记录复现条件、时间和回退固定 bit 的操作。

### 11.3 接口级观察

- [ ] `sd_miso`：多次换卡、长文件播放、拔插重连，记录扇区错误、超时和媒体恢复。
- [ ] SD SPI 输出：条件允许时用示波器检查 `sd_dclk/sd_mosi` 卡端数据窗口。
- [ ] HDMI TMDS：至少两种显示设备验证首图和连续播放。
- [ ] HDMI DDC：确认目标显示器是否使用 EDID；不使用则明确记录未使用。
- [ ] SDRAM：执行缩略图、MV、音频并发和至少 1 小时稳定播放，观察彩点、错位、欠载。

### 11.4 物理极性

- [ ] 母板 SW1~SW4：逐位记录上拨/下拨对应 `0/1` 和逻辑语义。
- [ ] 母板 SW5：确认硬件通断档以及软件低电平驱动蜂鸣器的条件。
- [ ] 母板 SW6：确认数码管档位或供电/亮度档位。
- [ ] J2 LED1~LED4：逐个确认灯位、低有效极性和丝印编号。
- [ ] J2 WS2812：记录灯珠方向、GRB 顺序和数据线 J11；本轮不要求接入 X1B 业务。
- [ ] J2 EXT1~EXT6：确认 EXT1 反馈音波形和其余 EXT 当前输出状态。
- [ ] 母板 KEY1~KEY3：记录按键极性和稳定消抖结果。
- [ ] J2 KEY3/KEY7/KEY11：用户已确认 S7-03b 验收完成，本轮只记录“用户已确认”，不重复测试。

## 12. 最终结论

X0R 的证据链已经闭合到“固定基线可综合、可布局布线、片内时序通过、可生成 bit、可下载”。但资源门禁没有通过，R1/R2 实验也没有形成可发布收益，因此 X0R 不能作为资源优化通过版本发布，也不能据此放行 X1。

在没有完成板级人工验收前，本报告只声明构建与下载证据；不声明 HDMI、音频、SD、SDRAM 或物理外设功能板上全部通过。
