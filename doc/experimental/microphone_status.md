# 片内 ADC 麦克风实验版状态

## 当前结论（2026-10-30 17:00，codex/microphone 工作树）

- 数字功能与物理实现均已完成：4 个仿真测试台通过；3 种子 closeout 构建通过，best_result = seed 13，Setup WNS +0.104 ns、Hold WNS +0.012 ns，Setup/Hold 违例端点均为 0。
- 可烧录固件：`prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`，684,332 字节，SHA-256 `1E2C48FE8FCA7042A6CC2F3A361C86D95A48F23D8DF24C681DC28AC931512F7A`。
- 本版相对上一版（3BF76CE7…）只改数字增益：默认麦克风增益由 0.25×（4×）提高到 5.0×（约 +26 dB），音乐通路不变。
- 尚未上板实测：GPIO 模拟供电安全性、实际引脚映射、ADC 输入电压范围、人声音质、抗啸叫与长期稳定性。烧录前必须阅读 [microphone_bringup.md](microphone_bringup.md) 的安全前提。

## 约束修复（本次构建通过的直接原因）

286982c 曾把生成时钟目标从 `u_mic_adc/u_adc.clk` 改到 `u_mic_adc/adc_clk_reg.q`，综合阶段无时钟告警消失，但布局阶段该寄存器被改名，`create_generated_clock` 找不到目标（USR-6001/USR-8108），随后 `set_clock_groups -asynchronous` 整条失败（USR-8130/USR-8159），video_clk 与 clk 跨域被按同步分析，产生约 −1.5 ns 的伪 hold 违例。

`constraints/timing.sdc` 现采用条件目标：优先取 `u_mic_adc/adc_clk_reg.q`，取不到时回退 `u_mic_adc/u_adc.clk`；视频时钟组改为变量 `mic_video_group`，仅当生成时钟建立成功时才把 `mic_adc_clk` 并入。两个目标描述同一分频网，因此任何阶段都只建立一个时钟；时钟缺失时也不会拖垮整条 `set_clock_groups`。修复后布局日志无 USR-6001/USR-8108/USR-8130/USR-8159。

## 实现概要

- `src/audio/mic_adc_capture.v:10-56`：`video_clk` 25 MHz 二分频得到 12.5 MHz ADC 时钟，`sample_phase` 每 ADC 周期加 144，回绕阈值 12500，约 144 kS/s；`sample_valid` 仅在 `adc_eoc` 时有效；硬核实例 `EG_PHY_ADC #(.CH5("ENABLE"), .VREF("ENABLE")) u_adc(.clk(adc_clk), .pd(!rst_n), .s(3'd5), .soc(adc_soc), .eoc(adc_eoc), .dout(adc_data))`。
- `src/audio/mic_signal_condition.v:10-21`：去直流（一阶 IIR）、三点平均降采样到 48 kHz、12 位超时约 164 µs 后静音。
- `src/audio/mic_pcm_mixer.v`：增益寄存器 `mic_gain` 0..255，每 64 个样本步进 ±`MIC_GAIN_STEP`（=8），`mic_scaled = mic_sample * mic_gain >>> 5`，即 0…7.97×，16 位饱和后再与音乐在 18 位域饱和相加，静音键同时清零两路。上限由端口 `mic_gain_max` 决定，默认 160（5.0×）。
- 顶层 `src/top_tf_hdmi_audio.v:710-716` 实例化三段（另加 `mic_gain_follow`），`mic_enable = !boot_active`，启动画面结束后约 20 ms 自动淡入；`mic_gain_setting` 由用户音量映射而来（VOL=200 → 160 = 5.0×）；`hdmi_pcm_source_bridge` 改接混音结果。
- 引脚：`constraints/pin.adc` 中 EXT3/N12 → ADC_CH5，EXT4/P14 → `mic_gnd_exp4`，EXT5/P12 → `mic_vcc_exp5`，EXT6/R12 → `mic_do_exp6`（未使用输入）。

## 验证记录

| 项目 | 结果 |
|---|---|
| `sim/microphone/tb_mic_pcm_mixer.v` | PASS：bypass、ramp、saturation、mute、backpressure |
| `sim/microphone/tb_mic_signal_condition.v` | PASS：decimation、DC rejection、polarity、reset |
| `sim/tb_mic_adc_capture.v` | PASS：287 conversions，采样间隔与复位 |
| `sim/microphone/tb_mic_pipeline.v` | PASS：frames=195 changed=190 muted=4 |
| `tools/verify_finish_rtl.py` | 10/10 PASS，含 top 级 `tb_closure_top_handoff`、`tb_audio_reserve_priority_top` |
| closeout 构建（种子 13/14/15） | 通过，best_result = seed 13，SWNS +0.104 ns / HWNS +0.012 ns，0 违例端点 |

