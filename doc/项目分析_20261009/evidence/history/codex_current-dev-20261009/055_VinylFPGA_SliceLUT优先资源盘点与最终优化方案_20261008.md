# VinylFPGA Slice/LUT 优先资源盘点与最终优化方案

> 日期：2026-10-08
> 器件：Anlogic EG4S20BG256（EG4S20BG256，19600 LUT / 19600 REG / 64 BRAM9K / 29 DSP / 4 PLL）
> 分析范围：R0 收尾（未签核）后的**当前工作区源码**
> 数据口径：器件利用率一律取 area 报告的 `#lut ... out of 19600` 行；QoR 的 `#luts` 与 area 的 `#Total_luts` 仅作统计口径，**不用于门禁判定**
> 一句话结论：当前源码资源超门禁且时序未收敛；已验证过的结构优化试验**全部没有降低 LUT**；真正可落地的是「清理死代码（零 LUT 收益，只降噪）」+「针对 `ui_asset_loader` CRC 与 FAT32 栈的定向重构（需实现并重新综合验证）」+「器件/功能架构取舍」。

---

## 0. 关键前提与证据边界（务必先读）

**结论 0.1｜当前源码 ≠ `closeout_gate` 构建源码，两者只差一个文件。**

- 依据：对 `closeout_gate` / `gate_area_prior` / `seed5` 三份 `build_manifest.json` 的全部输入逐文件 SHA-256 与当前工作区比对，**131 个输入中仅 `src/SD/fat32_media_loader.v` 不一致**，其余 130 个文件哈希完全一致。
- 差异内容：扇区仲裁「请求/LBA 快照 + 单拍物理命令 + 完成 cooldown」流水重写，`git diff` 统计 **+101 / −27 行**（依据 `src/SD/fat32_media_loader.v:678-780`）。
- 清单登记哈希：`d138421bde31ab81de1a0b0e389761b21a63025688763acbe5f387e9677fbb78`（依据 `prj/r0_signoff/closeout_gate/build_manifest.json`）。
- **含义：本文所有 LUT / 时序数字来自 `closeout_gate`（旧源码），对当前源码只能作为上界参考，不能直接宣称最终源码签核。**

**结论 0.2｜R0 物理签核未通过。**

- 依据：`doc/开发资料/优化项目/优化资源优化/R0-signoff.md`（`signed_off=false`，无签核 bit，未烧录，用户已选择停止长构建）。

**结论 0.3｜门禁与现状。**

| 门禁项 | 阈值 | 现状 | 判定 |
|---|---|---|---|
| LUT | ≤ 16500 | 17110（87.30%） | **超 610** |
| BRAM | ≤ 60 | 58（90.62%） | 合格（接近上限） |
| route slices | ≤ 90% | place 已 99.26%，route 未收敛 | **超 927**，致命 |
| Setup / Hold WNS | ≥ 0 | gate Setup −1.229 ns / place Hold −0.011 ns | **不满足** |

---

## 1. 第一步交付：资料与代码核查

### 1.1 已核查资料

| 文档 | 作用 | 关键结论 |
|---|---|---|
| `VinylFPGA_后续完整开发方案_R0至最终交付_20261008.md` | R0→最终交付总纲 | 定义 R0-A/R0-B/R0-C 与资源门禁 |
| `VinylFPGA_最终后续开发方案_X2之后_核心链路优先_20261007.md` | X2 之后核心链路优先 | 核心链路优先级依据 |
| `R0-signoff.md` | R0 收尾与架构决策记录 | 未签核；gate 为中间证据；不得用 QoR `#luts` 代替 area 利用率行 |
| `VinylFPGA_SliceLUT资源盘点与优化方案_20261008.md` | 上一版分析稿（**存在口径问题**） | 需以本报告修订：试验收益未经验证、死代码结论不完整 |
| `VinylFPGA_X2后当前阶段收尾报告_20261008.md` / `VinylFPGA_深度资源审计与优化执行方案_复核修订版_20261007.md` 等 | 历史审计 | 作为背景，不作为签核依据 |

### 1.2 顶层例化与 `include` 关系

