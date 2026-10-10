# VinylFPGA src/ 全量模块详解文档

> 生成日期：2026-10-07（北京时间）
> 分析基线：Git HEAD `9848757`（X2 r11-r12）
> 工程路径：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\src\`
> 器件：安路 Anlogic EG4S20BG256
> 顶层：`top`（`top_tf_hdmi_audio.v`）
> 本文逐文件解析 `src/` 下所有 RTL，说明每个模块的功能、端口语义、时钟域、数据通路与在系统中的角色。

---

## 0. 系统总览

### 0.1 一句话定位

VinylFPGA 是一个基于安路 EG4S20 FPGA 的"黑胶唱片造型"多媒体播放器：从 FAT32 SD 卡读取封面 BMP、WAV 音频、MV 视频帧和 LRC 歌词，在 FPGA 内部完成 SDRAM 四 bank 帧缓存、黑胶唱片旋转渲染、频谱/波形/歌词 OSD 叠加和转场特效，最终经 HDMI 1.4b 输出 640×480@60Hz 视频 + 48kHz 立体声音频。外设覆盖旋转编码器、红外遥控、DIP 开关、WS2812 灯效、蜂鸣器、6 位数码管和扩展板 UART 遥测。

### 0.2 顶层物理端口（`top_tf_hdmi_audio.v`）

| 类别 | 信号 | 方向 | 说明 |
|---|---|---|---|
| 时钟/复位 | `clk` | in | 50 MHz 板载晶振 |
| | `rst_n` | in | 低有效复位 |
| 母板按键 | `key1` / `key2` / `key3` | in | KEY3=B1，操作反馈音 |
| 母板拨码 | `sw1`/`sw2`/`sw3`/`sw4` | in | C8/C7/C6/C5 |
| 数码管 | `seg_sel[5:0]` / `seg_data[7:0]` | out | 6 位共阴/共阳段码 |
| HDMI | `HDMI_CLK_P`/`HDMI_D0_P`/`HDMI_D1_P`/`HDMI_D2_P` | out | TMDS 单端正端（负端由 PHY 处理） |
| | `HDMI_DDC_SCL` / `HDMI_DDC_SDA` | out/inout | DDC/EDID I²C |
| SD 卡 SPI | `sd_ncs`/`sd_dclk`/`sd_mosi`/`sd_miso` | out/out/out/in | SPI 模式 |
| J2 按键 | `exp_key_n[11:0]` | in | KEY1–KEY12，低有效 |
| J2 DIP | `exp_dip_n[5:0]` | in | DIP1–DIP6 |
| J2 编码器 | `exp_enc1_a/b/sw_n`、`exp_enc2_a/b/sw_n` | in | EC1 切歌、EC2 待 X5 调参 |
| J2 红外 | `exp_ir_rx` | in | NEC 接收 |
| J2 LED | `exp_led_n[3:0]` | out | LED1–4，低有效点亮 |
| J2 WS2812 | `exp_ws2812_data` | out | 单线 NRZ |
| J2 扩展 | `exp_ext_o[5:0]` | out | EXT1=蜂鸣波形，其余预留 |
| 蜂鸣器 | `board_buzzer_n` | out | H11，PNP，低电平鸣叫 |
| UART | `uart_tx` | out | 115200 8N1 遥测 |

### 0.3 时钟域

| 时钟 | 来源 | 频率 | 用途 |
|---|---|---|---|
| `clk` | 板载 | 50 MHz | 主域：UI 事件总线、命令路由、参数 FSM、WS2812、LED、UART |
| `sd_card_clk` | `sys_pll.clk0` | 100 MHz | SD 卡 SPI、FAT32、BMP/WAV/MV 读取、帧写 SDRAM |
| `ext_mem_clk` | `sys_pll.clk1` | 125 MHz | SDRAM 用户接口 |
| `ext_mem_clk_sft` | `sys_pll.clk2` | 125 MHz 180° | SDRAM 硬核相移时钟 |
| `video_clk` | `video_pll.clk0` | 25 MHz | 640×480 像素时钟、HDMI 核、I²S 接收 |
| `hdmi_5x_clk` | `video_pll.clk1` | 125 MHz | HDMI TMDS 10:1 串化 |
| `audio_mclk` | `PLL_HDMI_AUDIO.clk2` | 12.295 MHz | I²S 测试音主时钟 |

### 0.4 SDRAM 地址分区（21-bit word = 2 MiB × 4B = 8 MiB）

| 地址范围（word） | 大小 | 用途 |
|---|---|---|
| `[0, 307200)` | 1.17 MiB | 封面 bank 0（640×480×32bpp） |
| `[307200, 614400)` | 1.17 MiB | 封面 bank 1 |
| `[614400, 921600)` | 1.17 MiB | 封面 bank 2 |
| `[921600, 1228800)` | 1.17 MiB | 封面 bank 3 |
| `[1228800, 1305600)` | 300 KiB | MV bank 0（320×240×32bpp） |
| `[1305600, 1382400)` | 300 KiB | MV bank 1 |
| `[1382400, 1459200)` | 300 KiB | MV bank 2 |
| `[1459200, 2097152)` | 2.43 MiB | 预留（X4 歌词区将分配在此） |

---

## 1. `src/` 根目录（11 个文件）

系统级胶水、顶层集成、HDMI PHY、复位同步。

### 1.1 `top_tf_hdmi_audio.v` — 顶层集成

- **角色**：整个系统的顶层，例化所有 PLL、SD/BMP、帧缓存、SDRAM、音频、HDMI 核、PHY、数码管、J2 扩展板。
- **关键参数**：
  - `FRAME_PIXELS = 307200`（640×480）
  - `BUF0_ADDR..BUF3_ADDR = 0, 307200, 614400, 921600`
  - `MV_ADDR0/1/2 = 1228800, 1305600, 1382400`
  - `ECHO_TEST_ENABLE=1`：串口回显开关
  - `BUZZER_FEEDBACK_ENABLE=1`：蜂鸣反馈总开关
  - `S2_BOOT_ENABLE=1`：开机 logo 开关
  - `S3_J2_BROWSE_ENABLE=1`：J2 选曲事件开关
  - `S5_PLAY_ENABLE=1`：播放态控制开关
  - `S6_VIDEO_ENABLE=1`：MV/黑胶开关
- **复位逻辑**：`rst_all = ~rst_n | ~audio_pll_lock`，仅等音频 PLL lock。
- **include 策略**：通过 `` `include `` 直接引入 `expansion_integration.v` 及其子模块，避免 TD 工程文件列表遗漏。

