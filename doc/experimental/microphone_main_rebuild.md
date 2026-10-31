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
- 固定 5.0× 增益（`top_tf_hdmi_audio.v` 中 `mic_gain_setting = 8'd160`），OSD/参数接入留作后续可选项。

## 3. 落地改动

| 文件 | 说明 |
|---|---|
| `src/audio/mic_adc_capture.v` | video_clk 二分频出 12.5 MHz ADC 时钟，144 kS/s 采样，EOC 锁存 12 位码值 |
| `src/audio/mic_signal_condition.v` | Q4 定标、一阶 IIR 去直流、3 点平均降到 48 kHz、164 µs 超时静音、16 位饱和 |
| `src/audio/mic_pcm_mixer.v` | 增益斜坡（每 64 样本 ±8，1/32 单位）、18 位域饱和混音、全局静音联动、反压直通 |
| `src/top_tf_hdmi_audio.v` | 三个 include、`exp_ext_o` 收窄到 2 位、新增 mic 端口与 `exp_ext_internal`、三段例化、`hdmi_pcm_source_bridge` 改接混音输出 |
| `constraints/pin.adc` | EXT4/P14=mic_gnd_exp4（0）、EXT5/P12=mic_vcc_exp5（1）、EXT6/R12=mic_do_exp6（输入）；删除 exp_ext_o[2..5] |
| `constraints/timing.sdc` | 条件式 ADC 生成时钟（优先 `u_mic_adc/adc_clk_reg.q`，回退 `u_mic_adc/u_adc.clk`），`mic_adc_clk` 并入视频时钟组 |
| `prj/VinylFPGA.al` | CompileOrder 58/59/60 追加三个源文件 |
| `sim/tb_mic_adc_capture.v`、`sim/microphone/*` | 4 个自检 TB |
| `sim/integration/vendor_control_stubs.v` | 新增 `EG_PHY_ADC` 协议占位模型，供两个 top 级 TB 编译 |

## 4. 验证结果

### 4.1 数字仿真（iverilog，全部 PASS）

```
PASS ADC capture: 287 conversions, cadence and reset
PASS mic conditioning: decimation, DC rejection, polarity, reset
PASS mixer ramp gain-law saturation mute backpressure (17 steps)
PASS digital ADC to mixer path: frames=195 changed=190 muted=4
```

`python -X utf8 tools/verify_finish_rtl.py --output <dir>`：10/10 PASS（含 top 级 `tb_closure_top_handoff`、`tb_audio_reserve_priority_top`）。

### 4.2 综合与布局布线（TD 6.2.168，closeout 流程）

| 轮次 | 种子 | Setup WNS | Hold WNS | 违例端点 | 结果 |
|---|---|---|---|---|---|
| 第 1 轮 | 10 | -0.382 ns（sd_card_clk 域 6 端点） | +0.030 ns | 6 | 失败（新增逻辑后布局拥挤所致） |
| 第 2 轮 | 13/14/15 | **+0.104 ns** | **+0.012 ns** | **0** | **通过，best_result = seed 13** |

- 失败路径与麦克风无关：`u_background_cache_loader/source_enabled_reg` → `u_media_write_pipeline/pixel_data_reg[20]`，10 ns 预算里 7.24 ns 是走线，属 93%→95% 占用下的布局随机性；换种子即可恢复。
- 最终时序报告中存在 `mic_adc_clk 12.5 MHz` 时钟条目，布局日志无 USR-6001/USR-8108/USR-8130/USR-8159，说明条件式生成时钟按预期建立。
- video_clk 域 Setup WNS +7.1 ns，麦克风链路本身余量充足。

### 4.3 资源对比

| 指标 | 基线 fe383ab | 本次（seed 13） | 增量 |
|---|---|---|---|
| LUT（place / route） | 17,859 (91.12%) / 18,243 (93.08%) | 18,253 (93.13%) / 18,650 (95.15%) | +394 / +407 |
| REG | ~12,217 | 12,357 | +140 |
| BRAM | 63 / 64 | 63 / 64 | 0 |
| DSP | 10 | 11（混音乘法） | +1 |
| ADC | 1 | 1 | 0 |

### 4.4 交付物

- 固件：`prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`（684,332 B，sha256 `59c59c473fd40e7888776eb0bcfccff5f00d9cac7b6a0e85c46a34be07121623`）。
- 工程：`prj/VinylFPGA.al`（MultiSeed 13/14/15，选中 13；策略 map_mode=area_prior、pack_effort=high、opt_timing=high、effort=routability）。

## 5. 上板前必须确认（安全）

详见 [microphone_bringup.md](microphone_bringup.md)。摘要：

1. 麦克风模块 AO 输出经 47 Ω 串入 EXT3/N12（ADC_CH5），ADC 输入范围 0.1–0.9×VREF，模块 AO 直流偏置需在范围内；
2. EXT5/P12 供 3.3 V、EXT4/P14 接地，模块标称 3.3–5 V，切勿把 5 V 灌到 P14；
3. 先只接母板确认原有功能（视频、SD、HDMI、按键）无回归，再插扩展板与麦克风；
4. KEY4 全局静音可同时静音音乐与麦克风；启动画面期间麦克风自动淡入（约 20 ms 斜坡）。

## 6. 后续可选项（本次未做）

- 增益跟随 VOL：把 `mic_gain_setting` 接到既有音量值（需在 OSD/参数层新增一个 8 位映射，属额外改动，会再动 OSD 资源）。
- 降噪档位：当前为 3 点平均 + 一阶高通的最简版；如实测噪声偏大，可加 2 阶低通或噪声门，代价约 +50–80 LUT。
