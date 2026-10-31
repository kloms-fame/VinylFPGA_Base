# main 分支重建记录：片内 ADC 麦克风（2026-10-31）

## 1. 背景与基线

- 重置目标：`fe383abf1d78519986bff60b7fc495737d60971d`（main 上的已验证 release）。
- 重置前 main 为 `2c4657d`（含 mic/OSD v3 试验，出现无法播放视频、麦克风一说话断开、HDMI 重连等故障）。
- 备份：分支 `backup/pre-reset-main-2c4657d`（提交 `b39d908`，含当时 TB 残留）与标签 `backup/pre-reset-20261031`。
- 重置方式：`git branch -f main fe383ab` 后 `git switch main`，工作区干净。
- 基线综合（同日实测锚点）：Setup WNS +0.105 ns、Hold WNS +0.024 ns，bit 684,332 B，sha256 `3926ef95…`，LUT 17,859（place）/ 18,243（route），BRAM 63/64，DSP 10。

## 2. 设计来源与取舍

直接重放已验证的 `codex/microphone` 分支实现（`724cd44` 计划 → `1030da8` 三模块 → `aa96472` 顶层与约束 → `fd44bde` 时钟保留 → `286982c`/`c6de6c7` 生成时钟修复 → `b838d31` 固定 5×稳定版），而不是重新设计 v3/v4：

- 三模块合计仅 33 + 114 + 60 门，综合增量约 +400 LUT，比 v3（fde3af1）小一个量级。
- 不含参数、OSD 页、Flash 记录格式改动，不影响既有 5 个 OSD 页与参数存储。
- 增益跟随 VOL（第三轮追加）：`src/audio/mic_gain_follow.v` 把用户音量映射为增益 `gain_q5 = round(VOL×4/5)`，VOL=200→160（5.0×）、VOL=100→80（2.5×）、VOL=0→0（静音）、VOL>200 封顶 5.0×；只用移位与加法，无乘法器/ROM，不新增参数或 OSD 页。

## 3. 落地改动

| 文件 | 说明 |
|---|---|
| `src/audio/mic_adc_capture.v` | video_clk 二分频出 12.5 MHz ADC 时钟，144 kS/s 采样，EOC 锁存 12 位码值 |
| `src/audio/mic_signal_condition.v` | Q4 定标、一阶 IIR 去直流、3 点平均降到 48 kHz、164 µs 超时静音、16 位饱和 |
| `src/audio/mic_pcm_mixer.v` | 增益斜坡（每 64 样本 ±8，1/32 单位）、18 位域饱和混音、全局静音联动、反压直通 |
| `src/audio/mic_gain_follow.v` | 用户音量 → 麦克风增益（=round(VOL×4/5)，封顶 5.0×，VOL=0 静音），纯组合移位/加法 |
| `src/top_tf_hdmi_audio.v` | 三个 include、`exp_ext_o` 收窄到 2 位、新增 mic 端口与 `exp_ext_internal`、三段例化、`hdmi_pcm_source_bridge` 改接混音输出、例化 `mic_gain_follow` 并把 `mic_gain_setting` 由常量改为其输出 |
| `constraints/pin.adc` | EXT4/P14=mic_gnd_exp4（0）、EXT5/P12=mic_vcc_exp5（1）、EXT6/R12=mic_do_exp6（输入）；删除 exp_ext_o[2..5] |
| `constraints/timing.sdc` | 条件式 ADC 生成时钟（优先 `u_mic_adc/adc_clk_reg.q`，回退 `u_mic_adc/u_adc.clk`），`mic_adc_clk` 并入视频时钟组 |
| `prj/VinylFPGA.al` | CompileOrder 58/59/60/61 追加四个源文件 |
| `sim/tb_mic_adc_capture.v`、`sim/microphone/*` | 5 个自检 TB（含 `tb_mic_gain_follow.v`） |
| `sim/integration/vendor_control_stubs.v` | 新增 `EG_PHY_ADC` 协议占位模型，供两个 top 级 TB 编译 |

## 4. 验证结果

### 4.1 数字仿真（iverilog，全部 PASS）

```
PASS ADC capture: 287 conversions, cadence and reset
PASS mic conditioning: decimation, DC rejection, polarity, reset
PASS mixer ramp gain-law saturation mute backpressure (17 steps)
PASS digital ADC to mixer path: frames=195 changed=190 muted=4
PASS mic gain follow: linear 0..5x, 0 mutes, clamped, monotonic
```

`python -X utf8 tools/verify_finish_rtl.py --output <dir>`：10/10 PASS（含 top 级 `tb_closure_top_handoff`、`tb_audio_reserve_priority_top`）。

### 4.2 综合与布局布线（TD 6.2.168，closeout 流程）

| 轮次 | 种子 | Setup WNS | Hold WNS | 违例端点 | 结果 |
|---|---|---|---|---|---|
| 第 1 轮 | 10 | -0.382 ns（sd_card_clk 域 6 端点） | +0.030 ns | 6 | 失败（新增逻辑后布局拥挤所致） |
| 第 2 轮 | 13/14/15 | **+0.104 ns** | **+0.012 ns** | **0** | **通过，best_result = seed 13** |
| 第 3 轮（增益跟随 VOL） | 13/14/15 | **+0.060 ns** | **+0.021 ns** | **0** | **通过，best_result = seed 15**（seed 13 -0.247 ns、seed 14 -2.876 ns 淘汰） |