### 1.2 `audio_arc_calculate.v` — HDMI ACR 时钟同步计算

- **参数**：`ACR_N = 6144`
- **输入**：`I_clk`、`I_rst`、`I_audio_valid`（音频样本有效脉冲）
- **输出**：`O_acr_valid`、`O_acr_cts[19:0]`、`O_acr_n[19:0]`
- **功能**：每 48 个音频有效样本输出一次 ACR（Audio Clock Regeneration）包，`N=6144`，使 HDMI 接收端能从 TMDS 时钟恢复出 48kHz 音频时钟。

### 1.3 `hdmi_audio_tone_i2s_64fs.v` — I²S 八音阶测试音发生器

- **参数**：`AMP=24'sd2000000`（幅度）、`NOTE_HOLD_FRAMES=24000`（每音 0.5s @48kHz）
- **输入**：`I_mclk`（12.288 MHz）、`I_rst`
- **输出**：`O_i2s_BCLK`、`O_i2s_LRCK`、`O_i2s_DOUT`
- **功能**：DDS 相位累加器产生 do/re/mi/fa/so/la/si/do（C4–C5）八音阶方波，左右声道复用同一样本，24-bit 左对齐到 64fs 时隙。
- **音符频率表**：do=261.63Hz、re=293.66Hz、mi=329.63Hz、fa=349.23Hz、so=392.00Hz、la=440.00Hz、si=493.88Hz、do'=523.25Hz。

### 1.4 `I2S_receiver.v` — I²S 接收器

- **输入**：`I_clk`（video_clk 25MHz）、`I_rst`、`I_i2s_BCLK`、`I_i2s_LRCK`、`I_i2s_DOUT`
- **功能**：在 25MHz 域对 BCLK/LRCK/DOUT 分别三拍同步，检测 BCLK 上升沿采样，输出 24-bit 左右样本和有效脉冲。用于把内部测试音送入 HDMI 核。

### 1.5 `hdmi_phy_warpper.v` — HDMI PHY 包装器

- **参数**：`DEVICE="EG"`
- **输入**：`I_pixel_clk`（25MHz）、`I_serial_clk`（125MHz）、`I_rst`、4 组 10-bit TMDS 字（ch0/ch1/ch2/clk）
- **输出**：4 对 TMDS 正端
- **功能**：把 10-bit TMDS 字交给 `lane_lvds_10_1` 做 10:1 串化，输出到 EG4 的 LVDS PHY。

### 1.6 `lane_lvds_10_1.v` — 10:1 LVDS 串化器

- **功能**：把并行 10-bit TMDS 字在 125MHz 串行时钟下串成 1-bit DDR 流，通过 EG4 的 OSERDES/LVDS 物理资源输出。共实例化 4 份（ch0/ch1/ch2/clk）。

### 1.7 `reset_sync.v` — 复位同步释放

- **功能**：第六讲优化一。把异步复位在目标时钟域同步释放，避免亚稳态。`rst_out = rst_n_synchronized`。

### 1.8 `sync_2ff.v` — 双触发器同步器

- **功能**：第六讲优化二配套。单比特电平两级同步器，用于跨时钟域的控制信号。

### 1.9 `startup_pulse.v` — 上电一次性脉冲

- **功能**：在 video_clk 域计数 100,000 周期（约 4ms）后输出一个单拍脉冲，触发 HDMI 核读取 EDID/DDC。

### 1.10 `video_rgb_to_axis_640x480.v` — RGB→AXI-Stream 转换器

- **输入**：`I_clk`、RGB/DE/hsync/vsync
- **输出**：AXI-Stream 主信号（`axis_tvalid`、`axis_tuser`=帧首、`axis_tlast`=第 640 像素、`axis_tdata`）
- **功能**：把视频时序输出转为 HDMI 加密核期望的 AXI-Stream 格式。未使用 `axis_s_ready` 回压。

### 1.11 `video_source_test.v` — 1080p 测试视频源（未使用）

- **状态**：在 `.al` 中 `AutoExcluded`，仅作备用测试图案生成器。

---

## 2. `src/audio/`（13 个文件）

音频播放链路：WAV 流 → PCM 处理 → HDMI 音频桥。

### 2.1 `wav_stream_player.v` — WAV 流播放器核心

- **参数**：`ADDR_WIDTH=12`（4096×16bit = 8KB BRAM 环形缓冲）、`SAMPLES_PER_SECTOR=256`（512B/2B）
- **数据格式**：16-bit signed little-endian PCM / 48kHz / 单声道
- **功能**：
  - 从 SD 卡按扇区读入 WAV 数据，写入 8KB BRAM 环形缓冲（格雷码指针）
  - 48kHz 时基从缓冲取样本输出 `sample_out[15:0]`
  - 检测 underrun（`cnt_underrun`）和 buffer-low
  - `stream_end`：FIFO 排空后输出单次 EOF 脉冲（X2 新增）
  - `target_sample`：seek 目标样本号（X2 新增）