- 顶层：`src/top_tf_hdmi_audio.v`（3190 行），负责所有子模块例化与时钟/复位分发。
- 编译方式：`.al` 显式列出 **69** 个 `.v`；顶层再用 **54** 条 `` `include `` 把其余子模块并入同一编译单元（`src/top_tf_hdmi_audio.v:9-75`）；两者去重后共 **115** 个设计文件。
- 例化示例（顶层行号）：`sd_card_bmp` @1141、`ui_asset_loader` @1238、`lrc_cache` @1422、`media_supervisor` @1448、`frame_read_write` @2012、`wav_stream_player` @2444、`s6_video_layer` @2677、`lrc_five_line_osd` @2885、`hdmi_1_4b_transmitter_core_wrapper` @2950、`expansion_integration` @3032。
- 层级链路：`sd_card_bmp`(686 行) → `fat32_media_loader`(1213 行) → `{fat32_volume_scanner, fat32_file_streamer, sd_sector_adapter, song_index_db}`；`sd_card_bmp` → `sd_card_top` → `{sd_card_cmd, sd_card_sec_read_write, spi_master}`（依据 `src/SD/sd_card_bmp.v:586,666`；`src/SD/fat32_media_loader.v:555,607,640,1191`）。
- Git 核查：`1e96f31`（trim redundant project source entries）只删除 `param_csr.v` / `param_knob_fsm.v` / `param_snapshot_bridge.v` 三处**重复显式条目**（共 27 行），顶层仍在 `src/top_tf_hdmi_audio.v:22-24` 以 `` `include `` 纳入，**不是功能丢失**。

### 1.3 约束与时钟

- 约束文件：`constraints/timing.sdc` + `constraints/pin.adc`（**不是 XDC**）。
- 时钟：`clk` 50 MHz、`sd_card_clk` 100 MHz、`video_clk` 25 MHz、125 MHz 移位/HDMI 串行。
- PLL：`sys_pll`、`video_pll` 共 2 个（4 个资源中占 2），无 MMCM（Anlogic 口径为 PLL）。

---

## 2. 模块盘点表

> 数据来源：`prj/r0_signoff/closeout_gate/gate_latest_hier.area`（gate 层）。LUT/REG/BRAM/DSP 为该实例及其子层合计值。