- 失败路径与麦克风无关：`u_background_cache_loader/source_enabled_reg` → `u_media_write_pipeline/pixel_data_reg[20]`，10 ns 预算里 7.24 ns 是走线，属 93%→95% 占用下的布局随机性；换种子即可恢复。
- 第 3 轮再次验证随机性：同一 seed 13 上轮 +0.104 ns，本轮 -0.247 ns；seed 14 更差（-2.876 ns、238 端点，`sd_card_clk` 域 Min Period 12.876 ns）。`sd_card_clk` 是唯一脆弱域，95% 占用下每加一小块逻辑都可能损失 1 个可用种子。
- 最终时序报告中存在 `mic_adc_clk 12.5 MHz` 时钟条目，布局日志无 USR-6001/USR-8108/USR-8130/USR-8159，说明条件式生成时钟按预期建立。
- video_clk 域 Setup WNS +7.1 ns，麦克风链路本身余量充足。

### 4.3 资源对比

| 指标 | 基线 fe383ab | 本次（seed 15） | 增量 |
|---|---|---|---|
| LUT（最终布局布线） | 18,243 (93.08%) | 18,688 (95.35%) | +445 |
| REG | ~12,217 | 12,363 | +146 |
| slices（route） | — | 9,604 (98.00%) | — |
| BRAM | 63 / 64 | 63 / 64 | 0 |
| DSP | 10 | 11（混音乘法） | +1 |
| ADC | 1 | 1 | 0 |

### 4.4 交付物

- 固件：`prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`（684,332 B，sha256 `12888be734514bce75fbf16651caca2c2e680833a75909ad35f90cc582c4b2f8`）。
- 工程：`prj/VinylFPGA.al`（MultiSeed 13/14/15，选中 15；策略 map_mode=area_prior、pack_effort=high、opt_timing=high、effort=routability）。

## 5. 上板前必须确认（安全）

详见 [microphone_bringup.md](microphone_bringup.md)。摘要：

1. 麦克风模块 AO 输出经 47 Ω 串入 EXT3/N12（ADC_CH5），ADC 输入范围 0.1–0.9×VREF，模块 AO 直流偏置需在范围内；
2. EXT5/P12 供 3.3 V、EXT4/P14 接地，模块标称 3.3–5 V，切勿把 5 V 灌到 P14；
3. 先只接母板确认原有功能（视频、SD、HDMI、按键）无回归，再插扩展板与麦克风；
4. KEY4 全局静音可同时静音音乐与麦克风；启动画面期间麦克风自动淡入（约 20 ms 斜坡）。

## 6. 后续可选项（本次未做）

- ~~增益跟随 VOL~~：已在本轮实现（`mic_gain_follow.v`，按 `play_volume_video` 映射），OSD 未新增任何菜单项。
- 降噪档位：当前为 3 点平均 + 一阶高通的最简版；如实测噪声偏大，可加 2 阶低通或噪声门，代价约 +50–80 LUT。

## 7. 版本冻结（2026-10-31）

- 冻结版本 `mic-followvol-v1.0`：git 提交 `cb251d7`，标签 `mic-followvol-v1.0-seed15`。
- 决策：按用户要求停止继续优化，**不再做降噪增强，不再改动 RTL/约束**。原因：3 个种子里仅 seed 15 通过（seed 13 −0.247 ns、seed 14 −2.876 ns），`sd_card_clk` 域在 95% 占用下对布局随机性极敏感，任何新增逻辑都可能让时序无法收敛。
- 冻结包：`output/VinylFPGA_MicFollowVol_Firmware/`（`VinylFPGA.bit`、`manifest.json`、`README.txt`、`route.qor`、`VinylFPGA_phy.area`、`VinylFPGA_phy.ts`、`VinylFPGA_inst.bid`）；`manifest.json` 含规范固件 sha256 与全部产物哈希。
- 规范固件 sha256 `12888be7…`（684,332 B，seed 15，SWNS +0.060 / HWNS +0.021，0 违例端点）；根目录副本 `稳定固件_麦克风跟随VOL_seed15_12888BE7.bit`。
- 重跑等价性：2026-10-31 15:13 TD GUI 重跑同一工程得到 `8f22b6f3…`，与规范固件逐字节比较仅 3 字节不同，全部位于 bitgen ASCII 时间戳头（`13:46`→`15:13`），配置数据完全一致；`verify_gui_runs.py` 对重跑结果复核通过（SWNS +0.060 / HWNS +0.021，seed 15）。**两份 bit 可互换烧录。**
- 回滚固件：`output/VinylFPGA_Contest_Firmware/VinylFPGA.bit`（sha256 `97b37026…`，主线 fe383ab 冻结版）。
- 上板待验：仅剩 C3-8（音量 200→100→200 时麦克风增益随动，VOL=0 静音，无咔哒）；A/B/C 其余步骤按 [microphone_bringup.md](microphone_bringup.md)。
- 将来若必须再改：从 `mic-followvol-v1.0-seed15` 拉分支，先跑 `verify_finish_rtl.py` 全量回归，并预留 4–6 个种子重跑时序；不要直接在 main 上增量叠加。

