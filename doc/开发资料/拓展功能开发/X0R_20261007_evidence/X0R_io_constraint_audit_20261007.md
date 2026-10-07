# X0R IO 与约束审计

日期：2026-10-07

审计对象：

- 固定基线：`prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7`
- 顶层：`src/top_tf_hdmi_audio.v`
- 引脚约束：`constraints/pin.adc`
- 时序约束：`constraints/timing.sdc`
- TD 实测引脚表：`doc/开发资料/拓展功能开发/X0R_20261007_evidence/io_table.json`
- TD 最终约束与检查报告：固定基线中的 `final.constraints`
- 物理映射标定：`doc/开发资料/拓展功能开发/J2扩展板引脚按键映射标定.md`

## 1. 结论摘要

1. `io_table.json` 的 130 行全部是物理 pad，且物理位置 130 个唯一，无重复 LOCATION。
2. 130 个 pad 可以由顶层端口和硬核派生 pad 完整解释，不是同一信号被错误展开或约束重复：

   `71 个顶层逻辑端口 + 55 个 SDRAM 硬核派生 pad + 4 个 HDMI 差分负端 = 130`

3. 方向统计同样闭合：

   `INPUT 35 = 顶层输入 35`

   `OUTPUT 62 = 顶层输出 35 + SDRAM 输出 23 + HDMI 差分负端 4`

   `INOUT 33 = 顶层 HDMI_DDC_SDA 1 + SDRAM dq[31:0] 32`

4. `final.constraints` 的高优先级检查全部为 0 错误：no clock、clock definition、invalid constraint、combinational loops、soft FIFO exception、no path 均为 0。
5. 35 个 no input delay 和 36 个 no output delay 是既有约束策略，不是本轮引入；其中绝大多数是板内低速按键/拨码/编码器/红外/数码管/LED/UART，另有 SD SPI、HDMI DDC、HDMI TMDS 需要按板级接口单独解释。
6. 本轮不修改 `pin.adc` 或 `timing.sdc`。原因是：地址/IO 口径已闭合，新增 IO delay 需要板级走线延迟、负载和源同步时序数据；在没有这些实测参数前强行填入会制造虚假精度并可能改变既有 PPA。

## 2. 物理 pad 展开口径

### 2.1 顶层逻辑端口

顶层模块 `top` 共 71 个逻辑端口：

| 分类 | 端口数 | 方向 | 物理外设/用途 |
|---|---:|---|---|
| 系统时钟与复位 | 2 | 2 输入 | `clk`、`rst_n` |
| 母板按键 | 3 | 3 输入 | `key1`、`key2`、`key3` |
| 母板拨码 | 4 | 4 输入 | `sw1`~`sw4` |
| 数码管 | 14 | 14 输出 | `seg_sel[5:0]`、`seg_data[7:0]` |
| HDMI TMDS 正端 | 4 | 4 输出 | `HDMI_CLK_P`、`HDMI_D0_P`~`HDMI_D2_P` |
| HDMI DDC | 2 | 1 输出 + 1 双向 | `HDMI_DDC_SCL`、`HDMI_DDC_SDA` |
| SD SPI | 4 | 3 输出 + 1 输入 | `sd_ncs`、`sd_dclk`、`sd_mosi`、`sd_miso` |
| J2 KEY | 12 | 12 输入 | `exp_key_n[11:0]`，低有效 |
| J2 DIP | 6 | 6 输入 | `exp_dip_n[5:0]`，上拨为 1 |
| J2 EC1/EC2 | 6 | 6 输入 | `exp_enc1_a/b/sw_n`、`exp_enc2_a/b/sw_n` |
| J2 红外 | 1 | 1 输入 | `exp_ir_rx` |
| J2 LED | 4 | 4 输出 | `exp_led_n[3:0]`，低有效点亮 |
| J2 WS2812 | 1 | 1 输出 | `exp_ws2812_data` |
| J2 EXT | 6 | 6 输出 | `exp_ext_o[5:0]` |
| 母板蜂鸣器 | 1 | 1 输出 | `board_buzzer_n`，低电平鸣叫 |
| 板载串口 | 1 | 1 输出 | `uart_tx` |
| 合计 | 71 | 35 输入 / 35 输出 / 1 双向 | - |

