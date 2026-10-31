# 麦克风输入与 OSD MIC 页（v3）

本文件记录 `feature/mic-osd-v3` 上新增的「扩展板麦克风 + OSD 音量页 + 降噪」实现，
以及可复现的综合/布线配方与实测资源、时序数字。基线为 `fe383ab`
（`release: 整理当前比赛工程、精选回归及可复建提交材料`）。

## 1. 功能一览

| 项目 | 行为 |
| --- | --- |
| OSD 页 | 在原有 5 页（VOL/BRI/CON/ROT/WSL）之后新增第 6 页 `MIC`，标题显示 `M I C` |
| 档位 | `0X / 4X / 5X / 6X / 7X` 五档循环；0X 为麦克风关闭，4X..7X 对应 Q8 增益 1024/1280/1536/1792 |
| 默认值 | 上电默认 `5X`（`mic_level = 3'd5`），与 `DEFAULT_PARAMS` 一致 |
| 掉电保存 | MIC 档位并入原参数记录（版本 03），随音量/亮度/对比度/旋转/壁纸一起自动保存与恢复 |
| 降噪 | 直流跟踪高通 + 两级一阶低通（12 dB/oct）+ 软噪声门（瞬时起振、慢释放、线性过渡） |
| 混音 | 麦克风与音乐 PCM 在 `hdmi_pcm_source_bridge` 之前饱和相加，静音/开机流程仍走原 `mic_output_mute` |

## 2. 硬件连接（扩展板）

| 扩展板脚 | FPGA 引脚 | 方向 | 用途 |
| --- | --- | --- | --- |
| EXT3 | N12 | ADC 输入 | 麦克风模块 `AO`（模拟输出 → `ADC_CH5`，`EG_PHY_ADC` 专用脚，不能当普通 IO） |
| EXT4 | P14 | 输出 0 | 麦克风模块 `G`（地） |
| EXT5 | P12 | 输出 1 | 麦克风模块 `+`（3.3 V，DRIVESTRENGTH 8 mA） |
| EXT6 | R12 | 输入 | 麦克风模块 `DO`（本方案不使用，保持高阻输入） |

模块按 `AO / G / + / DO` 顺序直插 `EXT3..EXT6`，与上表一一对应。
`constraints/pin.adc` 里原 `exp_ext_o[2..5]`（N12/P14/P12/R12）已改为
`mic_gnd_exp4` / `mic_vcc_exp5` / `mic_do_exp6`，`exp_ext_o` 收窄为 2 位，
其余扩展口输出不受影响。

注意：EXT5 的 3.3 V 由 FPGA 引脚提供，只适合模块标称的几毫安级电流；
若模块实测电流较大或上电有明显跌落，应改接扩展板的 `+3V3` 并用导线共地，
不要长期超出手册的引脚电流限值。

## 3. RTL 结构

新增两个模块，均在 `video_clk`（25 MHz）域内，没有新增跨时钟路径：

### `src/audio/mic_adc_capture.v`

- `EG_PHY_ADC #(.CH5("ENABLE"), .VREF("ENABLE"))`，通道号 `s = 3'd5`，`pd = !rst_n`。
- ADC 硬核时钟 = `video_clk` 二分频（12.5 MHz），用 `(* keep = "true" *)` 保住该寄存器，
  便于 `timing.sdc` 用 `get_pins u_mic_adc/adc_clk_reg.q` 建生成时钟。
- 采样率：14 bit 相位累加器，每次 `adc_clk` 下降沿加 192，模 12500
  → 每样本 65.1 个 12.5 MHz 周期 → **192 kS/s**。
- `soc` 在 `adc_clk` 高电平期间建立，保证跨过下一个 ADC 上升沿时稳定；
  `eoc` 经两级同步后取上升沿，把 `dout` 采到 `sample_code` 并给出 `sample_valid`。
- `conversion_active` 配 8 bit 超时（4096 个 25 MHz 周期）兜底，ADC 无响应不会卡死。

### `src/audio/mic_signal_condition.v`

处理顺序（全部按 192 kHz 样本推进，输出 48 kHz）：

1. **偏置转补码**：`centered = {~code[11], code[10:0]}`，左移 4 位补小数位。
2. **直流跟踪高通**：`dc += (target - dc) >>> 8`，拐点 ≈ 192k/(2π·256) ≈ **120 Hz**，
   抵消 ADC 偏置与麦克风模块的直流。