| 模块实例 | 源文件 | 职责 | 主要子模块 | LUT | REG | BRAM | DSP |
|---|---|---|---|---:|---:|---:|---:|
| `top` | `top_tf_hdmi_audio.v` | 顶层，时钟/复位/总线分发 | 见下行 | 15363 | 12043 | 58 | 17 |
| `sd_card_bmp_m0` | `SD/sd_card_bmp.v` | SD 卡媒体装载总入口 | fat32_media_loader, sd_card_top | **4036** | 3614 | 0 | 0 |
| └ `fat32_media_loader_m0` | `SD/fat32_media_loader.v` | FAT32 扇区读取/仲裁/展开 | volume_scanner, file_streamer, sd_sector_adapter, song_index_db | **3695** | 3391 | 0 | 0 |
| └─ `u_volume_scanner` | `SD/fat32_volume_scanner.v` | 目录扫描建索引 | — | 803 | 1178 | 0 | 0 |
| └─ `u_song_index_db` | `SD/song_index_db.v` | 歌曲索引库 | — | 708 | 919 | 0 | 0 |
| └─ `u_file_streamer` | `SD/fat32_file_streamer.v` | 文件连续流读取 | — | 542 | 278 | 0 | 0 |
| └ `sd_card_top_m0` | `SD/sd_card_top.v` | SD 协议层 | sd_card_cmd, sd_card_sec_read_write, spi_master | 243 | 180 | 0 | 0 |
| `u_expansion_integration` | `io/expansion_integration.v` | 扩展板集成 | io_hub, key/ir/led/ws2812/param/ui_* | **2028** | 1023 | 0 | 2 |
| └ `u_expansion_io_hub` | `io/expansion_io_hub.v` | 编码器/开关集线 | encoder_monitor | 737 | 446 | 0 | 0 |
| └ `u_ir_nec_decoder` | `io/ir_nec_decoder.v` | 红外解码 | — | 228 | 138 | 0 | 0 |
| └ `u_key_dip_monitor` | `io/key_dip_monitor.v` | 拨码/按键监测 | debounce_bank | 306 | 198 | 0 | 0 |
| └ `u_ws2812_effects` | `io/ws2812_effects.v` | 灯效 | ws2812_driver | 251 | 96 | 0 | 2 |
| `u_ui_asset_loader` | `SD/ui_asset_loader.v` | UIRES 资源槽解析/CRC | — | **1413** | 1248 | 0 | 0 |
| `u_hdmi_1_4b_transmitter_core_wrapper` | `hdmi1.4b_transmitter_core/*.enc.v` | HDMI 1.4b 加密 IP | tmds/edid/audio 包 | 1251 | 1503 | **16** | 0 |
| `u_s6_video_layer` | `video/s6_video_layer.v` | MV/黑胶叠加层 | mv_frame_scheduler, vinyl_renderer | 622 | 310 | 0 | 4 |
| `u_lrc_cache` | `display/lrc_cache.v` | 歌词字形缓存 | — | 519 | 0 | **18** | 0 |
| `frame_read_write_m0` | `SD/frame_read_write.v` | SDRAM 帧读写缓冲 | frame_fifo_read/write, rfifo/wfifo | 469 | 359 | 4 | 0 |
| `u_lrc_five_line_osd` | `display/lrc_five_line_osd.v` | 五行歌词叠加 | lyric_timeline | 443 | 193 | 0 | 1 |
| `u_wav_stream_player` | `audio/wav_stream_player.v` | WAV 流播放 | — | 441 | 293 | 8 | 0 |
| `u_video_rgb_to_axis_640x480` | `video_rgb_to_axis_640x480.v` | RGB→AXIS 打包 | — | 365 | 26 | 0 | 0 |
| `u_seek_controller` | `audio/seek_controller.v` | 跳转控制 | — | 337 | 230 | 0 | 0 |
| `u_thumbnail_view_reader` | `display/thumbnail_view_reader.v` | 缩略图读取 | thumbnail_layout | 293 | 246 | 2 | 1 |
| `u_wallpaper_loader` | `SD/wallpaper_loader.v` | 背景装载 | — | 272 | 172 | 0 | 0 |
| `u_playback_progress` | `display/playback_progress.v` | 播放进度计算 | — | 263 | 129 | 0 | 0 |
| `u_ws2812_progress` | `io/ws2812_progress.v` | 灯环进度 | — | 181 | 118 | 0 | 0 |
| `u_boot_layer` | `boot/boot_layer.v` | 开机 Logo | boot_logo_rom | 144 | 53 | 10 | 3 |
| `u_promax_audio_waveform` | `display/promax_audio_waveform.v` | 音频波形 | — | 145 | 49 | 0 | 0 |
| `u_timebase_48k` | `audio/timebase_48k.v` | 48k 时基 | — | 140 | 88 | 0 | 0 |
| `u_media_supervisor` | `SD/media_supervisor.v` | 媒体故障恢复 | — | 137 | 62 | 0 | 0 |
| `u_sdram_rd_arbiter` | `SD/sdram_rd_arbiter.v` | SDRAM 读仲裁 | — | 16 | 9 | 0 | 0 |
| `U3` | `SD/sdram.v` | SDRAM 控制器 | sdr_as_ram, sdr_init_ref, sdr_wrrd | 128 | 453 | 0 | 0 |
| 其余小模块（seg/browse/cover/reset/sync/pll/pcm 等） | 多个 | 分散控制 | — | <150 each | — | — | — |

---

## 3. 资源占用数据表

### 3.1 器件总量（gate 实测）

| 资源 | 已用 | 总量 | 占用率 | 门禁 | 余量 |
|---|---:|---:|---:|---:|---:|
| LUT | **17110** | 19600 | **87.30%** | ≤16500 | **超 610** |
| REG（触发器） | 11986 | 19600 | 61.15% | — | 充裕 |
| BRAM（9Kb） | 58 | 64 | 90.62% | ≤60 | 合格（余 2） |
| DSP | 17 | 29 | 58.62% | — | 空闲 12 |
| IO Pad | 75 | 188 | 39.89% | — | 充裕 |
| PLL | 2 | 4 | 50.00% | — | 空闲 2 |
| GCLK | 2 | 16 | 12.50% | — | 充裕 |
| Slices（seed5 place 实测） | 9727 | 9800 | **99.26%** | ≤90% | **超 927** |

