# VinylFPGA Slice/LUT 优先资源盘点与优化分析 — 最终方案报告

> **日期**：2026-10-08
> **器件**：Anlogic EG4S20BG256（LUT 19600 / REG 19600 / BRAM9K 64 / BRAM32K 16 / DSP 29 / PLL 4 / GCLK 16 / PAD 188）
> **工程**：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`，入口 `prj/VinylFPGA.al`，顶层 `src/top_tf_hdmi_audio.v` 的 `module top`
> **Git**：分支 `main`，HEAD `428b777 refactor: reduce fat32 volume scanner boot parsing cost`
> **数据口径**：器件利用率一律取 area 报告的 `#lut ... out of 19600` 行。QoR 的 `#luts`（13568）与 area 的 `#Total_luts`（13568）属**统计口径，不用于门禁判定**（依据 `R0-signoff.md:60`）
> **首要目标**：Slice/LUT 下降；兼顾时序收敛与代码可维护性

---

## 0. 结论摘要

| 项 | 结论 |
|---|---|
| 当前 LUT | **17110 / 19600 = 87.30%**，门禁 ≤16500，**超 610** |
| 当前 BRAM | 58 / 64 = 90.62%，门禁 ≤60，合格（余 2，**无压缩余量**） |
| 当前 DSP | 17 / 29 = 58.62%，**空闲 12** |
| place slices | **9727 / 9800 = 99.26%**，门禁 ≤90%，**超 927 —— 比 LUT 更硬的瓶颈** |
| 时序 | gate Setup WNS −1.229 ns / 28 违例；place Hold WNS −0.011 ns / 11 违例 |
| 签核状态 | **未签核**（`R0-signoff.md:3`，`signed_off=false`，无 bit、未烧录） |
| **核心判断** | 8 项已实测优化试验**全部未降低 LUT**（§3.5）。真正可落地的是**结构性浪费清理**：本报告识别出 **「确定可删」约 325~430 LUT** + **「需确认后删」约 270~480 LUT**，具备达门禁的路径，但**必须逐项重新 gate 验证** |
| **最重要发现** | ① `song_index_db` 的 3 位索引建了 8:1 mux（应为 4:1），约 65 LUT；② `lrc_five_line_osd` 的 128-bit 掩码 mux 只为取 8 bit，约 120 LUT；③ `mv_frame_scheduler` 为省 DSP 手写 `×100` 移位加，**在 DSP 空闲 12 个的今天方向已过时**，改回 DSP 可省 50~64 LUT |

---

## 1. 第一步：资料与代码核查

### 1.1 已核查资料

| 文档 | 作用 | 本报告采信的关键结论 |
|---|---|---|
| `VinylFPGA_后续完整开发方案_R0至最终交付_20261008.md` | R0→最终交付总纲 | 定义 R0-A/B/C 与统一硬门禁（`:95-107`）；候选优化顺序（`:289-296`） |
| `VinylFPGA_最终后续开发方案_X2之后_核心链路优先_20261007.md` | X2 后核心链路优先 | 资源控制原则（`:722-760`）；「资源紧张时处理顺序」；UIRES 格式定义 |
| `R0-signoff.md` | R0 收尾与架构决策 | **未签核**；面积口径纪律（`:60`）；UART/诊断已常量关闭、不能再计收益（`:75`）；已保存 hierarchy 的四大模块 |
| `VinylFPGA_SliceLUT资源盘点与优化方案_20261008.md` | 上一版盘点稿 | 死代码清单；试验对比表 |
| `VinylFPGA_SliceLUT优先资源盘点与最终优化方案_20261008.md` | 上一版方案稿 | **口径已修订**：试验收益未经验证、死代码结论不完整 —— 本文取代之 |
| `VinylFPGA_X2后当前阶段收尾报告_20261008.md`、`VinylFPGA_开发进度全面分析报告_20261008.md`、`优化.md` | 历史审计/进度 | 作为背景，不作签核依据 |

### 1.2 编译结构与死文件核查（实测）

**双重编译机制**：`.al` 显式列出 74 个 `.v`；顶层再用 `` `include `` 把另外 54 个并入同一编译单元（`src/top_tf_hdmi_audio.v:9-75`）。两者**无重叠**（实测 `comm -12` 为空），去重后共 115 个设计文件。

**完全未编译的孤立文件（4 个）**：

| 文件 | 行数 | 判定依据 |
|---|---:|---|
| `src/display/playback_line_reader.v` | 349 | 不在 `.al`、未被 include、无实例（C4 草稿） |
| `src/display/playback_line_buffers.v` | 84 | 同上 |
| `src/display/playback_view_ctrl.v` | 82 | 同上 |
| `src/include/global_def.v` | 13 | **例外**：被 `src/SD/sdram.v` 以 `` `include `` 引用，属共享头，**不属孤立文件** |

> 与 `VinylFPGA_后续完整开发方案_R0至最终交付_20261008.md:21` 一致：C4 三文件是草稿，不在 `.al`、无顶层实例。

### 1.3 关键约束与时钟

- 约束文件是 `constraints/timing.sdc` + `constraints/pin.adc`（**非 XDC**）。
- 时钟：`clk` 50 MHz、`sd_card_clk` 100 MHz、`video_clk` 25 MHz、`ext_mem_clk` 125 MHz、`ext_mem_clk_sft` 125 MHz（shift）、`hdmi_5x_clk` 125 MHz。
- PLL 2 个（`sys_pll`、`video_pll`）；**无 MMCM**（Anlogic 口径为 PLL）。GCLK 2/16。
- 门禁要求：Setup/Hold WNS ≥0、TNS=0、违例端点=0、overflow=0，且**不得用 false path 隐藏同域路径**。

---

## 2. 模块盘点表

> 数据源：`prj/r0_signoff/closeout_gate/gate_latest_hier.area`（gate 层）。LUT/REG/BRAM/DSP 为该实例**及其子层合计**。