### 2.2 硬核派生 pad

| 来源 | 数量 | 方向 | 说明 |
|---|---:|---|---|
| `U3/u2_ram` SDRAM 地址 | 11 | 输出 | `addr[10:0]` |
| SDRAM bank | 2 | 输出 | `ba[1:0]` |
| SDRAM 控制 | 5 | 输出 | `ras_n`、`cas_n`、`we_n`、`cs_n`、`cke` |
| SDRAM 数据掩码 | 4 | 输出 | `dm0`~`dm3` |
| SDRAM 数据 | 32 | 双向 | `dq[31:0]` |
| SDRAM 时钟 | 1 | 输出 | `clk`，LOCATION `S73`，与系统输入 `clk` 的 `R7` 不是同一 pad |
| SDRAM 小计 | 55 | 23 输出 / 32 双向 | 由硬核 IP 展开，不出现在顶层端口声明 |
| HDMI 差分负端 | 4 | 输出 | `HDMI_*_P(n)`，由 LVDS 输出对派生 |
| 合计 | 59 | - | - |

### 2.3 数量校验

| 项目 | 数量 |
|---|---:|
| 顶层逻辑端口 | 71 |
| SDRAM 派生 pad | 55 |
| HDMI 差分负端 | 4 |
| 物理 pad 总数 | 130 |

物理 pad 方向校验：

| 方向 | 计算 | 实测 |
|---|---|---:|
| INPUT | 顶层输入 35 | 35 |
| OUTPUT | 顶层输出 35 + SDRAM 输出 23 + HDMI 负端 4 | 62 |
| INOUT | 顶层 1 + SDRAM dq 32 | 33 |

结论：`130 = 35 + 62 + 33`，且 `71 + 55 + 4 = 130`，两项口径互相闭合。

## 3. IO 分类与板级用途

| 类别 | 顶层信号/派生 pad | 数量 | 逻辑极性/模式 | 约束状态 | 审计结论 |
|---|---|---:|---|---|---|
| 系统时钟 | `clk` R7；SDRAM `clk` S73 | 2 pad | 50 MHz 输入；SDRAM 输出时钟 | `clk` 有 `create_clock`；SDRAM 时钟由硬核/PLL 派生 | 两个 `clk` 名称相同但方向、LOCATION、用途不同；不是重复约束 |
| 复位 | `rst_n` A2 | 1 | 异步置位、同步释放 | `set_false_path -from [get_ports {rst_n}]` | 既有复位同步约定，保持不改 |
| 母板按键 | `key1` B2、`key2` C1、`key3` B1 | 3 | 上拉、低有效 | 无 input delay；内部消抖/同步 | 慢速人机输入，无 input delay 属于既有策略 |
| 母板拨码 | `sw1` C8、`sw2` C7、`sw3` C6、`sw4` C5 | 4 | 上拉、低有效 | 无 input delay；内部同步 | 慢速配置输入；SW1~SW4 的电平/极性需板级逐项确认 |
| 数码管 | `seg_sel[5:0]`、`seg_data[7:0]` | 14 | 推挽输出，8 mA | 无 output delay | 板内扫描显示，低风险；需确认位序、共阴/共阳和档位 |
| HDMI TMDS | 正端 4 + 负端 4 | 8 | LVDS33 | 正端有 `set_max_delay ... 8.000 -datapath_only`；无 output delay | 源同步高速输出；不使用普通 output delay 是既有策略，需以显示器实测为最终判据 |
| HDMI DDC | `HDMI_DDC_SCL` P2、`HDMI_DDC_SDA` R2 | 2 | I2C 开漏、上拉、8 mA | SCL 无 output delay；SDA 无 input delay | 低速 DDC；当前工程由 HDMI IP 驱动，需确认是否实际使用 EDID |
| SD SPI | `sd_ncs` A12、`sd_dclk` A14、`sd_mosi` A13、`sd_miso` B14 | 4 | SPI 模式，输出 8 mA | 无 input/output delay | SD 卡回读时序是残余风险点；既有多卡回归和板级拔插/播放必须覆盖 |
| J2 KEY | `exp_key_n[11:0]` | 12 | 上拉、低有效 | 无 input delay；`sync_bit` 两级同步 | KEY07/KEY11 已由用户确认 S7-03b 验收完成，本轮不重复验收 |
| J2 DIP | `exp_dip_n[5:0]` | 6 | DIP0 下拉、DIP1~5 上拉；上拨为 1 | 无 input delay；运行时同步/消抖 | DIP3/4/5/6 业务使能待 X1/X5；本轮只做物理极性记录 |
| J2 编码器 | `exp_enc1_*`、`exp_enc2_*` | 6 | 上拉、按键低有效 | 无 input delay；正交解码 | EC1 已用于现有功能；EC2 事件层待 X5 |
| J2 红外 | `exp_ir_rx` K6 | 1 | 上拉、NEC 输入 | 无 input delay；NEC 解码 | DIP5 总使能与 15 个 IR 向量属于后续 G-EXT |
| J2 LED | `exp_led_n[3:0]` | 4 | 低有效点亮、8 mA | 无 output delay | 逐个灯位/丝印必须人工确认；当前固件行为以现有代码为准 |
| J2 WS2812 | `exp_ws2812_data` J11 | 1 | 单线 NRZ、GRB、800 kHz | 无 output delay | X1B 才接入业务执行器；本轮只记录物理脚位 |
| J2 EXT | `exp_ext_o[5:0]` | 6 | 3.3 V、8 mA | 无 output delay | 当前固件未实现业务联动；需确认 EXT1 反馈音与其他 EXT 的实测状态 |
| 蜂鸣器 | `board_buzzer_n` H11 | 1 | PNP 驱动、低电平鸣叫 | 无 output delay | SW5 是硬件通断档，软件低电平才鸣叫；必须与 SW5 一起验收 |
| 串口 | `uart_tx` D12 | 1 | 115200 8N1 | 无 output delay | 遥测提交独立快照验证，不与零行为减负合并 |
| SDRAM | `addr/ba/ras/cas/we/cs/cke/dm/dq/clk` | 55 | 硬核 2M x 32 SDRAM | 专用 `ext_mem_clk` / `ext_mem_clk_sft`，有 false path | 地址、数据、时钟完整性依赖板级长时间运行与现有帧缓冲回归 |