> 口径说明：本表 `17110` 为 area 利用率行 `#lut ... out of 19600`；同一次 gate 的 QoR `#luts` = 13568、area `#Total_luts` = 13568 属统计口径，**不用于门禁**（依据 `R0-signoff.md`「不能用 QoR 的 `#luts` 或 area 的 `#Total_luts` 代替 area 利用率行」）。

### 3.2 模块级 LUT / REG 排行（Top 15，来自 `gate_latest_hier.area`）

| 排名 | 模块实例 | LUT | REG | BRAM | DSP | 占总 LUT |
|---:|---|---:|---:|---:|---:|---:|
| 1 | `sd_card_bmp_m0`（含 FAT32/SD 栈） | 4036 | 3614 | 0 | 0 | 23.6% |
| 2 | `u_expansion_integration` | 2028 | 1023 | 0 | 2 | 11.9% |
| 3 | `u_ui_asset_loader` | 1413 | 1248 | 0 | 0 | 8.3% |
| 4 | `u_hdmi_1_4b_transmitter_core_wrapper`（加密 IP） | 1251 | 1503 | 16 | 0 | 7.3% |
| 5 | `u_s6_video_layer` | 622 | 310 | 0 | 4 | 3.6% |
| 6 | `u_lrc_cache` | 519 | 0 | 18 | 0 | 3.0% |
| 7 | `frame_read_write_m0` | 469 | 359 | 4 | 0 | 2.7% |
| 8 | `u_lrc_five_line_osd` | 443 | 193 | 0 | 1 | 2.6% |
| 9 | `u_wav_stream_player` | 441 | 293 | 8 | 0 | 2.6% |
| 10 | `u_video_rgb_to_axis_640x480` | 365 | 26 | 0 | 0 | 2.1% |
| 11 | `u_seek_controller` | 337 | 230 | 0 | 0 | 2.0% |
| 12 | `u_thumbnail_view_reader` | 293 | 246 | 2 | 1 | 1.7% |
| 13 | `u_wallpaper_loader` | 272 | 172 | 0 | 0 | 1.6% |
| 14 | `u_playback_progress` | 263 | 129 | 0 | 0 | 1.5% |
| 15 | `u_ws2812_progress` | 181 | 118 | 0 | 0 | 1.1% |

> FAT32 栈合计（`fat32_media_loader` ∪ `sd_card_top` + `sd_card_bmp` 自身逻辑）≈ 4036 LUT，占全设计约 1/4，是**第一热点**；`expansion_integration` 与 `ui_asset_loader` 次之。三者合计 ≈ 7477 LUT，占全设计约 44%。

### 3.3 BRAM 与 DSP 归属

| 资源 | 归属 | 数量 |
|---|---|---:|
| BRAM (58) | `u_lrc_cache` 18、HDMI wrapper 16、`u_boot_layer` 10、`u_wav_stream_player` 8、`frame_read_write` 4、`u_thumbnail_view_reader` 2 | 58 |
| DSP (17) | `u_s6_video_layer` 4、`u_boot_layer` 3、`u_pcm_volume_fade` 2、`u_brightness_contrast_adjust` 2、`u_video_transition_apply` 2、`u_expansion_integration` 2、`u_lrc_five_line_osd` 1、`u_thumbnail_view_reader` 1 | 17 |

### 3.4 时序现状（关键路径）

| 项 | gate（closeout_gate） | place（seed5） | 门禁 |
|---|---:|---:|---:|
| Setup WNS | **−1.229 ns** | +0.108 ns | ≥0 |
| Setup TNS | −5.616 ns | 0 | =0 |
| Setup 违例端点 | 28 | 0 | 0 |
| Hold WNS | +0.471 ns | **−0.011 ns** | ≥0 |
| Hold 违例端点 | 0 | 11 | 0 |
| route overflow | 未收敛（拥塞终止） | — | 0 |

**gate 最差 5 条路径（依据 `closeout_gate/gate_latest.timing`）：**

