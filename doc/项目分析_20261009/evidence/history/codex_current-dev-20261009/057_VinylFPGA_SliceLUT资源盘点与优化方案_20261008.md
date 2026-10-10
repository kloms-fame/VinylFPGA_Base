# VinylFPGA Slice/LUT 优先资源盘点与优化方案

> 日期：2026-10-08
> 器件：Anlogic EG4S20BG256
> 分析基线：`prj/r0_signoff/closeout_gate/gate_latest_hier.area`（gate 层，LUT 17110/19600）
> 门禁目标：LUT ≤ 16500、BRAM ≤ 60、route slices ≤ 90%
> 数据口径：所有 LUT/BRAM/DSP 数字均来自 `gate_latest_hier.area` 分层报告，文件引用为 `src/` 相对路径

---

## 1. 总体资源占用现状

### 1.1 器件资源总表（gate 阶段实测）

| 资源 | 已用 | 总量 | 占用率 | 门禁 | 余量 |
|---|---:|---:|---:|---:|---:|
| LUT | 17110 | 19600 | **87.30%** | ≤16500 | **超 610** |
| REG（触发器） | 11986 | 19600 | 61.15% | — | 充裕 |
| BRAM（9Kb） | 58 | 64 | **90.62%** | ≤60 | 超 -2 |
| DSP | 17 | 29 | 58.62% | — | 12 个空闲 |
| IO Pad | 75 | 188 | 39.89% | — | 充裕 |
| PLL | 2 | 4 | 50% | — | 2 个空闲 |
| GCLK | 2 | 16 | 12.5% | — | 充裕 |
| Slices（place 实测） | 9727 | 9800 | **99.26%** | ≤90% | **超 927** |

### 1.2 时序现状

| 指标 | gate | place(seed5) | 门禁 |
|---|---:|---:|---:|
| Setup WNS | −1.229 ns | +0.108 ns | ≥0 |
| Setup TNS | −5.616 ns | 0 | =0 |
| Hold WNS | +0.471 ns | **−0.011 ns** | ≥0 |
| Hold 违例端点 | 0 | 11 | 0 |
| Route overflow | — | 未收敛（拥塞终止） | 0 |

**结论：** LUT 超门禁 610 个（需砍 3.6%），BRAM 超 2 个，slices 在 place 后触及 99.26% 是当前最致命问题——高占用直接导致 route 拥塞、hold 修复被跳过。

---

## 2. 模块级 LUT 消耗排行（Top 25）

依据 `gate_latest_hier.area` 第 35–186 行分层数据，按 LUT 降序：