| 模块实例 | 源文件 | 职责 | 主要子模块 | LUT | REG | BRAM | DSP |
|---|---|---|---|---:|---:|---:|---:|
| `top` | `top_tf_hdmi_audio.v` | 顶层，时钟/复位/总线分发 | 见下行 | 15363 | 12043 | 58 | 17 |
| `sd_card_bmp_m0` | `SD/sd_card_bmp.v` | SD 媒体装载总入口 | fat32_media_loader, sd_card_top | **4036** | 3614 | 0 | 0 |
| └ `fat32_media_loader_m0` | `SD/fat32_media_loader.v` | FAT32 扇区读取/仲裁/展开 | volume_scanner, file_streamer, song_index_db | **3695** | 3391 | 0 | 0 |
| └─ `u_volume_scanner` | `SD/fat32_volume_scanner.v` | 目录扫描建索引 | — | 803 | 1178 | 0 | 0 |
| └─ `u_song_index_db` | `SD/song_index_db.v` | 歌曲索引库 | — | 708 | 919 | 0 | 0 |
| └─ `u_file_streamer` | `SD/fat32_file_streamer.v` | 文件连续流读取 | — | 542 | 278 | 0 | 0 |
| └ `sd_card_top_m0` | `SD/sd_card_top.v` | SD 协议层 | sd_card_cmd, sec_read_write, spi_master | 243 | 180 | 0 | 0 |
| `u_expansion_integration` | `io/expansion_integration.v` | 扩展板集成 | io_hub, key_dip, ws2812, ir, param, ui_* | **2028** | 1023 | 0 | 2 |
| └ `u_expansion_io_hub` | `io/expansion_io_hub.v` | 编码器/开关集线 | encoder_monitor | 737 | 446 | 0 | 0 |
| └ `u_key_dip_monitor` | `io/key_dip_monitor.v` | 拨码/按键监测 | debounce_bank | 306 | 198 | 0 | 0 |
| └ `u_ws2812_effects` | `io/ws2812_effects.v` | 灯效 | ws2812_driver | 251 | 96 | 0 | 2 |
| └ `u_ir_nec_decoder` | `io/ir_nec_decoder.v` | 红外解码 | — | 228 | 138 | 0 | 0 |
| └ `u_buzzer_feedback` | `io/buzzer_feedback.v` | 提示音 | — | 202 | 80 | 0 | 0 |
| `u_ui_asset_loader` | `SD/ui_asset_loader.v` | UIRES 资源槽解析/CRC | — | **1413** | 1248 | 0 | 0 |
| `u_hdmi_1_4b_transmitter_core_wrapper` | `hdmi1.4b_transmitter_core/*.enc.v` | HDMI 1.4b 加密 IP | tmds/edid/audio | 1251 | 1503 | **16** | 0 |
| `u_s6_video_layer` | `video/s6_video_layer.v` | MV/黑胶叠加层 | mv_frame_scheduler, vinyl_renderer | 622 | 310 | 0 | 4 |
| └ `scheduler` | `video/mv_frame_scheduler.v` | MV 时间调度 | — | 298 | 196 | 0 | 0 |
| `u_lrc_cache` | `display/lrc_cache.v` | 歌词字形/行表缓存 | — | 519 | 0 | **18** | 0 |
| `frame_read_write_m0` | `SD/frame_read_write.v` | SDRAM 帧读写缓冲 | frame_fifo_read/write | 469 | 359 | 4 | 0 |
| `u_lrc_five_line_osd` | `display/lrc_five_line_osd.v` | 五行歌词叠加 | lyric_timeline | 443 | 193 | 0 | 1 |
| `u_wav_stream_player` | `audio/wav_stream_player.v` | WAV 流播放 | — | 441 | 293 | 8 | 0 |
| `u_video_rgb_to_axis_640x480` | `video_rgb_to_axis_640x480.v` | RGB→AXIS 打包 | — | **365** | 26 | 0 | 0 |
| `u_seek_controller` | `audio/seek_controller.v` | 跳转控制 | — | 337 | 230 | 0 | 0 |
| `u_thumbnail_view_reader` | `display/thumbnail_view_reader.v` | 缩略图读取 | thumbnail_layout | 293 | 246 | 2 | 1 |
| `u_wallpaper_loader` | `SD/wallpaper_loader.v` | 背景装载 | — | 272 | 172 | 0 | 0 |
| `u_playback_progress` | `display/playback_progress.v` | 播放进度计算 | — | 263 | 129 | 0 | 0 |
| `u_ws2812_progress` | `io/ws2812_progress.v` | 灯环进度 | — | 181 | 118 | 0 | 0 |
| `u_promax_audio_waveform` | `display/promax_audio_waveform.v` | 音频波形 | — | 145 | 49 | 0 | 0 |
| `u_boot_layer` | `boot/boot_layer.v` | 开机 Logo | boot_logo_rom | 144 | 53 | 10 | 3 |
| `u_timebase_48k` | `audio/timebase_48k.v` | 48k 时基 | — | 140 | 88 | 0 | 0 |
| `u_media_supervisor` | `SD/media_supervisor.v` | 媒体故障恢复 | — | 137 | 62 | 0 | 0 |
| `U3` | `SD/sdram.v` | SDRAM 控制器 | sdr_as_ram/init_ref/wrrd | 128 | 453 | 0 | 0 |
| `u_seg_business_mux` | `display/seg_business_mux.v` | 数码管业务映射 | 5× seg_decoder | 123 | 68 | 0 | 0 |
| `u_mv_stream_player` | `video/mv_stream_player.v` | MV 流播放 | — | 101 | 71 | 0 | 0 |
| `seg_scan_m0` | `SD/seg_scan.v` | 数码管扫描 | — | 96 | 19 | 0 | 0 |
| `u_ui_event_bridge` | `io/ui_event_bridge.v` | 事件桥接 | — | 91 | 74 | 0 | 0 |
| `u_wallpaper_ctrl` | `display/wallpaper_ctrl.v` | 背景轮播控制 | — | 90 | 62 | 0 | 0 |
| `u_sdram_rd_arbiter` | `SD/sdram_rd_arbiter.v` | SDRAM 读仲裁 | — | 16 | 9 | 0 | 0 |
| 其余小模块 | 多个 | seg/browse/cover/reset/sync/pll/pcm 等 | — | 合计 < 800 | — | 0 | 0 |

### 2.1 层级关系（三大热点）

```text
sd_card_bmp (686行)                              4036 LUT  ← 23.6%
 └─ fat32_media_loader (1213行)                  3695 LUT
     ├─ u_volume_scanner (569行)                  803
     ├─ u_song_index_db (334行)                   708
     ├─ u_file_streamer (275行)                   542
     └─ u_sd_sector_adapter (90行)                 62
 └─ sd_card_top → sd_card_cmd / sec_read_write / spi_master   243

u_expansion_integration (651行)                  2028 LUT  ← 11.9%
 └─ u_expansion_io_hub (151行) → encoder_monitor → quadrature_decoder
 ├─ u_key_dip_monitor (81行) → debounce_bank
 ├─ u_ws2812_effects → u_ws2812_driver            (DSP 2)
 ├─ u_ir_nec_decoder (206行)
 └─ u_buzzer_feedback (135行)

u_ui_asset_loader (800行)                       1413 LUT  ← 8.3%（同时是最差时序路径）
```

**三大热点合计 7477 LUT = 全设计 43.7%** —— 优化必须从这里入手。

---

## 3. 资源占用数据表

### 3.1 器件总量

| 资源 | gate（closeout_gate） | place（seed5） | 总量 | 门禁 | 判定 |
|---|---:|---:|---:|---:|---|
| **LUT** | **17110 (87.30%)** | 17856 (91.10%) | 19600 | ≤16500 | **超 610** |
| REG | 11986 (61.15%) | 12046 (61.46%) | 19600 | — | 充裕 |
| **BRAM 9K** | 58 (90.62%) | 58 (90.62%) | 64 | ≤60 | 合格（余 2） |
| BRAM 32K | 0 | 0 | 16 | — | 空闲 |
| DSP | 17 (58.62%) | 17 (58.62%) | 29 | — | **空闲 12** |
| IO Pad | 75 (39.89%) | 75 (39.89%) | 188 | — | 充裕 |
| PLL | 2 | 2 | 4 | — | 空闲 2 |
| GCLK | 2 | 2 | 16 | — | 充裕 |
| **Slices** | — | **9727 (99.26%)** | 9800 | ≤90% | **超 927** |

> **重要口径警告（R0-signoff.md:60）**：不能用 QoR 的 `#luts`（13568）或 area 的 `#Total_luts`（13568）代替 area 利用率行 `#lut ... out of 19600`（17110）。**门禁按后者判定。**
> gate 阶段 `#slices 1771 (18.07%)` 是**宏级统计**，无物理意义；真实 slices 只有 place/route 后的 9727。

### 3.2 时序现状

| 指标 | gate（closeout_gate） | place（seed5） | 门禁 |
|---|---:|---:|---:|
| Setup WNS | **−1.229 ns** | +0.108 ns | ≥0 |
| Setup TNS | −5.616 ns | 0 | =0 |
| Setup 违例端点 | **28** | 0 | 0 |
| Hold WNS | +0.471 ns | **−0.011 ns** | ≥0 |
| Hold TNS | 0 | −0.121 ns | =0 |
| Hold 违例端点 | 0 | **11** | 0 |
| Route overflow | 未收敛（拥塞终止） | — | 0 |

