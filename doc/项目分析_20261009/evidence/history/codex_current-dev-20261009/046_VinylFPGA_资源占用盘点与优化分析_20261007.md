# VinylFPGA 资源占用盘点与优化分析

> 日期：2026-10-07（北京时间）
> 工程：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`
> 顶层：`top`，器件：EG4S20BG256，工具：Tang Dynasty v6.2.168116
> 结论基线：工作区源码 `HEAD=66da60f` 与构建目录 `X2_r15s5_20261007` 的 112 个输入文件 SHA256 全部一致
> 文档性质：本文只做资源盘点、冗余识别和优化分析，未修改 RTL、未重新综合、未烧录

---

## 0. 结论摘要

### 0.1 当前真实资源基线

| 指标 | 占用量 / 容量 | 占用率 | 余量 | 判断 |
|---|---:|---:|---:|---|
| Slice | **9288 / 9800** | **94.78%** | 512 | 第一瓶颈，已越过 90% 风险线 |
| LUT | 17415 / 19600 | 88.85% | 2185 | 紧张，但不等于可布通余量 |
| FF/REG | 10527 / 19600 | 53.71% | 9073 | 不是瓶颈 |
| BRAM9K | 40 / 64 | 62.50% | 24 | 有余量，可承接少量 LUT 转 BRAM |
| BRAM32K | 0 / 16 | 0.00% | 16 | 未使用 |
| DSP | 17 / 29 | 58.62% | 12 | 不是瓶颈 |
| IO | 71 / 188 | 37.77% | 117 | 不是瓶颈 |
| PLL | 2 / 4 | 50.00% | 2 | 不是瓶颈 |
| GCLK | 2 / 16 | 12.50% | 14 | 不是瓶颈 |

判断依据：`prj/resource_opt_verified_20261005/X2_r15s5_20261007/final.area` 与同目录 `final.qor`。

### 0.2 最重要的三条结论

1. **当前设计的主要矛盾是 Slice，不是 LUT、FF、BRAM 或 DSP。**
   Slice 已达到 94.78%，只剩 512 个 Slice。此时单个模块节省几百 LUT，仍可能因为布局、布线、时钟树和 IP 占用而无法等价转化为大量 Slice 余量。

2. **两大逻辑消耗源是 SD/FAT32 子系统和 J2 扩展子系统。**
   `sd_card_bmp_m0` 累计约 3997 LUT，`u_expansion_integration` 累计约 3268 LUT，两者合计 7265 LUT，占顶层层次 LUT 14944 的约 48.6%。其中 `fat32_media_loader_m0` 单模块累计约 3491 LUT，是最大单一逻辑体。

3. **时序目前名义通过，但 Hold 很脆。**
   最终报告为 Setup WNS `+48 ps`、Hold WNS `+24 ps`、TNS 均为 0。但布线后第一次 Hold 修复时结果为 Hold WNS `-12 ps`、TNS `-18 ps`、3 个违例端点，且日志明确记录：
   `Slice utilization ... higher than 90%, hold fixing is skipped.`
   后续 TD 在 Stage 6 通过 Hold Fix By Pin 才把 Hold 拉回 `+24 ps`。因此当前结果不能视为稳健时序余量。

### 0.3 文档口径纠正

`VinylFPGA_src_全量模块详解_20261007.md` §13、`拓展功能开发/*` 等文档中的 `8412/9800 = 85.84%`、`Setup +114 ps`、`Hold +3 ps` 来自旧构建 `S7_03b_key07_key11_20261006_s7`（seed7），不是当前 HEAD 的最新资源结果。

当前结果应按以下趋势理解：

| 节点 | Slice | 占用率 | Setup WNS | Hold WNS | BRAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| `p05_s5` | 4527 | 46.19% | +53 ps | +3 ps | 30 | 10 |
| `S7_03b_key07_key11_20261006_s7` | 8412 | 85.84% | +114 ps | +3 ps | 40 | 15 |
| `X0R_R1_thumb_20261007` | 8433 | 86.05% | +123 ps | +4 ps | 40 | 15 |
| `X1_r2_20261007` | 8733 | 89.11% | +140 ps | +3 ps | 40 | 15 |
| `X2_r12_20261007` | 9216 | 94.04% | -156 ps | -20 ps | 40 | 17 |
| **`X2_r15s5_20261007`** | **9288** | **94.78%** | **+48 ps** | **+24 ps** | **40** | **17** |

---

## 1. 判断依据与证据链

### 1.1 源码与构建一致性

| 项目 | 结果 |
|---|---|
| 当前 Git HEAD | `66da60f` |
| 顶层源码 | `src/top_tf_hdmi_audio.v` |
| 器件 | EG4S20BG256 |
| 工具版本 | Tang Dynasty v6.2.168116 |
| 构建目录 | `prj/resource_opt_verified_20261005/X2_r15s5_20261007` |
| 输入哈希清单 | `inputs.sha256.json`，112 项 |
| SHA256 逐项复核 | 112/112 匹配，0 缺失，0 不一致 |

因此，本文的资源和时序数字可以对应到当前工作区源码，不受旧提交、旧 XML 工程表或旧报告口径影响。

### 1.2 权威报告

| 证据 | 路径 | 用途 |
|---|---|---|
| 最终资源利用率 | `X2_r15s5_20261007/final.area` | LUT、FF、BRAM、DSP、IO、PLL、GCLK、IO 明细 |
| 最终 QoR | `X2_r15s5_20261007/final.qor` | Slice、最终 Setup/Hold、RAM/DSP |
| 最终时序 | `X2_r15s5_20261007/final.timing` | 各时钟域 WNS/TNS、端点、路径 |
| 布线阶段时序 | `X2_r15s5_20261007/final_timing.rpt` | Hold 修复前状态 |
| 综合层次面积 | `X2_r15s5_20261007/gate.area` | 逐实例 LUT、ripple、FF、BRAM、DSP 分解 |
| 构建日志 | `X2_r15s5_20261007/td_20261007_154313.log` | Hold 修复跳过、阶段迭代、最终结果 |
| 输入哈希 | `X2_r15s5_20261007/inputs.sha256.json` | 源码与构建一致性 |
| 工程文件表 | `prj/VinylFPGA.al` | AutoExcluded、源文件列表、约束列表 |
| 时序约束 | `constraints/timing.sdc` | 主时钟、派生时钟、异步组、IO delay 现状 |

### 1.3 口径说明

- `final.area` 的顶层总计是实现后的资源结果，用于判断全局占用率。
- `gate.area` 的层次表是综合后的累计值。父实例 LUT 包含子实例 LUT，不能再把父子相加。
- `final.area` 的时钟域 LUT/BRAM/DSP 是 TD 的域归属统计。部分硬 IP、跨域 FIFO 和共享资源会被重复归属，因此该表各域数字不应简单相加当作总资源。

---

## 2. 资源占用分析

### 2.1 全局资源与占用率

| 资源 | 占用 | 容量 | 占用率 | 可用余量 |
|---|---:|---:|---:|---:|
| Slice | 9288 | 9800 | 94.78% | 512 |
| LUT | 17415 | 19600 | 88.85% | 2185 |
| FF/REG | 10527 | 19600 | 53.71% | 9073 |
| LE | 17982 | - | - | - |
| LUT only | 7455 | 17982 | 41.46% | - |
| REG only | 567 | 17982 | 3.15% | - |
| LUT & REG | 9960 | 17982 | 55.39% | - |
| BRAM9K | 40 | 64 | 62.50% | 24 |
| FIFO9K | 0 | - | - | - |
| BRAM32K | 0 | 16 | 0.00% | 16 |
| DSP | 17 | 29 | 58.62% | 12 |
| PAD | 75 | 188 | 39.89% | 113 |

结论：

- Slice 比 LUT 更早接近上限，说明当前设计的限制更多来自布局、布线、控制逻辑、局部拥塞和寄存器打包，而不是单纯的算术 LUT 数量。
- FF 只用了 53.71%，意味着寄存器本身不是面积瓶颈。
- BRAM 和 DSP 都有余量，适合做“牺牲少量 BRAM/DSP，换取 Slice/LUT 下降”的定向优化。
- 当前余量不足以安全承载新的完整功能层，尤其不适合继续增加 100 MHz 的 `sd_card_clk` 逻辑。

### 2.2 IO、PLL、GCLK

| 类型 | 数量 | 说明 |
|---|---:|---|
| IO | 71 / 188 | 输入 35、输出 35、双向 1 |
| PAD | 75 / 188 | 含带寄存器 IO |
| IREG | 32 | 输入寄存 |
| OREG | 25 | 输出寄存 |
| TREG | 1 | 双向寄存 |
| PLL | 2 / 4 | `sys_pll_m0`、`video_pll_m0` |
| GCLK | 2 / 16 | 全局时钟资源未构成瓶颈 |

IO 和时钟资源充裕。当前问题不是“引脚不够”或“PLL 不够”，而是 fabric 中的 Slice 已接近饱和。

### 2.3 时钟域分布

来源：`final.timing` 的 Clock Summary 与 `final.area` 的 Report Clock Domain Luts。

| 时钟域 | 约束频率 | 逻辑 LUT | DRAM LUT | BRAM | DSP | 端点 | 备注 |
|---|---:|---:|---:|---:|---:|---:|---|
| `sd_card_clk` | 100 MHz | 3764 | 0 | 10 | 0 | 9649 | 最紧、逻辑最大、端点最多 |
| `video_clk` | 25 MHz | 1894 | 28 | 38 | 16 | 4961 | 视频和 HDMI 数据通路 |
| `clk` | 50 MHz | 1707 | 36 | 0 | 0 | 3552 | 扩展输入、遥测、反馈 |
| `ext_mem_clk` | 125 MHz | 317 | 0 | 6 | 1 | 1307 | SDRAM/帧缓存 |
| `hdmi_5x_clk` | 125 MHz | 16 | 0 | 0 | 0 | 49 | HDMI 串行域 |
| `ext_mem_clk_sft` | 125 MHz | - | - | - | - | 1 | SDRAM 相移采样时钟 |

关键判断：

- `sd_card_clk` 是资源、端点和时序压力的共同热点。它跑在 100 MHz，预算只有 10 ns，同时拥有 9649 个端点。
- 当前 Setup 全局最差路径位于 `sd_card_bmp_m0/fat32_media_loader_m0`，与 `pixel_byte_cnt` 和 `pixel_count` 相关。
- 对 `sd_card_clk` 域的 LUT 削减，边际收益通常高于对 25 MHz `video_clk` 域做同等规模的削减。

### 2.4 顶层主要模块资源排序

以下为 `gate.area` 的累计 LUT，父实例包含子实例；按 LUT 降序排列。

| 排名 | 实例 | 模块 | 累计 LUT | 累计 FF | BRAM | DSP | 主要功能 |
|---:|---|---|---:|---:|---:|---:|---|
| 1 | `sd_card_bmp_m0` | `sd_card_bmp` | 3997 | 3367 | 0 | 0 | SD/FAT32/BMP、索引、扫描、文件流 |
| 2 | `u_expansion_integration` | `expansion_integration` | 3268 | 1768 | 0 | 0 | J2 输入、事件、遥测、蜂鸣、LED 总线 |
| 3 | `u_hdmi_1_4b_transmitter_core_wrapper` | HDMI 加密核 | 1248 | 1503 | 16 | 0 | HDMI TX、EDID、TMDS 数据岛 |
| 4 | `u_video_rgb_to_axis_640x480` | RGB 转 AXI-Stream | 650 | 106 | 0 | 0 | 24-bit 像素打包与帧同步 |
| 5 | `u_lrc_osd` | `lrc_osd` | 624 | 91 | 0 | 0 | 单行歌词 OSD |
| 6 | `u_s6_video_layer` | `s6_video_layer` | 545 | 337 | 0 | 4 | Black Vinyl 视频层与 MV 合成 |
| 7 | `frame_read_write_m0` | `frame_read_write` | 459 | 387 | 4 | 0 | SDRAM 帧缓冲读写 |
| 8 | `u_wav_stream_player` | `wav_stream_player` | 458 | 326 | 8 | 0 | WAV 流缓存与 PCM 输出 |
| 9 | `u_seek_controller` | `seek_controller` | 297 | 225 | 0 | 0 | Seek/重播目标计算 |
| 10 | `u_thumbnail_view_reader` | `thumbnail_view_reader` | 270 | 232 | 2 | 1 | 2×2 缩略图取像 |
| 11 | `u_param_menu_controller` | `param_menu_controller` | 269 | 168 | 0 | 0 | 亮度/对比度菜单 |
| 12 | `u_board_key_sw_monitor` | `key_dip_monitor` | 260 | 188 | 0 | 0 | 母板 KEY/SW 消抖 |
| 13 | `u_ui_event_bridge` | `ui_event_bridge` | 236 | 85 | 0 | 0 | UI 事件跨域 |
| 14 | `u_buzzer_feedback` | `buzzer_feedback` | 205 | 95 | 0 | 0 | 蜂鸣反馈音 |
| 15 | `u_media_supervisor` | `media_supervisor` | 155 | 80 | 0 | 0 | 媒体故障恢复 |

顶层 `gate.area` 的总层次 LUT 为 14944。前 3 项合计 8513 LUT，约占 57.0%；前 8 项合计 12263 LUT，约占 82.1%。

### 2.5 最大模块的第二层展开

#### `sd_card_bmp_m0`：约 3997 LUT / 3367 FF

| 子实例 | 模块 | 累计 LUT | 累计 FF | 说明 |
|---|---|---:|---:|---|
| `fat32_media_loader_m0` | `fat32_media_loader` | 3491 | 3060 | 最大逻辑体 |
| `u_volume_scanner` | `fat32_volume_scanner` | 792 | 1079 | FAT32 卷扫描 |
| `u_song_index_db` | `song_index_db` | 715 | 919 | INDEX.BIN 流式解析 |
| `u_file_streamer` | `fat32_file_streamer` | 550 | 278 | FAT 链文件流 |
| `u_sd_sector_adapter` | `sd_sector_adapter` | 161 | 69 | 扇区适配 |
| `sd_card_top_m0` | `sd_card_top` | 248 | 180 | SD 协议栈 |
| `u_key_auto` | `key_press_debounce` | 36 | 24 | 内部按键消抖 |

#### `u_expansion_integration`：约 3268 LUT / 1768 FF

| 子实例 | 模块 | 累计 LUT | 累计 FF | 说明 |
|---|---|---:|---:|---|
| `u_expansion_io_hub` | `expansion_io_hub` | 1229 | 693 | J2 输入汇聚、编码器、IR、按键 |
| `u_exp_echo_reporter` | `exp_echo_reporter` | 943 | 359 | UART 文本遥测 |
| `u_key_dip_monitor` | `key_dip_monitor` | 731 | 416 | 18 路 J2 按键/DIP 消抖 |
| `u_board_key_sw_monitor` | `key_dip_monitor` | 260 | 188 | 母板 KEY/SW 消抖 |
| `u_buzzer_feedback` | `buzzer_feedback` | 205 | 95 | 蜂鸣反馈 |
| `u_ui_event_bus` | `ui_event_bus` | 170 | 79 | 统一事件总线 |
| `u_ui_command_router` | `ui_command_router` | 126 | 56 | 命令路由 |
| `u_health_monitor` | `health_monitor` | 118 | 103 | 健康遥测统计 |
| `u_led_business_driver` | `led_business_driver` | 81 | 39 | LED 业务指示 |
| `u_ws2812_effects` | `ws2812_effects` | 148 | 83 | WS2812 灯效 |

其中 J2 按键/DIP 监控含 18 个 `debounce_filter`，母板监控含 7 个，编码器子模块另含 2 个，共 27 个消抖实例。每个消抖实例约 36 至 47 LUT、19 至 28 FF。

### 2.6 BRAM 构成

| 实例 | BRAM9K | 说明 | 可压缩性 |
|---|---:|---|---|
| `u_hdmi_1_4b_transmitter_core_wrapper` | 16 | HDMI TX、音频岛、EDID | 低，加密核不可改 |
| `u_boot_layer` / `u_boot_logo_rom` | 10 | 开机 Logo ROM | 中，取决于是否保留 Logo |
| `u_wav_stream_player` | 8 | 音频环形 FIFO | 中，受音频缓冲语义约束 |
| `frame_read_write_m0` | 4 | 读写 FIFO 各 2 | 低，双缓冲必需 |
| `u_thumbnail_view_reader` | 2 | 缩略图 FIFO | 中 |
| **合计** | **40** | - | 余量 24 |

结论：

- BRAM 不是当前瓶颈。
- HDMI 核已固定占用 16 块，属于不可改项。
- 当前有 24 块 BRAM 余量，可用于把 `lrc_font_rom` 这类分布式 ROM 转为块 RAM。

### 2.7 DSP 构成

| 实例 | DSP | 说明 |
|---|---:|---|
| `u_s6_video_layer` | 4 | Black Vinyl 渲染与帧调度 |
| `u_boot_layer` | 3 | 开机 Logo 层 |
| `u_brightness_contrast_adjust` | 3 | 亮度/对比度 |
| `u_video_transition_apply` | 3 | 视频转场 |
| `u_timebase_48k` | 2 | 48 kHz 时基 |
| `u_thumbnail_view_reader` | 1 | 缩略图处理 |
| `u_pcm_volume_fade` | 1 | 音量/淡变 |
| **合计** | **17** | 余量 12 |

结论：

- DSP 不是瓶颈。
- 不建议为了省 LUT 而把 DSP 逻辑改回 fabric 乘法器。
- 如果后续某些乘法器导致 Slice 压力，可考虑用剩余 DSP 换 LUT，但收益需单变量实测。

### 2.8 时序分析

最终结果：

| 指标 | 数值 | 判断 |
|---|---:|---|
| Setup WNS | +48 ps | 名义通过，余量很小 |
| Setup TNS | 0 | 无违例 |
| Hold WNS | +24 ps | 名义通过，余量很小 |
| Hold TNS | 0 | 无违例 |
| Setup 违例端点 | 0 | 最终为 0 |
| Hold 违例端点 | 0 | 最终为 0 |
| STA coverage | 99.95% | 覆盖充分 |

但风险证据如下：

- `final_timing.rpt` 在布线阶段记录 Hold WNS `-12 ps`、TNS `-18 ps`、3 个违例端点。
- `td_20261007_154313.log` 记录 `Slice utilization ... higher than 90%, hold fixing is skipped.`
- 后续 Stage 6 通过 Hold Fix By Pin 才恢复为 `+24 ps`。

因此，当前时序应定义为“条件通过”，不应定义为“有充足余量的稳定收敛”。

---

## 3. 模块与功能盘点

### 3.1 目录与文件盘点

以下只统计 `src/` 下的 RTL、头文件和说明文件。标有“已排除”的文件在 `prj/VinylFPGA.al` 中带 `AutoExcluded=true`。

#### `src/` 根目录（11 个 Verilog + 1 个说明）

| 文件 | 功能 |
|---|---|
| `top_tf_hdmi_audio.v` | 顶层集成，连接 PLL、SD、SDRAM、视频、HDMI、扩展板 |
| `audio_arc_calculate.v` | HDMI ACR 音频时钟再生包 |
| `hdmi_phy_warpper.v` | HDMI PHY 包装层 |
| `lane_lvds_10_1.v` | 10:1 LVDS 串化器 |
| `reset_sync.v` | 复位同步释放 |
| `sync_2ff.v` | 单比特两级同步器 |
| `startup_pulse.v` | 上电单次脉冲 |
| `video_rgb_to_axis_640x480.v` | RGB 到 AXI-Stream 640×480 打包 |
| `hdmi_audio_tone_i2s_64fs.v` | 旧 I2S 测试音，已排除 |
| `I2S_receiver.v` | 旧 I2S 接收器，已排除 |
| `video_source_test.v` | 旧测试视频源，已排除 |
| `_IP核需在TD中生成.txt` | IP 生成说明 |

#### `src/audio/`（13 个文件）

`audio_source_mux.v`、`hdmi_pcm_source_bridge.v`、`m06_pcm_contract_adapter.v`、`pcm_media_tone.v`、`pcm_tap.v`、`pcm_volume_fade.v`、`play_ctrl.v`、`seek_controller.v`、`stream_session.v`、`sync_fade_gain.v`、`timebase_48k.v`、`wav_stream_player.v`、`hdmi_pcm_audio_bridge.v`（已排除）。

功能：

- WAV 文件缓存和 PCM 输出
- 播放、暂停、切曲、Seek 和重播状态
- 音量、淡变、LED/波形抽头
- PCM 到 HDMI 音频岛的桥接
- 音频测试音和 48 kHz 时基

#### `src/boot/`（2 个文件）

`boot_layer.v`、`boot_logo_rom.v`。

功能：

- 上电 Logo 显示和超时跳过
- 640×480 Logo ROM

#### `src/display/`（15 个文件）

`brightness_contrast_adjust.v`、`lrc_font_rom.v`、`lrc_lines_rom.v`、`lrc_osd.v`、`osd_overlay_24.v`、`promax_audio_waveform.v`、`seg_business_mux.v`、`status_osd_overlay.v`、`thumbnail_layout.v`、`thumbnail_view_reader.v`、`video_fade_transition.v`、`video_transition_apply.v`、`vinyl_renderer.v`、`frame_blend.v`（已排除）、`bilinear_8q8.v`（已排除）。

功能：

- Black Vinyl 视觉层
- 歌词 OSD 和字体 ROM
- 状态 OSD、波形、缩略图
- 亮度/对比度、转场、淡变
- 数码管业务显示选择

#### `src/io/`（23 个文件）

`browse_fsm.v`、`buzzer_feedback.v`、`cover_navigation.v`、`debounce_filter.v`、`encoder_monitor.v`、`exp_baud_tick.v`、`exp_echo_reporter.v`、`exp_uart_tx.v`、`expansion_integration.v`、`expansion_io_hub.v`、`health_monitor.v`、`ir_nec_decoder.v`、`key_dip_monitor.v`、`led_business_driver.v`、`param_menu_controller.v`、`quadrature_decoder.v`、`sync_bit.v`、`thumbnail_controller.v`、`ui_command_router.v`、`ui_event_bridge.v`、`ui_event_bus.v`、`ws2812_driver.v`、`ws2812_effects.v`。

功能：

- J2 扩展输入和母板输入
- 按键、DIP、编码器、IR 消抖和解码
- 统一事件总线、命令路由、跨域桥
- UART 遥测、健康统计、蜂鸣反馈
- LED、WS2812、菜单和浏览状态机

#### `src/SD/`（26 个文件）

`color_bar.v`、`fat32_file_streamer.v`、`fat32_media_loader.v`、`fat32_volume_scanner.v`、`frame_fifo_read.v`、`frame_fifo_write.v`、`frame_read_write.v`、`key_press_hold.v`、`media_probe.v`、`media_supervisor.v`、`sd_card_bmp.v`、`sd_card_cmd.v`、`sd_card_sec_read_write.v`、`sd_card_top.v`、`sd_sector_adapter.v`、`sdram_rd_arbiter.v`、`sdram.v`、`seg_decoder.v`、`seg_scan.v`、`song_index_db.v`、`spi_master.v`、`video_delay.v`、`video_timing_data.v`、`ax_debounce.v`（已排除）、`bmp_read.v`（已排除）、`video_define.v`（已排除）。

功能：

- SD SPI 协议
- FAT32 卷扫描、文件流和 INDEX.BIN 解析
- BMP 头解析和像素流
- SDRAM 帧缓存、读写 FIFO 和仲裁
- 媒体在场探测和故障恢复
- 数码管扫描、视频时序和按键长按

#### `src/video/`（4 个文件）

`mv_frame_scheduler.v`、`mv_sector_mux.v`、`mv_stream_player.v`、`s6_video_layer.v`。

功能：

- MV 扇区复用、流播放和帧调度
- Black Vinyl 视频层与封面/MV 合成

#### `src/hdmi1.4b_transmitter_core/`（1 个文件）

`hdmi_1_4b_transmitter_core_wrapper.enc.v`。

功能：

- HDMI 1.4b 加密发送核包装
- 含 TMDS 编码、音频岛、EDID、视频 AXI-Stream 接收

#### `src/include/`（8 个文件）

`global_def.v`、`boot_logo_geom.vh`、`lrc_geom.vh`、`exp_event_defs.vh`、`song_index_defs.vh`、`sdr_as_ram.enc.v`、`sdr_init_ref.enc.v`、`sdr_wrrd.enc.v`。

功能：

- 全局参数、几何参数和事件码
- 歌曲索引结构
- SDRAM 初始化、刷新、读写加密实现

#### `src/IP/`（6 个文件）

`sys_pll.v`、`video_pll.v`、`afifo_16_32_256.v`、`afifo_32_16_256.v`、`PLL_HDMI_AUDIO.v`（已排除）、`sdram.v`（已排除）。

功能：

- 系统 PLL 和视频 PLL
- 异步 FIFO
- 旧音频 PLL 和旧 SDRAM Wrapper

### 3.2 顶层例化关系

顶层 `src/top_tf_hdmi_audio.v` 使用 `` `include `` 把相当一部分子模块纳入同一编译单元，同时在 `VinylFPGA.al` 中保留独立文件条目，模块级 include guard 防止重复定义。

主要例化关系：

| 子系统 | 顶层实例 | 主要子实例 | 功能 |
|---|---|---|---|
| 系统时钟 | `sys_pll_m0`、`video_pll_m0` | PLL、GCLK | 生成 50/100/125/25 MHz 时钟 |
| SD/FAT32 | `sd_card_bmp_m0` | `fat32_media_loader_m0`、`sd_card_top_m0` | 扫描卡、解析索引、读 BMP/WAV/MV |
| SDRAM/帧缓存 | `U3`、`frame_read_write_m0` | `sdr_wrrd`、读写 FIFO | 帧缓存和 SDRAM 仲裁 |
| 视频合成 | `u_s6_video_layer`、`u_lrc_osd`、`u_osd_overlay_24` | `vinyl_renderer`、`mv_frame_scheduler` | 黑胶、歌词、状态 OSD |
| 视频输出 | `u_video_rgb_to_axis_640x480`、HDMI 核、`u_hdmi2phy_wrapper` | TMDS、LVDS | 像素打包、HDMI 发送 |
| 音频 | `u_wav_stream_player`、`u_pcm_volume_fade`、`u_sync_fade_gain` | PCM 桥、ACR | WAV 播放和 HDMI 音频 |
| 输入事件 | `u_expansion_integration` | `expansion_io_hub`、`ui_event_bus`、`ui_command_router` | 按键、DIP、EC、IR 事件 |
| 业务控制 | `u_browse_fsm`、`u_play_ctrl`、`u_seek_controller` | `ui_event_bridge` | 选歌、播放、Seek |
| 状态反馈 | `u_exp_echo_reporter`、`u_health_monitor`、`u_seg_business_mux` | LED、WS2812、UART | 遥测、显示和灯效 |
| 开机画面 | `u_boot_layer` | `u_boot_logo_rom` | Logo 层 |

### 3.3 数据通路

#### 视频通路

```text
SD/FAT32
  -> SDRAM 帧缓存
  -> frame_fifo_read / thumbnail_view_reader
  -> video_delay
  -> brightness_contrast_adjust
  -> video_fade_transition
  -> vinyl_renderer
  -> lrc_osd
  -> promax_audio_waveform
  -> osd_overlay_24 / status_osd_overlay
  -> boot_layer
  -> video_rgb_to_axis_640x480
  -> HDMI 1.4b TX
  -> hdmi_phy_wrapper
  -> lane_lvds_10_1
  -> TMDS
```

#### 音频通路

```text
SD/FAT32
  -> sd_sector_adapter
  -> fat32_file_streamer
  -> wav_stream_player
  -> pcm_volume_fade
  -> sync_fade_gain
  -> hdmi_pcm_source_bridge
  -> m06_pcm_contract_adapter
  -> HDMI 音频岛
  -> I2S/ACR
  -> TMDS
```

#### 输入事件通路

```text
J2/母板按键、DIP、EC1/EC2、IR
  -> expansion_io_hub
  -> ui_event_bus
  -> ui_command_router
  -> ui_event_bridge
  -> browse_fsm / play_ctrl
```

#### 状态反馈通路

```text
health_monitor
  -> exp_echo_reporter
  -> status_osd_overlay
  -> seg_business_mux
  -> seg_scan
  -> led_business_driver
  -> ws2812_effects
  -> ws2812_driver
  -> buzzer_feedback
```

---

## 4. 冗余与废弃代码识别

### 4.1 确定可删除

#### A. 已 AutoExcluded 且不在当前综合层次的 RTL

这 11 个文件已在 `prj/VinylFPGA.al` 中标记 `AutoExcluded=true`，当前综合没有它们，因此删除它们不会释放 FPGA 资源，但可以清理工程树、降低误编译和路径失效风险。

| 文件 | 工程文件位置 | 判断 |
|---|---|---|
| `src/hdmi_audio_tone_i2s_64fs.v` | `VinylFPGA.al:30-37` | 旧音频测试音，确定可删 |
| `src/I2S_receiver.v` | `VinylFPGA.al:47-54` | 旧音频接收，确定可删 |
| `src/video_source_test.v` | `VinylFPGA.al:80-87` | 旧测试视频源，确定可删 |
| `src/SD/ax_debounce.v` | `VinylFPGA.al:89-96` | 旧按键去抖，确定可删 |
| `src/SD/bmp_read.v` | `VinylFPGA.al:98-105` | 旧 BMP 解析，确定可删 |
| `src/SD/video_define.v` | `VinylFPGA.al:195-202` | 旧视频宏壳，确定可删 |
| `src/IP/PLL_HDMI_AUDIO.v` | `VinylFPGA.al:236-243` | 旧音频 PLL，确定可删 |
| `src/IP/sdram.v` | `VinylFPGA.al:301-308` | 旧 SDRAM Wrapper，确定可删 |
| `src/audio/hdmi_pcm_audio_bridge.v` | `VinylFPGA.al:326-333` | 旧 PCM 适配层，确定可删 |
| `src/display/frame_blend.v` | `VinylFPGA.al:415-422` | 旧帧混合，确定可删 |
| `src/display/bilinear_8q8.v` | `VinylFPGA.al:472-479` | 旧双线性缩放，确定可删 |

注意：这里的“确定可删除”只表示源码可以从工程中移除，不表示可以释放 94.78% 的 Slice。因为综合阶段已经排除了它们，删除的收益主要在工程可维护性。

#### B. 根目录与 `prj/` 下的临时验证残留

以下内容不影响综合结果，清理收益为 0 个 FPGA 资源，但会减少目录噪声和后续误用风险：

- 根目录 `_tb_final.v`、`_tb_ref_check.v`、`_tb_refvld_check.v`
- 根目录 `_tb_*.vvp`、`_macro_check.v`、`_macro_check.vvp`
- 根目录 30 多个 `td_*.log`、`td_*.logw`
- `prj/_apply_params.tcl`、`_fixhold_test.tcl`、`_probe_userparams.tcl`、`_enum_cmds.txt`、`_verify_launch.tcl`、`_x1_*.tcl`
- `prj/minidump-*.dmp`
- `prj/resource_opt_verified_20261005` 下的历史实验目录

当前 `prj/resource_opt_verified_20261005` 约 3.30 GiB、14415 个文件，包含大量 X2_r1 到 X2_r15s5、S7、OPT、S1 到 S6 的迭代目录。建议归档而不是直接删除，至少保留当前基线和已知可复现实验。

### 4.2 需确认后删除

#### A. UART 遥测与健康监测

证据：

- `src/top_tf_hdmi_audio.v:126`：`ECHO_TEST_ENABLE = 1'b1`
- `src/io/expansion_integration.v:293-345`：`health_monitor` 与 `exp_echo_reporter` 常驻例化
- `src/io/exp_echo_reporter.v:70-72`：96 字节 `msg` 缓冲
- `src/io/exp_echo_reporter.v:351-372`：STAT/ERR 文本格式化

判断：

- 当前不是死逻辑，`ECHO_TEST_ENABLE=1` 时会真实工作。
- `exp_echo_reporter` 累计 LUT 943，`health_monitor` 累计 LUT 118。
- 如果产品验收不需要 UART 遥测，可通过编译期 generate 或完全移除回收约 700 至 1060 LUT。
- 如果保留遥测，可把文本协议改成更紧凑的表驱动/二进制格式，预计回收约 200 至 400 LUT。
- 此改动影响诊断能力，需要产品和测试确认，不能按“确定可删除”处理。

#### B. 27 路重复消抖器

证据：

- `src/io/debounce_filter.v:15`：每个实例含 `reg [19:0] stable_cnt`
- `src/io/debounce_filter.v:36`：比较 `DEBOUNCE_CYCLES - 1`
- `u_expansion_io_hub` 内 18 个、`u_board_key_sw_monitor` 内 7 个、编码器内 2 个

判断：

- 逻辑确实重复，但每个实例面对不同物理输入。
- 不能直接删除消抖，否则机械按键、DIP、编码器会产生抖动事件。
- 可考虑共享时基、按通道保存短状态或集中式消抖引擎。
- 该优化属于“功能等价但实现重构”，需要上板和事件回归。

#### C. 母板 KEY 的重复消抖路径

证据：

- `u_board_key_sw_monitor` 位于 `src/io/expansion_integration.v:364-379`，已消抖 KEY1 到 KEY3。
- `sd_card_bmp_m0` 内另有 `u_key_auto`，综合后约 36 LUT、24 FF。

判断：

- 两条路径很可能对同一母板 KEY 信号进行重复消抖。
- 若能把已验证的 `u_board_key_sw_monitor` 输出复用于 `sd_card_bmp`，可回收约 36 至 72 LUT。
- 需要确认 `u_key_auto` 的时钟域、有效沿和自动播放语义完全一致后再删。

#### D. 编译期回滚开关

证据：

- `src/top_tf_hdmi_audio.v:126`：`ECHO_TEST_ENABLE`
- `src/top_tf_hdmi_audio.v:130` 附近：`BUZZER_FEEDBACK_ENABLE`
- `src/top_tf_hdmi_audio.v:136` 附近：`S2_BOOT_ENABLE`
- `src/top_tf_hdmi_audio.v:146` 附近：`S3_J2_BROWSE_ENABLE`
- `src/top_tf_hdmi_audio.v:155` 附近：`S5_PLAY_ENABLE`
- `src/top_tf_hdmi_audio.v:160` 附近：`S6_VIDEO_ENABLE`

判断：

- 这些参数当前都取启用值，不是未例化的死代码。
- 删除这些开关会降低回滚能力，不适合在资源优化第一轮直接做。
- 可先把它们保留为实验入口，用单变量综合测量每个功能关闭时的真实资源收益。

#### E. 歌词字库组合 ROM

证据：

- `src/display/lrc_font_rom.v` 是 974 行自动生成的组合 `case`
- 综合后 `u_font_rom` 约 424 LUT

判断：

- 不是死代码，歌词功能真实使用。
- 改成块 RAM 可把约 350 至 424 LUT 转成约 1 块 BRAM。
- 但同步 BRAM 会增加一级读延迟，可能改变 OSD 像素边界，必须逐像素比对。
- 属于“需确认后替换”，不是“确定可删”。

#### F. 可选功能层

以下模块不是当前死代码，但如果产品功能冻结，可整层旁路或删除：

- Boot Logo：约 142 LUT、10 BRAM、3 DSP
- LED/WS2812/蜂鸣反馈：约 434 LUT 合计，取决于统计边界
- MV/Black Vinyl：除 `u_s6_video_layer` 外，还牵连 `mv_frame_scheduler`、`mv_stream_player` 和 SDRAM 通道
- UART 遥测：约 1061 LUT

这些属于功能取舍，潜在收益大，但风险也最高。

### 4.3 假靶点与已修复项

以下项目容易被旧报告误判，当前源码已经不应再按旧结论处理：

| 项目 | 旧结论 | 当前源码与构建证据 | 当前判断 |
|---|---|---|---|
| `song_cover0..3` / `song_audio0..3` 512 FF 拷贝 | 可省约 512 FF | `song_index_db.v:131-138` 已使用 `assign` 直连，不再有 512-bit 输出寄存器组 | 已修复，不再作为优化项 |
| `hdr_max` 解析后无校验 | 可省 16 FF | 当前文件未保留该字段 | 已移除 |
| `header_byte_cnt` 32 位常数比较 | 可收窄 | `fat32_media_loader.v:223` 已是 `[5:0]`，case 已用 6 位常数 | 已修复 |
| `width` / `height` 32 位高 16 位只写不读 | 可收窄 | `fat32_media_loader.v:216-217` 已是 `[15:0]` | 已修复 |
| `fat32_volume_scanner` 4 K FF | 可裁剪 sector buffer | 当前综合累计约 1079 FF，TD 已裁剪常量下标之外的元素 | 不是 4 K FF，继续裁剪空间有限 |
| FF 是主瓶颈 | 需重点省 FF | 当前 FF 53.71%，Slice 94.78% | FF 不是主瓶颈 |
| BRAM 是主瓶颈 | 需避免使用 BRAM | 当前 BRAM 62.50%，余量 24 | 可用 BRAM 换 LUT |
| DSP 是主瓶颈 | 需避免使用 DSP | 当前 DSP 58.62%，余量 12 | DSP 不是主瓶颈 |

---

## 5. 优化建议

### 5.1 总原则

1. 在 Slice 降到 90% 以下前，暂停新增完整功能层。
2. 每轮只改一个变量，重新综合和布线，不能把多个修改绑在同一轮。
3. 优化目标优先看 Slice，其次看 `sd_card_clk` 域 LUT 和 WNS，最后才看总 LUT。
4. 任何“预计节省”都必须以实测 `final.area`、`final.qor`、`final.timing` 为准。
5. 功能改动必须做视频、音频、SD、事件、遥测和上板回归。

### 5.2 按收益与风险排序

| 优先级 | 优化项 | 证据 | 预估收益 | 影响范围 | 风险 | 建议 |
|---:|---|---|---:|---|---|---|
| P0 | 暂停新增功能，先减 Slice | `final.qor: 94.78%` | 防止继续恶化 | 全局 | 低 | 立即执行 |
| P1 | 合并母板 KEY 重复消抖路径 | `u_key_auto` 36 LUT、`u_board_key_sw_monitor` 260 LUT | 36 至 72 LUT | 母板 KEY1/2、自动播放 | 中 | 先做等价性确认，最优先实测 |
| P2 | `lrc_font_rom` 组合 ROM 转 BRAM | 424 LUT；BRAM 余量 24 | 350 至 424 LUT，+1 BRAM | 歌词 OSD | 中 | 加流水线后做逐像素比对 |
| P3 | 消抖器共享时基或集中式引擎 | 27 个实例，每个 36 至 47 LUT | 300 至 600 LUT，可能减 300 至 400 FF | J2/母板输入、编码器 | 中高 | 行为重写，需上板长测 |
| P4 | UART 遥测裁剪或紧凑协议 | `exp_echo_reporter` 943 LUT、`health_monitor` 118 LUT | 200 至 1060 LUT | 诊断、串口 | 高 | 取决于产品是否保留遥测 |
| P5 | `video_rgb_to_axis_640x480` 接口简化 | 650 LUT，逻辑本身很短 | 100 至 250 LUT | HDMI 像素时序 | 中高 | 先做时序和接口分析 |
| P6 | 固定计数器和等待器的位宽整理 | `debounce_filter` 用 20 位，400000 只需 19 位 | 50 至 150 LUT | 输入和等待状态 | 中 | 已有宽位宽实验导致 WNS 下降，必须与前项合并验证 |
| P7 | 可选功能层旁路或删除 | Boot、MV、LED/WS2812、遥测 | 700 至 1500 LUT，视功能取舍 | 用户可见功能 | 高 | 仅在功能冻结后做 |
| P8 | 清理死文件和历史实验目录 | 11 个 AutoExcluded、根目录临时文件 | 0 FPGA 资源 | 工程可维护性 | 低 | 建议归档，不直接影响烧录结果 |

### 5.3 P1：母板 KEY 重复消抖合并

目标：

- 让 `sd_card_bmp` 消费已经过 `u_board_key_sw_monitor` 消抖的 KEY1/KEY2/KEY3，删除内部 `u_key_auto` 的重复消抖。

预估收益：

- LUT：约 36 至 72
- FF：约 24 至 48

确认条件：

- `u_key_auto` 的按键极性、消抖时间、有效沿和自动播放语义必须与母板监控一致。
- 跨域传递必须是电平 toggle 或已有同步器，不能直接跨时钟采样。

回退方式：

- 保留原 `u_key_auto` 源文件，只改例化连接；若行为不一致，立即恢复。

### 5.4 P2：歌词字库转块 RAM

目标：

- 把 `lrc_font_rom` 的组合 `case` 改为 TD 可推断的块 RAM 初始化 ROM，或直接例化 ROM IP。

预估收益：

- LUT：约 350 至 424
- BRAM：约 +1
- Slice：预计可同步下降，但幅度需实测

影响：

- BRAM 读是同步的，需要处理一拍延迟。
- OSD 像素边界、`dx12`、行有效信号和字模位选必须重新对齐。

验证：

- 对每一帧歌词区域做逐像素比对。
- 检查 HDMI 输出是否有横向或纵向偏移。
- 检查 `video_clk` 域 WNS 是否保持非负。

### 5.5 P3：消抖器共享时基或集中式引擎

目标：

- 减少 27 个 `debounce_filter` 中重复的 20 位计数器、比较器和加法器。

可行方向：

1. 全局 1 ms tick + 每通道小幅稳定计数。
2. 单个集中式时间轮询器，按通道轮转并保存通道状态。
3. 对不需要独立消抖时间的通道复用公共状态机。

预估收益：

- LUT：约 300 至 600
- FF：约 300 至 400

风险：

- 消抖时间变化会直接影响按键、DIP 和编码器事件。
- 共享资源可能引入轮询延迟，需要评估最坏响应时间。

验证：

- 连续按键、快速按键、DIP 切换、EC 正反转、IR 并发。
- 重点观察事件丢失、重复触发和长按判定。
- 至少做一次上板长时运行。

### 5.6 P4：UART 遥测裁剪

目标：

- 如果 UART 遥测不是产品验收必需项，则通过编译期 generate 关闭 `exp_echo_reporter` 和 `health_monitor`。
- 如果必须保留，则把文本格式化改成紧凑协议，减少 96 字节消息缓冲和多个文本 task 的展开。

预估收益：

- 完全移除：约 700 至 1060 LUT。
- 仅改紧凑协议：约 200 至 400 LUT。

影响：

- 完全移除会丢失 STAT、ERR、IR、KEY、DIP、ENC、BOOT 等调试信息。
- 紧凑协议需要同步修改上位机接收脚本。

判断：

- 这是收益最大的功能取舍项，但不能归类为“确定可删除”。
- 建议先做一次 `ECHO_TEST_ENABLE=0` 的编译实验，确认真实资源收益，再决定是否永久移除。

### 5.7 P5：`video_rgb_to_axis_640x480` 简化

证据：

- 模块只有 67 行，但综合后约 650 LUT。
- 主要逻辑是 24 位数据寄存、`S_x_cnt[10:0]`、`O_video_user`、`O_video_valid`、`O_video_last`。

可行方向：

- 检查是否能减少 24 位数据寄存的复制和控制 mux。
- 检查 `S_x_cnt` 是否只需要到 639，仍需 10 位加 1 位比较。
- 检查 `O_video_user` 是否能用已经存在的 `S_frame_arm` 边沿直接输出。

预估收益：

- LUT：约 100 至 250

风险：

- 会改变 HDMI AXI-Stream 的 SOF/EOF 语义，容易出现首帧、末像素或行对齐问题。

### 5.8 P6：固定计数器位宽整理

证据：

- `debounce_filter.v:15` 使用 `[19:0]`，而 `DEBOUNCE_CYCLES=400000` 需要 19 位。
- 旧实验 OPT_R2 单独收窄后得到 LUT 下降，但 Setup WNS 从 +31 ps 降到 -291 ps。

判断：

- 位宽本身有多余，但单独修改会改变布局，不能只看组合逻辑收益。
- 建议作为 P2 或 P3 的附带改动，不做孤立优化。

### 5.9 P7：可选功能层削减

如果前 P1 至 P6 仍不能把 Slice 拉回 88%，需要做功能取舍：

| 功能 | 直接资源证据 | 影响 |
|---|---|---|
| UART 遥测 | 约 1061 LUT | 丢失诊断信息 |
| Boot Logo | 约 142 LUT、10 BRAM、3 DSP | 去掉开机 Logo |
| LED/WS2812/蜂鸣 | 约 434 LUT | 去掉部分状态反馈 |
| MV/Black Vinyl | `u_s6_video_layer` 545 LUT、4 DSP，另有调度和 SDRAM 逻辑 | 去掉 MV 或黑胶视觉层 |
| 歌词 OSD | `u_lrc_osd` 624 LUT，其中字库 424 | 去掉或简化为状态文本 |

这类改动收益最大，但不能以“冗余代码”名义直接删除，必须按产品功能决策。

### 5.10 P8：代码和工程清理

建议顺序：

1. 先归档完整历史实验目录和 bitstream。
2. 再删除 11 个 AutoExcluded 源文件。
3. 清理根目录 `_tb_*`、`_macro_check.*`、`td_*.log`。
4. 清理 `prj/_*.tcl`、`_enum_cmds.txt`、minidump。
5. 保留 `X2_r15s5_20261007` 作为当前可复现基线。

预期 FPGA 资源收益：

- 0

预期工程收益：

- 工程树更稳定
- 避免旧文件被 GUI 误加入
- 减少后续脚本误用旧报告的概率

---

## 6. 约束与剩余风险

### 6.1 当前约束特点

`constraints/timing.sdc` 当前状态：

- `timing.sdc:17` 创建 50 MHz 输入主时钟。
- `timing.sdc:22` 使用 `derive_clocks` 推导 PLL 输出。
- `timing.sdc:33-37` 重命名五个关键时钟。
- `timing.sdc:53-55` 设置 `video_clk` 与 `hdmi_5x_clk` 为 exclusive。
- `timing.sdc:77-82` 把几个 PLL 派生域设为 asynchronous。
- `timing.sdc:85-87` 明确说明 Input/Output delay 暂时为空。
- `timing.sdc:114-118` 说明 J2 异步输入暂未设置 input delay。

### 6.2 约束风险

| 风险 | 证据 | 影响 | 建议 |
|---|---|---|---|
| IO delay 全空 | `timing.sdc:85-87` | 外设接口时序没有量化约束 | 上板验收前补充 input/output delay |
| 全局异步组较粗 | `timing.sdc:77-82` | 可能掩盖真实跨域路径 | 配合 CDC 审计逐条确认同步器 |
| Hold 余量极小 | `final.timing: +24 ps` | 温度、电压、布局变化可能翻转 | 优先把 Slice 降到 90% 以下 |
| 初始 Hold 修复被跳过 | `td_20261007_154313.log:2280` | 当前时序依赖后续补丁 | 不把当前结果视为稳定收敛 |
| 最差路径在 100 MHz SD 域 | `final.timing` | 小改动可能引入 WNS 回归 | 所有 SD 域优化必须重新跑完整时序 |

---

## 7. 建议实施顺序

### 第 1 轮：低风险清理与测量

1. 归档历史实验目录，不物理删除当前基线。
2. 删除 11 个 AutoExcluded 源文件。
3. 执行 `ECHO_TEST_ENABLE=0` 的编译实验，只测量资源，不立即合入。
4. 执行 `S6_VIDEO_ENABLE=0` 的编译实验，只测量资源，不立即合入。

目标：

- 得到遥测和 MV 层的真实资源上限。
- 不改变当前产品功能。

### 第 2 轮：低风险 Slice 回收

1. 合并母板 KEY 重复消抖。
2. 把 `lrc_font_rom` 改为块 RAM。
3. 每次只提交一个变量，记录 `final.area`、`final.qor`、`final.timing`。

目标：

- 争取把 Slice 从 94.78% 降到 92% 以下。
- 保持 Setup/Hold TNS 为 0。

### 第 3 轮：结构化削减

1. 消抖器共享时基或集中式引擎。
2. UART 遥测紧凑协议或关闭。
3. `video_rgb_to_axis_640x480` 接口简化。

目标：

- 争取把 Slice 拉回 88% 至 90%。
- `sd_card_clk` 域 LUT 明显下降。

### 第 4 轮：产品功能取舍

如果前三轮仍不能达到目标，再评估：

- 去掉或冻结 MV/Black Vinyl。
- 去掉或冻结歌词 OSD。
- 关闭 Boot Logo。
- 精简 LED/WS2812/蜂鸣反馈。

---

## 8. 验证与验收标准

每一轮优化必须满足：

| 项目 | 门槛 |
|---|---|
| Slice | 必须下降，目标最终小于 90%，优先小于 88% |
| Setup WNS | 大于等于 0 |
| Hold WNS | 大于等于 0，且不能只依赖边界补丁 |
| Setup TNS / Hold TNS | 均为 0 |
| 违例端点 | 均为 0 |
| BRAM | 不超过 64 |
| DSP | 不超过 29 |
| IO | 不超过 188 |
| 功能 | 视频、音频、SD、事件、遥测、扩展板全部回归 |
| 上板 | 至少完成一次持续播放、切歌、Seek、IR、DIP、EC 和遥测测试 |

单变量验证流程：

1. 固定源码哈希，记录基线。
2. 只改一个模块或一个参数。
3. 重新综合、布局、布线。
4. 比较 `final.area`、`final.qor`、`final.timing`。
5. 运行等价性测试或上板回归。
6. 通过后合入，失败则保留实验目录并回退。

建议保留的实验产物：

- `gate.area`
- `final.area`
- `final.qor`
- `final.timing`
- `native_build.log`
- `release_bitgen.log`
- `VinylFPGA_optimized.bit`
- `inputs.sha256.json`

---

## 9. 不确定性与待确认项

| 项目 | 当前判断 | 需要确认 |
|---|---|---|
| UART 遥测是否产品必需 | 资源收益大，但当前启用 | 产品验收是否要求 STAT/ERR/UART |
| 母板 KEY 重复消抖 | 很可能可合并 | 两路消抖参数和有效沿是否完全一致 |
| 消抖共享实现 | 理论收益明显 | 能否保持事件时序和长按语义 |
| 字库转 BRAM | BRAM 余量足够 | OSD 像素边界是否逐像素一致 |
| `video_rgb_to_axis` 简化 | LUT/功能比异常高 | AXI-Stream 接口是否允许改时序 |
| 关闭 MV/歌词/Boot | 收益大 | 产品功能是否冻结 |
| IO delay | 当前为空 | 上板是否需要量化外部接口 |
| 历史实验目录 | 约 3.30 GiB | 哪些版本需要保留为证据 |

---

## 10. 总结

当前 VinylFPGA 的资源状态可以概括为：

- **不是 FF 不够，也不是 BRAM/DSP 不够，而是 Slice 已经接近满。**
- **最大逻辑消耗来自 `sd_card_bmp_m0` 和 `u_expansion_integration`。**
- **当前时序只是名义通过，Hold 余量只有 +24 ps，且初次 Hold 修复因 Slice 超过 90% 被跳过。**
- **旧文档中的 8412/85.84% 不是当前基线，当前应使用 9288/94.78%。**
- **11 个 AutoExcluded 文件确定可以从工程树删除，但不会释放 FPGA 资源。**
- **真正能回收资源的是消抖器共享、遥测裁剪、字库转 BRAM、RGB 接口简化和可选功能层取舍。**
- **最优先行动是停止新增功能，先用低风险项把 Slice 压回 90% 以下，再决定是否需要牺牲产品功能。**

---

*本文基于当前工作区源码 `66da60f` 与构建 `X2_r15s5_20261007` 的 112 项输入哈希一致性生成。*