| 排名 | 模块实例 | 源文件 | LUT | REG | BRAM | DSP | 占总LUT |
|---:|---|---|---:|---:|---:|---:|---:|
| 1 | sd_card_bmp（含 FAT32/SD 协议栈） | `src/SD/sd_card_bmp.v` | **4036** | 3614 | 0 | 0 | 23.6% |
| 1a | └ fat32_media_loader | `src/SD/fat32_media_loader.v` | 3695 | 3391 | 0 | 0 | 21.6% |
| 1b | └─ fat32_volume_scanner | `src/SD/fat32_volume_scanner.v` | 803 | 1178 | 0 | 0 | 4.7% |
| 1c | └─ song_index_db | `src/SD/song_index_db.v` | 708 | 919 | 0 | 0 | 4.1% |
| 1d | └─ fat32_file_streamer | `src/SD/fat32_file_streamer.v` | 542 | 278 | 0 | 0 | 3.2% |
| 1e | └ sd_card_top | `src/SD/sd_card_top.v` | 243 | 180 | 0 | 0 | 1.4% |
| 2 | expansion_integration（扩展板集成） | `src/io/expansion_integration.v` | **2028** | 1023 | 0 | 2 | 11.9% |
| 2a | └ expansion_io_hub | `src/io/expansion_io_hub.v` | 737 | 446 | 0 | 0 | 4.3% |
| 2b | └ key_dip_monitor | `src/io/key_dip_monitor.v` | 306 | 198 | 0 | 0 | 1.8% |
| 2c | └ ws2812_effects | `src/io/ws2812_effects.v` | 251 | 96 | 0 | 2 | 1.5% |
| 2d | └ ir_nec_decoder | `src/io/ir_nec_decoder.v` | 228 | 138 | 0 | 0 | 1.3% |
| 2e | └ encoder_monitor（×2 EC） | `src/io/encoder_monitor.v` | 203 | 110 | 0 | 0 | 1.2% |
| 2f | └ buzzer_feedback | `src/io/buzzer_feedback.v` | 202 | 80 | 0 | 0 | 1.2% |
| 2g | └ ui_event_bus | `src/io/ui_event_bus.v` | 143 | 70 | 0 | 0 | 0.8% |
| 2h | └ param_csr | `src/io/param_csr.v` | 163 | 24 | 0 | 0 | 1.0% |
| 2i | └ ui_command_router | `src/io/ui_command_router.v` | 110 | 52 | 0 | 0 | 0.6% |
| 3 | ui_asset_loader（UIRES 装载） | `src/SD/ui_asset_loader.v` | **1413** | 1248 | 0 | 0 | 8.3% |
| 4 | hdmi_1_4b_transmitter（加密IP） | `src/hdmi1.4b_transmitter_core/` | 1251 | 1503 | 16 | 0 | 7.3% |
| 5 | s6_video_layer（含MV调度/黑胶渲染） | `src/video/s6_video_layer.v` | 622 | 310 | 0 | 4 | 3.6% |
| 5a | └ mv_frame_scheduler | `src/video/mv_frame_scheduler.v` | 298 | 129 | 0 | 1 | 1.7% |
| 6 | lrc_cache（歌词字形缓存） | `src/display/lrc_cache.v` | 519 | 0 | **18** | 0 | 3.0% |
| 7 | frame_read_write（SDRAM帧缓冲） | `src/SD/frame_read_write.v` | 469 | 359 | 4 | 0 | 2.7% |
| 8 | lrc_five_line_osd（五行歌词） | `src/display/lrc_five_line_osd.v` | 443 | 193 | 0 | 1 | 2.6% |
| 9 | wav_stream_player | `src/audio/wav_stream_player.v` | 441 | 293 | 8 | 0 | 2.6% |
| 10 | video_rgb_to_axis_640x480 | `src/video_rgb_to_axis_640x480.v` | 365 | 26 | 0 | 0 | 2.1% |
| 11 | seek_controller | `src/audio/seek_controller.v` | 337 | 230 | 0 | 0 | 2.0% |
| 12 | thumbnail_view_reader | `src/display/thumbnail_view_reader.v` | 293 | 246 | 2 | 1 | 1.7% |
| 13 | wallpaper_loader（背景装载） | `src/SD/wallpaper_loader.v` | 272 | 172 | 0 | 0 | 1.6% |
| 14 | playback_progress（进度计算） | `src/display/playback_progress.v` | 263 | 129 | 0 | 0 | 1.5% |
| 15 | ws2812_progress（灯环进度） | `src/io/ws2812_progress.v` | 181 | 118 | 0 | 0 | 1.1% |
| 16 | boot_layer（开机Logo） | `src/boot/boot_layer.v` | 144 | 53 | 10 | 3 | 0.8% |
| 17 | promax_audio_waveform（音谱） | `src/display/promax_audio_waveform.v` | 145 | 49 | 0 | 0 | 0.8% |
| 18 | timebase_48k | `src/audio/timebase_48k.v` | 140 | 88 | 0 | 0 | 0.8% |
| 19 | media_supervisor | `src/SD/media_supervisor.v` | 137 | 62 | 0 | 0 | 0.8% |
| 20 | seg_business_mux（数码管） | `src/display/seg_business_mux.v` | 123 | 92 | 0 | 0 | 0.7% |
| — | 其他（<120 LUT 模块合计） | — | ~2300 | ~1800 | 0 | 0 | ~13% |

### 1.3 BRAM 分布（58/64）