- **时钟域**：`sd_card_clk` 100MHz

### 2.2 `play_ctrl.v` — 播放态控制器

- **时钟域**：`sd_card_clk`，与 `browse_fsm` 同域
- **功能**：
  - 选曲（`sel_song`）、播放/暂停（`play_active`/`paused`）、切曲（`track_step`）
  - 音量（`volume[7:0]`，范围 32–255，步进 16）
  - `end_mode` 三态：0=播完暂停、1=单曲循环、2=自动下一曲（KEY12 循环）
  - 接收 `stream_end` 和 `eof_policy`，按 end_mode 触发 next/replay/browse
- **输入 toggle**：来自 `ui_event_bridge` 的跨域脉冲

### 2.3 `seek_controller.v` — Seek/重播目标计算器（X2 新增）

- **时钟域**：`sd_card_clk`
- **功能**：只做三件事，不复制播放状态机：
  1. 接收红外 F8(+5s)/EA(−5s)/F6(重播) 脉冲
  2. 把时间偏移换算成目标样本号 `target_sample`，钳位 `[0, total_samples-1]`
  3. 输出 `seek_req` 和 `seek_target_ms` 给 `stream_session`
- **步长**：旋钮 ±2s/格（96000 样本），红外 ±5s（240000 样本）

### 2.4 `stream_session.v` — 播放代次切换器

- **时钟域**：`sd_card_clk`
- **功能**：停 FIFO 两端 → 排空不可抢占的存储事务 → 等待元数据稳定 31 拍 → 切换播放代次（generation）。用于切曲/seek/重播时丢弃旧 LBA 的在途数据，防止样本跳序。

### 2.5 `timebase_48k.v` — 48kHz 毫秒时基

- **功能**：全工程唯一的媒体时基。输入 `wav_sample_tick`（video_clk 25MHz 上的 48kHz 分数节拍），输出 `cur_time_ms[31:0]`。暂停时冻结。
- **消费者**：`lrc_osd`（歌词选行）、`seg_business_mux`（数码管 MM:SS）、`ws2812_effects`（进度条）、`seek_controller`（目标时间）。

### 2.6 `pcm_volume_fade.v` — 音量与淡入淡出增益

- **功能**：对 WAV PCM 施加用户音量（`volume[7:0]`）和转场淡入淡出 alpha。乘法结果先按 1/255 缩放，再按 1/255 缩放，回到 16-bit。保留完整 8×8 增益积，不中间舍入。

### 2.7 `sync_fade_gain.v` — 视频 alpha 到音频域同步

- **功能**：第十一讲。把视频域按帧边界锁存的 alpha 包络用 2FF 同步到音频域，避免一帧内跳变造成爆音。

### 2.8 `pcm_tap.v` — PCM 只读旁路抽头（X1B 新增）

- **功能**：挂在 `wav_stream_player` 的 `sample_out/sample_valid` 上，纯观测、不握手、不反压、不改 ready/valid。输出给 `ws2812_effects` 做音频律动包络。

### 2.9 `audio_source_mux.v` — 音频源选择器

- **功能**：第十一讲。WAV 播放优先于原有的 `pcm_media_tone` 琶音。ready 只回给被选中的音源，避免未选音源内部 FIFO 被意外排空。

### 2.10 `pcm_media_tone.v` — 六音阶琶音测试音

- **功能**：每个加载的 image bank 播放自己的六音阶琶音循环（C 大调上行、A 小调、五声音阶、低高摆动），切图时有听觉反馈。

### 2.11 `hdmi_pcm_source_bridge.v` — PCM 源到 HDMI 桥

- **功能**：通用 16-bit PCM 源 → M06 契约 → 安路 HDMI 1.4b 加密核 24-bit 接口。

### 2.12 `hdmi_pcm_audio_bridge.v` — HDMI PCM 适配层

- **功能**：第 3 课。把完赛工程原有的 `pcm_media_tone → m06_pcm_contract_adapter → hdmi_audio_symbol_core` 路径适配到当前 WAV 播放链路。

### 2.13 `m06_pcm_contract_adapter.v` — M06 PCM 契约适配器

- **功能**：M06 边界层。媒体特定源可以改旋律/音量/内容策略，但必须向 M07 呈现冻结的 PCM valid/ready 契约。

---

## 3. `src/boot/`（2 个文件）

### 3.1 `boot_layer.v` — 开机 Logo 像素替换层

- **位置**：像素链最末端（波形叠加之后、RGB→AXIS 之前）的纯像素替换层。
- **功能**：上电进入 `STATE_BOOT`，先显示片内 Logo 6 秒（`BOOT_HOLD_MS=6000`），保护窗 4 秒内忽略按键事件，8 秒超时退出。

### 3.2 `boot_logo_rom.v` — 开机 Logo 片上 ROM

- **参数**：`ADDR_BITS=15`
- **功能**：由 `tools/gen_boot_logo.py` 从 `doc/资源/开机logo透明背景.png`（640×480）生成的调色板 ROM。M4 阶段做了 banked 分组，省 6 块 BRAM（46→40）。

---

## 4. `src/display/`（16 个文件）

视频合成与 OSD 叠加层。

### 4.1 `vinyl_renderer.v` — 黑胶转盘视觉层（项目主题核心）

- **功能**：S6。纯组合像素层，只按 `(pixel_x, pixel_y)` 和 `phase` 生成黑胶盘面：同心圆纹路、中心标签、旋转角度。不读 SD/SDRAM，零 BRAM。无 MV 曲目时作为默认视觉。

