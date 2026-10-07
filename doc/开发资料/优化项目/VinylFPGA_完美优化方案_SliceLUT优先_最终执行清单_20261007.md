# VinylFPGA 完美优化方案：Slice/LUT 优先最终执行清单

> 日期：2026-10-07（美西 UTC-7，对应北京同日深夜）
> 工程：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`
> 器件：Anlogic EG4S20BG256；工具：Tang Dynasty v6.2.168116；顶层模块 `top`（`src/top_tf_hdmi_audio.v`）
> 源码基线：Git HEAD **`66da60f`**（工作树另有 X1/X2 调试未提交改动，见 §0.4）
> 构建基线：`prj/resource_opt_verified_20261005/X2_r15s5_20261007`，112 项输入 SHA256 与当前 src/constraints 一致
> 文档性质：**资源审计 + 功能裁剪设计 + 逐轮任务书**。本文只做分析与方案设计，未改任何生产 RTL、未重新布线、未生成位流、未烧录。

---

## 0. 一页结论（TL;DR）

1. **唯一硬瓶颈是 Slice，不是 LUT/FF/BRAM/DSP。** 当前 Slice **9288/9800 = 94.78%**（余 512），已越过 90% 风险线；LUT 17415/19600 = 88.85%。Slice 比 LUT 更早满，说明压力来自布局/布线/控制逻辑打包，而非单纯算术。
2. **最大两块逻辑体**：`sd_card_bmp_m0`（SD/FAT32，累计 3997 LUT）+ `u_expansion_integration`（J2 扩展，累计 3268 LUT）= 7265 LUT，占顶层层次 LUT 的 48.6%。
3. **用户已拍板删除的四块是确定性收益**：UART 遥测、母板 KEY1/KEY2 全部旧交互（短按/长按/组合/自动轮播/调参菜单）、左上角三行调试字符、重复消抖。预期净回收 **约 1800–2800 LUT / 800–1400 Slice**（区间估算，非实测承诺）。
4. **时序名义通过但很脆**：Setup WNS +48ps、Hold WNS +24ps；布线阶段曾出现 Hold −12ps 且日志记录"Slice>90% 跳过 hold 修复"。Slice 降下来本身就是时序裕量。
5. **执行顺序（收益/风险排序）**：`O0 冻结基线 → O1 删 UART → O2 删母板 KEY1/2 全链 → O3 删三行调试 OSD → O4 消抖共享时基 → O5 字库转 BRAM → O6 工程卫生/约束清理 → O7 双 seed 验收`。
6. **目标**：把 Slice 从 9288 压到 ≤8624（88%，本轮开发门禁），争取 ≤8232（84%），为后续 X3A/X4/X5/X6/X8（暂估 +350–790 Slice）留出预算。

---

## 1. 事实基线与可复核性

### 1.1 资源基线（直接实读 `final.area` / `final.qor`，非转述）

| 资源 | 使用 / 容量 | 占用率 | 余量 | 判断 |
|---|---:|---:|---:|---|
| **Slice** | **9288 / 9800** | **94.78%** | **512** | **首要瓶颈** |
| **LUT** | **17415 / 19600** | **88.85%** | **2185** | 第二目标 |
| FF / REG | 10527 / 19600 | 53.71% | 9073 | 非瓶颈，勿为省 FF 牺牲流水 |
| LE | 17982 | — | — | LUT-only 7455 / REG-only 567 / LUT&REG 9960 |
| BRAM9K | 40 / 64 | 62.50% | 24 | 有余量，可拿 2 块换 LUT |
| BRAM32K | 0 / 16 | 0% | 16 | 不与 BRAM9K 余量相加承诺 |
| DSP | 17 / 29 | 58.62% | 12 | 非瓶颈，保留现映射 |
| IO | 71 / 188 | 37.77% | 117 | 输入 35 / 输出 35 / 双向 1 |
| PAD | 75 / 188 | 39.89% | 113 | 与 IO 口径不同 |
| PLL | 2 / 4 | 50% | 2 | 无需删时钟 |
| GCLK | 2 / 16 | 12.50% | 14 | 非瓶颈 |

> 依据：`X2_r15s5_20261007/final.area:4–29`、`final.qor:6–24`。Slice 占用率(94.78%) 高于 LUT(88.85%)，说明应重视布局布线与寄存器打包，不能用 LUT/2 反推 Slice。

### 1.2 时序基线

| 指标 | 数值 | 依据 |
|---|---:|---|
| Setup WNS | **+48 ps** | `final.qor` |
| Setup TNS / 违例端点 | 0 / 0 | `final.qor` |
| Hold WNS | **+24 ps** | `final.qor`（Stage6 hold-fix-by-pin 后） |
| Hold TNS / 违例端点 | 0 / 0 | `final.qor` |
| 布线阶段 Hold 历史 | 曾 −12ps / TNS −18 / 3 端点 | `final_timing.rpt`、`native_build.log` |
| 最差 Setup 路径 | `sd_card_bmp_m0/fat32_media_loader_m0`（pixel_byte_cnt/pixel_count） | `final.timing`，100MHz 域 |

**结论**：时序是"条件通过"，不是"裕量充足"。Slice 压回 90% 以下，hold 修复就不必再依赖边界补丁。

### 1.3 时钟域

| 时钟 | 频率 | 主要消费者 |
|---|---:|---|
| `clk` | 50 MHz | J2 输入、事件总线、UART、LED/WS/蜂鸣 |
| `sd_card_clk` | 100 MHz | SD/FAT32、媒体、Seek、**母板旧 KEY 逻辑**、param_menu |
| `ext_mem_clk` | 125 MHz | SDRAM 用户接口、帧 FIFO |
| `ext_mem_clk_sft` | 125MHz 相移 | SDRAM 硬 IP 采样 |
| `video_clk` | 25 MHz | 像素、歌词、Logo、PCM 时基、HDMI 核 |
| `hdmi_5x_clk` | 125 MHz | TMDS 串化 |

> 注意：`param_menu_controller` 与两个 `key_press_hold` 都挂在 **100MHz `sd_card_clk`** 域（`top:705`、`top:1022`、`top:1037`）。删它们同时减轻最紧、端点最多的 100MHz 域——这是 O2 时序收益的来源。

### 1.4 工作树状态提醒（动手前必须知道）

`git status` 显示 HEAD `66da60f` 之上有**未提交改动**，包括 `top_tf_hdmi_audio.v`、`expansion_integration.v`、`seg_business_mux.v`、`timebase_48k.v`、`s6_video_layer.v`、`mv_frame_scheduler.v` 等，以及一批 `sim/tb_x1x2_*.v` 新测试和 `tools/verify_x1x2_repair.py`。**O0 第一步必须先提交或 stash 这些改动**，否则"当前 112 项哈希基线"与工作树不一致，后续差分无法归因。

---

## 2. 模块与功能盘点（顶层例化与依赖）

`src/` 共 105 个 `.v`（含加密 IP 与仅宏文件），有效逻辑层次见 `gate.area` 194 行实例树。核心依赖图：

```text
top
 ├─ sys_pll / video_pll → 各域 reset_sync
 ├─ sd_card_bmp_m0 (100MHz) ─┬─ fat32_media_loader ─ volume_scanner/song_index_db/file_streamer
 │                           ├─ sd_card_top → sd_cmd/sec_rw/spi_master
 │                           └─ u_key_auto(=key_press_debounce)  ←【O2 删除：KEY2 自动轮播/长按上一张】
 ├─ media_supervisor / media_probe   ←【保留：SD 恢复/探测/错误】
 ├─ frame_read_write → 写/读 FIFO → SDRAM(U3)；thumbnail_reader 经读仲裁共享 SDRAM
 ├─ WAV/MV 扇区仲裁 → wav_stream_player / mv_stream_player
 ├─ play_ctrl → seek_controller / stream_session   ←【保留 X2 行为】
 ├─ expansion_integration (50MHz) ─┬─ expansion_io_hub → 18路J2键/DIP + 2编码器 + NEC
 │                                  ├─ ui_event_bus → ui_command_router → ui_event_bridge → browse/play
 │                                  ├─ board_key_sw_monitor → KEY3/SW（KEY1/2 待撤）
 │                                  ├─ health_monitor → LED4 错误锁存        ←【O1 精简保留】
 │                                  ├─ exp_echo_reporter → baud/tx/UART     ←【O1 删除】
 │                                  └─ LED/WS effects→driver / buzzer_feedback
 ├─ u_param_menu_controller (100MHz) ←【O2 删除：母板双键调亮度/对比度菜单】
 ├─ key_next_transition / key_thumb_left_confirm (两个 key_press_hold,100MHz) ←【O2 删除】
 ├─ video_delay → 画质 → 转场 → 旧OSD(status_osd)→ 波形 → S6 → 歌词 → Logo/消隐 → AXIS
 └─ PCM mux→volume/fade→PCM 桥、ACR→HDMI 加密核→PHY