| BRAM 来源 | 数量 | 占比 |
|---|---:|---:|
| lrc_cache（歌词字形缓存） | 18 | 31.0% |
| hdmi_tx_controller（HDMI 加密核内部） | 14 | 24.1% |
| boot_layer（开机 Logo ROM） | 10 | 17.2% |
| wav_stream_player | 8 | 13.8% |
| frame_read_write（读写 FIFO） | 4 | 6.9% |
| thumbnail_view_reader | 2 | 3.4% |
| hdmi_edid / iic FIFO | 2 | 3.4% |
| **合计** | **58** | 100% |

---

## 3. 工程文件一致性问题（必须先修）

**依据：** 对比 `prj/VinylFPGA.al`（71 个文件）与 `gate_latest_hier.area` 报告的模块实例。

### 3.1 确定问题：主工程 .al 缺少今日新增模块

`prj/VinylFPGA.al` 的 `<File Path>` 列表中**没有**以下今日新增/活跃模块，但它们出现在分层面积报告中（说明归档 gate 用了完整 .al）：

- `src/SD/ui_asset_loader.v`（1413 LUT，第 3 大热点）
- `src/SD/lyric_loader.v`、`src/SD/wallpaper_loader.v`、`src/SD/wallpaper_ctrl.v`
- `src/display/lrc_five_line_osd.v`、`src/display/lrc_cache.v`、`src/display/lyric_timeline.v`
- `src/display/playback_progress.v`、`src/display/song_meta_osd.v`
- `src/video/s6_video_layer.v`、`src/video/mv_frame_scheduler.v`、`src/video/mv_stream_player.v`、`src/video/mv_sector_mux.v`
- `src/audio/seek_controller.v`、`src/audio/play_ctrl.v`、`src/audio/pcm_tap.v`、`src/audio/timebase_48k.v`、`src/audio/stream_session.v`
- `src/io/param_csr.v`、`src/io/param_knob_fsm.v`、`src/io/param_snapshot_bridge.v`、`src/io/ui_command_router.v`、`src/io/ui_event_bridge.v`
- `src/io/ws2812_driver.v`、`src/io/ws2812_effects.v`、`src/io/ws2812_progress.v`、`src/io/buzzer_feedback.v`、`src/io/led_business_driver.v`、`src/io/health_monitor.v`
- `src/io/browse_fsm.v`、`src/io/cover_navigation.v`
- `src/boot/boot_layer.v`、`src/boot/boot_logo_rom.v`
- `src/SD/media_probe.v`、`src/SD/media_supervisor.v`
- `src/include/ui_asset_defs.vh`、`src/include/lyric_asset_defs.vh`、`src/include/song_index_defs.vh`、`src/include/playback_layout.vh`、`src/include/exp_event_defs.vh`

**风险：** 用当前 `prj/VinylFPGA.al` 综合会得到一个**不含歌词/UIRES/MV调度/EC2参数**的裁剪固件，与今日所有验证过的行为不一致。提交 `1e96f31`（"trim redundant project source entries"）疑似在裁剪时误删了这些条目。

**处置：** 以 `prj/acceptance_20261008/VinylFPGA.al`（666 行完整清单）或 `prj/r0_signoff/gate_area_prior/VinylFPGA.al` 为基准，补回缺失的 `<File Path>` 条目。这是后续一切优化的前置条件。

---

## 4. 确定可删除项（死代码：在 .al 中但未被任何模块例化）

以下文件在 `prj/VinylFPGA.al` 列表中，但在 `gate_latest_hier.area` 的模块树中**完全不出现**——综合器已将其优化掉，不占物理面积，但：
- 拖慢综合/布局时间
- 增加工程噪音和误读风险
- 可能在未来被意外例化