| Slack | 起点 | 终点 | 定位 |
|---:|---|---|---|
| −1.229 ns | `u_ui_asset_loader/slot_cnt_reg[3]` | `u_ui_asset_loader/slot_crc_ok_reg.d` | `ui_asset_loader.v` CRC 组合链，9 级逻辑 |
| −0.863 ns | `frame_fifo_write_m0/write_cnt_reg[0]` | `frame_fifo_read_m0/state_reg[2]` | 帧读写 FIFO |
| −0.681 ns | `u_ui_asset_loader/slot_cnt_reg[3]` | `u_ui_asset_loader/hdr_crc_ok_reg.d` | 同上 CRC 链 |
| −0.174 ns | `frame_fifo_write_m0/write_cnt_reg[0]` | `u_thumbnail_view_reader/burst_base_mem_reg[*].ce` | 缩略图 CE 组合 |
| −0.170 ns | `sd_card_sec_read_write_m0/state_reg[8]` | `u_ui_asset_loader/slot_line_ok_reg.d` | SD→UI 跨段 |

> 结论：**时序最差点集中在 `ui_asset_loader` 的 CRC 组合累加/比较链**（`src/SD/ui_asset_loader.v:130-157,752`），其次是帧 FIFO 与缩略图；这与 LUT 热点高度重叠，说明「降 LUT」与「收时序」可以共用同一批重构目标。

### 3.5 已实测优化试验一览（全部在 `prj/r0_opt/`，gate 阶段）

> 统一以面积利用率行 `#lut` 对比基线 `closeout_gate` = 17110。**没有一项低于基线，也没有一项把 LUT 降到门禁 16500 以下。**

| 试验目录 | #lut | 相对基线 | REG | Setup WNS | 判定 |
|---|---:|---:|---:|---:|---|
| `closeout_gate`（基线，旧源码） | 17110 | 0 | 11986 | −1.229 ns | 参考 |
| `arb_prereg` | 17101 | −9 | 11853 | −1.231 ns | 无有效收益（slices/违例恶化） |
| `volume_scanner_fields` | 17196 | +86 | 11820 | −1.198 ns | **否决** |
| `arb_input_reg` | 17264 | +154 | 11985 | −0.727 ns | **否决** |
| `packio` | 17259 | +149 | 11820 | −1.225 ns | **否决** |
| `ui_asset_loader` | 17321 | +211 | 11820 | −0.756 ns | **否决** |
| `songidx_input_pipe` | 17460 | +350 | 11835 | −1.480 ns | **否决** |
| `songidx_case_mutex` | 17779 | +669 | 11826 | −1.126 ns | **否决** |
| `songidx_payload_regs` | 18219 | +1109 | 12588 | −1.200 ns | **否决** |

**结论 3.5｜** 旧稿把这些试验列为「确定收益」不成立；它们必须标注为「**试验已否决**」。后续任何优化都必须以「同源码、同策略、同口径重新 gate」为唯一收益证据。

---

## 4. 死代码与冗余分析

> 判定方法：① 全树扫描模块定义与实例化；② 与 `gate_latest_hier.area` 综合层级交叉验证；③ 核对 `.al` / 顶层 `` `include ``。

### 4.1 确定可删除（无任何实例化，删除不改变当前综合结果）

**A 类：进入编译（在 `.al` 中或被顶层 include），但从未被实例化——综合已优化为 0 面积，删除只减少分析/综合噪音与维护面。**

| 文件 | 定义模块 | 引用位置 | 判定依据 |
|---|---|---|---|
| `src/hdmi_audio_tone_i2s_64fs.v` | `hdmi_audio_tone_i2s_64fs` | `.al:30` | 无实例；层级报告无此模块 |
| `src/I2S_receiver.v` | `I2S_receiver` | `.al:47` | 无实例 |
| `src/video_source_test.v` | `video_source_test` | `.al:80` | 无实例 |
| `src/SD/ax_debounce.v` | `ax_debounce` | `.al:89` | 无实例 |
| `src/SD/bmp_read.v` | `bmp_read` | `.al:98` | 已被 `fat32_media_loader` 取代（`sd_card_bmp.v:584`） |
| `src/IP/PLL_HDMI_AUDIO.v` | `PLL_HDMI_AUDIO` | `.al:236` | 无实例（仅注释出现） |
| `src/audio/hdmi_pcm_audio_bridge.v` | `hdmi_pcm_audio_bridge` | `.al:326` | 无实例；实际使用 `hdmi_pcm_source_bridge` |
| `src/display/frame_blend.v` | `frame_blend` | `.al:399` | 无实例 |
| `src/display/bilinear_8q8.v` | `bilinear_8q8` | `.al:456` | 无实例 |
| `src/io/debounce_filter.v` | `debounce_filter` | `.al:513` | 无实例（扩展板用 `debounce_bank`） |
| `src/IP/sdram.v` | `sdram_phy` | `.al:301` | 无实例；实际使用 `src/SD/sdram.v` 的 `sdram` |

**B 类：完全未进入编译（既不在 `.al`，也未被顶层 include）——磁盘上的孤立文件。**

| 文件 | 定义模块 | 判定依据 |
|---|---|---|
| `src/display/playback_line_buffers.v` | `playback_line_buffers` | 未在 `.al`、未被 include、无实例 |
| `src/display/playback_line_reader.v` | `playback_line_reader` | 同上 |
| `src/display/playback_view_ctrl.v` | `playback_view_ctrl` | 同上 |

> 说明：`src/include/global_def.v` 虽不在 `.al`，但被 `src/SD/sdram.v` 以 `` `include `` 引用，属共享头文件，**不属孤立文件**。