**gate 最差路径（`gate_latest.timing`）**：

| Slack | 起点 → 终点 | 定位 |
|---:|---|---|
| −1.229 ns | `ui_asset_loader/slot_cnt_reg[3]` → `slot_crc_ok_reg.d` | **CRC 组合链，9 级** |
| −0.863 ns | `frame_fifo_write/write_cnt_reg[0]` → `frame_fifo_read/state_reg[2]` | 帧 FIFO |
| −0.681 ns | `ui_asset_loader/slot_cnt_reg[3]` → `hdr_crc_ok_reg.d` | 同一 CRC 链 |
| −0.174 ns | `frame_fifo_write/write_cnt_reg[0]` → `thumbnail_view_reader/burst_base_mem_reg.ce` | 缩略图 CE |
| −0.170 ns | `sd_card_sec_read_write/state_reg[8]` → `ui_asset_loader/slot_line_ok_reg.d` | SD→UI 跨段 |

> **关键洞察**：最差时序路径（LUT 第二热点 `ui_asset_loader`）与 LUT 热点重叠 —— **降 LUT 与收时序可共用同一批重构目标**。

**逻辑级数分布（`gate_latest.qor`）**：`sd_card_clk`(100MHz) 有 7119 条 1 级、2290 条 4 级路径；`clk`(50MHz) 最深达 16 级（37 条）；`video_clk`(25MHz) 分布最宽。`ext_mem_clk_sft` 无路径。

### 3.3 BRAM / DSP 归属

| 资源 | 归属明细 | 合计 |
|---|---|---:|
| BRAM (58) | `lrc_cache` 18、HDMI wrapper 16、`boot_layer` 10、`wav_stream_player` 8、`frame_read_write` 4、`thumbnail_view_reader` 2 | 58 |
| DSP (17) | `s6_video_layer` 4、`boot_layer` 3、`pcm_volume_fade` 2、`brightness_contrast_adjust` 2、`video_transition_apply` 2、`expansion_integration` 2、`lrc_five_line_osd` 1、`thumbnail_view_reader` 1 | 17 |

> **BRAM 结构性异常**：`lrc_cache` 519 LUT / **0 ripple / 0 seq** —— 纯 RAM 模块出现 519 LUT 且无寄存器，不正常。根因是 `line_glyph_mem` 的 **128-bit 读端口**（`src/display/lrc_cache.v:36`），按 BRAM9K 端口宽 ≤16bit 计算需 8 片。详见 §5 M12。

### 3.4 Rent 高复杂度模块（`gate_latest.qor`）

| 实例 | Rent | Cell | Pin | Term |
|---|---:|---:|---:|---:|
| `top` | 0.20 | 27797 | 117822 | 33 |
| `u_ui_asset_loader` | **0.64** | 2661 | 11002 | 632 |
| `sd_card_bmp_m0` | 0.57 | 7650 | 33771 | 739 |
| `u_hdmi_..._wrapper` | 0.57 | 2712 | 9820 | 328 |
| `u_expansion_integration` | 0.46 | 3039 | 12795 | 169 |

> 高 fanout 顶部 43.48；`dff(single fanout)->dff` 1322 条。

### 3.5 已实测优化试验（全部否决）

> 全部在 `prj/r0_opt/`，gate 阶段 `area_prior` 策略，统一以 `#lut` 对比基线 17110。

| 试验目录 | LUT | Δ vs 基线 | REG | 判定 |
|---|---:|---:|---:|---|
| **`closeout_gate`（基线）** | **17110** | 0 | 11986 | 参考 |
| `arb_prereg` | 17101 | **−9** | 11853 | 无有效收益（远不足 610，且 slices/违例恶化） |
| `volume_scanner_fields` | 17196 | +86 | 11820 | **否决** |
| `packio` | 17259 | +149 | 11820 | **否决** |
| `arb_input_reg` | 17264 | +154 | 11985 | **否决** |
| `ui_asset_loader` | 17321 | +211 | 11820 | **否决** |
| `songidx_input_pipe` | 17460 | +350 | 11835 | **否决** |
| `songidx_case_mutex` | 17779 | +669 | 11826 | **否决** |
| `songidx_payload_regs` | 18219 | +1109 | 12588 | **否决** |

> **结论 3.5**：历史 8 项试验**没有一项把 LUT 降到门禁 16500 以下**。`volume_scanner_fields`、`songidx_*` 四个方向已实测恶化，**禁止重走**。「加寄存器隔离」类策略在本综合器上普遍反增 LUT。
> **因此本报告全部收益均为「估算 + 待重新 gate 验证」，不得写成签核结果。**

---

## 4. 死代码与冗余清单

### 4.1 确定可删除 — 进入编译但无实例（LUT 收益 = 0）

实测确认这些模块**综合器已裁为 0 面积**（`gate_latest_hier.area` 无对应实例）：

| 文件 | 定义模块 | 依据 |
|---|---|---|
| `src/display/lrc_osd.v` | `lrc_osd` | 被 include(`:58`) 但**无实例**；日志中 `elaborate module lrc_osd` 计数 **0** |
| `src/display/lrc_renderer.v` | `lrc_renderer` | 同上，计数 **0** |
| `src/display/lrc_font_rom.v`(1041行) | `lrc_font_rom` | 唯一实例点在 `lrc_osd.v:63` → 随之为死；计数 **0** |
| `src/display/lrc_lines_rom.v`(155行) | `lrc_lines_rom` | 唯一实例点在 `lrc_osd.v:51`；计数 **0** |
| `src/hdmi_audio_tone_i2s_64fs.v` | `hdmi_audio_tone_i2s_64fs` | `.al:30`，无实例 |
| `src/I2S_receiver.v` | `I2S_receiver` | `.al:47`，无实例 |
| `src/video_source_test.v` | `video_source_test` | `.al:80`，无实例 |
| `src/SD/ax_debounce.v` | `ax_debounce` | `.al:89`，无实例 |
| `src/SD/bmp_read.v` | `bmp_read` | `.al:98`，已被 `fat32_media_loader` 取代 |
| `src/IP/PLL_HDMI_AUDIO.v` | `PLL_HDMI_AUDIO` | `.al:236`，无实例 |
| `src/audio/hdmi_pcm_audio_bridge.v` | `hdmi_pcm_audio_bridge` | `.al:326`，实际用 `hdmi_pcm_source_bridge` |
| `src/display/frame_blend.v` | `frame_blend` | `.al:399`，无实例 |
| `src/display/bilinear_8q8.v` | `bilinear_8q8` | `.al:456`，无实例 |
| `src/io/debounce_filter.v` | `debounce_filter` | `.al:513`，扩展板用 `debounce_bank` |
| `src/IP/sdram.v` | `sdram_phy` | `.al:301`，实际用 `src/SD/sdram.v` 的 `sdram` |

### 4.2 确定可删除 — 完全未编译（孤立文件，LUT 收益 = 0）

`src/display/playback_line_reader.v`(349)、`playback_line_buffers.v`(84)、`playback_view_ctrl.v`(82) —— C4 草稿，见 §1.2。

### 4.3 需确认后删除

| 文件 | 现状 | 需确认点 |
|---|---|---|
| `src/display/lrc_osd.v`、`lrc_renderer.v` | 无实例，但顶层 `:2801` 注释提到「保留旧单行 ROM 行为」 | 旧歌词回退路径是否已废弃；若未来要恢复需保留 |
| `src/display/playback_line_*.v` | C4 草稿 | R0 通过后 C4 阶段需重写（`后续完整开发方案:125-131` 列出必须修正的草稿问题），**建议归档而非删除** |