| # | 文件 | 判断依据 | 预估收益 | 风险 |
|---|---|---|---:|---|
| D1 | `src/video_source_test.v` | hier.area 无实例；测试用彩条源，已被 `color_bar.v` 替代 | 0 LUT（已优化）；综合提速 | 无 |
| D2 | `src/SD/bmp_read.v` | hier.area 无实例；BMP 读取已整合进 `sd_card_bmp.v` | 0 LUT；综合提速 | 无 |
| D3 | `src/audio/audio_source_mux.v` | hier.area 无实例；音频选通在 `wav_stream_player` 内部完成 | 0 LUT；综合提速 | 无 |
| D4 | `src/display/frame_blend.v` | hier.area 无实例；转场已由 `video_fade_transition` 承担 | 0 LUT；综合提速 | 无 |
| D5 | `src/display/bilinear_8q8.v` | hier.area 无实例；未被 `thumbnail_view_reader` 调用 | 0 LUT；综合提速 | 无 |
| D6 | `src/io/debounce_filter.v` | hier.area 无实例；去抖统一用 `debounce_bank.v` | 0 LUT；综合提速 | 无 |
| D7 | `src/SD/seg_decoder.v` | hier.area 无实例；数码管译码在 `seg_scan.v` 内 | 0 LUT；综合提速 | 无 |
| D8 | `src/SD/ax_debounce.v` | hier.area 无实例 | 0 LUT；综合提速 | 无 |
| D9 | `src/IP/afifo_16_32_256.v` | hier.area 无实例；工程内未例化该异步 FIFO | 0 LUT；综合提速 | 无 |
| D10 | `src/IP/afifo_32_16_256.v` | 同上 | 0 LUT；综合提速 | 无 |
| D11 | `src/IP/PLL_HDMI_AUDIO.v` | hier.area 无实例；实际用 `sys_pll` + `video_pll` | 0 LUT；综合提速 | 无 |
| D12 | `src/hdmi_audio_tone_i2s_64fs.v` | hier.area 无实例；I2S 音频已走 HDMI PCM 通路 | 0 LUT；综合提速 | 无 |
| D13 | `src/I2S_receiver.v` | hier.area 无实例；无外部 I2S 输入 | 0 LUT；综合提速 | 无 |
| D14 | `src/include/global_def.v`（如未被 `include`） | 需 grep 确认 | 0 | 低 |

> **注意：** D1–D13 当前已被综合器优化为 0 LUT，移除它们**不直接释放面积**，但能消除工程误导、缩短编译时间。真正的面积收益来自第 5 节。

---

## 5. 结构性 LUT 优化措施（按收益/风险排序）

### 措施 O1：`fat32_media_loader` 五路仲裁流水化已落地，复核其 LUT 收益

- **依据：** 工作区未提交 diff 显示 `src/SD/fat32_media_loader.v` 新增了 `arb_req_snap_*` 五路寄存器打拍 + `arb_sector_req_q/lba_q` 输出寄存（diff 第 676–760 行）。这把 `probe_owner → 9 级 32bit LBA mux` 的 100 MHz 组合路径切成两段。
- **当前状态：** R0-signoff.md 记录 `arb_prereg` gate 为 17101 LUT，比 `volume_scanner_fields`（17196）低 95 LUT。
- **预估收益：** 已实现 −95 LUT；若最终源码重跑 gate 确认稳定，可固化。
- **影响范围：** SD 扇区仲裁，所有播放/浏览/歌词/背景数据通路。
- **风险：** 🟡 中——R0-signoff 记录修复前一次 UI 请求触发 3 次物理命令，修复后已通过 5 场景定向测试（`tb_r0_sector_arbitration`）。需重跑 14 项默认回归确认无回归。
- **分类：** 需确认后固化（已开发，待 gate 复核）。

### 措施 O2：`fat32_volume_scanner` 启动解析字段收窄

- **依据：** `src/SD/fat32_volume_scanner.v` 占 803 LUT / 1178 REG。今日提交 `428b777` "reduce fat32 volume scanner boot parsing cost" 已减少 97 行。R0-signoff 记录 `volume_scanner_fields` gate 为 17196 LUT。
- **优化方向：**
  - 启动时只解析 BPB 必要字段（每扇区字节数、簇大小、FAT 起始、根目录簇），其余延迟到首次访问。
  - 32 bit 扇区地址在启动扫描期可用 24 bit（SD 卡容量 < 8 GiB 时 LBA < 2^24）。
- **预估收益：** −80 ~ −150 LUT。
- **影响范围：** SD 卡挂载流程，不影响播放中数据通路。
- **风险：** 🟡 中——需保证 card_A_broken.img / 坏卡容错测试仍通过。