### 4.2 `promax_audio_waveform.v` — 音频波形可视化

- **功能**：第十二讲。32 根从底部向上生长的柱，右侧保留一根独立峰值柱。只替换 RGB 像素，不改 de/vs 节拍。零 BRAM，时域幅度柱（**不是 FFT**）。

### 4.3 `lrc_osd.v` — 单行歌词 OSD

- **功能**：S5。按 `timebase_48k` 的 `cur_time_ms` 选行，从固化 `lrc_lines_rom` 取歌词文本，用 `lrc_font_rom` 的字模渲染到屏幕底部。本模块不做任何时间计数。当前是单份固化 ROM，切曲不换歌词（X4 将改为多曲装载）。

### 4.4 `lrc_lines_rom.v` — 歌词行文本 ROM

- **功能**：由 `tools/gen_lrc_assets.py` 自动生成。存储 9 行歌词的时间戳和文本索引。

### 4.5 `lrc_font_rom.v` — 歌词字模 ROM

- **功能**：由 `tools/gen_lrc_assets.py` 自动生成。60 个字形的点阵字模。

### 4.6 `osd_overlay_24.v` — 24-bit RGB OSD 包装器

- **功能**：12-bit 状态 OSD 的 24-bit RGB 包装层。纯组合，不增加流水线延迟。

### 4.7 `status_osd_overlay.v` — 状态 OSD（左上角 4 字符）

- **功能**：左上角显示 4 个字符 `[曲目号][a/e][err高4位][err低4位]`。`a`=自动轮播，`e`=手动模式。错误码来自 `health_monitor` sticky 锁存。

### 4.8 `bilinear_8q8.v` — 双线性缩放（8.8 定点）

- **功能**：第十三讲 3.3.1。R/G/B 三通道完整双线性插值，用于封面缩略图的 4:1 缩小。

### 4.9 `thumbnail_layout.v` — 2×2 缩略图布局

- **功能**：第十三讲。每格 160×120，源图 640×480 → 4:1 缩小。输出每个像素对应的源 bank 和坐标。

### 4.10 `thumbnail_view_reader.v` — 缩略图取像引擎

- **参数**：`BANK_WORDS=307200`（640×480）
- **功能**：按 `thumbnail_layout` 给出的坐标，从 SDRAM 随机取像素。通过 `sdram_rd_arbiter` 复用唯一一路读口。

### 4.11 `brightness_contrast_adjust.v` — 亮度/对比度调节

- **功能**：第十四讲。亮度 5 档 LUT（0/64/128/192/255），对比度 5 档。母板 KEY1+KEY2 组合调节，X5 将改为 `param_csr` 统一写入。

### 4.12 `frame_blend.v` — 帧混合

- **功能**：两帧 alpha 混合，用于转场淡入淡出。

### 4.13 `video_fade_transition.v` — 视频转场控制器

- **参数**：`FADE_FRAMES`
- **模式**：
  - Mode 0：帧边界硬切
  - Mode 1：16 帧（~0.27s @60Hz）翻页揭示，不变暗
  - Mode 2：淡入淡出
- **功能**：每笔 bank 交易保持一个请求。手动切换用 alpha 淡变，自动轮播用左到右擦除。

### 4.14 `video_transition_apply.v` — 转场像素应用

- **功能**：第十讲。在像素域应用转场效果。因帧读口单端口，自动轮播切换用左到右 wipe。

### 4.15 `seg_business_mux.v` — 6 位数码管业务 mux（X1C 新增）

- **时钟域**：`sd_card_clk`，与 `seg_scan` 同域
- **功能**：6 位段码业务选择，优先级：
  1. 错误码（`Err-01..09`，`err_sticky` 时）
  2. 参数临时值（调参后显示 2s）
  3. 默认 MM:SS 播放时间（99:59 封顶）

### 4.16 `seg_business_mux` 辅助

- 见 `src/SD/seg_decoder.v` 和 `seg_scan.v`（硬件扫描器）。

---

## 5. `src/io/`（25 个文件）

用户输入处理、事件总线、外设驱动。

### 5.1 `expansion_integration.v` — J2 扩展板集成子系统（单一边界）

- **功能**：S1。把 S1 的物理通路收进一个自包含子系统，顶层只需对接 `exp_*` 端口。内部例化 `expansion_io_hub`、`key_dip_monitor`、`quadrature_decoder`、`ir_nec_decoder`、`exp_echo_reporter`、`buzzer_feedback` 等。

### 5.2 `expansion_io_hub.v` — J2 输入统一汇聚层

- **功能**：S1。把 `exp_*` 原始异步输入汇聚成"已同步/已消抖/已边沿检测/已解码"的标准事件流。

### 5.3 `quadrature_decoder.v` — 正交编码器解码器

- **参数**：`AB_STABLE_CYCLES = 50_000`（50MHz 下 1ms）
- **功能**：A/B 相稳定 1ms 后判定方向，输出 `rot_pulse` 和 `rot_dir`。消除机械触点抖动。

### 5.4 `encoder_monitor.v` — 编码器监控

- **功能**：监控 EC1/EC2 的 step/sw 事件，输出给事件总线。

### 5.5 `ir_nec_decoder.v` — 红外 NEC 解码器

- **功能**：解码 NEC 协议（9ms 载波 burst + 4.5ms gap + 地址/数据 + 反码校验），输出 `ir_event`、`ir_code[31:0]`。

### 5.6 `key_dip_monitor.v` — 按键/DIP 监控

- **功能**：消抖后采集 12 个按键和 6 路 DIP 的电平变化，输出边沿事件。复位建立时的 DIP 状态被视为初始配置而非用户操作。

### 5.7 `debounce_filter.v` — 通用消抖滤波器