### 4.4 重要结论：死代码 ≠ LUT 收益

上述 A/B 类文件**已被综合器裁为 0 面积**，删除它们**不释放任何 LUT/BRAM/DSP**。真实收益是：缩短读网表与综合时间、消除维护歧义、避免后人误引用。**不得把这些删除计入 LUT 下降指标。**

### 4.5 悬空端口（已确认无消费者）

| 端口 | 位置 | 说明 |
|---|---|---|
| `lrc_five_line_osd.hit` | `top:2803,2902`；`lrc_five_line_osd.v:478` | 全文仅声明+连接，无消费者 |
| `promax_audio_waveform.waveform_active` | `top:345,2009`；`promax:218` | 4 项 OR 树已用于 `rgb_out`，此 OR 为附加逻辑 |
| `thumbnail_view_reader.focus_border/line_mismatch` | `top:448-449,2202-2203` | 内部已用于 `pixel_rgb` |
| `lrc_five_line_osd.tl_w0..tl_w4` | `lrc_five_line_osd.v:178,190-194` | 5 个窗口输出全未用；`lyric_timeline` 的 `win_idx_*` 实测已被 DCE（seq=48，若窗口存在需 ≥95） |

---

## 5. 逐项优化措施

> **收益口径**：全部为**静态估算**，须以「同源码、同策略（`area_prior`）、同口径重新 gate」验证。**估算不得写成签核结果。**
> **不变量**：不删 CRC/长度/绑定/魔数校验，不改像素输出行为，不改 HS/VS/DE，不动加密 SDRAM/HDMI IP 内部。

### A 组｜确定可删除（零/低风险，逐位等价已证）

---

#### M1｜`song_index_db`：3 位索引误建 8:1 mux → 收窄为 4:1 ★最高性价比

- **位置**：`src/SD/song_index_db.v:71`（`reg [2:0] chk_idx;`）、`:144-148`（`cover_entry_bad`）
- **问题**：`e_cov_cl`/`e_cov_by` 声明为 `[0:MAX_SONGS-1]`（`:86-87`，`MAX_SONGS=4` @ `:30`），却被 **3 位** `chk_idx` 索引 → 综合器必须建 **8:1** mux（索引 4~7 恒越界但工具无法证明）。独立位宽 = 1 + 32 + 32 = 65 bit。
- **等价证明**：唯一消费点 `:302` 位于 `else` 分支，该分支条件为 `chk_idx < hdr_count[2:0]`（`:299`）。`hdr_count` 在 `:285` 已被校验 `1 ≤ hdr_count ≤ SIDX_MAX_SONGS(=4)`，否则 `fin_err <= SIDX_ERR_COUNT`。故进入 `else` 时 `chk_idx ≤ 3`，**`chk_idx[2]` 恒为 0**。`chk_idx` 初值 `3'd0`（`:291`），每拍 +1（`:304`）。
- **改法**：`cover_entry_bad` 内四处索引改 `[chk_idx[1:0]]`。
- **预估 LUT 收益**：8:1→4:1 约省 1 LUT4/bit × 65 bit ≈ **60~70 LUT**
- **影响功能范围**：无（判据一字未改，簇号范围校验完整保留）
- **风险等级**：**低**
- **分类**：**确定可删除**

---

#### M2｜`lrc_five_line_osd`：128-bit 掩码 mux 只为取 8 bit ★最大单点收益

- **位置**：`src/display/lrc_five_line_osd.v:379`（`reg [127:0] sel_glyphs;`）、`:411`（默认 `128'd0`）、`:454-455`（`(live_valid && (live_slot==sel_slot)) ? live_glyphs : 128'd0`）、`:462-463`（消费）
- **问题**：128-bit 2:1 mux ≈ **128 LUT4**（每 bit 一个 LUT4），之后才做 16:1 8-bit 选字（≈32 LUT），共 ≈160 LUT，**只为产出 8 bit**。
- **等价证明**：`cond==0` 时原路径 `glyph_at(128'd0, idx) == 0`，新路径 `gid_sel == 0`；`cond==1` 时两者同为 `live_glyphs[8*idx +: 8]`。**两条分支逐位相同 → 像素输出逐位相同。**
- **改法**：把选字节提到掩码之前 —— 先 `live_byte = live_glyphs[8*char_nxt[3:0] +: 8]`（32 LUT），再做 8-bit 条件选择（8 LUT），删除 `sel_glyphs`。
- **预估 LUT 收益**：160 − 40 ≈ **120 LUT**
- **影响功能范围**：仅歌词字形像素，输出不变
- **风险等级**：**低**（建议仿真回读 `gid_nxt` 逐拍比对）
- **分类**：**确定可删除**

---

#### M3｜`lrc_five_line_osd`：行范围判定复用已有减法器

- **位置**：`:418-423`（生成 6 个 10-bit 加法器 `row_ycur[kk]+32/16` + 12 个 10-bit 比较器）；`:431-433`（**已有** `pixel_y - row_ycur[kk]` 减法器）
- **问题**：同一循环内既算了差值，又另建加法器与比较器做上下界判定。
- **等价证明**：`row_ycur` 最大 316（`slot_y` 最大 300 见 `:81-85`；`lerp_y` 输出 ∈[28,316]）。若 `pixel_y < row_ycur`，则 `dly = 1024-(row_ycur-pixel_y) ≥ 1024-316 = 708 > 32 ≥ H`，故 `dly < H` 天然排除下溢情形。`row_ycur==0` 时原条件退化为 `pixel_y < H`，与 `dly<H` 一致。
- **改法**：`dly = pixel_y - row_ycur[kk]`（复用），判定改为 `dly < H`（H 为编译期常量 16/32）；`sel_srow` 改用 `dly[4:1]` / `dly[3:0]`。
- **预估 LUT 收益**：删 6 个 10-bit 加法器(≈36) + 6 个 10-bit 比较器(≈36)，减 6 个 5-bit 常量比较(≈18) ⇒ **≈40~70 LUT**
- **影响功能范围**：无（像素输出等价已证）
- **风险等级**：**低**
- **分类**：**确定可删除**

---

#### M4｜`lrc_five_line_osd`：`row_pres[0:5]` 数组可由 `row_idx` 推导

- **位置**：`:200-201`（声明）、`:239-240,270-271,274-275,312-313,328-329,333-334`（12 处赋值）、`:419`、`:447-452`、`:450-453`（`line_glyph_rd_addr` case）
- **不变量**：**`row_pres[k] ≡ ~row_idx[k][7]`**。依据 `rel_row`（`:120-132`）只返回两类值 —— 有效值 `v[7:0]` 且 `:127` 保证 `v ≤ 127`（bit7=0）；无效值 `LRC_ROW_INVALID = 8'hFF`（`:70`，bit7=1）。逐一核对全部赋值点均满足。
- **改法**：删 `row_pres` 数组与 12 处赋值；`:419` 改 `row_idx[kk][7] == 1'b0`；`:447-452` 改按 `row_idx[k][7]` 掩码取低位。
- **预估 LUT 收益**：消除 12 处 8-bit `!= 0xFF` 比较（`:313`/`:329` 各 6 处）≈ **15~40 LUT** + 6 FF
- **影响功能范围**：无（不变量恒成立）
- **风险等级**：**低**
- **分类**：**确定可删除**

---

#### M5｜`lrc_five_line_osd`：`sel_climit` 重复计算