`tools/verify_submission.py` 与 `tools/run_current_regression.py` 固定核验旧发布版本的源码与工程哈希，不适用于本实验工作树；原功能回归以上表的 `verify_finish_rtl.py` 与各 `verify_*.py` 为准。

## 音量调参

- 增益律：混音器内 `mic_gain` 满量程 255 对应 7.97×，斜坡步进 8 对应 0.25×；实际增益值由 `src/audio/mic_gain_follow.v` 按用户音量生成：`gain_q5 = round(VOL×4/5)`，VOL=200→160（5.0×）、VOL=100→80（2.5×）、VOL=0→0（静音），VOL>200 封顶 5.0×。
- 上限 5.0×（VOL=200；较原 0.25× 提升约 +26 dB）。硬核 ADC 有效精度约 8 位，理论噪声底约 −48 dBFS，放大 5× 后约 −34 dBFS，仍低于音乐典型电平，因此不会明显抬高底噪；若实测觉得过响或啸叫，把主音量降到 128（≈2.5×）复测。
- 已改为跟随既有用户音量，无需新增 OSD 菜单项；若以后要独立麦克风档位，再扩 OSD（本次未做）。

## 已知限制与风险

- 三点平均的阻带抑制较弱，不等于完整抗混叠滤波；官方硬核 ADC 有效精度约 8 位，人声质量只能实测确认。
- 麦克风无独立硬件开关（按键与 DIP 位已全部占用），靠启动后自动淡入与 KEY4 全局静音控制。
- PCM 波形/灯效应仍反映音乐而非混音；没有音乐有效帧时麦克风无法独立向 HDMI 提供帧，暂停路径是否持续输出零样本帧需实测。
- GPIO 模拟供电、EXT4–EXT6 引脚映射、47 Ω 串联压降、AO 偏置与 ADC 输入范围均未实测，详见 [microphone_bringup.md](microphone_bringup.md)。
- 主分支 `main` 与已验收 bit 未修改；本实验产物只存在于 `codex/microphone` 工作树。

## main 分支重建（2026-10-31）

本文档记录的是 `codex/microphone` 工作树。main 已于 `fe383ab` 基线上重放同一实现：4 个 TB 与 `verify_finish_rtl.py` 10/10 通过，closeout 构建 seed 13 通过（SWNS +0.104 ns / HWNS +0.012 ns，0 违例端点），新固件哈希与资源对比见 [microphone_main_rebuild.md](microphone_main_rebuild.md)。

## 增益跟随 VOL（2026-10-31，main 第三轮）

- 备份：标签 `mic-fixed5x-seed13-59c59c47`、分支 `backup/mic-fixed5x-20261031` 均指向 `1a93881`（固定 5× 版）。
- 新增 `src/audio/mic_gain_follow.v`（纯组合，移位+加法，无乘法器/ROM）；顶层 `src/top_tf_hdmi_audio.v:710-716` 例化，混音器 `.mic_gain_max` 接其输出；`prj/VinylFPGA.al` CompileOrder 61。
- 映射：增益 = round(VOL×4/5)，VOL>200 封顶 5.0×，VOL=0 静音；混音器每 64 个已接受样本 ±8 斜坡（约 27 ms），音量跳变无咔哒。
- 新增 `sim/microphone/tb_mic_gain_follow.v`（关键点/全量程/单调/封顶）；5 个麦克风 TB 全 PASS，集成回归 `verify_finish_rtl.py` 10/10 PASS。
- 构建：3 种子 13/14/15，seed 13（-0.247 ns）与 seed 14（-2.876 ns）失败，seed 15 通过（SWNS +0.060 / HWNS +0.021）；固件 sha256 `12888BE7…`，684,332 B。
- 资源：LUT 18,688（95.35%）、REG 12,363、BRAM 63/64、DSP 11、ADC 1；route slices 9,604（98.00%）。
- 风险：`sd_card_clk` 域在 95% 占用下对种子敏感（同一 seed 13 上轮通过、本轮 -0.247 ns），本轮仅 seed 15 兜住。
- 详见 [microphone_main_rebuild.md](microphone_main_rebuild.md)。
- 2026-10-31 冻结为 `mic-followvol-v1.0`（标签 `mic-followvol-v1.0-seed15`，提交 `cb251d7`），冻结包 `output/VinylFPGA_MicFollowVol_Firmware/`，规范固件 sha256 `12888BE7…`；不再做降噪增强。