## 4. `final.constraints` 逐项审计

### 4.1 检查项总表

| 检查项 | TD 计数 | 定性 | 处理结论 |
|---|---:|---|---|
| no clock | 0 | 通过 | 无需处理 |
| clock definition | 0 | 通过 | 无需处理 |
| dummy node | 3 | 需解释 | 见 4.2；不构成组合环，但保留为残余观察项 |
| invalid constraint | 0 | 通过 | 无需处理 |
| PLL/clock buffer clock constraints | 2 | 2 个 PLL 实例被检查，均无违例 | 见 4.3；不是 2 个错误 |
| combinational loops | 0 | 通过 | 无需处理 |
| soft FIFO timing exception | 0 | 通过 | 无需处理 |
| no path constraints | 0 | 通过 | 无需处理 |
| shadowed/ignored exceptions | 0 | 通过 | 无需处理 |
| no input delay | 35 | 既有空白 | 见第 5 节 |
| no output delay | 36 | 既有空白 | 见第 5 节 |
| partial input/output delay | 0/0 | 通过 | 没有“只约束一部分位”的情况 |
| abnormal input delay | 0 | 通过 | 无异常 input delay |

### 4.2 dummy node

TD 报告计数为 3，明细跨 `EG_PHY_LSLICE`、`EG_PHY_MSLICE`、`EG_PHY_PAD` 三类模型。PAD 类可见：

- `exp_ext_o[5:1]`
- `exp_ws2812_data`
- `seg_data[7]`
- `U3/sdram_syn_5.opad`
- `U3/sdram_syn_10.opad`

判断：

1. 这些是综合/物理模型内部的未连接端或闲置 opad，不是组合环。
2. `exp_ext_o`、`exp_ws2812_data`、`seg_data[7]` 都是实际顶层输出，不能因为 dummy-node 明细而判定为“未连接业务信号”。
3. 是否真的输出正确仍以板级 LED、WS、数码管和 EXT 实测为准。
4. 本轮不改 RTL；若后续 X1 修改 LED/WS/数码管，再顺带核对 opad 明细是否消失或变化。

残余风险：低到中，取决于板级输出验收；不影响本轮固定 bit 的时序通过结论。