### 措施 O3：`song_index_db` 互斥 case 收窄

- **依据：** `src/SD/song_index_db.v` 占 708 LUT / 919 REG。`prj/r0_opt/songidx_case_mutex/` 和 `songidx_payload_regs/` 已有实验目录。
- **优化方向：**
  - 曲目索引表通常 ≤ 16 首，索引指针 4 bit 足够，当前若用 8 bit 可收窄。
  - 元数据 payload（歌名/歌手）串行读取而非并行寄存器堆。
- **预估收益：** −60 ~ −120 LUT。
- **影响范围：** 切曲、选歌索引。
- **风险：** 🟢 低——纯数据路径，时序余量充裕。

### 措施 O4：`ui_asset_loader` CRC/解析逻辑合并（R0 计划候选 #1）

- **依据：** `src/SD/ui_asset_loader.v` 占 1413 LUT / 1248 REG，是第 3 大热点。R0 方案第 7.2 节已锁定为优化候选 #1。
- **优化方向：**
  - 合并重复的 magic/version/geometry 比较逻辑（当前每个字段独立比较）。
  - CRC32 组合逻辑拆分：按字节流水，不做宽位并行。
  - 1248 REG 说明装载器内有大量锁存的字段描述符，可改为读后即用、不锁存全量。
- **预估收益：** −150 ~ −300 LUT。
- **影响范围：** UIRES 背景/歌词字形装载，仅后台低优先级。
- **风险：** 🟡 中——R0 方案明确禁止删除 CRC/长度/INDEX 绑定检查；需保留 `test_vinyl_packer.py` 全量回归。
- **注意：** 今日已有一次"逐字节 CRC 代替宽寄存字段"实验，面积反增 153 LUT 已回退。方向应是**合并重复比较 + 收窄锁存字段**，不是改 CRC 算法。

### 措施 O5：`expansion_integration` 内非常驻诊断逻辑清理

- **依据：** `src/io/expansion_integration.v` 占 2028 LUT，其中：
  - `key_dip_monitor` 306 LUT（去抖计数器占大头）
  - `ir_nec_decoder` 228 LUT
  - `buzzer_feedback` 202 LUT
  - `ws2812_effects` 251 LUT + `ws2812_progress` 181 LUT（合计 432 LUT 灯效）
- **优化方向：**
  - `quadrature_decoder` 稳定计数器已在工作区改为 `$clog2(STABLE_CYCLES+1)`（R0-B），×2 实例预计省 ~32 LUT + 32 REG，待提交。
  - `buzzer_feedback` 的音调发生逻辑可从 LUT 改为查表（`buzzer_feedback.v` 202 LUT 中大量是分频计数器比较）。
  - **需确认：** 灯效（WS2812）和蜂鸣器是否为竞赛必需功能？若为装饰性，可考虑通过 DIP 拨码在非演示时关闭综合（`generate if`），或整体砍掉释放 ~430 LUT。
- **预估收益：** 保守 −50 LUT（计数器收窄）；激进 −400+ LUT（砍灯效/蜂鸣器）。
- **影响范围：** 扩展板交互。
- **风险：** 🟠 高（砍功能）/ 🟢 低（仅计数器收窄）。
- **分类：** 计数器收窄=确定可做；砍灯效/蜂鸣器=**需用户确认**。

### 措施 O6：`lrc_cache` BRAM 占用复核（18 个 BRAM，BRAM 超限主因）

- **依据：** `src/display/lrc_cache.v` 占 519 LUT + **18 BRAM**，是 BRAM 超限（58/64，门禁 60）的最大单项。
- **优化方向：**
  - 歌词字形缓存当前用 18 个 BRAM 做 255 字形 × 8 位槽（提交 `cc57a03`）。若实际字形数 < 128，可减为 12 BRAM。
  - 与 `lrc_font_rom.v`（35 KB，固化 ROM）核对：是否有字形数据在 ROM 和 cache 间重复存储。
- **预估收益：** −4 ~ −6 BRAM（BRAM 从 58 降到 52~54，回到门禁内）。
- **影响范围：** 歌词渲染，无功能变化。
- **风险：** 🟡 中——需确认实际字形数量不超。
- **分类：** 需确认后删除。