```

### 2.1 顶层主要模块资源排序（`gate.area` 累计 LUT，父子不可相加）

| 排名 | 实例 | 累计 LUT | ripple | seq | BRAM | DSP | 处置 |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | sd_card_bmp_m0 | 3997 | 260 | 3367 | 0 | 0 | 保留主体，删 u_key_auto/自动轮播 |
| 2 | u_expansion_integration | 3268 | 517 | 1768 | 0 | 0 | **删 reporter + 精简 health + 消抖共享** |
| 3 | hdmi_1_4b_transmitter_core_wrapper | 1248 | 149 | 1503 | 16 | 0 | 黑盒保留 |
| 4 | u_hdmi_1_4b...（含） | — | — | — | — | — | — |
| 5 | u_s6_video_layer | 628 | 131 | 312 | 0 | 4 | 保留（黑胶/MV 主题） |
| 6 | u_lrc_osd | 623 | 13 | 88 | 0 | 0 | 保留；**其下 u_font_rom 424 LUT → O5 BRAM** |
| 7 | u_video_rgb_to_axis_640x480 | 597 | 0 | 26 | 0 | 0 | 保留（勿轻信"能省 250"，见 §5.3） |
| 8 | frame_read_write_m0 | 471 | 115 | 357 | 4 | 0 | 保留 |
| 9 | u_wav_stream_player | 448 | 69 | 292 | 8 | 0 | 保留（音频缓冲语义） |
| 10 | u_seek_controller | 337 | 27 | 230 | 0 | 0 | 保留（X2 新功能） |
| 11 | u_thumbnail_view_reader | 294 | 65 | 246 | 2 | 1 | 保留 |
| 12 | **u_param_menu_controller** | **267** | 41 | 168 | 0 | 0 | **【O2 删除】** |
| 13 | u_ui_event_bridge | 203 | 45 | 54 | 0 | 0 | 保留 |
| 14 | u_sync_fade_gain | 165 | 0 | 101 | 0 | 0 | 保留 |
| 15 | u_media_supervisor | 145 | 28 | 62 | 0 | 0 | 保留 |
| 16 | u_boot_layer | 142 | 40 | 53 | 10 | 3 | 保留（Logo 已优化分组） |

### 2.2 深入热点（O1/O2 的具体体量）

| 子实例 | LUT/ripple/seq | 处置 |
|---|---|---|
| fat32_media_loader_m0 | 3491/221/3060 | 不动（碰 100MHz 与媒体可靠性，风险高） |
| **u_exp_echo_reporter** | **860/23/358** | **【O1 删除】含 baud/tx、96B 报文缓冲、STAT/ERR 格式化** |
| u_expansion_io_hub / u_key_dip_monitor | 738/198/432 | 18 路 J2 键/DIP 消抖，**O4 共享时基** |
| u_board_key_sw_monitor | 267/52/187 | 母板 3 键+4SW；O2 后 KEY_COUNT 3→1 |
| u_health_monitor | 112/43/100 | **O1 精简**：保留 err_code→LED4，删 UART 计数/定时 |
| u_key_next_transition + u_key_thumb_left_confirm | 169/26/110 | **【O2 删除】两个母板短/长按识别器** |
| sd_card_bmp_m0/u_key_auto | 36/6/24 | **【O2 删除】KEY2 在 100MHz 域再消抖** |
| **u_lrc_osd/u_font_rom** | **424/0/0** | **【O5 转 BRAM】组合 case** |

---

## 3. 删除项结构化清单（确定删 vs 需确认）

### 3.1 ✅ 确定可删除（用户已拍板，按任务回归后合入）

| # | 项 | 代码落点（已实读核对） | 删除闭包 | ⛔ 禁止误删 |
|---|---|---|---|---|
| D1 | **UART 遥测整条** | `top:19-20` include exp_uart_tx/exp_echo_reporter；`expansion_integration.v:320-344` u_exp_echo_reporter；`top:126 ECHO_TEST_ENABLE`；`top:2457 .ECHO_ENABLE`；`top:112/2482 uart_tx`；`pin.adc:90 uart_tx=D12` | reporter、96B `msg` 缓冲、文本格式化 task、baud_tick、exp_uart_tx、只供串口的 STAT 定时/版本号/饱和计数/队列溢出私有 CDC | ui_event_bus、command_router、IR、媒体错误恢复、`io_ready/present_count`（DIP 热插拔用） |
| D2 | **母板 KEY1/KEY2 调参菜单** | `top:698-718 u_param_menu_controller`（直接消费原始 key1/key2）；`io/param_menu_controller.v` | combo/hold/idle/debounce、menu_event/menu_active/cfg_* 副本、BxxCyy 显示 | 画质默认值 brightness=255/contrast=128 常量、像素流水延时；未来 EC2/CSR 协议接口 |
| D3 | **母板 KEY1/KEY2 短/长按** | `top:1017-1028 u_key_next_transition`、`top:1032-1043 u_key_thumb_left_confirm`；`top:230-231 key1_eff_n/key2_eff_n`；`top:1200 key2_to_sd`、`top:1276`；`browse_fsm.mb_*` | 两个 key_press_hold 实例、thumb 锁、browse 中 mb_next/mb_mode/mb_left/mb_confirm | **J2 KEY01/02、KEY07/KEY11、EC1**；"上一项/缩略图确认"业务本身 |
| D4 | **KEY2 自动轮播/长按上一张** | `SD/sd_card_bmp.v:654-660 u_key_auto`（key_press_debounce）；`:111-112 auto_play_en/auto_cnt[31:0]`；`:136-137 long_press_cnt[31:0]/long_press_marked`；`:421-455,527-548` 自动分支；`:29 key_auto` 端口 | 内部再消抖、auto_play_en、32 位 auto_cnt/long_press_cnt、唯一旧触发分支 | prev_event/next_event、帧提交、四 bank 预加载、坏图重试；**X2 end_mode=E2 歌曲 EOF 自动下一曲保留** |
| D5 | **母板监控里的 KEY1/2** | `expansion_integration.v:358-369 u_board_key_sw_monitor`（KEY_COUNT=3，key_async={key3,key2,key1}）；`:408,426` board_key_fall_pulse 参与 | 两路 50MHz 消抖、Boot skip/蜂鸣中的这两键；KEY_COUNT 3→1，KEY3 fall 索引 [2]→[0] | KEY3 页面、4 路 SW、上电保护窗、500ms Boot 跳过 |
| D6 | **左上角三行调试字符** | `display/status_osd_overlay.v:95-109`（第一行 索引+1/a或e/err高低 = "1E00"）、`:112-125`（第三行 E+end_mode/F+effect = "E0F0"）、`:128-145`（第二行菜单 BxxCyy）；`top` 中该 overlay 例化与 rgb 走线 | 整个旧 overlay 实例、私有行计数/字模/font_row 函数、ui_modes/auto/menu_active 视频同步副本 | **end_mode/effect_mode 业务本身保留**（KEY09/KEY12 仍切换）；数码管错误码、LED4、消隐/重启；adjusted_pixel_x（供波形/S6/歌词/Logo）、media_id |
| D7 | **字库组合 ROM → BRAM** | `display/lrc_font_rom.v`（974 行组合 case，u_font_rom 424 LUT）；容量 60 字×16 行×16bit=15360bit | 综合后从分布式 LUT 转为 2 块 BRAM9K + 提前取行流水线 | 像素边界、hit/背景 RGB 对齐；生成器 `tools/gen_lrc_assets.py` 是源头 |
| D8 | **重复消抖器** | `io/debounce_filter.v`（每路 `[19:0] stable_cnt`，DEBOUNCE_CYCLES=400000）；原 27 路 = J2 18 + 母板 7 + 编码器按压 2 | O2 后 25 路共享 100µs clock-enable + 每通道独立稳定计数 | 编码器 A/B 正交稳定状态机（另算，不改 8ms 低速采样）；两级同步器 |

> "确定可删除" = 功能取舍已定，**不等于直接删文件就能编译过**。生产删除、测试迁移、约束清理必须同阶段闭环。

### 3.2 🟡 需确认后删除（本轮默认保留，除非你另行指示）

| 项 | 当前证据 | 建议 |
|---|---|---|
| `pcm_media_tone` 琶音测试音 | 仍例化（audio_source_mux 可选源），约 15 层次 LUT | **保留**；WAV 优先时它不发声但综合仍展开。要删需先确认无 bank 加载提示音需求 |
| 母板 KEY3、SW1–4 | KEY3=B1 切显示页；SW1 使能、SW3 诊断页、SW4 预留 | **保留**（用户只点名删 KEY1/2） |
| `health_monitor` 整体 | LED4 消费其 err_code | **不盲删**，O1 只精简到"错误寄存器+必要故障标志" |
| Logo / MV黑胶 / 歌词 / LED/WS/蜂鸣 | 属后续产品目标 | **保留**，超资源再另做产品取舍 |
| CRC/文件校验/FIFO 保护、media_supervisor、超时/probe | 坏卡容错 | **保留**，历史删改收益未证明 |
| `video_rgb_to_axis_640x480` 650 LUT | 模块仅 67 行，归属可能含跨模块逻辑 | **本轮不动**；旧 OSD 删除收益会迁移至此，须整机差分，禁止双重记账 |
| `sync_fade_gain` 同域特化 | top 中 pix_clk/aud_clk 同为 video_clk，仍有 frame 锁存/变化检测/回 255 | 后续候选，约 165 LUT 规模锚点，不预承诺 |
| seg_business_mux 独立播放计时 | `display/seg_business_mux.v` 自建 ms/秒/BCD，未接媒体时间 | 交 X6 统一，跨域+BCD 有成本，不预承诺减面积 |

### 3.3 ⚪ 已 AutoExcluded（生产面积收益为 0，仅工程清理）

11 个文件已在 `.al` 标 `AutoExcluded=true`，当前综合不含：
`src/hdmi_audio_tone_i2s_64fs.v`、`I2S_receiver.v`、`video_source_test.v`、`SD/ax_debounce.v`、`SD/bmp_read.v`、`SD/video_define.v`、`IP/PLL_HDMI_AUDIO.v`、`IP/sdram.v`、`audio/hdmi_pcm_audio_bridge.v`、`display/frame_blend.v`、`display/bilinear_8q8.v`。

> 它们**已不占 FPGA 资源**，删它们 = 0 LUT。但 `bmp_read` 被 `sim/tb_bmp_read_stability.v` 例化、`bilinear_8q8` 被 `sim/tb_bilinear_8q8.v` 例化、`hdmi_pcm_audio_bridge` 被对应 TB 例化——先把这些测试归 legacy，再移动文件，别物理删。

---

## 4. 优化收益/风险排序（最终执行顺序）

> 区间为**规划估算**，不是实测承诺。各轮在上一已接受版本上测净增量，重叠子模块收益不可相加。保守目标：净 LUT ≈ 1800–2800，Slice ≈ 800–1400。

| 优先级 | 轮次 | 优化 | 规模依据（已核） | 暂估净 LUT | FF/BRAM/DSP | 风险 |
|---|---|---|---|---:|---|---|
| **1** | **O1** | 删 UART，健康状态与传输分离 | reporter 860 + health 112 中可裁部分 | **750–1000** | 数百 FF↓；BRAM/DSP 不增 | 中低：须保留 LED4 错误与最小故障观测口 |
| **2** | **O2** | 撤销母板 KEY1/2 全链 + 32 位计数器收窄 | menu 267 + hold 169 + key_auto 36 + 母板两路 ~70 | **550–850** | 300–500 FF↓；画质常量化可能顺带减 DSP（临时，不预算） | 中：别把 J2 路径/自动下一曲误删 |
| **3** | **O3** | 三行调试 OSD 旁路 | 层次行仅 6 LUT，但可能迁入 AXIS 级 | **0–250** | 少量 FF↓ | 中低：保持像素旁路与错误替代观测 |
| **4** | **O4** | 25 路开关量共享 100µs 时基 | 27→25 路 debounce，每路省计数器/比较器 | **250–500** | 250–380 FF↓ | 中：稳定窗口/热插拔/初始化语义 |
| **5** | **O5** | 字库同步 BRAM + 提前取行 | font_rom 424 LUT，15360 bit | **280–400** | **+2 BRAM9K**，少量预取寄存器 | 中：字库映射与像素边界 |
| 6 | O6 | 生产清单/约束/旧注释/测试整理 | AutoExcluded、临时 tcl/log | 0 | 0 | 低，别弄坏回归 |
| 条件 | — | FAT 字段/算术共享、SD 只读精简 | 大模块仍有仲裁开销 | 未证明，不计预算 | — | 高：碰 100MHz 与媒体可靠性 |

**O1+O2 是主回收点。** O3 收益必须差分测量（拒绝把 AXIS 的 597 LUT 双重记账）。O4 按 O2 后 25 路预算。O2 把画质常量化后 DSP 可能临时省出 3 个，但 X5 恢复动态 BRI/CON 时会回来——不算永久余量。

---

## 5. 逐轮任务书

### O0 — 冻结基线（不动功能）
- [ ] 先把工作树未提交改动提交或 stash（见 §1.4），重新确认 HEAD 与 112 项输入哈希一致。
- [ ] 保存 `X2_r15s5_20261007` 的 `final.area/.qor/.timing`、routed.db 为回滚锚点。
- [ ] 固定生产构建 `area_prior`、seed5 主测 + seed7 对照（SynthPilot MCP 的 auto 映射结果只作综合参考，不作发布差分）。
- [ ] 跑现有回归 `tools/verify_s7_acceptance.py`、`verify_s0_s5_fixes.py`、`verify_s6.py`，记录 PASS/FAIL。
- **放行标准**：输入一致、回归清单明确、基线报告可重算。

### O1 — UART 退出生产，健康状态与传输分离
- [ ] 删 `u_exp_echo_reporter` 实例及 `exp_baud_tick`/`exp_uart_tx` 依赖；删 `top:19-20` include、`ECHO_TEST_ENABLE` generate。**禁止只在输出端 mask 而让格式化状态机继续跑。**
- [ ] `uart_tx` 引脚建议保留并固定 `1'b1`（串口空闲态），保留 `pin.adc:90 D12`，避免接收器悬空；若彻底删端口则同步删该行。
- [ ] `health_monitor` 拆为"当前错误寄存器 + 4 个 sticky 故障标志"（欠载 UR / 视频失败 VF / 事件溢出 OV / 低水位 BL），删 STAT 计时、版本号、只供串口的饱和计数；**当前错误在有效零码到来时清零，不能回退成永久 sticky。**
- [ ] 保留 `err_code→LED4`；在 SW3 诊断页用紧凑显示暴露这 4 个标志（50MHz 域锁存→两级同步到 100MHz 数码管域，允许各标志独立 1 拍延迟）。
- [ ] 负例：复位/按键/IR/Boot/媒体错误均不产生 UART 发送；旧 `tb_echo_telemetry` 改"静默且其他业务正常"。
- **陷阱**：删 UART **不要**顺手关 LED/WS/蜂鸣（`expansion_integration.v:7-17` 头注释已过时，一并更新）。