### 4.3 PLL/clock buffer

TD 检查了两个 PLL 实例：

- `sys_pll_m0/pll_inst`
- `video_pll_m0/pll_inst`

两者均为：

- 0 个无时钟约束的时钟脚
- 0 个时钟频率与 PLL 设置不匹配

因此第 4.3 节是“2 个实例通过”，不是“2 个告警”。

但 native build 另有两条 `USR-6135 CRITICAL-WARNING`：

- `sys_pll_m0/pll_inst` 的反馈路径位于本地网络
- `video_pll_m0/pll_inst` 的反馈路径位于本地网络

解释：两个 PLL 都使用 `FEEDBK_PATH=CLKC0_EXT`，反馈补偿延迟被工具判定为不可完全预测。该现象来自既有 IP 配置，不在 X0R 业务 RTL 改动范围内。固定基线最终 Setup WNS `+114 ps`、Hold WNS `+3 ps`、TNS `0/0`、违例端点 `0/0`，但这不等于板级时钟质量自动合格。

残余风险：HDMI PHY、SDRAM 时钟树和 PLL 相位相关的板级行为必须在固定 bit 上验证；本轮不通过修改约束来掩盖。

### 4.4 SDRAM 地点与本地时钟

native build 包含：

- `PHY-7002` 两次：`U3/sdram` 的初始位置两次未被保持；初始位置在 ECO placement 开始时非法，工具自动移动。
- `PHY-5079`：1 条时钟网使用本地布线资源。
- `RUN-1001` 明细：`ext_mem_clk_sft` 的 fanout 为 0/1，sink 为 `U3/u2_ram/SDRAM_CLK`。

解释：

1. SDRAM 硬核的初始位置不是用户最终位置契约；工具移动后仍完成放置、布线、时序检查。
2. `ext_mem_clk_sft` 是 SDRAM 采样移位时钟，只进硬核；既有 `timing.sdc` 已用 false path 隔离 `ext_mem_clk` 与 `ext_mem_clk_sft`。
3. 本地布线是该硬核时钟的既有实现特征，不能简单等同于时钟树错误；但它确实使物理偏斜不可由普通 STA 完整表示。

残余风险：SDRAM 数据完整性必须通过既有四 bank、缩略图、MV、音频长时间运行来验证；若出现图像彩点/音频错位，应优先复现并回退固定 bit。

## 5. no input delay / no output delay 逐项

### 5.1 35 个 no input delay 分组

| 分组 | 数量 | 信号 | 归因 |
|---|---:|---|---|
| 复位/母板按键/拨码 | 8 | `rst_n`、`key1`、`key2`、`key3`、`sw1`~`sw4` | 异步/慢速输入；`rst_n` 已有 false path，按键/拨码内部同步或消抖 |
| J2 按键 | 12 | `exp_key_n[11:0]` | 异步板外输入，`sync_bit` 两级同步 |
| J2 DIP | 6 | `exp_dip_n[5:0]` | 运行时配置输入，两级同步/消抖 |
| J2 编码器 | 6 | `exp_enc1_a/b/sw_n`、`exp_enc2_a/b/sw_n` | 机械编码器/按键，正交解码加滤波 |
| J2 红外 | 1 | `exp_ir_rx` | NEC 异步帧，内部解码 |
| SD 数据回读 | 1 | `sd_miso` | SPI 源同步回读；缺量化板级延迟，列为主要残余风险 |
| HDMI DDC 数据 | 1 | `HDMI_DDC_SDA` | 低速 I2C 双向 |
| 合计 | 35 | - | - |

结论：没有“忘记约束”的高优先级错误；`sd_miso` 和 `HDMI_DDC_SDA` 是仅有的接口级时序风险，其余属于异步/慢速人机输入。当前阶段的正确做法是保留既有空白并做板级验收，而不是编造 input delay。

### 5.2 36 个 no output delay 分组