- **位置**：`:434-435` 定义 `sel_climit = sel_scale ? (is_mv ? 5'd8 : 5'd10) : 5'd16`；`:438-439` 紧邻处**又算一遍**完全相同的表达式
- **改法**：`:439` 改用 `sel_climit`。
- **预估 LUT 收益**：**3~6 LUT**
- **影响功能范围**：无　**风险等级**：极低
- **分类**：**确定可删除**

---

#### M6｜`s6_video_layer`：12-bit 宏与 10-bit 信号比较

- **位置**：`src/video/s6_video_layer.v:108-112`；宏定义在 `src/include/playback_layout.vh`（全部 12-bit：`PLAY_MEDIA_X0=24`、`PLAY_MV_X1=344`、`PLAY_MEDIA_Y0=28`、`PLAY_MEDIA_Y1=268`）；`raw_x/raw_y/out_y` 为 10-bit（`:26`）
- **等价证明**：`raw_x ≤ 639 < 1024`，高 2 位恒 0；四个常量均 < 1024 ⇒ `{2'b00,raw_x} >= 12'd24` 与 `raw_x >= 10'd24` 在 `raw_x∈[0,639]` 上**逐位等价**。
- **改法**：模块内定义 10-bit localparam（值不变）。
- **预估 LUT 收益**：8 个比较器各省 2 bit ⇒ **8~16 LUT**
- **影响功能范围**：无　**风险等级**：极低
- **分类**：**确定可删除**

---

#### M7｜`thumbnail_view_reader`：12-bit 减法器只判零

- **位置**：`src/display/thumbnail_view_reader.v:230`（`pending_returns = issued_count_mem - returned_count_mem`），唯一使用点 `:232-233` 仅判 `== 0`
- **等价证明**：无符号下 `a-b==0 ⟺ a==b`，**对任意 a,b 成立**（含 `returned > issued` 病态情况，两种写法都判非 0，行为完全一致）。
- **预估 LUT 收益**：**≈12 LUT**　**风险等级**：极低　**分类**：**确定可删除**

---

#### M8｜`fat32_volume_scanner`：目录 8.3 文件名匹配公共项未提取

- **位置**：`src/SD/fat32_volume_scanner.v:313-361`，5 个匹配分支
- **重复项**（实测）：`sector_byte == 8'h20` 出现 **5 次**（`:314,324,334,344,354`）；`dir_name5/6/7 == " "` 出现 **5 次**；`.BIN` 扩展名三连比较出现 **3 次**（`:339-341,349-351,359-361`）
- **改法**：提取 `attr_ok` / `sp3_ok` / `ext_bin` 三个 wire，各分支只留真正区分性的 `name0..4` 比较。**纯布尔因式分解，输出逐位相同。**
- **预估 LUT 收益**：省 22 个 8-bit 等值比较 ≈ **40~60 LUT**，另加 AND 树缩短
- **影响功能范围**：无（文件名匹配结果不变）　**风险等级**：低
- **分类**：**确定可删除**

---

#### M9｜`song_index_db`：CRC 跨度判定 32 位加法+比较 → 3 位比较

- **位置**：`src/SD/song_index_db.v:103-105`
```verilog
103:    wire [31:0] crc_end     = 32'd64 + ({16'd0, hdr_count} << 6);
104:    wire        crc_span_ok = (hdr_count >= 16'd1) && (hdr_count <= SIDX_MAX_SONGS);
105:    wire        crc_in_span = crc_span_ok && (off >= 32'd64) && (off < crc_end);
```
- **问题**：`crc_end` 是 16→32 位移位 + 32 位加法链（≈20 LUT），驱动 32 位幅值比较器（≈10 LUT）。
- **等价证明**：`off ≥ 64` 时 `off < 64 + 64*count ⟺ off[8:6] < count`（因 `off = 64*entry + entry_off`，`entry_off < 64`）。`crc_span_ok` 已保证 `count∈[1,4]`，`byte_idx` 为 9-bit（`:82`）⇒ `off < 512`，两侧均落在 3 位内。
- **改法**：`off[8:6] < hdr_count[2:0]`，`crc_end` 删除。
- **预估 LUT 收益**：删 32-bit 加法器(20) + 32-bit 比较器(10)，增 3-bit 比较器(≈4) ⇒ **≈25 LUT**
- **影响功能范围**：无。**注意：这不是删 CRC** —— CRC 本体 `crc32_byte`(`:151-162`)、`crc_final` 比较(`:287`) 完整保留
- **风险等级**：低　**分类**：**确定可删除**

---

#### M10｜`fat32_media_loader`：扇区返回流 byte/index/error 冗余门控

- **位置**：`src/SD/fat32_media_loader.v:788-803`（scanner 三项）、`:813-828`（streamer 三项）
- **不可观测证明**：门控条件生效时对应 `valid`/`done` 必为 0（`:784`、`:796`）。消费端全部受保护：`fat32_volume_scanner.v:257,293`（`if (sector_valid && ...)`）、`:455,478,548`（`if (sector_done)`）、`fat32_file_streamer.v:159,167,204,228`。
- **改法**：`byte`/`byte_index`/`error` 三项直接透传 `arb_sector_*`；**保留 `busy`/`valid`/`done` 门控（这三个是功能性隔离，不可删）**。
- **预估 LUT 收益**：6 个 mux × (8+9+8) bit ≈ **≈50 LUT**
- **风险等级**：低。**注意**：若 TD 已做 dont-care 传播则收益为 0，**需实测**
- **分类**：**确定可删除（收益需实测）**

---

#### M11｜`mv_frame_scheduler`：`×100` 手写移位加 → 改回 DSP ★资源方向反转

- **位置**：`src/video/mv_frame_scheduler.v:29-33`
```verilog
29:    // *100 用移位加法实现，避免为一次定位请求额外占用 DSP。
32:    wire [31:0] rst_frame_x100 = {10'd0, rst_frame, 6'b0} +
33:                              {11'd0, rst_frame, 5'b0} + {14'd0, rst_frame, 2'b0};
```
- **问题**：两个 32-bit 加法器 ≈ 32 LUT，只为 `frame_count*100`。注释说明这是「为省 DSP 牺牲 LUT」的历史决策。
- **方向反转依据**：当前 **DSP 17/29，空闲 12**；而 **LUT 超限 610**。约束方向已改变。同工程 `s6_video_layer.v:29`（`×300`）与 `thumbnail_view_reader.v:272`（`×640`）**都已在用 DSP**，是正确做法。
- **预估 LUT 收益**：**50~64 LUT**；DSP **+1**（→18/29，仍余 11）
- **影响功能范围**：Seek 定位后的 `next_time` 时间基准
- **风险等级**：**中** —— ① 16×32 乘法在 `video_clk`(40ns) 下建立时间需跑 TD 时序；② DSP 增 1；③ 需验证 seek 落在 1 帧(100ms)边界附近时 `next_frame` 推进
- **分类**：**需确认后删除**

---

#### M12｜`lrc_cache`：128-bit 读口 → 字节地址读口（BRAM 8→2）