### O2 — 撤销母板 KEY1/KEY2 全链，消除重复消抖根源
- [ ] 先写负例测试：母板两键单击/长按 1s/组合/上电按住，均不改变曲目/view/auto/亮度对比度/Boot 跳过/蜂鸣；J2 对应键仍正常。
- [ ] 删 `u_param_menu_controller`（`top:698-718`）、两个 `key_press_hold`（`top:1017-1043`）、`key1_eff_n/key2_eff_n`、`key2_thumb_lock_sd`、`top:1200/1276` 相关分支。
- [ ] `browse_fsm` 删除 `mb_next/mb_mode/mb_left/mb_confirm` 接口与 OR 分支，保留 J2 prev/next/confirm/mode/home 与 KEY07/11。
- [ ] `sd_card_bmp.v` 删 `key_auto` 端口、`u_key_auto`（:654）、`auto_play_en`、`auto_cnt/long_press_cnt`（**[31:0]→可全删**，连位宽收窄都不用做）、:421-455/:527-548 自动轮播分支。**保留 prev/next、select 请求/ACK、首图/预加载/坏图重试；保留 X2 EOF 自动下一曲。**
- [ ] `u_board_key_sw_monitor`：`KEY_COUNT` 3→1，只传 key3；`key_async` 改为 {key3}，fall 位索引 [2]→[0]；Boot/蜂鸣只保留 KEY3 来源。KEY3 仍走既有 toggle 同步到 100MHz，**不把 50MHz 脉冲直连 100MHz 域**。
- [ ] `pin.adc:21-22`（key1=B2、key2=C1）随端口删除同步移除；**保留 key3=B1(97) 与 rst_n**。过渡版若暂留端口，须保证无内部消费者。
- [ ] 画质默认 `brightness=255/contrast=128`，旧菜单不可进；**不能因常量旁路而手工跳过 brightness_contrast_adjust 的输出寄存那拍**，其余像素级延迟分别核对。
- **关键裁决**："合并母板 KEY 重复消抖"在本任务里 = 删掉这两路的所有消费者，而不是把它们再送回 SD 域做第二遍消抖。