### 4.2 需确认后删除（无实例但存在功能/回退语义）

| 文件 | 定义模块 | 现状 | 需确认点 |
|---|---|---|---|
| `src/display/lrc_osd.v` | `lrc_osd` | 被顶层 `` `include ``（`top_tf_hdmi_audio.v:58`），**无实例** | 旧单行歌词叠加；顶层注释（`top_tf_hdmi_audio.v:2801`）提到「否则保留旧单行 ROM 行为」——需确认该回退是否已废弃 |
| `src/display/lrc_renderer.v` | `lrc_renderer` | 被顶层 `` `include ``（`top_tf_hdmi_audio.v:62`），**无实例** | X4 三行歌词，已被 `lrc_five_line_osd` 取代；需确认无回退路径 |

> 两者删除**不改变当前综合结果**（无实例），但若后续要恢复旧歌词显示模式，需保留为储备；因此归入「需确认后删除」。

### 4.3 冗余实现核查：`sdram`

- `src/SD/sdram.v` 定义 `module sdram`（活，顶层 `U3` 例化，`gate_latest_hier.area` 有 `U3 sdram`，128 LUT）。
- `src/IP/sdram.v` 定义 `module sdram_phy`（死，无实例，层级报告无 `sdram_phy`）。
- 二者**不是同名重复定义**（模块名不同），不存在编译冲突；是「前代 PHY primitive 变体」残留，可按下表处理。

### 4.4 重要结论：死代码 ≠ LUT 收益

上述 A/B 类文件在综合时**已经成为 0 面积**（未被实例化即被裁剪），因此：

- **删除它们不会释放 LUT / BRAM / DSP。**
- 真实收益是：缩短读网表与综合时间、消除维护歧义、避免误引用。**不能把这些删除计入「LUT 下降」指标。**
- 要真正压低 LUT，必须走第 5 章 M3/M4/M5 的定向重构路线。

---

## 5. 逐项优化措施（预估收益 / 影响范围 / 风险等级）

> 收益口径：区分「**已实测**」「**试验已否决**」「**估算/待重新验证**」三档；估算不得写成签核结果。

### M1｜死代码与孤立文件清理（确定可删除）

- 动作：按 4.1 从 `.al` 移除 A 类文件条目、从顶层移除 `lrc_osd/lrc_renderer` 的 `` `include ``（见 M2）、归档 B 类孤立文件。
- **预估 LUT 收益：0（已实测为 0 面积）。** 收益为构建时间与可维护性。
- 影响功能范围：无（无实例）。
- 风险等级：**低**。
- 判断依据：4.1 表 + `gate_latest_hier.area` 无对应实例。
- 验证方式：清理后重新 gate，确认 LUT/BRAM/DSP 与清理前一致（预期一致），仅日志更短。

### M2｜旧歌词渲染链 `lrc_osd` / `lrc_renderer` 退役（需确认后删除）

- 动作：确认当前仅使用 `lrc_five_line_osd`（含 `lyric_timeline`）后，移除两条 `` `include ``。
- **预估 LUT 收益：0（当前无实例）。** 若未来恢复旧模式则不可删。
- 影响功能范围：旧单行/三行歌词显示回退路径。
- 风险等级：**中**（需人工确认无回退需求）。
- 判断依据：`top_tf_hdmi_audio.v:58,62,2801`；`gate_latest_hier.area` 仅有 `u_lrc_five_line_osd`。

### M3｜`ui_asset_loader` CRC 组合链流水化（需实现，**最高优先级**）