- **功能**：参数化消抖，默认 8ms。

### 5.8 `sync_bit.v` — 单比特同步器

- **功能**：跨时钟域单比特信号同步。

### 5.9 `ui_event_bus.v` — 统一 UI 事件总线（S7-03 重构）

- **功能**：把原来"同拍只按优先级选一个"的组合仲裁升级为"逐源 pending 位图"。每个事件源（按键/EC1/EC2/IR/DIP）有独立的 pending bit，仲裁器按固定优先级扫描，非 FIFO。KEY_UP 无 pending（M6 优化）。输出溢出计数 `ev_overflow`。

### 5.10 `ui_event_bridge.v` — 事件→toggle 跨域桥

- **时钟域**：`clk` 50MHz
- **功能**：把事件总线的"选曲业务"事件解码成电平翻转 toggle，跨域到 `sd_card_clk`。**当前 EC2 事件在此被丢弃**（K1，X5 将补）。已处理：KEY01/02/03/04/05/07/08/11。

### 5.11 `ui_command_router.v` — 业务命令路由器

- **时钟域**：`clk`
- **功能**：S7-03。位于事件总线之后、bridge 之前，把"已确认"的物理事件流翻译为业务命令：
  - 红外 15 键白名单 + 双反码校验 + repeat 节流（150/250ms）
  - 运行时 DIP 门控（DIP5=0 时 IR 不执行业务）
  - 60s 自动消隐
  - 3s 重启确认框
  - 优先级链：重启确认框 > 消隐唤醒吞首事件 > 业务

### 5.12 `browse_fsm.v` — 主界面选歌状态机

- **时钟域**：`sd_card_clk` 100MHz
- **功能**：S3。事件→控制适配层。管理全屏浏览 ↔ 2×2 缩略图视图切换、焦点移动、确认选曲。S7-03b 修改：KEY07 主界面/播放态直达缩略图，不再翻转 view_mode。

### 5.13 `cover_navigation.v` — 封面导航目标累加器

- **功能**：SD 域。用户在转场期间的步进更新 desired；每个在途 bank 保持到 `select_ack`，不覆盖不丢失。

### 5.14 `thumbnail_controller.v` — 缩略图控制器

- **功能**：第十五讲。管理 2×2 缩略图的焦点、确认选择。`key_confirm` 需 `image_complete[focus]=1` 才生效。

### 5.15 `play_ctrl` 见 §2.2。

### 5.16 `buzzer_feedback.v` — 蜂鸣反馈混音器

- **功能**：低有效蜂鸣反馈混音。音型：KEY、DIP、EC1、EC2、encoder push、IR command。X5 将新增 1320Hz（进 adjust）和 990Hz（退 adjust）。

### 5.17 `led_business_driver.v` — LED1–4 业务化（X1A 新增）

- **时钟域**：`clk` 50MHz
- **功能**：
  - LED1 = 有效 IR 帧指示（延展 ~80ms）
  - LED2 = 已接受操作脉冲（~80ms）
  - LED3 = ~1Hz 心跳
  - LED4 = `health_monitor` sticky 告警
  - DIP3=0 时全灭

### 5.18 `ws2812_driver.v` — WS2812 单线 NRZ 串行器（X1B 新增）

- **时钟域**：`clk` 50MHz
- **功能**：移植自标定工程。8 颗串联 WS2812，NRZ 时序：50MHz 下 0 高 18 拍、1 高 35 拍、reset 3000 拍。

### 5.19 `ws2812_effects.v` — WS2812 灯效层（X1B 新增）

- **时钟域**：`clk`
- **功能**：KEY10 循环三模式：
  1. 全灭
  2. 音频律动：PCM 饱和绝对值 + 快升慢降包络（处理 −32768）
  3. 播放进度条：`cur_time_ms / (audio_bytes/2/48) × 8` 灯单调填充
- **约束**：每通道上限 76（~30% 亮度）；DIP6=0 时先发全黑帧再拉低。

### 5.20 `exp_uart_tx.v` — UART 发送字节引擎

- **功能**：8N1，低有效起始位。115200 波特率。

### 5.21 `exp_baud_tick.v` — 波特率节拍发生器

- **功能**：产生 115200 波特率的 16x 过采样 tick。

### 5.22 `exp_echo_reporter.v` — 串口回显上报器

- **功能**：S1。通过 `ECHO_TEST_ENABLE` 参数切换。每 2 秒输出一行 `STAT UR=xxxx BL=xxxx VF=xxxx OV=xxxx ERR=xx VER=0701_0001`，以及事件行 `INFO DONE=x IDX=x PIC=x AUD=x`、`IR xxxxxxxx CMD FF`、`DIP n x`。

### 5.23 `health_monitor.v` — 诊断遥测汇聚（S7-01）

- **时钟域**：`clk`
- **功能**：把顶层同步到 clk 域的慢变/单拍可观测信号汇聚成：
  - `cnt_underrun`（音频 underrun，16-bit 饱和）
  - `cnt_buffer_low`（buffer-low）
  - `cnt_video_fail`（MV 取帧失败）
  - `ev_overflow`（事件队列溢出）
  - `err_code`（sticky 错误码，只在新的非零错误到来时更新）
  - 运行版本号 `VER=0701_0001`

### 5.24 `param_menu_controller.v` — 亮度/对比度参数菜单

- **功能**：第十四讲。母板 KEY1+KEY2 组合调节亮度/对比度各 5 档。X5 将改为发 `param_csr` STEP 命令，不再持有副本。

### 5.25 `io/` 辅助

- `expansion_io_hub`、`expansion_integration` 已述。

---

## 6. `src/SD/`（30 个文件）