### O3 — 删除 1E00/E0F0/BxxCyy，保持像素对齐
- [ ] 删整个 `status_osd_overlay` 生产实例，原 `rgb_in` 直接送原 `rgb_out` 消费者；保留"首图未就绪且媒体错误时背景色"策略，不改 DE/VS/像素时刻。
- [ ] 删仅服务该 OSD 的 ui_modes/auto/menu_active 视频同步副本与私有行计数；**保留** end_mode/effect_mode（业务仍在）、adjusted_pixel_x、media_id、osd_error_code（仍供挂载判断）。
- [ ] 整帧逐像素比较旁路 RGB：字幕区、首末像素、DE=0、VS 翻转、出错/恢复；验证 KEY09 仍切 F0/F1/F2、KEY12 仍切 E0/E1/E2，屏幕不再出现旧状态码。
- [ ] PnR 整机差分记录 OSD 删除净收益，检查 AXIS 归属变化，**拒绝双重记账**。

### O4 — 25 路开关量共享消抖时基
- [ ] 新增 `src/io/debounce_tick.v`（50MHz 域，5000 周期=100µs，13bit 分频，单拍 clock-enable，**不是新时钟**）+ `src/io/debounce_bank.v`。
- [ ] 每物理输入保留独立两级同步器；每通道保留 level、candidate/armed、7bit 稳定计数（8ms=80 个 100µs 区间）。任一拍不连续立即清零该通道计数，不共享"任意键变化就归零"的全局计数器。
- [ ] 候选变化后首个 tick 只建起点，再累积 80 个完整区间才提交；稳定窗口 ≥8ms，额外等待 <100µs。
- [ ] 改 `key_dip_monitor`/`expansion_io_hub`/`encoder_monitor`；**A/B 正交稳定状态机不改低速采样**（`quadrature_decoder` 先不动）。
- [ ] `PRESENT_SETTLE`/热插拔恢复窗/Boot 500ms 保护窗须按新最坏稳定时间重算，不能照搬原 DEBOUNCE_CYCLES+8。
- [ ] 测试：门限 1、真实 8ms、<8ms 毛刺、tick 间毛刺、复位中按住、25 路并发、EC 正反转、IR 并发、DIP 热插拔。
- [ ] 一次 PnR 对比 25 路原实现 vs 共享实现。集中式 RAM 轮询引擎作第二候选另起轮次，不假设小数组必映 BRAM。