- 动作：把 `crc32_byte` 8 轮组合累加 + 末尾「取反比较期望值」拆成两级流水（例如先寄存 `crc_calc` 中间值，再下一拍比较 `slot_crc_ok` / `hdr_crc_ok`），消除 `slot_cnt → CRC 树 → 比较 → 寄存器` 的 9 级单周期路径。
- **预估 LUT 收益：待重新验证（可能小幅释放数十~百余 LUT，主收益在时序）。**
- 影响功能范围：UIRES 资源槽/公共头 CRC 校验时序；语义不变（字节吞吐晚 1 拍）。
- 风险等级：**中**（需保证 CRC 校验结果与现有一致，需回归 UIRES 资产验证）。
- 判断依据：`closeout_gate/gate_latest.timing` 最差 3 条中有 2 条（−1.229 / −0.681 ns）起止均在 `u_ui_asset_loader`；源码 `src/SD/ui_asset_loader.v:101,105,130-157,752`。
- 验证方式：`ui_asset_loader` 定向 testbench + `vinyl_packer.py verify`（UIRES CRC/INDEX 绑定）+ 重新 gate 看 WNS 与 LUT。

### M4｜FAT32 栈定向重构（需实现，**最大 LUT 块**）

- 目标模块：`fat32_media_loader`（3695 LUT）、`fat32_volume_scanner`（803）、`song_index_db`（708）、`fat32_file_streamer`（542），合计约占全设计 1/4。
- 注意：`songidx_case_mutex` / `songidx_input_pipe` / `songidx_payload_regs` / `volume_scanner_fields` 四个方向**已实测恶化，禁止重走**（第 3.5 节）。
- 可探索方向：`fat32_volume_scanner` 的状态机分支合并 / 字段裁剪、`song_index_db` 的索引存储位宽与判重逻辑、`fat32_media_loader` 与 `sd_card_top` 的握手精简（避免长组合跨段）。
- **预估 LUT 收益：待重新验证（潜在最大，但目前无一项已验证成功）。**
- 影响功能范围：SD 卡扫描、歌曲索引、文件流读取——核心链路。
- 风险等级：**高**（核心功能，需完整 RTL 回归 + 真实卡镜像验证）。
- 判断依据：`gate_latest_hier.area:53-58`；`src/SD/fat32_media_loader.v:555,607,640`；第 3.5 节否决清单。

### M5｜`expansion_integration` 精简（需确认）

- 目标：2028 LUT 的扩展板集成（io_hub 737、key_dip_monitor 306、ws2812_effects 251、ir_nec_decoder 228 等）。
- 可探索方向：未使用的扩展模式常量关闭（如已常量关闭的 UART/诊断**不可再计入收益**）、重复去抖/同步层级合并、状态机分支裁剪。
- **预估 LUT 收益：待重新验证。**
- 影响功能范围：扩展板按键/编码器/红外/灯效/参数 CSR。
- 风险等级：**中**。
- 判断依据：`gate_latest_hier.area:72-95`；`src/io/expansion_integration.v`。

### M6｜BRAM 减压（可选，仅在需要腾余量时）

- 现状 58 ≤ 60 已合格，但 `u_lrc_cache` 18 + HDMI wrapper 16 占大头。
- 可探索：`lrc_cache` 的槽宽/深度压缩（历史 `55a1cd2` 曾压缩歌词行缓存）。
- **预估 BRAM 收益：待重新验证；LUT 可能上升（用逻辑换 BRAM 通常反增 LUT），需权衡。**
- 风险等级：**中**。
- 判断依据：`gate_latest_hier.area:130`（lrc_cache 519 LUT / 18 BRAM）。

### M7｜器件/功能架构取舍（战略级）

- 现状：place slices 99.26% 是**比 LUT 更硬的瓶颈**；即使 LUT 降到 16500，slices 仍可能超 90%。
- 选项：① 保留器件与全部功能，集中攻 FAT32/UI/扩展三大块（长周期）；② 保留器件，精简非核心常驻显示（需用户确认取舍）；③ 换更大器件（独立立项）。
- 风险等级：**高**（涉及验收语义或板卡迁移）。
- 判断依据：`R0-signoff.md` 架构决策表；`prj/r0_signoff/seed5/metrics.json`（slices 9727/9800）。