3. **两级一阶低通**：`lpf += (in - lpf) >>> 2`，α = 1/4。
   单级 −3 dB ≈ 8.8 kHz，两级级联 −3 dB ≈ **5.7 kHz**，滚降 12 dB/oct。
   实测 20 kHz 相对 200 Hz 抑制约 −23.6 dB（仿真 T6）。
4. **4:1 抽取**：累加 4 个样本后 `>>> 2` 平均，得到 48 kHz 的 `s16`（Q4 满刻度）。
5. **软噪声门**：包络取 `|s16| >> 4`（0..2048），瞬时起振；
   释放 `env -= (env >> 10) + 1`（时间常数约 21 ms，`+1` 防止 12 bit 包络衰减停滞）。
   门限 `GATE_SHUT_ENV = 24`（≈1.2% FS）以下全关，`GATE_OPEN_ENV = 72`（≈3.5% FS）以上全开，
   中间线性过渡。
6. **Q8 增益**：`gain_target = {1'b0, mic_level, 8'h00}`，即档位 × 256；
   每 48 kHz 样本最多变化 8（`GAIN_RAMP_STEP`），0→5X（1280）约 3.3 ms，7X→0X 约 4.7 ms，避免切档爆音。
7. **乘法与饱和**：`gain_eff = (gain_q8 * gate_factor)[18:8]`，
   `mic = (s16 * gain_eff) >>> 8`，超 16 bit 时饱和到 32767/−32768。

0X 档 `gain_target = 0`，配合斜坡自然淡出到静音，不产生咔哒声。

### 顶层混音（`src/top_tf_hdmi_audio.v`）

- `mic_adc_capture u_mic_adc` 与 `mic_signal_condition u_mic_condition` 挂在 `video_clk/video_rst_n`。
- `mic_hold` 在 `mic_valid` 时锁存样本，`mic_output_mute`（`board_audio_mute_v2 || boot_active`）
  有效时清零，实现与原有静音/开机流程一致的软静音。
- 在 `audio_source_mux`（音乐/WAV/提示音混合结果）之后、`hdmi_pcm_source_bridge` 之前：
  `{1'b0, mix_left} + mic_hold` 用 17 bit 有符号相加后饱和，左右独立。
  麦克风只作用于本地 HDMI 音频输出，不改变音量/淡入淡出链路。

## 4. 参数与持久化链路

参数位宽由 20 bit 扩到 **23 bit**：`{MIC[22:20], WSL[19:17], ROT[16:14], CON[13:11], BRI[10:8], VOL[7:0]}`

- `src/io/ui_param_csr.v`：新增 `mic_level[2:0]` 输出、`DEFAULT_MIC_LEVEL = 3'd5`。
  MIC 步进循环 `0 → 4 → 5 → 6 → 7 → 0`（上行）与 `0 → 7 → 6 → 5 → 4 → 0`（下行）；
  恢复校验只接受 `0` 或 `4..7`，非法值回落默认 5X。
- `src/io/ui_param_persistence.v`：`DEFAULT_PARAMS = {3'd5, 3'd4, 3'd2, 3'd2, 3'd3, 8'd200}`，
  `AUTO_SAVE_MS = 5000`，参数变化 5 s 后自动写 Flash；上电优先恢复用户值。
- `src/io/w25q64_param_store.v`：记录格式
  `56 50 03 flags 00 seq VOL BRI CON ROT WSL MIC crcHi crcLo A5 5A`，
  CRC16/CCITT-FALSE（`16'h1021`）覆盖前 12 字节。版本号从 02 升到 03，
  旧版记录会被判非法并回落到默认值（等价于恢复出厂）。
- `src/io/ec2_param_controller.v`：顶层以 `PARAM_COUNT(6)` 例化，第 6 页即 MIC，
  隐藏超时 `HIDE_TIMEOUT_MS = 1800` 不变。

## 5. OSD 显示

`src/display/ec2_param_osd.v` 新增 `PARAM_MIC = 3'd5`：