### O5 — 字库转 BRAM
- [ ] 改生成器 `tools/gen_lrc_assets.py` 而非手改 `lrc_font_rom.v`。容量实算 60×16×16=15360 bit，按 1024×16 = 16384 bit，**目标 +2 块 BRAM9K**（旧"+1 BRAM"估计错误）。
- [ ] 参照工程内 `boot_logo_rom.v`（已有 initial 数组+同步读成功映 BRAM 先例），选 TD 可识别模板；`rom_style` 等 Vivado 属性勿盲用。
- [ ] 接口 `clk, addr[9:0] → row[15:0]`，读延迟固定 1 拍，不复位存储数组；960–1023 地址保持 default=0。
- [ ] **像素方案：提前取字形行**，不改整条 RGB/DE 流水。字宽 16px、起始 x=96，在字边界前发下一字地址，缓存 next_row、字边界提交 active_row；实际提前拍数由仿真定。
- [ ] 对 1024 地址顺序/随机/bank 边界 511/512/末有效 959/越界 960–1023 逐拍比对；整帧逐像素对照 9 行歌词、字边界、首末扫描行、Seek/暂停/enable 切换。
- [ ] 重 PnR，确认 u_font_rom 层次 LUT 明显下降且 BRAM 增加可定位到字库实例。