- **位置**：`src/display/lrc_cache.v:36`（`reg [127:0] line_glyph_mem [0:127];`）；消费者 `lrc_five_line_osd.v:462-463`（`glyph_at` 只取 8 bit，`:158-164`）
- **异常证据**：`lrc_cache` 报 519 LUT / **0 ripple / 0 seq** / 18 BRAM。BRAM 账可精确核对：`line_glyph_mem` 128×128 需 8 片（128-bit 口）、`line_time_mem` 128×32 需 2 片、`glyph_mem` 4096×16 需 8 片，合计 **18**，与报告**完全吻合** → 证实 128-bit 读口是 BRAM 主因。
- **改法**：改字节地址 `addr = {row_addr[6:0], col[3:0]}`（11-bit 地址、8-bit 数据）→ 2048×8 = 16384 bit → **2 片**
- **预估收益**：**BRAM 8→2（省 6）** + 可能消掉 519 LUT 中的宽读路径部分（估 **150~350 LUT**）
- **风险等级**：**高** —— 现有 `live_glyphs`（`:385`）是「行首整行预取」结构（`:394-406`），依赖 `line_glyph_rd_addr` 在整行内**保持稳定**（`:446-453` 由 `sel_slot` 驱动）。改字节地址后地址逐像素变化，**需重新推导 1 拍同步读时序**（`row_cache`/`render_row` `:467-475` 只补偿末级 `glyph_mem`）。
- **分类**：**需确认后删除 —— 明确不建议与本轮 LUT 门禁捆绑**

---

### B 组｜需确认后删除（收益大，需仿真或 TB 同步）

---

#### M13｜`song_index_db`：MV 四路 64-bit 零门控后移

- **位置**：`src/SD/song_index_db.v:124-127`（4 路 64-bit 门控 ≈ **256 LUT**）；`src/SD/fat32_media_loader.v:246-248`（再做 4:1 选 + 再门一次）
- **改法**：`song_index_db` 改为导出 4 位有效位 `song_mv_present`，零门控移到 loader 的 4:1 选**之后**只做一次。
- **等价性**：`valid && hdr_version==2 && e_has_mv[k]` 完整搬入 `song_mv_present[k]`，`index_mode` 门控位置不变 ⇒ `mv_metadata` 逐位相同（已核对 `s6_video_layer.v:29-31,74-75` 只用 `meta2[63:0]`）。
- **预估 LUT 收益**：−256 + 64 ≈ **净 190 LUT**
- **风险等级**：**中** —— 需同步 `sim/` 下 `tb_song_index_db.v`、`tb_mv_index.v`
- **分类**：**需确认后删除**

---

#### M14｜`fat32_media_loader`：`arb_sector_lba` 9:1 mux → 5:1

- **位置**：`src/SD/fat32_media_loader.v:750-754`（9:1 32-bit）、`:775`（`arb_sector_lba_q`）
- **不可观测证明**：所有 grant 都含 `arb_can_grant`（`:729-731`），后者**强制四个 `*_active` 全为 0** ⇒ 750-753 四分支在 grant 周期永不成立。而 `arb_sector_lba_q` 只在 `sector_req` 时被消费（`sd_sector_adapter.v:58-59`），该条件只在 grant 次拍成立。
- **可连带删除**：`audio_lba_latched`(`:208`)、`ui_lba_latched`(`:212`)、`lyric_lba_latched`(`:210`)、`bg_lba_latched`(`:214`) 及其写逻辑 —— **−128 FF**
- **预估 LUT 收益**：**40~70 LUT**　**风险等级**：中（需实测 TD 是否已传播；已确认 `arb_sector_lba_q` 仅 `:1195` 一处消费）
- **分类**：**需确认后删除**

---

#### M15｜`song_index_db`：`song_flags` 16 位 → 4 位

- **位置**：`src/SD/song_index_db.v:47`（`output reg [15:0] song_flags`）、`:322`；唯一消费点 `fat32_media_loader.v:281-282`（只取 bit[2] = lrc）
- **推论**：12 位（mv/pcm/cover 位）从未被读；`e_has_audio` 因此失效。
- **注意**：`e_has_cover` **不可删** —— 被 `cover_entry_bad`(`:145`) 用于簇号范围校验。
- **预估 LUT 收益**：**15~30 LUT** + 16 FF　**风险等级**：中（需同步 TB）
- **分类**：**需确认后删除**

---

#### M16｜`lrc_five_line_osd`：`lerp_y` / `rel_row` 用 `integer` 致 32-bit 乘加

- **位置**：`src/display/lrc_five_line_osd.v:135-156`（`lerp_y`，`d*ph` 为 32-bit signed 乘法）、`:120-132`（`rel_row`）
- **异常证据**：层次报告显示 `u_lrc_five_line_osd` **占用 1 个 DSP** ⇒ 该乘法未被常量折叠消除。
- **值域证明**：`a,b ∈ [28,316]`、`ph ∈ [0,16]`、`d ∈ [-76,0]`、`r ∈ [28,316]` ⇒ 全部可用 **11-bit signed** 承载。`rel_row` 的 `v ∈ [-3,130]` ⇒ 10-bit signed 足够。
- **预估 LUT 收益**：**60~150 LUT**，并**释放 1 个 DSP**
- **风险等级**：**中** —— 需完整波形仿真覆盖 16 帧动画全程；影响动画期间 y 坐标
- **分类**：**需确认后删除**

---

#### M17｜`playback_progress`：40-bit 除法通路收窄到 33-bit

- **位置**：`src/display/playback_progress.v:30-42`
- **不变量**：恢复余数除法保证 `remainder < divisor ≤ 2^32−1` ⇒ `remainder` 32-bit 足够；`rem_shift = {remainder[31:0], numerator[39]}` 33-bit 足够。`divisor = {8'd0, total_latched}` 高 8 位恒 0。`numerator` 必须保持 40-bit。
- **预估 LUT 收益**：**20~30 LUT**　**风险等级**：低，但**必须验证 `floor(cur*240/total)` 逐帧一致**
- **分类**：**需确认后删除**

---

#### M18｜`pcm_tap`：16-bit 幅值计算只取 9 bit

- **位置**：`src/audio/pcm_tap.v:32-37`；`target` 只用 `mag[15]` 与 `mag[14:7]`
- **改法**：利用 `max(a,b)[15:7] == max(a[15:7], b[15:7])`（单调性），改 9-bit 域运算。注意负数取反进位：`abs[15:7] = L[15] ? (~L[15:7] + (L[6:0]==0)) : L[15:7]`
- **预估 LUT 收益**：约 64 → 36 ⇒ **20~30 LUT**　**风险等级**：中（进位细节易错，须穷举/随机仿真）
- **影响**：`level` 只驱动 `ws2812_effects` 的 LED（`top:591`），**不在像素路径**
- **分类**：**需确认后删除**

---

#### M19｜`promax_audio_waveform`：双 bank 合并为单 64 深度 RAM

- **位置**：`src/display/promax_audio_waveform.v:42-43`（两个 `reg [7:0] sample_bankN [0:31]`）、`:96-99`（写）、`:171-173`（读）
- **综合日志证据**：`SYN-1027 ... ramread0_syn_4 read 32x8` 与 `ramread1_syn_4 read 32x8` ⇒ 两个独立 RAM。
- **等价性**：`:84-85` 保证读写 bank 恒不重叠 ⇒ 单 RAM `{write_bank, capture_count}` 索引空间天然分离，**逐位等价**。
- **预估 LUT 收益**：消除一个 32:1×8bit 读 mux ≈ **30~40 LUT**　**风险等级**：中（**有像素影响，需波形仿真**）
- **分类**：**需确认后删除**

---

### C 组｜冗余位宽收窄（确定可删为主，两项例外）