SD 卡协议、FAT32 文件系统、SDRAM 帧缓存、数码管扫描。

### 6.1 SD 卡 SPI 协议层

#### 6.1.1 `sd_card_top.v` — SD 卡顶层

- **功能**：集成 SPI 信号、命令与扇区读写。当前只用读路径。

#### 6.1.2 `sd_card_sec_read_write.v` — 扇区读写状态机

- **功能**：CMD0/CMD8/CMD55/ACMD41/CMD16/CMD17/CMD24 流程。初始化后单扇区读写。

#### 6.1.3 `sd_card_cmd.v` — SD 命令发送

- **功能**：发送 48-bit SD 命令帧，接收 R1/R2/R3 响应。

#### 6.1.4 `spi_master.v` — SPI 主控制器

- **功能**：字节级 SPI 传输。卡初始化低速分频 248，高速分频 0。

#### 6.1.5 `sd_sector_adapter.v` — 扇区读接口适配层

- **参数**：`SECTOR_TIMEOUT_CYCLES = 25_000_000`（250ms @100MHz）
- **功能**：把 `sd_card_top` 的电平请求式接口适配为带 `busy`/`byte_index`/`error` 的流式接口。250ms 无数据输出超时错误 `0x05`。

### 6.2 FAT32 文件系统层

#### 6.2.1 `fat32_volume_scanner.v` — FAT32 卷扫描器

- **功能**：第七讲。读 LBA0，识别直接 FAT32 引导扇区或 MBR，解析 BPB，扫描根目录第一个簇，按 8.3 短文件名匹配 `PIC1.BMP ~ PIC4.BMP`。
- **错误码**：0x10=扇区错、0x20=boot 签名错、0x21=不支持的 BPB、0x22=资源缺失。

#### 6.2.2 `fat32_file_streamer.v` — FAT32 文件流读取器

- **功能**：从目录项给出的起始簇开始，按 FAT 链逐扇区输出文件字节流。只负责原始字节流，不解析 BMP。

#### 6.2.3 `fat32_media_loader.v` — FAT32 媒体加载兼容层

- **功能**：第七讲。对外保持旧 `bmp_read` 的接口语义。内部协调 scanner/streamer/索引加载。`pixel_end` 加法外提优化（不得回退）用于时序收口。

#### 6.2.4 `song_index_db.v` — 曲目索引 INDEX.BIN 解析

- **功能**：S4。输入是已由 `fat32_file_streamer` 走完 FAT 簇链的字节流，解析 512B 定长索引（v1/v2，最多 4 曲）。支持碎片链。条目含：曲名、BMP 封面 LBA、WAV 音频 LBA+长度、MV LBA、歌词偏移等。

### 6.3 BMP 与图片加载

#### 6.3.1 `bmp_read.v` — BMP 解析器

- **参数**：`SCAN_START_SECTOR=0`、`SCAN_MAX_SECTOR=131071`
- **功能**：按扇区扫描 BMP 头，只接受 `BM`、640×480、24bpp、compression=0。读取文件长度、像素偏移、宽高字段，连续输出像素字节。BGR→RGB 重排为 `[31:8]=R:G:B`。

#### 6.3.2 `sd_card_bmp.v` — BMP 应用状态机

- **功能**：第三/五/六/七/八讲。应用状态机、双缓冲选择、按键去抖、扫描和加载调度。默认找 4 张图。首图写 buffer0，后续写非显示 buffer，整帧 SDRAM 写完才翻转显示 buffer。

### 6.4 SDRAM 与帧缓存

#### 6.4.1 `sdram.v` — SDRAM Wrapper

- **功能**：把用户接口接入 `sdr_as_ram`，再实例化 `EG_PHY_SDRAM_2M_32` 硬核。32-bit 数据、21-bit 地址、4-bit DM、11-bit row、2-bit bank，125MHz。

#### 6.4.2 `frame_read_write.v` — 帧读写总控

- **功能**：把读写请求分配给两个异步 FIFO 与读/写 FSM。写优先级通过 busy 信号协调。

#### 6.4.3 `frame_fifo_write.v` — 写侧调度

- **功能**：512 word FIFO、水位触发、256 word burst。支持 `WRITE_V_FLIP=1` 的逐行反向地址（修正 BMP bottom-up 行序）。

#### 6.4.4 `frame_fifo_read.v` — 读侧调度

- **参数**：`BURST_GAP_CYCLES=12`（两次读突发之间留 12 周期给自动刷新）
- **功能**：512 word FIFO、128 word burst。视频时序每帧请求当前显示 buffer。

#### 6.4.5 `sdram_rd_arbiter.v` — SDRAM 读口换手开关

- **功能**：第十三讲。SDRAM 控制器只有一路 App_rd_en/App_rd_addr 只读口，原本由 `frame_fifo_read` 独占。缩略图视图需要按坐标随机取像，此仲裁器在正常帧读和缩略图取像之间换手。

### 6.5 媒体监督

#### 6.5.1 `media_supervisor.v` — 媒体故障恢复监督器（S7-02）

- **时钟域**：`sd_card_clk`
- **功能**：SD 域生命周期监督。`media_ready` = 元数据已校验 AND 封面已预加载（不是仅 scan_done）。5s 挂载期限、3 次重试、30s 冷却、SD 复位代次（`media_epoch`）。

#### 6.5.2 `media_probe.v` — 媒体在场探测

- **功能**：1 秒无客户端 IO 后，在 LBA 0 发最低优先级 CMD17 只读探测。探测独占整个扇区，字节/done 不泄漏到 WAV/MV 客户端。

### 6.6 数码管扫描

#### 6.6.1 `seg_decoder.v` — 段码译码器