### O6 — 工程卫生与约束清理（0 硬件收益）
- [ ] 11 个 AutoExcluded 文件移 legacy 目录（先处理 TB 依赖），从生产 glob 移除。
- [ ] 更新 `tools/verify_s7_acceptance.py` 等引用旧 UART/菜单的入口；旧测试归 legacy，生产回归不因缺模块失败，也不用"忽略缺失模块"掩盖。
- [ ] 清 `prj/_*.tcl`、`_enum_cmds.txt`、`minidump-*.dmp`、根目录 `td_*.logw`、`_tb_*`；**保留** `X2_r15s5_20261007` 基线与输入哈希。
- [ ] `timing.sdc:53-55` exclusive 与 77-82 asynchronous 覆盖另审，**不在面积轮次偷偷改时序例外**；IO delay 为空项另列未闭合项。
- [ ] 不删历史 bit/下载日志/用户未跟踪临时脚本做"磁盘清理"冒充 Slice 收益。

### O7 — 验收门禁
- [ ] 至少 seed5 + seed7 两候选过门禁；失败 seed 如实记录，不挑结果隐去失败。
- [ ] 全局：Setup/Hold WNS≥0、TNS=0、违例端点=0；**Slice ≤ 8624（88%）为门禁，争取 ≤8232（84%）**；BRAM9K≤64、DSP≤29。
- [ ] 功能矩阵全过：12 键×100、EC1/2 正反×100、DIP×20、IR 合法/非法/重复；J2 切曲/Seek/EOF 三策略；Logo/缩略图/MV/歌词/消隐逐像素；连续播放/暂停/切曲/坏卡；故障注入 UR/VF/OV/低水位可观察可恢复。
- [ ] 板验：1h 交叉操作、切曲/Seek 各 100 次、冷启动；**仿真 PASS 不能代替实拍画面与声音**。