| 分组 | 数量 | 信号 | 归因 |
|---|---:|---|---|
| HDMI TMDS | 4 | `HDMI_CLK_P`、`HDMI_D0_P`~`HDMI_D2_P` | 源同步差分输出；已有 `set_max_delay 8 ns -datapath_only` |
| HDMI DDC | 2 | `HDMI_DDC_SCL`、`HDMI_DDC_SDA` | 低速 I2C |
| J2 LED | 4 | `exp_led_n[3:0]` | 指示输出，无时序闭合要求 |
| J2 WS2812 | 1 | `exp_ws2812_data` | 单线 800 kHz，输出延迟裕量由协议保证 |
| J2 EXT | 6 | `exp_ext_o[5:0]` | 低速扩展输出 |
| SD SPI | 3 | `sd_ncs`、`sd_dclk`、`sd_mosi` | 源同步 SPI 输出；缺量化板级延迟，列为残余风险 |
| 数码管 | 14 | `seg_sel[5:0]`、`seg_data[7:0]` | 板内扫描显示 |
| 蜂鸣器 | 1 | `board_buzzer_n` | 低速开关输出 |
| 串口 | 1 | `uart_tx` | 115200 8N1 |
| 合计 | 36 | - | - |

结论：低速控制输出不需要逐脚 output delay；HDMI TMDS 和 SD SPI 需要源同步/板级验证来覆盖。当前固定基线的时序数字只证明片内时序，不代表外部走线窗口已被量化。

## 6. 人工验收清单

### 6.1 必须由人确认的物理极性

- [ ] 母板 KEY3（B1）：按下时串口/日志状态变化与软件极性一致。
- [ ] 母板 SW1（C8）、SW2（C7）、SW3（C6）、SW4（C5）：逐位记录上拨/下拨对应 `0/1` 和逻辑语义。
- [ ] 母板 SW5：确认硬件通断档；只有在接通档时软件 `board_buzzer_n` 低电平才会鸣叫。
- [ ] 母板 SW6：确认数码管档位或供电/亮度档位，不影响 FPGA 逻辑电平判断。
- [ ] J2 LED1~LED4：逐个确认 `exp_led_n[0..3]` 对应灯位、低有效点亮和丝印编号。
- [ ] J2 WS2812：记录灯珠方向、GRB 顺序和数据线 J11；本轮不要求实现 X1B 业务。
- [ ] J2 EXT1~EXT6：确认 EXT1 反馈音波形与其余 EXT 的当前输出状态。
- [ ] J2 KEY3/KEY7/KEY11：用户已确认 S7-03b 验收完成，本轮不重复验收；仅在整体冒烟时记录“用户已确认”状态。

### 6.2 固定基线最小冒烟

- [ ] 使用固定 bit `VinylFPGA_optimized.bit`，SHA256 必须等于 `23fd3bb166f7627ad9fd43759081ca6202644380400208658eee661bb542cac6`。
- [ ] 上电后 HDMI 首图/开机 Logo 正常，无黑屏、花屏、撕裂。
- [ ] 播放一张已知 WAV，确认音频连续、无爆音、无死锁。
- [ ] 插入/拔出 SD 卡，确认媒体恢复进入和退出，串口出现 `STAT/ERR` 变化。
- [ ] 数码管扫描正常，无错位、重影或亮度异常。
- [ ] UART 115200 8N1 可接收固定版本 banner/状态；遥测提交另行独立验证。
- [ ] 记录失败项的复现条件、时间和回退固定 bit 的操作。

### 6.3 接口级残余风险观察项

- [ ] `sd_miso`：多次换卡、长文件播放、拔插重连，记录是否出现扇区错误重试或媒体恢复。
- [ ] SD SPI 输出：若条件允许，用示波器检查 `sd_dclk`/`sd_mosi` 在卡端的数据窗口。
- [ ] HDMI DDC：确认目标显示器是否需要 EDID；若不使用 DDC，明确记录为未使用接口。
- [ ] HDMI TMDS：多显示器或至少两种显示设备验证首图和连续播放。
- [ ] SDRAM：执行缩略图、MV、音频并发和至少 1 小时稳定播放，观察彩点/错位/欠载。

## 7. 结论

IO 审计通过“数量口径、方向口径、物理位置唯一性和外设分类”检查。当前没有证据支持修改 `pin.adc` 或 `timing.sdc`；35/36 个 delay 空白应在板级接口数据齐备后再决定是否量化。X0R 的下一步是把告警审计、遥测独立快照和最小冒烟结果补齐，而不是在 IO 约束上做无证据的装饰性改动。