- **功能**：BCD/数字 → 7 段码字形。

#### 6.6.2 `seg_scan.v` — 数码管动态扫描

- **功能**：6 位位选动态扫描，多路复用段码输出。

### 6.7 其他

#### 6.7.1 `color_bar.v` — 彩条/时序发生器

- **功能**：生成 640×480 的 hsync/vsync/de 时序。当前只用其时序输出，彩条 RGB 未连接。

#### 6.7.2 `video_timing_data.v` — 视频时序数据

- **功能**：发起每帧 SDRAM 读请求。对同步信号延迟两拍，检测场同步边沿请求读帧。

#### 6.7.3 `video_delay.v` — 视频数据对齐

- **功能**：21 拍移位链：`read_en=de` 延迟 18 拍，数据在 19 拍取样，输出同步/DE 在 20 拍。

#### 6.7.4 `ax_debounce.v` — 旧按键去抖（已 AutoExcluded）

- **功能**：旧模块，当前使用 `sd_card_bmp.v` 内部的 `key_press_debounce`。

#### 6.7.5 `key_press_hold.v` — KEY1 短按/长按判别

- **功能**：第十三讲移植。区分短按和长按。

#### 6.7.6 `video_define.v` — 视频宏定义（空壳）

- **功能**：21 字节空文件，历史遗留。

---

## 7. `src/video/`（5 个文件）

MV 视频播放子系统。

### 7.1 `mv_stream_player.v` — MV 流播放器

- **参数**：`FRAME_SECTORS=300`（一帧 320×240 RGB565 = 300 扇区）
- **时钟域**：`sd_card_clk`
- **功能**：恰好取一帧（300 扇区），把 RGB565 LE 扩展为 `{RGB888, 8'b0}` 写入 FIFO。完成 = SDRAM `write_finish`，不是最后一个 SD 字节。命令数据在 `done_toggle` 前保持稳定。

### 7.2 `mv_frame_scheduler.v` — MV 帧调度器

- **时钟域**：`video_clk`
- **功能**：一单数据保持请求/ack 邮箱，循环 SDRAM slot 0/1/2。可预取一帧；只有已确认且到期的帧才能显示。存储慢时冻结显示 slot，然后跳到音频时间线。X2 修改：restart/invalidate 期间把播放位置直接落到目标帧，不从 0 重新数。

### 7.3 `mv_sector_mux.v` — MV/WAV 扇区复用器

- **时钟域**：`sd_card_clk`
- **功能**：一个不可抢占的扇区。音频在每个空闲边界优先。WAV 在 grant 沿（WS_REQ→WS_FILL）更新 sd_lba，下一拍地址稳定后请求下游 adapter。

### 7.4 `s6_video_layer.v` — S6 视频图层绑定

- **参数**：`ENABLE=1`
- **时钟域**：`video_clk`（像素域）
- **功能**：所有可见选择和相位在 `frame_start` 提交。管理 MV 窗口可见性、帧请求 toggle、SDRAM bank 选择。`visual_toggle`（KEY08）切换 MV/黑胶。

### 7.5 `video/` 辅助

- `mv_frame_scheduler` 已述。

---

## 8. `src/hdmi1.4b_transmitter_core/`（1 个文件）

### 8.1 `hdmi_1_4b_transmitter_core_wrapper.enc.v` — HDMI 1.4b 发射核包装器

- **状态**：加密 IP，内部不可审阅。
- **配置**：RGB、VIC=1（640×480p60）、48kHz 音频、800×525 时序。
- **接口**：AXI-Stream 视频 + PCM 音频 + ACR → TMDS 10-bit 输出。

---

## 9. `src/include/`（7 个文件）

### 9.1 `global_def.v` — 全局参数

- `DATA_WIDTH=32`、`ADDR_WIDTH=21`、`DM_WIDTH=4`、`ROW_WIDTH=11`、`BA_WIDTH=2`、`SDR_CLK_PERIOD=8ns`（125MHz）。

### 9.2 `sdr_as_ram.enc.v` — SDRAM 当 RAM 使用（加密）

- **功能**：安路加密 SDRAM 控制核，把 SDRAM 抽象为简单 RAM 接口。

### 9.3 `sdr_init_ref.enc.v` — SDRAM 初始化与刷新（加密）

- **功能**：SDRAM 上电初始化序列和自动刷新。

### 9.4 `sdr_wrrd.enc.v` — SDRAM 读写操作（加密）

- **功能**：SDRAM 读写数据路径。

### 9.5 `boot_logo_geom.vh` — 开机 Logo 几何参数

- `BOOT_LOGO_ADDR_BITS=15`。

### 9.6 `lrc_geom.vh` — 歌词 OSD 几何参数

- 歌词位置、字模尺寸等。

### 9.7 `exp_event_defs.vh` — 事件码定义

- 统一事件总线的事件编码定义。

### 9.8 `song_index_defs.vh` — 歌曲索引结构定义

- INDEX.BIN 的条目偏移、字段位定义。

---

## 10. `src/IP/`（6 个文件）

安路生成的 PLL 和 FIFO IP。

### 10.1 `sys_pll.v` — 系统 PLL

- **输入**：50MHz
- **输出**：100MHz（sd_card_clk）、125MHz（ext_mem_clk）、125MHz 180°（ext_mem_clk_sft）

### 10.2 `video_pll.v` — 视频 PLL

- **输入**：50MHz
- **输出**：25MHz（video_clk）、125MHz（hdmi_5x_clk）

### 10.3 `PLL_HDMI_AUDIO.v` — 音频 PLL

- **输入**：50MHz
- **输出**：12.295082MHz（audio_mclk）

### 10.4 `afifo_16_32_256.v` — 写异步 FIFO