---

## 6. 阶段差分表（实施时回填实测，禁止预填）

| 轮次 | 唯一变化 | Slice | LUT | REG | BRAM/DSP | Setup/Hold WNS | 回归/板验 |
|---|---|---:|---:|---:|---|---|---|
| O0 基线 | area_prior seed5，66da60f/X2_r15s5 | **9288** | **17415** | 10527 | 40/17 | +48 / +24 ps | 已归档，不重开历史板验 |
| O1 | 删 UART + health 精简 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 |
| O2 | 删母板 KEY1/2 全链 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 |
| O3 | 删三行调试 OSD | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 |
| O4 | 25 路共享消抖时基 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 |
| O5 | 字库 BRAM | 待测 | 待测 | 待测 | 待测 (+2 BRAM) | 待测 | 待测 |
| O7 终值 | 全部合入 | 目标≤8624 | 目标降 1800–2800 | — | ≤64/≤29 | ≥0/≥0 | 双 seed + 板验 |

---

## 7. 与后续开发（X3A→X8）的衔接

优化后路线：
`当前 X2 → O0–O7 资源优化与补验 → X3A 图层/转场 → X4 多曲歌词 → G-EXT → X5 EC2 浮窗/CSR → X6 参数字典 → [X7] → X8 演示`

| 原方案条款 | 优化后约定 |
|---|---|
| X5 保留母板组合键菜单 | **删除**。BRI/CON 先固定默认，X5 从 EC2/统一 param_csr 恢复动态调节 |
| UART STAT/ERR 为验收必需 | 改为 O1 非 UART 最小故障标志 + 定向仿真 + 板验 |
| 左上角 E/F 常驻调试字符 | **取消**；E/F 行为保留，必要临时反馈在后续统一 OSD 预算内 |
| 母板两键兜底 | **产品不再支持**，操作依赖 J2/IR/KEY3；操作手册须写明 J2 缺席时功能范围 |
| X4 字库/行表缓存 | 复用 O5 同步字库读接口，按"撤旧 2、加新 2+2"净增量预算 |
| X8 自动演示 | 走统一命令入口，**不得**重启 KEY2 图片定时器 |

