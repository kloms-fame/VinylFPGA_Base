# VinylFPGA 项目 AI 上下文文档

> 文档目的：为 AI 助手提供项目的完整、自洽、可独立阅读的上下文。后续针对本项目的提问、代码修改、方案设计，应优先以本文档为基准，不依赖对话历史。
> 快照日期：2026-10-07
> 代码基线：Git HEAD `a357339`（S7-03b），构建快照 `prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7/`
> 顶层文件：`src/top_tf_hdmi_audio.v`（98 KB，例化全部子模块）
> 本文档中所有代码片段均从实际源码摘录，未省略关键逻辑；行号引用以摘录版本为准。

---

## 目录

1. [项目概述](#1-项目概述)
2. [整体架构](#2-整体架构)
3. [核心链路](#3-核心链路)
4. [关键实现思路](#4-关键实现思路)
5. [核心代码片段](#5-核心代码片段)
6. [数据与接口约定](#6-数据与接口约定)
7. [关键配置与环境依赖](#7-关键配置与环境依赖)
8. [已知问题与优化空间](#8-已知问题与优化空间)

---

## 1. 项目概述

### 1.1 项目定位

VinylFPGA 是一个基于 **安路 EG4S20BG256 FPGA** 的"黑胶唱机形态"数字音频播放终端。它把 SD 卡上的 WAV（预处理为裸 PCM）音频、BMP 封面、可选 MV 视频、LRC 歌词，通过 HDMI 输出到显示器，模拟黑胶唱片机的交互：左旋钮选曲、右旋钮调参、扩展板 12 个按键 + 6 个拨码开关 + 红外遥控完成全部操作。

### 1.2 目标用户

- 硬件爱好者 / FPGA 学习者：工程分层清晰，每个阶段（S0–S7）独立可验收，适合作为 FPGA 全栈学习案例
- 嵌入式开发者：参考"两 PLL 时钟域 + CDC + 事件总线"的工程化范式
- 本人（杜垚，晋中学院物联网工程大一）：作为蓝桥杯/数学建模之外的长期硬件作品

### 1.3 解决的业务问题

| 问题 | 本方案做法 |
|---|---|
| SD 卡 FAT32 读 WAV 头复杂 | PC 工具 `vinyl_packer.py` 预处理：WAV→裸 PCM、BMP 裁剪、LRC→二进制行表、生成 INDEX.BIN 索引 |
| FPGA 资源有限（20k 逻辑单元） | 封面 BMP 在 SDRAM 环形缓存区，歌词/字库在 BRAM，MV 用 3 帧 SDRAM bank 10 fps |
| 多输入设备（12 键/2 编码器/6 DIP/红外/母板按键）事件冲突 | 统一事件总线 `ui_event_bus`，逐源 pending 位图，固定优先级仲裁 |
| 跨时钟域（50 MHz 板级 / 100 MHz SD / 25 MHz 视频）亚稳态 | toggle 电平翻转 + 3 级 FF + 边沿检测；BRAM 读写指针格雷码 |
| 硬件故障不可观测 | `health_monitor` 饱和计数 + `media_supervisor` 自动复位恢复 + 串口 STAT/ERR 上报 |

### 1.4 核心功能清单

| 功能 | 状态 | 模块 |
|---|---|---|
| SD 卡 FAT32 挂载 + 4 曲目索引 | ✅ 已验收 | `fat32_volume_scanner` / `fat32_media_loader` / `song_index_db` |
| 640×480 HDMI 输出（封面 + 2×2 缩略图选曲） | ✅ 已验收 | `sd_card_bmp` / `thumbnail_controller` / `hdmi_1_4b_transmitter_core_wrapper` |
| 48 kHz / 16 bit / 单声道 PCM 播放 | ✅ 已验收 | `wav_stream_player` / `timebase_48k` / `pcm_volume_fade` |
| 单行歌词叠加（从固化 LRC ROM） | ✅ 已验收 | `lrc_osd` / `lrc_lines_rom` / `lrc_font_rom` |
| MV 视频（320×240 @ 10 fps，RGB565，3 帧 SDRAM bank） | 🟡 构建通过板验待补 | `mv_stream_player` / `mv_frame_scheduler` / `mv_sector_mux` / `s6_video_layer` |
| J2 扩展板 12 键 + 2 编码器 + 6 DIP + 红外 | ✅ 已验收 | `expansion_io_hub` / `key_dip_monitor` / `quadrature_decoder` / `ir_nec_decoder` |
| 统一事件总线 + 业务命令路由（红外白名单/消隐/重启确认） | ✅ 构建通过 | `ui_event_bus` / `ui_command_router` / `ui_event_bridge` |
| 播放控制（选曲/暂停/音量/结束策略） | ✅ 已验收 | `play_ctrl` / `stream_session` |
| 媒体故障自动恢复（挂载超时/扇区错误复位） | ✅ 构建通过 | `media_supervisor` / `media_probe` |
| 诊断遥测（underrun/低水位/视频失败/事件溢出） | ✅ 构建通过 | `health_monitor` / `exp_echo_reporter` |
| 6 位数码管扫描 | 🟡 驱动在位，业务内容未接 | `seg_scan` / `seg_decoder` |
| WS2812 八灯灯效 | ⛔ 未开始 | （移植标定工程 `ws2812_driver`） |
| EC2 右旋钮 OSD 调参菜单 | ⛔ 未开始 | （规划见完美版开发方案） |
| W25Q64 用户 Flash 参数持久化 | ⛔ 未开始 | — |

---

## 2. 整体架构

### 2.1 技术栈

| 层 | 技术 |
|---|---|
| FPGA 工具链 | 安路 TD（Tang Dynasty），工程入口 `prj/VinylFPGA.al` |
| 器件 | EG4S20BG256（BGA256），Slices 9800、BRAM9K 64、DSP 29 |
| HDL | Verilog-2001，系统任务仅用于仿真，综合代码不依赖仿真宏 |
| 时钟体系 | 3 个 PLL 输出：`clk` 50 MHz（板级 IO）、`sd_card_clk` 100 MHz（SD/FAT32）、`video_clk` 25 MHz（HDMI 640×480） |
| 存储 | 板载 SDRAM（封面/MV 帧）+ BRAM（歌词/字库/PCM 环形缓冲）+ SD 卡（文件源） |
| PC 工具 | Python 3（`tools/vinyl_packer.py` 32 KB），生成镜像与索引 |
| 调试通道 | UART 115200（`exp_echo_reporter` 上报事件与 STAT/ERR） |

### 2.2 目录结构

```
VinylFPGA/
├── prj/                           # TD 工程与构建快照
│   └── VinylFPGA.al
├── constraints/
│   ├── pin.adc                    # BGA256 引脚约束（J2/HDMI/SD/数码管）
│   └── timing.sdc                 # 时序约束（3 个时钟域）
├── src/
│   ├── top_tf_hdmi_audio.v        # 顶层，例化全部子模块（98 KB）
│   ├── global_def.v               # 全局宏
│   ├── startup_pulse.v            # 上电复位
│   ├── reset_sync.v               # 异步复位同步释放
│   ├── sync_2ff.v                 # 2 级同步器
│   ├── IP/                        # PLL、SDRAM、异步 FIFO
│   │   ├── sys_pll.v / video_pll.v / PLL_HDMI_AUDIO.v
│   │   ├── sdram.v / afifo_16_32_256.v / afifo_32_16_256.v
│   ├── include/                   # 头文件（事件编码、索引布局、歌词几何）
│   │   ├── exp_event_defs.vh      # UI 事件编码单一事实来源
│   │   ├── song_index_defs.vh     # INDEX.BIN 布局
│   │   ├── lrc_geom.vh            # 歌词屏显几何（PC 工具生成）
│   │   └── boot_logo_geom.vh
│   ├── io/                        # 输入子系统
│   │   ├── expansion_io_hub.v      # J2 汇聚：key/dip/enc/ir 全部驱动
│   │   ├── key_dip_monitor.v      # 12 键 + 6 DIP 消抖
│   │   ├── debounce_filter.v      # 通用消抖（8 ms）
│   │   ├── quadrature_decoder.v    # EC 正交解码（1 ms 稳定采样）
│   │   ├── encoder_monitor.v      # 双 EC 封装
│   │   ├── ir_nec_decoder.v       # NEC 红外解码
│   │   ├── ui_event_bus.v          # 统一事件总线（逐源 pending 位图）
│   │   ├── ui_command_router.v    # 业务命令路由（红外白名单/消隐/重启）
│   │   ├── ui_event_bridge.v      # 事件→toggle 跨域桥
│   │   ├── browse_fsm.v           # 选曲 FSM（sd 域）
│   │   ├── play_ctrl.v            # 播放控制（选曲/暂停/音量/结束策略）
│   │   ├── expansion_integration.v # J2 子系统边界（含串口回显）
│   │   ├── exp_echo_reporter.v    # UART 事件上报
│   │   ├── exp_uart_tx.v / exp_baud_tick.v
│   │   ├── health_monitor.v       # 饱和计数遥测
│   │   ├── buzzer_feedback.v      # 蜂鸣器
│   │   ├── param_menu_controller.v # 母板旧两键菜单（遗留）
│   │   ├── cover_navigation.v / thumbnail_controller.v
│   ├── audio/
│   │   ├── wav_stream_player.v    # WAV 流式播放（8 KB BRAM 环形缓冲）
│   │   ├── stream_session.v       # 播放代次管理
│   │   ├── timebase_48k.v        # 全工程唯一 48 kHz 毫秒时基
│   │   ├── pcm_volume_fade.v       # 音量 + 淡变
│   │   ├── sync_fade_gain.v / pcm_media_tone.v
│   │   └── audio_source_mux.v / hdmi_pcm_*.v
│   ├── SD/
│   │   ├── sd_card_top.v / sd_card_cmd.v / spi_master.v
│   │   ├── fat32_volume_scanner.v # FAT32 挂载扫描
│   │   ├── fat32_media_loader.v   # 文件流读取（42 KB）
│   │   ├── fat32_file_streamer.v
│   │   ├── song_index_db.v        # INDEX.BIN 解析
│   │   ├── bmp_read.v / sd_card_bmp.v
│   │   ├── media_supervisor.v     # 故障恢复监督
│   │   ├── media_probe.v          # 空闲探测（无物理卡检测脚）
│   │   ├── seg_scan.v / seg_decoder.v # 6 位数码管
│   │   └── frame_fifo_read/write.v / sdram_rd_arbiter.v
│   ├── display/
│   │   ├── lrc_osd.v              # 单行歌词叠加
│   │   ├── lrc_lines_rom.v / lrc_font_rom.v # 固化歌词/字库
│   │   ├── vinyl_renderer.v       # 黑胶唱片渲染
│   │   ├── video_fade_transition.v # 转场淡变
│   │   ├── video_transition_apply.v
│   │   ├── promax_audio_waveform.v # 底部音频波形
│   │   ├── status_osd_overlay.v  # 状态/错误 OSD
│   │   ├── osd_overlay_24.v
│   │   ├── brightness_contrast_adjust.v
│   │   ├── thumbnail_view_reader.v / thumbnail_layout.v
│   │   └── bilinear_8q8.v / frame_blend.v
│   ├── video/
│   │   ├── mv_stream_player.v / mv_frame_scheduler.v
│   │   ├── mv_sector_mux.v / s6_video_layer.v
│   ├── boot/
│   │   ├── boot_layer.v           # 上电 Logo 500 ms 保护窗
│   │   └── boot_logo_rom.v        # 266 KB Logo 位图
├── tools/
│   ├── vinyl_packer.py            # PC 侧打包主工具（32 KB）
│   ├── gen_lrc_assets.py          # LRC→二进制行表/字库
│   ├── gen_boot_logo.py
│   ├── mv_pack.py
│   ├── verify_s0_s5_fixes.py / verify_s6.py / verify_s7_acceptance.py
│   └── build_resource_opt.py / build_verified_round.py / release_verified_round.py
└── doc/开发资料/                   # 全部设计文档与阶段交付说明
```

### 2.3 模块依赖关系（关键路径）

```
[J2 物理引脚]
    │
    ▼
expansion_io_hub (50 MHz clk 域)
    ├── key_dip_monitor  ──→ key_fall/rise_pulse, dip_level, dip_change_pulse
    ├── encoder_monitor  ──→ enc1/2_step_pulse, direction, count, sw_fall/rise
    └── ir_nec_decoder   ──→ ir_event, ir_code[31:0], ir_repeat_event
            │
            ▼
    ui_event_bus (逐源 pending 位图仲裁)
            │  ev_valid + ev_code[3:0] + ev_arg[15:0] + ev_aux[15:0]
            ▼
    ui_command_router (红外白名单/反码/repeat 节流/DIP 运行时/消隐/重启确认)
            │  cmd_valid + cmd_code + cmd_arg + cmd_aux
            ▼
    ui_event_bridge (业务事件 → toggle 电平翻转，为跨域做准备)
            │  prev_tgl / next_tgl / confirm_tgl / mode_tgl / home_tgl / ...
            ▼  (3 级 FF + 边沿检测，跨到 sd_card_clk 100 MHz)
    ┌───────┴────────┐
    ▼                ▼
browse_fsm     play_ctrl
(选曲导航)      (播放/暂停/音量/结束策略)
    │                │  restart_request / track_step / volume / sel_song
    ▼                ▼
sd_card_bmp     stream_session ──→ wav_stream_player ──→ SDRAM ──→ video_clk 域
(封面加载)      (代次管理)         (PCM 环形缓冲)                  │
                                                                  ▼
                                                          timebase_48k → lrc_osd
                                                                  │
                                                                  ▼
                                                          HDMI 1.4b transmitter
```

**三时钟域划分**：

| 时钟 | 频率 | 域内模块 |
|---|---|---|
| `clk` | 50 MHz | 全部 J2 输入、事件总线、命令路由、遥测、UART、蜂鸣器 |
| `sd_card_clk` | 100 MHz | SD SPI、FAT32、索引、封面 BMP、browse_fsm、play_ctrl、stream_session、wav_stream_player 写侧 |
| `video_clk` | 25 MHz | HDMI 输出、OSD 叠加、歌词、波形、wav_stream_player 读侧、timebase_48k |

跨域全部通过 toggle 电平翻转 + 3 级 FF + 边沿检测还原单拍脉冲；BRAM 读写指针用格雷码。

---

## 3. 核心链路

### 3.1 开机链路

1. 上电 → `startup_pulse` 产生复位 → `reset_sync` 做异步生效/同步释放
2. 3 个 PLL 锁定后，`boot_layer` 显示 `boot_logo_rom`（266 KB Logo），持续 500 ms
3. 500 ms 内任何 J2/母板按键事件都被忽略（`ui_ev_valid` 排除），避免误触
4. 同时 `fat32_volume_scanner` 在 sd_card_clk 域挂载 SD 卡，读根目录
5. `song_index_db` 读 INDEX.BIN（512 字节，1 个扇区），校验 magic/version/CRC
6. `sd_card_bmp` 预加载 4 张封面到 SDRAM 环形区
7. `media_supervisor` 等待 `media_ready`（= 校验完成 + 封面预加载完成）
8. 开机保护窗结束后，Boot Logo 淡出，进入全屏封面浏览态

### 3.2 选曲链路（浏览态）

输入源：EC1 旋转 / KEY01（左）/ KEY03（右）/ KEY07（切歌模式）/ KEY02（确认）/ KEY11（返回主界面）。

1. 物理按键 → `key_dip_monitor` 8 ms 消抖 → `key_fall_pulse`
2. `ui_event_bus` 把按键并入 `key_down_pending` 位图，同拍仲裁输出一个事件
3. `ui_command_router` 透传 KEY 事件（非红外不翻译）
4. `ui_event_bridge` 识别 `ev_arg==0`（KEY01）/`ev_arg==2`（KEY03），翻转 `prev_tgl`/`next_tgl`
5. `browse_fsm`（sd_card_clk 域）3 级 FF 同步后异或还原单拍，路由：
   - 全屏态（`view_mode=0`）：`next_any` → `fs_next`（下一张封面）
   - 缩略图态（`view_mode=1`）：`next_any` → `thumb_right`（焦点右移）
6. `sd_card_bmp` 收到 `fs_next`，转场后从 SDRAM 切到下一张封面
7. KEY02（`ev_arg==1`）→ `confirm_tgl` → `browse_fsm` 输出 `play_start`
8. `play_ctrl` 收到 `play_start`，锁存 `focus_index` 作为起始曲目，拉高 `play_active`，发 `restart_request`

### 3.3 播放链路

1. `play_ctrl` 发 `restart_request` → `stream_session` 停 FIFO、等 `storage_busy`/`video_busy` 清零、settle 31 拍后切代次
2. `wav_stream_player` 写侧（sd_card_clk）按 `start_lba` 扇区读 SD，拼成 16 bit 样本写入 8 KB BRAM 环形缓冲
3. 读侧（video_clk）在 `sample_tick`（48 kHz）到来时消费一个样本
4. `pcm_volume_fade` 应用 `volume[7:0]`（默认 200，步进 16，范围 32–255）
5. `audio_source_mux` 选择 PCM 输出 → HDMI I2S
6. `timebase_48k` 在每个 `sample_tick && running` 时累加 `sample_count`，每 48 个样本 `cur_time_ms++`
7. `lrc_osd` 在消隐期扫描 `lrc_lines_rom`，选出时间 ≤ `cur_time_ms` 的最后一行，字库查表输出像素
8. EOF：`wav_stream_player` 读完 `total_sectors` 后发 `stream_end`（已跨域同步）→ `play_ctrl` 按 `end_mode[1:0]` 决策：
   - `end_mode=0`（播完暂停）：拉高 `paused` + `ended`
   - `end_mode=1`（单曲循环）：发 `restart_request` 重新播本曲
   - `end_mode=2`（自动下一曲）：`sel_song` 切到下一首 + `track_step` + `restart_request`

### 3.4 红外遥控链路

1. `ir_nec_decoder` 解码 NEC 帧（引导码 9 ms/4.5 ms + 32 位数据 + repeat 帧 9 ms/2.25 ms）
2. `ui_event_bus` 把完整 32 位帧作为 `EV_IR_FRAME` 输出（arg=低 16，aux=高 16）
3. `ui_command_router`：
   - 拆帧：`ir_addr=frame[31:24]`、`~addr=frame[23:16]`、`cmd=frame[15:8]`、`~cmd=frame[7:0]`
   - 反码校验：`ir_addr_inv == ~ir_addr && ir_cmd_inv == ~ir_cmd`
   - 白名单匹配 15 个实测地址字节（`BA/B9/B8/BB/BF/BC/F8/EA/F6/E9/E7/AD/F7/A5/E3`）
   - 翻译为等价 KEY 事件输出到 `cmd_*`
   - 音量键（BB/BF）建立 `last_ir_kind`，repeat 帧按 150 ms 节流连发
4. 下游 `ui_event_bridge` 不区分事件来自物理键还是红外，按 `ev_arg` 路由

### 3.5 故障恢复链路

1. `media_supervisor` 监控 `mount_error`/`sector_error`/`media_ready`
2. 扇区读错误（`sector_done && sector_error != 0`）→ 立即拉低 `sd_rst_n` 100 拍 → 复位 SD 子系统
3. 挂载超时 5 s → 重试，最多 3 次；连续失败进 30 s 冷却
4. 错误码通过 `media_err_toggle` 翻转跨域握手到 video 域，`status_osd_overlay` 显示 `Err-01..09`
5. `health_monitor` 在 clk 域饱和计数 underrun/低水位/视频失败/事件溢出，2 s 周期通过 UART 上报 STAT 帧

---

## 4. 关键实现思路

### 4.1 统一事件总线：逐源 pending 位图而非 FIFO

**问题**：早期实现用"同拍按优先级选一个"的组合仲裁，同拍到达的多个事件会丢关键事件（例如同时按键 + 拨码）。

**做法**（见 `ui_event_bus.v`）：
- 每个事件源（12 KEY down、6 DIP、EC1 step/sw、EC2 step/sw、IR）各一个 pending 位
- 组合仲裁器每拍按固定优先级挑一个 pending 位输出，并在下一拍清掉
- KEY_UP 不设 pending（释放事件不驱动业务，丢一个只影响串口回显）
- DIP 同一位多次变化合并为最终电平
- 溢出时发 `ev_overflow` 脉冲给 `health_monitor`，绝不覆盖已 pending 的事件

**权衡**：用 12+6+4+1 = 23 个触发器换"不丢同拍事件"，比通用 32 深 FIFO 省资源。

### 4.2 跨域：toggle 电平翻转 + 3 级 FF + 边沿检测

**问题**：50 MHz → 100 MHz → 25 MHz 三个域，单拍脉冲跨域会因相位差丢失。

**做法**（见 `ui_event_bridge.v` + `browse_fsm.v`）：
- clk 域：业务事件到来时翻转一根电平（`prev_tgl <= ~prev_tgl`）
- sd_card_clk 域：3 级 FF 同步（`s1→s2→s3`），`s2 ^ s3` 还原单拍脉冲
- 单比特电平翻转是 CDC 经典安全手法，不要求跨域握手
- EC1 旋转因为是连续脉冲，额外做了"累计差值重放"：记录 `enc_target`，每 8 个源时钟补 1 个 delta 脉冲，避免快速旋转时 toggle 翻转过快导致跨域采样丢步

### 4.3 WAV 流式播放：8 KB BRAM 环形缓冲 + 格雷码指针

**问题**：SD 读扇区是 100 MHz 突发，音频消费是 25 MHz 域 48 kHz 匀速，两域速率不匹配。

**做法**（见 `wav_stream_player.v`）：
- 8 KB BRAM（4096×16 bit）环形缓冲
- 写侧 sd_card_clk，读侧 video_clk
- 读写指针各打格雷码，经 2FF 同步到对方域
- 写侧在缓冲达到高水位（2048 样本）后暂停请求下一扇区，避免覆盖未消费数据
- 读侧下溢时输出静音但保持 `sample_valid`，防止下游 HDMI 音频链停顿产生爆音
- `sample_counter` 由读侧累加，`timebase_48k` 复用作为全工程唯一时间源

### 4.4 唯一时间源：timebase_48k

**问题**：歌词进度、seek、数码管 MM:SS 都需要"歌曲播放了多久"，如果各自计数会漂移。

**做法**：`timebase_48k` 只认 `wav_stream_player` 的 `sample_tick`（48 kHz），每 48 个样本 `cur_time_ms++`。暂停时 `running=0` 冻结；切曲/重播时 `restart=1` 清零。所有时间消费方（lrc_osd、数码管、未来 seek）只读 `cur_time_ms`。

### 4.5 红外白名单 + 反码校验

**问题**：NEC 协议本身没有地址校验，不同遥控可能误触发。

**做法**（见 `ui_command_router.v`）：
- 15 个实测地址字节硬编码为白名单（`BA/B9/B8/...`）
- 每帧校验两组反码：`~Addr` 和 `~Cmd` 必须严格等于对应字节
- repeat 帧只对音量键生效，150 ms 节流、250 ms 超时
- DIP5=0 时红外业务全部门控（但仍上报串口用于调试）

### 4.6 资源优化：S7-03 时序收口

**问题**：100 MHz FAT32 路径历史上一直时序违例。

**做法**（已固化，不得回退）：
- `fat32_media_loader` 的 `pixel_end` 信号加法外提，恢复约 437 ps
- Logo 位图按 bank 分组，BRAM 46→40
- 不放宽 `timing.sdc`、不加假 false path
- 构建时 seed 扫描（5/7/1/2/3）直到 Setup/Hold 非负

---

## 5. 核心代码片段

> 以下代码均为实际源码摘录，保留注释。阅读顺序按调用链从输入到输出。

### 5.1 事件编码（`src/include/exp_event_defs.vh`）

```verilog
// 注意：本头文件使用 module 作用域的 localparam，且不能加 `ifndef 包含保护。
// TD 的预处理器是全局的，加保护会导致第二个包含它的模块拿不到这些常量。
localparam [3:0] EV_NONE       = 4'd0;
localparam [3:0] EV_KEY_DOWN   = 4'd1;
localparam [3:0] EV_KEY_UP     = 4'd2;
localparam [3:0] EV_DIP_CHANGE = 4'd3;
localparam [3:0] EV_ENC_STEP   = 4'd4;
localparam [3:0] EV_ENC_SW     = 4'd5;
localparam [3:0] EV_IR_FRAME   = 4'd6;
localparam [3:0] EV_IR_REPEAT  = 4'd7;
// enc_id 0=EC1 1=EC2；direction 0=递增(+) 1=递减(-)；pressed 1=按下。
// NEC 帧布局 = {Addr[31:24], ~Addr[23:16], Cmd[15:8], ~Cmd[7:0]}
```

### 5.2 索引布局（`src/include/song_index_defs.vh`）

```verilog
// INDEX.BIN 全文件小端，固定 512 字节（正好 1 个扇区）。
// 头部 64 字节：
//   0  8  magic = "VINYLIDX"
//   8  2  version = 1(legacy) or 2(S6 MV extension)
//   12 2  song_count（1..MAX_SONGS=4）
//   16 4  entries_crc32（覆盖条目区）
// 曲目条目 64 字节 × song_count，起始偏移 64：
//   0  4  flags: bit0=封面, bit1=音频, bit2=歌词, bit3=MV
//   4  4  cover_first_cluster
//   8  4  cover_bytes
//   16 4  audio_first_cluster
//   20 4  audio_bytes（裸 PCM 字节数）
//   56 8  v2: MV descriptor (physical LBA / frame_count / fps=10 / codec=1)
localparam [15:0] SIDX_MAX_SONGS   = 16'd4;
localparam [15:0] SIDX_ENTRY_SIZE  = 16'd64;
```

### 5.3 输入汇聚：`expansion_io_hub.v`

```verilog
module expansion_io_hub #(
    parameter integer KEY_COUNT        = 12,
    parameter integer DIP_COUNT        = 6,
    parameter integer DEBOUNCE_CYCLES  = 400_000,    // 8 ms @ 50 MHz
    parameter integer AB_STABLE_CYCLES = 50_000,    // 1 ms
    parameter integer IR_CLK_FREQ_HZ  = 50_000_000
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [KEY_COUNT-1:0] exp_key_n,
    input  wire [DIP_COUNT-1:0] exp_dip_n,
    input  wire                 exp_enc1_a, exp_enc1_b, exp_enc1_sw_n,
    input  wire                 exp_enc2_a, exp_enc2_b, exp_enc2_sw_n,
    input  wire                 exp_ir_rx,
    output wire [KEY_COUNT-1:0] key_level,
    output wire [KEY_COUNT-1:0] key_fall_pulse,
    output wire [KEY_COUNT-1:0] key_rise_pulse,
    output wire [DIP_COUNT-1:0] dip_level,
    output wire [DIP_COUNT-1:0] dip_change_pulse,
    output wire [2:0]           dip_change_index,
    output wire                 enc1_step_pulse, enc1_direction,
    output wire [15:0]          enc1_count,
    output wire                 enc1_sw_fall_pulse, enc1_sw_rise_pulse,
    output wire                 enc2_step_pulse, enc2_direction,
    output wire [15:0]          enc2_count,
    output wire                 enc2_sw_fall_pulse, enc2_sw_rise_pulse,
    output wire                 ir_event, ir_repeat_event,
    output wire [31:0]          ir_code,
    output wire [7:0]           ir_command
);
    // 内部例化 key_dip_monitor / encoder_monitor / ir_nec_decoder，参数与 J2 标定工程完全一致
endmodule
```

### 5.4 事件总线：`ui_event_bus.v`（核心仲裁逻辑）

```verilog
module ui_event_bus #(
    parameter integer KEY_COUNT = 12,
    parameter integer DIP_COUNT = 6
)(
    input  wire                 clk, rst_n,
    input  wire [KEY_COUNT-1:0] key_fall_pulse, key_rise_pulse,
    input  wire [DIP_COUNT-1:0] dip_level, dip_change_pulse,
    input  wire [2:0]           dip_change_index,
    input  wire                 enc1_step_pulse, enc1_direction,
    input  wire [15:0]          enc1_count,
    input  wire                 enc1_sw_fall_pulse, enc1_sw_rise_pulse,
    input  wire                 enc2_step_pulse, enc2_direction,
    input  wire [15:0]          enc2_count,
    input  wire                 enc2_sw_fall_pulse, enc2_sw_rise_pulse,
    input  wire                 ir_event, ir_repeat_event,
    input  wire [31:0]          ir_code,
    output reg                  ev_valid,
    output reg  [3:0]           ev_code,
    output reg  [15:0]          ev_arg, ev_aux,
    output reg                  ev_overflow
);
    // 逐源 pending 位图
    reg [KEY_COUNT-1:0] key_down_pending;
    reg [DIP_COUNT-1:0] dip_pending, dip_pending_level;
    reg enc1_step_pending, enc1_step_dir;
    reg enc2_step_pending, enc2_step_dir;
    reg enc1_sw_pending, enc1_sw_pressed;
    reg enc2_sw_pending, enc2_sw_pressed;
    reg ir_pending, ir_pending_repeat;

    // 组合仲裁：固定优先级 KEY_DOWN > KEY_UP > DIP > EC1 step > EC2 step
    // > EC1 sw > EC2 sw > IR
    reg arb_valid;
    reg [3:0] arb_code;
    reg [15:0] arb_arg, arb_aux;
    reg [KEY_COUNT-1:0] arb_key_down_clr;
    reg [DIP_COUNT-1:0] arb_dip_clr;
    // ... (方向、EC sw、IR 清除位)

    always @* begin
        arb_valid = 1'b0; arb_code = EV_NONE;
        for (i = 0; i < KEY_COUNT; i = i + 1)
            if (!arb_valid && key_down_pending[i]) begin
                arb_valid = 1'b1; arb_code = EV_KEY_DOWN;
                arb_arg = i[15:0]; arb_key_down_clr[i] = 1'b1;
            end
        // KEY_UP / DIP / EC step / EC sw / IR 同理
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin /* 清零全部 pending */ end
        else begin
            ev_valid <= arb_valid; ev_code <= arb_code;
            ev_arg <= arb_arg; ev_aux <= arb_aux;
            // 并入新脉冲，同时清除本拍已输出的 pending 位
            key_down_pending <= (key_down_pending | key_fall_pulse) & ~arb_key_down_clr;
            // DIP 合并最终电平
            dip_pending_level <= (dip_level & dip_change_pulse) |
                                 (dip_pending_level & ~dip_change_pulse);
        end
    end
endmodule
```

### 5.5 业务命令路由：`ui_command_router.v`（红外白名单）

```verilog
// 15 键地址字节白名单（键区分靠 code[31:24]）
localparam [7:0] IR_PREV    = 8'hBA;
localparam [7:0] IR_NEXT    = 8'hB9;
localparam [7:0] IR_PLAY    = 8'hB8;
localparam [7:0] IR_VOLUP   = 8'hBB;
localparam [7:0] IR_VOLDN   = 8'hBF;
localparam [7:0] IR_BLANK   = 8'hBC;
localparam [7:0] IR_SEEKP   = 8'hF8;   // S7-06 前不支持
localparam [7:0] IR_SEEKM   = 8'hEA;
localparam [7:0] IR_REPLAY  = 8'hF6;
localparam [7:0] IR_RESTART = 8'hE9;
// ... IR_UP/E7, IR_DOWN/AD, IR_LEFT/F7, IR_RIGHT/A5, IR_OK/E3

// 反码校验
wire [31:0] full_frame   = {ev_aux, ev_arg};
wire [7:0]  ir_addr      = full_frame[31:24];
wire [7:0]  ir_addr_inv  = full_frame[23:16];
wire [7:0]  ir_cmd       = full_frame[15:8];
wire [7:0]  ir_cmd_inv   = full_frame[7:0];
wire        ir_frame_ok  = (ir_addr_inv == ~ir_addr) && (ir_cmd_inv == ~ir_cmd);

// 运行时 DIP 使能冻结
assign led_enable = dip_level[2];  // DIP3 LED 总使能
assign ws_enable  = dip_level[5];  // DIP6 WS 总使能

// 消隐：60 s 无人操作自动黑屏
wire auto_blank = (idle_cnt >= BLANK_TIMEOUT_MS);
assign blank_active = (dip_level[3] && auto_blank) || manual_blank;
```

### 5.6 事件桥接：`ui_event_bridge.v`（toggle 跨域）

```verilog
// KEY 索引 = 端口数组位（KEYnn => idx nn-1）：
//   0=KEY01左  1=KEY02中  2=KEY03右  3=KEY04上  4=KEY05下
//   6=KEY07切歌模式  8=KEY09动效  10=KEY11返回主页  11=KEY12结束策略
wire key_prev = is_key_down && ((ev_arg == 16'd0) || (ev_arg == 16'd3));
wire key_next = is_key_down && ((ev_arg == 16'd2) || (ev_arg == 16'd4));
wire key_ok   = is_key_down &&  (ev_arg == 16'd1);
wire key_mode = is_key_down &&  (ev_arg == 16'd6);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin /* 全部 tgl 清零 */ end
    else begin
        if (ev_valid && is_key_down && ev_arg == 16'd10) home_tgl      <= ~home_tgl; // KEY11
        if (ev_valid && is_key_down && ev_arg == 16'd8)  effect_tgl    <= ~effect_tgl; // KEY09
        if (ev_valid && is_key_down && ev_arg == 16'd11) end_mode_tgl <= ~end_mode_tgl; // KEY12
        if (ev_valid && ev_prev)    prev_tgl    <= ~prev_tgl;
        if (ev_valid && ev_next)    next_tgl    <= ~next_tgl;
        if (ev_valid && ev_confirm) confirm_tgl <= ~confirm_tgl;
        if (ev_valid && ev_mode)    mode_tgl    <= ~mode_tgl;
    end
end
```

### 5.7 选曲 FSM：`browse_fsm.v`

```verilog
// CDC：3 级 FF + 边沿检测
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin /* s1/s2/s3 清零 */ end
    else begin
        prev_s1 <= ev_prev_tgl; prev_s2 <= prev_s1; prev_s3 <= prev_s2;
        // next/confirm/mode 同理
    end
end
wire j2_prev = prev_s2 ^ prev_s3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin /* 全部输出清零 */ end
    else begin
        fs_next     <= next_any & ~view_mode & ~mode_play;
        fs_prev     <= prev_any & ~view_mode & ~mode_play;
        thumb_right <= next_any &  view_mode & ~mode_play;
        thumb_left  <= left_any &  view_mode & ~mode_play;
        // KEY07 在浏览与播放两态都可直接进入/退出缩略图；
        // KEY11(home_event) 停止播放并强制 go_home 回主界面全屏。
        thumb_mode  <= j2_grid | mb_grid;
        play_start  <= confirm_any && !view_mode && !mode_play && !home_event && !mode_any;
        play_stop   <= home_event || (mode_any && mode_play);
        go_home     <= home_event || mb_stop_home;
    end
end
```

### 5.8 播放控制：`play_ctrl.v`

```verilog
module play_ctrl #(
    parameter [7:0] VOL_DEFAULT = 8'd200,
    parameter [7:0] VOL_STEP    = 8'd16,
    parameter [7:0] VOL_MIN     = 8'd32,
    parameter [7:0] VOL_MAX     = 8'd255
)(
    input  wire       clk, rst_n,
    input  wire [2:0] song_total,
    input  wire       song_confirm,
    input  wire [1:0] focus_index,
    input  wire       enc_cw_tgl, enc_ccw_tgl, confirm_tgl,
    input  wire       key_up_tgl, key_down_tgl,
    input  wire       stop_request, media_lost,
    input  wire       stream_end,
    input  wire       end_mode_tgl,
    output reg [1:0]  end_mode,   // 0=pause, 1=repeat, 2=next
    output reg        restart_request,
    output reg        play_active, paused,
    output reg [1:0]   sel_song,
    output reg [7:0]  volume,
    output reg        track_step,
    output reg        track_dir
);
    wire [1:0] sel_next = (sel_song >= (tot - 3'd1)) ? 2'd0 : (sel_song + 2'd1);
    wire [1:0] sel_prev = (sel_song == 2'd0) ? (tot - 2'd1) : (sel_song - 2'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin /* 复位 */ end
        else begin
            track_step <= 1'b0; restart_request <= 1'b0;
            if (mode_event) end_mode <= (end_mode == 2'd2) ? 2'd0 : end_mode + 1'b1;
            if (!stream_end) eof_seen <= 1'b0;

            if (p_stop || stop_request || media_lost) begin
                play_active <= 1'b0; paused <= 1'b0;
            end else if (!play_active) begin
                if (song_confirm && song_total != 0) begin
                    play_active <= 1'b1; sel_song <= focus_index;
                    restart_request <= 1'b1;
                end
            end else begin
                if (p_cw || p_ccw) begin
                    sel_song <= p_cw ? sel_next : sel_prev;
                    track_step <= 1'b1; track_dir <= p_cw;
                    restart_request <= 1'b1;
                end else if (p_cf) begin
                    if (ended) begin paused <= 1'b0; ended <= 1'b0; restart_request <= 1'b1; end
                    else paused <= ~paused;
                end else if (stream_end && !eof_seen && !paused) begin
                    eof_seen <= 1'b1;
                    if (end_mode == 2'd0) begin paused <= 1'b1; ended <= 1'b1; end
                    else begin
                        restart_request <= 1'b1;
                        if (end_mode == 2'd2) begin
                            sel_song <= sel_next; track_step <= 1'b1;
                        end
                    end
                end
                if (p_up)   volume <= (vol_up_sum > VOL_MAX) ? VOL_MAX : vol_up_sum[7:0];
                else if (p_dn) volume <= (volume < VOL_MIN+VOL_STEP) ? VOL_MIN : vol_dn_sub[7:0];
            end
        end
    end
endmodule
```

### 5.9 播放代次：`stream_session.v`

```verilog
module stream_session (
    input  wire clk, rst_n, requested, restart,
    input  wire storage_busy, video_busy, reader_idle,
    output reg  enable, start_toggle
);
    reg [1:0] idle_sync;
    reg [4:0] settle;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) idle_sync<=0;
        else idle_sync<={idle_sync[0],reader_idle};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin enable<=0; settle<=0; start_toggle<=0; end
        else if(!requested || restart) begin enable<=0; settle<=0; end
        else if(!enable) begin
            if(storage_busy || video_busy || !idle_sync[1]) settle<=0;
            else if(settle==31) begin enable<=1; start_toggle<=~start_toggle; end
            else settle<=settle+1'b1;
        end
    end
endmodule
```

### 5.10 唯一时基：`timebase_48k.v`

```verilog
module timebase_48k (
    input  wire        clk, rst_n,
    input  wire        sample_tick,   // 48 kHz 单拍（唯一时基源）
    input  wire        running,       // 1=播放中且未暂停
    input  wire        restart,       // 1 拍：清零
    output reg  [31:0] sample_count,
    output reg  [31:0] cur_time_ms,
    output reg  [5:0]  sub_sample
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sample_count<=0; cur_time_ms<=0; sub_sample<=0; end
        else if (restart) begin sample_count<=0; cur_time_ms<=0; sub_sample<=0; end
        else if (sample_tick && running) begin
            sample_count <= sample_count + 1'b1;
            if (sub_sample == 6'd47) begin
                sub_sample <= 0;
                cur_time_ms <= cur_time_ms + 1'b1;  // 48 样本/毫秒
            end else sub_sample <= sub_sample + 1'b1;
        end
    end
endmodule
```

### 5.11 故障监督：`media_supervisor.v`

```verilog
// 挂载总期限 5 s，单轮重试 3 次，连续失败 30 s 冷却
// 扇区读错误立即拉低 sd_rst_n 100 拍
always @(posedge clk or negedge rst_n) begin
    if ((state == ST_WAIT_MOUNT) && (mount_error != 8'd0) &&
        (mount_error != media_err_code)) begin
        media_err_code <= mount_error;
        media_err_toggle <= ~media_err_toggle;
    end
    if (sector_done && (sector_error != 8'd0)) begin
        media_err_code <= ERR_RD_TMO;       // Err-05
        state <= ST_RESET_PULSE;
        sd_rst_n <= 1'b0;
    end
    // ... ST_RESET_PULSE 保持 sd_rst_n=0 100 拍后释放
end
```

### 5.12 数码管扫描：`seg_scan.v`

```verilog
module seg_scan(
    input           clk, rst_n,
    output reg[5:0] seg_sel,      // 6 位位选（低有效）
    output reg[7:0] seg_data,     // 8 段码（MSB 小数点）
    input[7:0]      seg_data_0, seg_data_1, seg_data_2,
    input[7:0]      seg_data_3, seg_data_4, seg_data_5
);
    // 200 Hz 扫描，6 位轮显
    case(scan_sel)
        4'd0: begin seg_sel <= 6'b11_1110; seg_data <= seg_data_0; end
        4'd1: begin seg_sel <= 6'b11_1101; seg_data <= seg_data_1; end
        // ...
    endcase
endmodule
```

---

## 6. 数据与接口约定

### 6.1 J2 扩展板物理引脚（已冻结）

| 信号 | BGA 脚 | 方向 | 有效电平 | 说明 |
|---|---|---|---|---|
| `exp_key_n[11:0]` | N1/M2/M1/L1/H2/H1/G1/G3/L4/L5/J12/K11 | 输入 | 低有效 | KEY01-12，内部上拉 |
| `exp_dip_n[5:0]` | L3/J3/J4/H4/K14/L12 | 输入 | 拨上=1（不取反） | DIP1-6；DIP1 L3 例外为弱下拉 |
| `exp_enc1_a/b/sw_n` | R7/R6/R5 | 输入 | sw 低有效 | 左旋钮 EC1 |
| `exp_enc2_a/b/sw_n` | P7/P6/P5 | 输入 | sw 低有效 | 右旋钮 EC2 |
| `exp_ir_rx` | K6 | 输入 | 高电平脉冲 | NEC 红外 |
| `exp_led_n[3:0]` | F3/F4/E4/E5 | 输出 | 低有效点亮 | LED1-4 |
| `exp_ws2812_data` | D5 | 输出 | 800 kHz NRZ | WS2812 数据 |
| `exp_ext_o[5:0]` | C5/C6/B5/B6/A5/A6 | 输出 | — | EXT1 当前复用蜂鸣器 |
| `board_buzzer_n` | H11 | 输出 | 低有效 | 母板蜂鸣器（SW5 物理通断） |

### 6.2 按键索引 ↔ 业务（冻结）

| 索引 | 丝印 | 业务 |
|:---:|:---|:---|
| 0 | KEY01 左 | 浏览上一 / 播放上一曲 |
| 1 | KEY02 中 | 浏览确认 / 播放暂停 |
| 2 | KEY03 右 | 浏览下一 / 播放下一曲 |
| 3 | KEY04 上 | 播放音量+ |
| 4 | KEY05 下 | 播放音量− |
| 5 | KEY06 歌词动效 | 未开始（规划 X4） |
| 6 | KEY07 切歌模式 | 直达 2×2 缩略图 |
| 7 | KEY08 播控方式 | MV/黑胶切换 |
| 8 | KEY09 切歌动效 | F0/F1/F2 循环（已提前实现） |
| 9 | KEY10 WS 灯效 | 未开始（规划 X1B） |
| 10 | KEY11 拓展1 | 返回主界面 go_home |
| 11 | KEY12 拓展2 | 结束策略三态循环 |

### 6.3 DIP 语义（冻结）

| 位 | 丝印 | 语义 |
|:---:|:---|:---|
| 0 | DIP1 拓展2 | J2 在场声明（上拨=可用，L3 弱下拉） |
| 1 | DIP2 拓展1 | 预留，记录电平不触发业务 |
| 2 | DIP3 指示灯 | `led_enable` 总使能 |
| 3 | DIP4 屏幕消隐 | 60 s 自动消隐使能 |
| 4 | DIP5 红外接收 | 红外业务总门控 |
| 5 | DIP6 WS 总控 | `ws_enable` 总使能 |

### 6.4 PCM 数据格式

- 16 bit signed little-endian
- 48 kHz 采样率
- 单声道
- FPGA 不解析 WAV 头，PC 工具预处理为 `AUDIO.PCM`
- 每扇区 512 字节 = 256 样本
- 缓冲：4096×16 bit = 8 KB，高水位 2048 样本，低水位 1024 样本

### 6.5 MV 数据格式（v2 索引）

- RGB565LE，320×240
- 每帧 153600 字节 = 300 扇区
- 10 fps，3 帧 SDRAM 环形 bank
- 物理连续文件（PC 校验）

### 6.6 串口协议（`exp_echo_reporter`，115200 8N1）

- 事件上报：每事件一行文本（KEY/DIP/ENC/IR）
- STAT 帧：每 2 s 一次，含 underrun/低水位/视频失败/事件溢出计数 + fw_version
- ERR 帧：错误码变化时上报 `Err-01..09`

---

## 7. 关键配置与环境依赖

### 7.1 构建环境

| 项 | 值 |
|---|---|
| FPGA 工具 | 安路 TD（Tang Dynasty），支持 seed 扫描与 area_prior 布局模式 |
| 构建脚本 | `tools/build_resource_opt.py` → `build_verified_round.py --seed <n> --map-mode area_prior` → `release_verified_round.py` |
| Python | 3.x（用于 `vinyl_packer.py` 等 PC 工具与回归脚本） |
| iverilog | 可选，用于定向仿真；当前未在 PATH，15 帧 IR 向量仿真未补 |
| 板级调试 | USB-JTAG 下载 SRAM 验证；USB-UART 115200 看串口 |

### 7.2 时序约束（`timing.sdc` 关键值）

| 时钟 | 频率 | WNS 当前 |
|---|---|---|
| `clk`（50 MHz 板级） | 50 MHz | 非负 |
| `sd_card_clk`（100 MHz SD） | 100 MHz | Setup +114 ps / Hold **+3 ps**（贴线） |
| `video_clk`（25 MHz 视频） | 25 MHz | 非负 |

### 7.3 资源基线

| 资源 | 用量 | 总量 | 百分比 |
|---|---|---|---|
| Slices | 8412 | 9800 | **85.84%**（红线 88%） |
| BRAM9K | 40 | 64 | 62.5% |
| DSP | 15 | 29 | 51.7% |

### 7.4 SD 卡镜像要求

- FAT32 格式
- 根目录必须有 `INDEX.BIN`（512 字节，magic "VINYLIDX"）
- 每首歌：封面 `COVERxx.BMP`（24 bit BMP）+ 音频 `AUDIExx.PCM`
- 可选：MV `MVxx.RGB`（RGB565 连续文件）+ 歌词（当前固化在 BRAM）
- 由 `python tools/vinyl_packer.py` 一键生成镜像

---

## 8. 已知问题与优化空间

### 8.1 当前局限

| # | 问题 | 影响 | 缓解方向 |
|:---:|---|---|---|
| 1 | Slices 85.84%，距 88% 红线仅 212 | 新功能叠加可能破 90% 导致布局不收敛 | 每阶段资源增量审计；S7-04 第二轮 R2/R3 已验证功能等价可复用 |
| 2 | Hold WNS +3 ps 贴线 | 100 MHz SD 域新增寄存器可能翻负 | 不放宽 sdc；新增 sd 域逻辑同步做加法外提 |
| 3 | J2 端口无 IO delay 约束 | 排线/WS 800 kHz 无板外时序证据 | X0 阶段做 IO delay 审计表 |
| 4 | S6 MV 板上验收未做 | 后续 seek/歌词对齐建立在未验证假设上 | X0 烧 `S7_03b` bit 跑 10 分钟实卡录像 |
| 5 | 快速按键 UR=0005 根因未定 | "1h underrun 不增加"验收基线不可信 | X0 定性：真实 SD 停顿 vs 计数误报 |
| 6 | LED1-4 物理灯位未逐灯核对 | 状态灯语义可能错位一格 | X1A 第一步逐灯照丝印 |
| 7 | `audio_bytes` 字段未从 `song_index_db` 导出 | WS 进度条与 seek 阻塞 | X1B 一并做 |
| 8 | 数码管只显示测试图案/全灭 | MM:SS/错误码未接入 | X1C 新建业务 mux |
| 9 | 歌词是固化单份 ROM | 切曲不换歌词 | X4 新建 `lyric_loader` 从 SD 加载 |
| 10 | EC2 旋钮无业务消费者 | 右旋钮闲置 | X5 建 OSD 调参系统 |
| 11 | iverilog 不在 PATH | 15 帧 IR 向量仿真未跑 | X0 修复环境或用 TD 仿真器 |
| 12 | 32 位 48 kHz 样本计数 24.86h 回绕 | 24h 长稳覆盖不到边界 | X8 单独仿真回绕 |
| 13 | 单声道无 L-R 信息 | 人声消除不可实现 | 不做；文档标"依赖立体声资产的远期项" |
| 14 | `S704_ec2_menu` 草稿与 HEAD 分叉 | 直接合并会回退 KEY07/11 新语义 | X5 全新设计，不 rebase |
| 15 | 产品交互.md 仍是旧映射 | 协作者误读 | 以本文 §6 为权威；旧文档加废弃提示 |

### 8.2 优化空间（远期）

1. **EC2 OSD 调参**：参考 EC11-B 三态 FSM（idle/select/adjust），9 项参数环形列表，浮动小窗右上角，青色/金色边框区分选/调状态
2. **WS2812 八灯灯效**：从标定工程移植驱动，律动（PCM 旁路饱和绝对值）+ 进度条（`cur_time_ms / total_ms`）
3. **256 点 FFT**：替换当前时域波形为真实频谱，预算 ≤4 BRAM/≤4 DSP
4. **W25Q64 用户 Flash**：参数掉电持久化（A/B 双槽日志）
5. **多曲歌词**：PC 工具扩展每曲行表，SD 装载替代固化 ROM
6. **自动演示模式**：SW4 使能，无人操作时轮播封面 + 曲目
7. **参数淡变**：音量/亮度调整时平滑过渡，避免台阶感

---

## 附录：关键文件速查

| 想看什么 | 去哪个文件 |
|---|---|
| 事件怎么编码 | `src/include/exp_event_defs.vh` |
| 索引文件格式 | `src/include/song_index_defs.vh` |
| 按键/拨码/红外怎么解码 | `src/io/expansion_io_hub.v` + 子模块 |
| 事件怎么仲裁 | `src/io/ui_event_bus.v` |
| 红外怎么白名单 | `src/io/ui_command_router.v` |
| 事件怎么跨时钟域 | `src/io/ui_event_bridge.v`（toggle）+ `src/io/browse_fsm.v`（3FF+边沿） |
| 选曲怎么路由 | `src/io/browse_fsm.v` |
| 播放/暂停/音量/EOF 怎么决策 | `src/audio/play_ctrl.v` |
| PCM 怎么从 SD 流到 I2S | `src/audio/wav_stream_player.v` + `timebase_48k.v` |
| 故障怎么自动恢复 | `src/SD/media_supervisor.v` |
| 诊断计数 | `src/io/health_monitor.v` |
| 顶层怎么例化所有模块 | `src/top_tf_hdmi_audio.v`（98 KB，用 Grep 找模块名） |
| PC 怎么打包镜像 | `tools/vinyl_packer.py` |
| 引脚约束 | `constraints/pin.adc` |
| 时序约束 | `constraints/timing.sdc` |
| 阶段交付文档 | `doc/开发资料/` 下各 `VinylFPGA_S*_*.md` |

---

*本文档由代码实际阅读生成，后续代码变更时应同步更新对应章节。*