| 编号 | 位置 | 现状 | 实际范围 | 建议 | 收益 | 分类 |
|---|---|---|---|---|---|---|
| C1 | `thumbnail_view_reader.v:79` | `reg [11:0] line_y` | `:90` 已 clamp `< 479` | `[8:0]` | ~10 FF + 8 LUT | 确定可删 |
| C2 | `thumbnail_view_reader.v:96` | `wire [11:0] next_line_y` | `≤ 480` | `[9:0]` | ~6 LUT | 确定可删 |
| C3 | `thumbnail_view_reader.v:178` | `reg [7:0] gap_cnt_mem` | 参数 `BURST_GAP_CYCLES=12` | `[3:0]` | 4 FF + 4 LUT | 确定可删 |
| C4 | `thumbnail_view_reader.v:180-182` | 3×12-bit 计数 | 10 突发×128 = 1280 < 2^11 | `[10:0]` | 3 FF + 3 LUT | 确定可删 |
| C5 | `playback_progress.v:29` | `reg [1:0] state` | 只用 2 个状态 | 1 bit | 1 FF | 确定可删 |
| C6 | `lrc_five_line_osd.v:381` | `reg [4:0] sel_srow` | `dly[3:0]` / `dly[4:1] ≤ 15` | `[3:0]` | ~2 LUT | 确定可删（随 M3） |
| C7 | `lrc_five_line_osd.v:203` | `reg [3:0] row_cnt` | 只用 0/5/6 | 3 bit | 1 FF | 确定可删 |
| C8 | `seg_business_mux.v:20-21` | 33-bit 减法 | `remaining ≤ 287952000 < 2^29`；差值 `(-2^22, 2^29)` | 30-bit signed | ~6 LUT | 确定可删 |
| C9 | `seg_business_mux.v:27-28` | 32-bit 3:1 mux | 常量仅需 22 bit | 22-bit mux | ~20 LUT | 确定可删 |
| C10 | `promax_audio_waveform.v:48` | `reg [7:0] decimate_count` | `DECIMATE=12` | `[3:0]` | 4 LUT | **需确认**（改变波形采样节奏，**有像素影响**） |
| C11 | `promax_audio_waveform.v:36` | `reg [11:0] line_y` | 无 clamp，理论最大 480 | `[9:0]` | 2 FF | **需确认**（有像素影响） |
| C12 | `fat32_media_loader.v:338,410` | `reg [31:0] compression` 只用于 `==0` | — | 1-bit 粘滞位 | ~5 LUT + 31 FF | 确定可删 |
| C13 | `fat32_volume_scanner.v:107-108` | `fat_sectors`/`fat_count` **只写不读** | — | 删除 | 40 FF | 确定可删 |
| C14 | `fat32_media_loader.v:159,581` | `scanner_index_size` 全链未消费 | — | 删除 | 32 FF | 确定可删 |
| C15 | `fat32_media_loader.v:121` | `ERR_TIMEOUT` 零引用 | — | 删除 | 0（整洁） | 确定可删 |

**C 组小计：约 60~75 LUT + 120 FF**（C1~C9、C12~C15 为确定可删）

### D 组｜明确不可删（防止后续误判）

| 项 | 位置 | 原因 |
|---|---|---|
| CRC-32 校验 | `song_index_db.v:151-162,106,287`；`ui_asset_loader.v:130-157` | 已验收功能本体。**所有优化只改实现结构，判据一字不动** |
| BMP 头校验链 | `fat32_media_loader.v:404-414` | `data_offset>=54`、`planes==1`、`bit_count==24` 等 |
| 簇号范围校验 | `song_index_db.v:144-148` | M1 只改索引位宽 |
| `expected_pixel_count` 截断校验 | `fat32_media_loader.v:1162` | 已验收 |
| S7-04 双寄存器几何预计算 | `fat32_media_loader.v:397-398,1063-1067` | **陷阱**：看似 `required=3×expected` 可省寄存器，但会在 `header_valid` 路径重引入 32-bit 加法器，推翻 L384-396 记录的时序修复（曾致 WNS −0.125ns） |
| 仲裁隔离 `busy`/`valid`/`done` 门控 | `fat32_media_loader.v:780-828` | 功能性隔离，M10 只删 byte/index/error |
| `partition_lba` 寄存器 | `fat32_media_loader.v:562` | 端口未接但扫描器内部 `:462,466,506,511,524` 在用 |
| `promax` 颜色常量表 | `promax_audio_waveform.v:187-196` | 24-bit×8:1 常量 ROM ≈ 24 LUT4，**已是理论下限**，改动必改像素 |
| `vinyl_renderer` sin/cos | `vinyl_renderer.v:44-46` | 注释已说明改乘法会把 DSP 从 12 抬到 16~21 |
| UART / 诊断模式 | — | **已常量关闭，不能再计为面积收益**（`R0-signoff.md:75`） |

---

## 6. 按收益/风险排序的建议清单

> 缺口 = 17110 − 16500 = **610 LUT**；此外 slices 需从 9727 降到 ≤8820，**缺口 907 slices（更硬）**。

| 优先级 | 措施 | LUT 收益 | DSP | 风险 | 分类 | 批次 |
|---:|---|---:|---:|---|---|---|
| **1** | **M11** `×100` 改回 DSP | **50~64** | +1 | 中 | 需确认 | **C** |
| **2** | **M2** `lrc_five_line_osd` 128-bit mux 收窄 | **120** | 0 | 低 | **确定可删** | **A** |
| **3** | **M1** `song_index_db` 3→2 位索引 | **60~70** | 0 | 低 | **确定可删** | **A** |
| **4** | **M3** 行范围判定复用减法器 | **40~70** | 0 | 低 | **确定可删** | **A** |
| **5** | **M8** 文件名公共项提取 | **40~60** | 0 | 低 | **确定可删** | **A** |
| **6** | **M10** byte/error 冗余门控 | **≈50** | 0 | 低 | 确定（需实测） | **A** |
| **7** | **M4** 删 `row_pres` 数组 | **15~40** | 0 | 低 | **确定可删** | **A** |
| **8** | C 组位宽收窄 C1~C9、C12~C15 | **60~75** | 0 | 低~极低 | **确定可删** | **A** |
| **9** | **M9** CRC 跨度 3 位化 | **≈25** | 0 | 低 | **确定可删** | **A** |
| 10 | M5 `sel_climit` 复用 / M6 12→10-bit 宏 / M7 删减法器 | 23~34 | 0 | 极低 | 确定可删 | A |
| 11 | **M17** 除法通路收窄 | 20~30 | 0 | 低 | 需确认 | B |
| 12 | **M13** MV 门控后移 | **≈190** | 0 | 中 | 需确认（改 TB） | B |
| 13 | **M14** `arb_sector_lba` mux 收窄 | 40~70 | 0 | 中 | 需确认 | B |
| 14 | **M18** `pcm_tap` 9-bit | 20~30 | 0 | 中 | 需确认 | B |
| 15 | **M15** `song_flags` 收窄 | 15~30 | 0 | 中 | 需确认（改 TB） | B |
| 16 | **M16** `lerp_y`/`rel_row` 收窄 | 60~150 | **−1** | 中 | 需确认 | B |
| 17 | M19 双 bank 合并 | 30~40 | 0 | 中 | 需确认（**有像素**） | 兜底 |
| — | **M12** `lrc_cache` 字节读口 | 150~350 | 0 | **高** | 需确认 | **不建议本轮** |
| — | 死代码清理（§4.1/4.2） | **0** | 0 | 低 | 确定可删 | 先做（降噪） |

### 6.1 三批执行路径

**批次 A — 零像素影响、零/低风险（可立即做）**
M1 + M2 + M3 + M4 + M5 + M6 + M7 + M8 + M9 + M10 + C1~C9 + C12~C15
→ **合计 ≈ 325~430 LUT**，预计 **17110 → 约 16680~16785**

**批次 B — 需仿真验证的窄位宽/重构**
M11 + M17 + M16
→ **再减 130~245 LUT → 约 16440~16655** ✅ **达到 LUT ≤16500**