- **实际模块名**：`wfifo_32_32_512`，32-bit×512，SHOWAHEAD 模式。

### 10.5 `afifo_32_16_256.v` — 读异步 FIFO

- **实际模块名**：`rfifo_32_32_512`，32-bit×512。

### 10.6 `sdram.v` — 旧 SDRAM Wrapper（已 AutoExcluded）

- **状态**：备用/旧版，与 `src/SD/sdram.v` 同名，不可同时启用。

---

## 11. 数据通路总结

### 11.1 视频通路

```
SDRAM (封面/MV bank)
  → frame_fifo_read / thumbnail_view_reader
  → video_delay (21拍对齐)
  → brightness_contrast_adjust
  → video_fade_transition (转场)
  → vinyl_renderer (黑胶)
  → lrc_osd (歌词)
  → promax_audio_waveform (波形)
  → osd_overlay_24 / status_osd_overlay (状态)
  → boot_layer (开机 logo)
  → video_rgb_to_axis_640x480 (AXI-Stream)
  → HDMI 1.4b 加密核
  → hdmi_phy_wrapper → lane_lvds_10_1 → TMDS
```

### 11.2 音频通路

```
SD 卡 (WAV 文件)
  → sd_sector_adapter → fat32_file_streamer
  → wav_stream_player (8KB BRAM 环形缓冲)
  → pcm_volume_fade (音量+淡变)
  → sync_fade_gain (alpha 同步)
  → hdmi_pcm_source_bridge → m06_pcm_contract_adapter
  → HDMI 1.4b 加密核
  → I2S → ACR → TMDS
```

### 11.3 输入事件通路

```
J2 按键/EC1/EC2/IR/DIP
  → expansion_io_hub (同步+消抖+解码)
  → ui_event_bus (pending 位图仲裁)
  → ui_command_router (IR 白名单+DIP 门控+消隐+重启确认)
  → ui_event_bridge (toggle 跨域)
  → browse_fsm / play_ctrl (sd_card_clk 域)
```

### 11.4 输出反馈通路

```
health_monitor (遥测汇聚)
  → exp_echo_reporter (UART 115200)
  → status_osd_overlay (HDMI 屏幕左上角)
  → seg_business_mux → seg_scan (6 位数码管)
  → led_business_driver (LED1-4)
  → ws2812_effects → ws2812_driver (8 灯)
  → buzzer_feedback → board_buzzer_n (蜂鸣器)
```

---

## 12. 当前完成度（HEAD = 9848757）

| 子系统 | RTL | 仿真 | 构建 | SRAM 下载 | 板级验收 |
|---|:-:|:-:|:-:|:-:|:-:|
| SD/FAT32/BMP | ✓ | ✓ | ✓ | ✓ | ✓ |
| SDRAM 四 bank 帧缓存 | ✓ | ✓ | ✓ | ✓ | ✓ |
| HDMI 640×480 视频 | ✓ | ✓ | ✓ | ✓ | ✓ |
| WAV 48kHz 播放 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 单行歌词 OSD | ✓ | ✓ | ✓ | ✓ | ✓ |
| 开机 Logo | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2×2 缩略图选曲 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 亮度/对比度调节 | ✓ | ✓ | ✓ | ✓ | ✓ |
| J2 扩展板输入 | ✓ | ✓ | ✓ | ✓ | 部分 |
| 统一事件总线 | ✓ | ✓ | ✓ | ✓ | 部分 |
| 红外遥控 15 键 | ✓ | ✓ | ✓ | ✓ | 部分 |
| 蜂鸣反馈 | ✓ | ✓ | ✓ | ✓ | ✓ |
| UART 遥测 | ✓ | ✓ | ✓ | ✓ | ✓ |
| MV/黑胶渲染 | ✓ | ✓ | ✓ | ✓ | 待补 |
| media_supervisor | ✓ | ✓ | ✓ | ✓ | 待补 |
| health_monitor | ✓ | ✓ | ✓ | ✓ | ✓ |
| KEY07/KEY11 交互 | ✓ | ✓ | ✓ | ✓ | 待补 |
| LED1-4 业务化 (X1A) | ✓ | ✓ | ✓ | 待下载 | 待板验 |
| WS2812 灯效 (X1B) | ✓ | ✓ | ✓ | 待下载 | 待板验 |
| 数码管业务 mux (X1C) | ✓ | ✓ | ✓ | 待下载 | 待板验 |
| EOF/结束策略 (X2) | ✓ | ✓ | ✓ | 待下载 | 待板验 |
| Seek/重播 (X2) | ✓ | ✓ | ✓ | 待下载 | 待板验 |
| EC2 OSD 调参 (X5) | ✗ | ✗ | ✗ | ✗ | ✗ |
| 多曲歌词 (X4) | ✗ | ✗ | ✗ | ✗ | ✗ |
| 转场板验 (X3A) | 骨架 | 部分 | ✓ | — | 待板验 |
| W25Q64 Flash (X7) | ✗ | ✗ | ✗ | ✗ | ✗ |
| 256 点 FFT (X3B) | ✗ | ✗ | ✗ | ✗ | ✗ |

---

## 13. 资源与时序基线

| 指标 | 数值 |
|---|---:|
| Slices | 8412 / 9800 = 85.84% |
| BRAM9K | 40 / 64 |
| DSP | 15 / 29 |
| Setup WNS | +114 ps |
| Hold WNS | +3 ps |
| Setup TNS / Hold TNS | 0 / 0 |
| 违例端点 | 0 |
| 黑盒 / 组合环 / 时钟缺失 | 0 / 0 / 0 |

---

*文档结束。本文基于 Git HEAD `9848757` 的源码逐文件分析生成。*