- 标题区 `M I C`；数值区 `ratio_text` 输出 `0X/4X/5X/6X/7X` 两字符 + 对齐空格。
- 进度条 `level_bar_len`：0X/4X/5X/6X/7X 对应 0/56/112/168/224，与其它页共用 224 像素上限。
- 面板位置、字体、边框与现有 5 页完全一致（`PLAYBACK_EC2_OSD_X0..Y1`）。

## 6. 实测资源与时序

综合（`optimize_gate` 后，`map_mode=area_prior`、`pack_effort=high`）：

| 版本 | LUT | Reg | BRAM | DSP | ADC |
| --- | --- | --- | --- | --- | --- |
| 基线 `fe383ab` | 17859 / 19600（91.12%） | 12217 | 63 / 64 | 10 | 1 |
| v2（`e1933d4`，旧 mic 实现） | 18712（95.47%） | 12441 | 63 / 64 | 11 | 1 |
| **v3（本次）** | **17570（89.64%）** | **12218** | **55 / 64** | **10** | **1** |

布线：

| 指标 | 基线 `phy_b` | 探索性 `phy3_s18` | **官方收尾 `phy_1/seed_18`** |
| --- | --- | --- | --- |
| mslice | 4681 / 4900 | 4690 / 4900 | **4690 / 4900（95.71%）** |
| Setup WNS / FEP | +0.154 ns / 0 | +0.218 ns / 0 | **+0.218 ns / 0** |
| Hold WNS / FEP | −0.012 ns / 2 | −0.011 ns / 1 | **+0.030 ns / 0** |
| bitgen | OK | OK（684332 B） | **OK（684332 B）** |

说明：探索性 headless 配方把 `route fix_hold off` 传给了 TD，所以 hold 只到 −11 ps / 1 端点；
官方收尾流程（`tools/build_closeout.ps1` → `tools/run_closeout_project.tcl` → MultiSeed）会在流内执行
`fix_hold`，hold 收敛到 +30 ps / 0 端点，日志打印 `CLOSEOUT_BUILD_TIMING_PASSED`，
`tools/verify_gui_runs.py` 退出码 0。基线 `phy_b` 的小负 hold slack 位于 HDMI TX 内部既有时钟到时钟路径
（`u_hdmi_1_4b_transmitter_core_wrapper/u_hdmi_tx_controll`），本版由 fix_hold 一并收敛。

综合后 LUT 比基线少 289、BRAM 少 8，新功能没有侵占余量。最终固件为
`prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`（684,332 B，SHA-256
`a220d57ba6a4ec0b56e8d9ea1a5798ff329112a922ee90669d6f98d4398f1464`）；
`prj/VinylFPGA.al` 的 MultiSeed 已从 seed 10 改为 seed 18，与实测最优结果一致。

## 7. 复现综合 / 布线（TD 6.2.1 命令行）

```tcl
# syn_v3/flow_syn.tcl
cd {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA_Runs/syn_v3}
source ./settings.cfg
source D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl
flush stdout
exit
```

综合 `settings.cfg` 关键项：`run_type syn`、`start_step read_design`、`end_step opt_gate`、
`area_option -packarea`、`synWildParams { gate map_mode area_prior gate opt_area high gate pack_effort high }`，
并把 `VinylFPGA.al` 另存为运行目录的 `VinylFPGA.prj`（`Path` 改为 `../../../src/...`）。

布线 `settings.cfg` 关键项：`run_type phy`、`start_step opt_place`、`end_step bitgen`、
`set parent ../syn_v3`、`congestion 100`、`filter off`、`drHoldFix on`，
`phyWildParams` 含 `gate` 三条 + `place seed 18` 等十余条策略（见 `prj/VinylFPGA.al` 里的 Gate/Place 策略）。
上述手工流程用于快速探索面积/时序；**交付固件请用仓库自带的 `tools/build_closeout.ps1`**（TD GUI 引擎、
原生 MultiSeed、流内 `fix_hold`），再以 `tools/verify_gui_runs.py` 复核。

## 8. 仿真自检

见 `sim/mic_osd_v3/README.md`，两个测试台均带自检断言：

- `tb_mic_signal_condition.v`：0X 静音、5X ≈5.0×、门限压制、7X 饱和、20 kHz 抑制 >20 dB、4:1 抽取。
- `tb_ui_mic_params.v`：6 页轮转、MIC 档位循环与回绕、音量默认 200。