**批次 C — 资源结构置换（打通 slices 的真正关键）**
M13 + M14 + M15（需同步 2 个 TB）
→ **再减 245~290 LUT → 约 16200~16410**，为 slices ≤90% 腾出布局余量

**兜底**（若 slices 仍 >90%）：M18 + M19（≈50~70 LUT，需波形仿真）

> **重要提醒**：
> 1. **LUT 达标 ≠ slices 达标**。place slices 99.26% 是比 LUT 更硬的瓶颈；LUT 降到 16500 后 slices 通常仍在 95%+。**必须继续做 §6.2 的架构决策，不能靠 LUT 达标就宣布 R0 通过。**
> 2. **批次 A 的所有「确定可删」条目均已附逐位等价证明**，但仍建议对 `lrc_five_line_osd` 做整帧 `rgb_out` 逐拍 dump 比对作为回归基线。
> 3. **每批只改一个逻辑锥**，先补等价测试，再改实现，再比 gate（依据 `后续完整开发方案:279-296`）。
> 4. §3.5 的 8 项历史试验已否决，**禁止重走 `songidx_*` / `volume_scanner_fields` 方向**。

### 6.2 架构决策项（战略级，需用户确认）

| 选项 | 收益 | 代价与进入条件 |
|---|---|---|
| 保留器件与全部功能，集中优化三大热点 | 保持现有验收语义 | 需按批次 A/B/C 逐项实施 + 等价测试 + 完整物理构建，**不能承诺短时收敛** |
| 保留器件，精简非核心常驻显示 | 有机会较快释放布局余量 | 需用户确认具体功能取舍。**UART 已常量关闭、诊断模式已常量关闭，不能再计为面积收益** |
| 使用更大器件 | 获得明确容量余量 | 涉及板卡、引脚、IP 和时钟迁移，独立立项 |

> 依据 `R0-signoff.md:72-78` 架构决策表 + `prj/r0_signoff/seed5/metrics.json`（slices 9727/9800 = 99.26%）。

### 6.3 工具级调查项（不动 RTL，可能藏更大收益）

- **`u_video_rgb_to_axis_640x480` = 365 LUT / 26 seq**（`gate_latest_hier.area`）。模块仅 67 行，RTL 逻辑量约 15 LUT，**365 是 24 倍且 ripple=0**。最可能成因：area 优化器为满足 `video_clk` 40ns 建立时间复制了 24-bit `O_video_data` 寄存器锥。**建议先看 TD 的 Fanout / Logic Distribution 报告定性，再决定是否在 `final_rgb` 前插一级寄存器**（后者会改像素相位，禁止在本轮门禁中做）。
- **`axis_s_ready` 悬空**：`top:726` 声明、`:2980` 连接，**全文无第三处引用**；`video_rgb_to_axis_640x480.v:36` 的 `O_video_valid <= I_de` **从不按 ready throttle**。若 HDMI 核拉低 ready 会丢像素。**非 LUT 问题，但需登记。**

---

## 7. 未完成项与最小执行入口

- [ ] **批次 A** 实施 + 重新 gate，验证 LUT 下降且像素等价
- [ ] **批次 B** 实施 + 波形仿真（尤其 M16 动画 y 坐标）
- [ ] **批次 C** 实施 + 同步 `tb_song_index_db` / `tb_mv_index`
- [ ] **架构决策**（§6.2）—— 在错误容量假设上继续投入是最大浪费
- [ ] 当前源码重新 gate 达 LUT ≤16500、BRAM ≤60
- [ ] place/route 达 slices ≤90%、Setup/Hold WNS ≥0、TNS=0、0 违例、0 overflow
- [ ] 签核 bit + SHA-256 + JTAG + 原功能板级冒烟

**禁止事项**：
- 复用 `closeout_gate`（旧源码）或历史 place 宣称最终源码通过
- 把估算收益写成签核结果
- 仅删除文件名或换 seed 来声称降低器件利用率
- 用 false path 隐藏同域真实路径

---

## 8. 证据索引（文件:行）

| 证据 | 路径:行 |
|---|---|
| 器件总量（LUT 17110/87.30%、REG 11986、BRAM 58、DSP 17、PAD 75、PLL 2、GCLK 2） | `prj/r0_signoff/closeout_gate/gate_latest.area`（Utilization Statistics 段） |
| 模块级 LUT/REG/BRAM/DSP 全表 | `prj/r0_signoff/closeout_gate/gate_latest_hier.area:35-234` |
| 时序与资源汇总 | `prj/r0_signoff/closeout_gate/metrics.json`、`gate_latest.qor` |
| Rent 高复杂度模块、逻辑级数分布 | `prj/r0_signoff/closeout_gate/gate_latest.qor` |
| gate 最差路径（CRC 链） | `prj/r0_signoff/closeout_gate/gate_latest.timing` |
| place 实测（LUT 17856、slices 9727/99.26%、Setup +0.108、Hold −0.011） | `prj/r0_signoff/seed5/c3_place.area`、`c3_place.qor`、`metrics.json` |
| 死代码验证（0 elaborate / 0 实例） | `prj/r0_signoff/closeout_gate/td_20261008_161309.log`、`gate_latest_hier.area` |
| 历史 8 项试验全否决 | `prj/r0_opt/*/gate_latest.area` |
| 未签核状态与面积口径纪律 | `doc/开发资料/优化项目/优化资源优化/R0-signoff.md:3,52-62,72-78` |
| 顶层 include 与例化 | `src/top_tf_hdmi_audio.v:9-75,1141,1238,1422,1448,2012,2444,2677,2885,2950,3032` |
| M1 `chk_idx` 索引 | `src/SD/song_index_db.v:30,71,86-87,144-148,285,299-304` |
| M2 128-bit mux | `src/display/lrc_five_line_osd.v:158-164,379,411,454-455,461-463` |
| M3/M4/M5 行判定与 row_pres | `src/display/lrc_five_line_osd.v:70,120-132,135-156,200-201,312-334,379-381,418-463` |
| M6 12-bit 宏 | `src/video/s6_video_layer.v:26,108-112`、`src/include/playback_layout.vh` |
| M7/M8/C1~C4 | `src/display/thumbnail_view_reader.v:79,90,96,178,180-182,230-233`；`src/SD/fat32_volume_scanner.v:313-361` |
| M9/M13/M15 | `src/SD/song_index_db.v:47,103-105,124-127,151-162,322` |
| M10/M12/C12~C15 | `src/SD/fat32_media_loader.v:121,159,338,410,581,729-731,750-754,775,788-828` |
| M11 `×100` 移位加 | `src/video/mv_frame_scheduler.v:29-33` |
| M12 `lrc_cache` 128-bit 口 | `src/display/lrc_cache.v:36` |
| M16/M17 | `src/display/playback_progress.v:29-42` |
| M18/M19 | `src/audio/pcm_tap.v:32-37`；`src/display/promax_audio_waveform.v:36,42-43,48,84-85,96-99,171-173` |
| C6~C9 | `src/display/lrc_five_line_osd.v:203,381`；`src/display/seg_business_mux.v:20-28` |
| §6.3 待调查 | `src/video_rgb_to_axis_640x480.v:36,44-63`；`src/top_tf_hdmi_audio.v:726,2980` |
| Git 基线 | `git log --oneline` HEAD `428b777`；`git show 1e96f31 -- prj/VinylFPGA.al` |

---

> **本报告为盘点与方案结论，不含签核声明。** 全部 LUT 收益为静态估算，须经「同源码、同策略、同口径重新 gate」验证；批次 A 的条目均附逐位等价证明，但仍需仿真回归。所有「需确认后删除」项在确认前不得实施。