### 措施 O7：`s6_video_layer` / `mv_frame_scheduler` 调度逻辑收窄

- **依据：** `src/video/s6_video_layer.v` 622 LUT，其中 `mv_frame_scheduler` 298 LUT。MV 三 bank 环形调度状态机有大量在途计数和代次比较。
- **优化方向：**
  - 当前 MV 仅 3 bank，bank 编号 2 bit 足够；若代码用 8 bit 可收窄。
  - `vinyl_renderer`（41 LUT + 2 DSP）黑胶旋转若仅装饰，可与 MV 模式互斥综合。
- **预估收益：** −30 ~ −60 LUT。
- **影响范围：** MV 播放时序。
- **风险：** 🟡 中——MV 在途帧计数错误会导致画面撕裂。

### 措施 O8：`video_rgb_to_axis_640x480` 宽度收窄

- **依据：** `src/video_rgb_to_axis_640x480.v` 占 365 LUT / 26 REG。组合逻辑偏重，可能是行计数/地址生成用了过宽位宽。
- **优化方向：** 640×480 行计数器 10 bit、列计数器 10 bit 已足够；检查是否有 16 bit 计数器残留。
- **预估收益：** −20 ~ −40 LUT。
- **影响范围：** HDMI 输出最后一级，风险低但需上板确认画面。
- **风险：** 🟢 低。

### 措施 O9：`seek_controller` 除法/比较逻辑简化

- **依据：** `src/audio/seek_controller.v` 337 LUT / 230 REG。Seek 涉及 ms 到扇区的换算，可能有宽位除法。
- **优化方向：** Seek 粒度若固定为 1 秒，可预先计算每首歌的扇区偏移表（在 `song_index_db` 里），seek 时只做查表+比较，不做运行时除法。
- **预估收益：** −40 ~ −80 LUT。
- **影响范围：** 快进/快退。
- **风险：** 🟡 中——需保证 seek 精度。

### 措施 O10：`boot_layer` 开机 Logo（10 BRAM + 3 DSP）

- **依据：** `src/boot/boot_layer.v` 144 LUT + 10 BRAM + 3 DSP，`boot_logo_rom.v` 达 266 KB。
- **优化方向：** 开机 Logo 仅在上电后显示数秒。若竞赛允许，可在综合时用 `define BOOT_LOGO_EN` 包裹，或缩小 Logo 分辨率释放 BRAM。
- **预估收益：** −10 BRAM + 3 DSP（若砍掉 Logo）；−4 BRAM（若缩小）。
- **影响范围：** 上电画面。
- **风险：** 🟠 高——开机 Logo 常是竞赛演示第一印象。
- **分类：** **需用户确认**。

---

## 6. 优化收益汇总与排序

| 优先级 | 措施 | 预估 LUT 收益 | 预估 BRAM 收益 | 风险 | 是否确定可做 |
|---:|---|---:|---:|---:|---|
| 1 | O1 仲裁流水化固化 | −95（已实现） | 0 | 中 | 待 gate 复核 |
| 2 | O4 ui_asset_loader 合并重复比较 | −150 ~ −300 | 0 | 中 | 确定（不删 CRC） |
| 3 | O2 volume_scanner 字段收窄 | −80 ~ −150 | 0 | 中 | 确定 |
| 4 | O5a 编码器计数器位宽收窄 | −32 | 0 | 低 | 确定（已在工作区） |
| 5 | O3 song_index_db 收窄 | −60 ~ −120 | 0 | 低 | 确定 |
| 6 | O9 seek_controller 查表化 | −40 ~ −80 | 0 | 中 | 需验证精度 |
| 7 | O8 video_rgb_to_axis 收窄 | −20 ~ −40 | 0 | 低 | 确定 |
| 8 | O7 mv_frame_scheduler 收窄 | −30 ~ −60 | 0 | 中 | 确定 |
| 9 | O6 lrc_cache BRAM 减容 | 0 | −4 ~ −6 | 中 | 需确认字形数 |
| 10 | O5b 砍 WS2812/蜂鸣器（可选） | −400+ | 0 | 高 | **需用户确认** |
| 11 | O10 砍/缩开机 Logo | 0 | −4 ~ −10 | 高 | **需用户确认** |
| — | D1–D13 删除死代码 .al 条目 | 0（已优化） | 0 | 无 | 确定 |