### 明确「不计入收益」的项（避免重复计算）

- UART / 诊断模式：**已常量关闭**，不能再作为面积收益（依据 `R0-signoff.md`）。
- 仅删除文件名 / 换 seed：无法证明降低器件利用率（依据 `R0-signoff.md`）。

---

## 6. 按收益/风险排序的建议清单

| 优先级 | 措施 | LUT 收益 | 风险 | 确定性 | 是否需重新综合 |
|---:|---|---:|---|---|---|
| P0 | M1 死代码/孤立文件清理（A 类 + B 类） | 0（已实测 0 面积） | 低 | **确定可执行** | 是（验证 0 变化） |
| P1 | M3 `ui_asset_loader` CRC 流水化 | 待验证（主收益时序） | 中 | 估算 | 是 |
| P1 | M7 架构取舍决策（先于长构建） | — | 高 | 决策项 | 视方案 |
| P2 | M2 `lrc_osd`/`lrc_renderer` 退役 | 0 | 中 | 需确认 | 是 |
| P2 | M5 `expansion_integration` 精简 | 待验证 | 中 | 需确认 | 是 |
| P3 | M4 FAT32 栈重构 | 待验证（潜在最大） | 高 | 需实现 | 是 |
| P3 | M6 BRAM 减压 | 待验证（可能反增 LUT） | 中 | 需确认 | 是 |

**推荐执行顺序：** P0 清理（低风险、先做）→ M7 决策（避免在错误容量假设上继续投入）→ M3（同时收时序与试降 LUT）→ P2/P3 视 M3/M7 结论推进。所有措施一律以「同源码、同策略、同口径重新 gate」为唯一收益证据；**禁止复用 `closeout_gate` 或历史 place 宣称最终源码通过**。

---

## 7. 未完成项与最小执行入口

- [ ] 当前源码（含 `fat32_media_loader` 仲裁重写）重新 gate，达到 LUT ≤ 16500、BRAM ≤ 60。
- [ ] place / route 达到 slices ≤ 90%，Setup/Hold WNS ≥ 0、TNS = 0、0 违例、0 overflow。
- [ ] 签核 bit + 哈希 + JTAG + 原功能板级冒烟。
- [ ] M1 清理后回归 LUT 不变的对照 gate。

---

## 8. 证据索引（文件:行）

| 证据 | 路径:行 |
|---|---|
| 器件总量（LUT 17110/87.30%、REG 11986、BRAM 58、DSP 17、PAD 75、PLL 2） | `prj/r0_signoff/closeout_gate/gate_latest.area`（IO/LUT/Utilization 段） |
| 模块级 LUT/REG/BRAM/DSP | `prj/r0_signoff/closeout_gate/gate_latest_hier.area:35-186` |
| 时序与资源汇总 | `prj/r0_signoff/closeout_gate/metrics.json`、`gate.qor` |
| 最差时序路径（CRC 链） | `prj/r0_signoff/closeout_gate/gate_latest.timing:85-145` |
| place 资源/时序（slices 99.26%、Hold −0.011 ns） | `prj/r0_signoff/seed5/metrics.json`、`c3_place.area` |
| 源码哈希与「仅 loader 不一致」 | `prj/r0_signoff/closeout_gate/build_manifest.json` |
| 顶层 include / 例化 | `src/top_tf_hdmi_audio.v:9-75,1141,1238,1422,1448,2012,2444,2677,2885,2950,3032` |
| FAT32 仲裁重写 | `src/SD/fat32_media_loader.v:678-780,1191` |
| `ui_asset_loader` CRC 组合链 | `src/SD/ui_asset_loader.v:101,105,130-157,431,752` |
| `.al` 源文件清单（69 项） | `prj/VinylFPGA.al:14-570` |
| 试验对比（全部未降 LUT） | `prj/r0_opt/*/gate_latest.area`、`gate.qor` |
| 未签核状态与门禁口径 | `doc/开发资料/优化项目/优化资源优化/R0-signoff.md` |
| `1e96f31` 仅删重复条目 | `git show 1e96f31 -- prj/VinylFPGA.al`；`src/top_tf_hdmi_audio.v:22-24` |

---

> 本报告为**盘点与方案**结论，不含签核声明；所有「待验证」项必须经过重新综合与完整物理构建后才可写入签核证据。