剩余预算（仅规划额度）：X3A 10–50 + X4 120–250 + X5 200–400 + X6 0–30 + X8 20–60 = **核心 350–790 Slice**。硬公式：**当前实测 Slice + 下阶段实测增量 ≤ 8624**；若优化后只到 8488（86.6%），仅够小步开发，不能承诺 X4/X5 全装下。

---

## 8. 最终判断

- 用户选定的方向成立：**最该先做的是 O1 删 UART 与 O2 删母板 KEY1/2 整条旧交互**，它们是确定性高收益、低功能风险的入口；O4 消抖共享与 O5 字库 BRAM 负责进一步回收。
- 当前**没有依据**把 SD/FAT32、HDMI、SDRAM 整体称作冗余——它们是产品主链。
- 当前**没有依据**承诺一次达到"完美"资源数；本方案以可验证删除边界、逐轮单变量差分、双 seed + 板验作为完成标准。
- 本文交付的是**分析与执行方案**，尚未改动任何生产代码；所有收益区间待 O1–O7 实施后以 `final.area/.qor/.timing` 实测回填。

> 证据来源：`final.area:4-29`、`final.qor:6-24`、`gate.area` 194 行层次表、`final.timing`；源码行号对应 `66da60f`（工作树未提交改动前）；SynthPilot MCP（SynthPilot 1.4.0 Anlogic）已由前次分析对独立快照跑 `td_build(opt_gate)`，其 auto 映射结果仅作综合参考（见 `VinylFPGA_最终优化执行方案_Slice与LUT优先_20261007.md` §3.4）。后续修改后行号会移动，应以哈希、实例名、信号名重新定位。