**保守路径（不砍功能）合计收益：** −500 ~ −780 LUT + 4~6 BRAM。
- 当前 LUT 17110 → 目标 ≤16500 需砍 610。
- 保守路径**刚好达标**（−500~−780），但余量为零。

**激进路径（砍装饰功能）：** 在保守路径基础上再 −400 LUT + 4~10 BRAM，可把 LUT 压到 ~16000（81.6%），BRAM 降到 ~48（75%），为 C4 组合取像腾出物理余量。

---

## 7. 建议执行顺序

### 第一步（前置，0 风险）
1. **修 `prj/VinylFPGA.al` 文件清单**，补回今日缺失的模块条目（第 3 节），否则后续优化都在错误工程上做。
2. **从 .al 移除 D1–D13 死代码文件**，综合提速。
3. **提交工作区现有改动**：`fat32_media_loader` 仲裁打拍 + `quadrature_decoder` 计数器收窄 + `c3_gate_export.tcl` 时序报告。

### 第二步（低风险结构性优化）
4. 跑 `O2 volume_scanner` → gate 对比 → 提交。
5. 跑 `O3 song_index_db` → gate 对比 → 提交。
6. 跑 `O8 video_rgb_to_axis` 位宽检查。
7. 每步固定循环：补定向测试 → 改 RTL → 跑 14 项回归 → gate 对比 → LUT 不降即回退。

### 第三步（中风险、高收益）
8. `O4 ui_asset_loader` 合并重复比较（R0 计划首选，预估最大单项收益）。
9. `O9 seek_controller` 查表化。
10. `O6 lrc_cache` BRAM 减容（需先 grep 确认实际字形数）。

### 第四步（需用户决策）
11. 是否砍 WS2812 灯效 + 蜂鸣器（−400 LUT）。
12. 是否缩小/删除开机 Logo（−4~10 BRAM）。
13. 若两轮后 LUT 仍 >16500，按 R0 方案触发架构决策：换 EG4S30/S40 器件。

### 放行检查（每步必做）
- `python tools/verify_core_acceptance.py --out sim/r0_opt_<step>` → 14/14 PASS
- `& tools/c3_gate_export.ps1 -OutDir prj/r0_opt/<step> -SynMode area_prior`
- `python tools/check_stage_resource_budget.py prj/r0_opt/<step>/gate.qor --max-lut 16500 --max-bram 60`
- Setup WNS 不恶化超过 0.20 ns
- 达标后才进 place/route；route slices ≤90% 才允许 bitgen。

---

## 8. 关键依据索引

| 结论 | 数据来源 |
|---|---|
| LUT 17110/19600 (87.30%) | `prj/r0_signoff/closeout_gate/gate_latest_hier.area` 第 19 行 |
| BRAM 58/64 (90.62%) | 同上 第 21 行 |
| sd_card_bmp 4036 LUT | 同上 第 53 行 |
| expansion_integration 2028 LUT | 同上 第 72 行 |
| ui_asset_loader 1413 LUT | 同上 第 170 行 |
| lrc_cache 18 BRAM | 同上 第 130 行 |
| boot_layer 10 BRAM + 3 DSP | 同上 第 66 行 |
| Setup WNS −1.229 ns | `prj/r0_signoff/closeout_gate/metrics.json` 第 31 行 |
| place slices 99.26% | `R0-signoff.md` 第 58 行 |
| 仲裁流水化已省 95 LUT | `R0-signoff.md` 第 55 行（arb_prereg 17101 vs 17196） |
| .al 缺少新模块 | `prj/VinylFPGA.al` 71 个 File Path vs hier.area 模块树对比 |
| 优化门禁 LUT ≤16500 | `R0至最终交付方案` 第 100 行、`R0-signoff.md` 第 82 行 |
