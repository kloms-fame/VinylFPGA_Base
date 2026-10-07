# VinylFPGA 资源占用深度分析与优化方案

> **报告日期**：2026-10-06（北京时间）
> **工程**：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`
> **器件**：安路 `EG4S20BG256`｜**顶层**：`top`｜**工具**：Tang Dynasty v6.2.168116
> **当前 HEAD**：`0828f4f` S7-04 资源优化 R1（切断乘法组合链，时序收敛）
> **报告性质**：资源诊断 + 优化方案。**本轮未修改任何产品 RTL、未烧录。**

---

# ⚠️ 第零章：必须先知道的一件事（最高优先级）

**在我做本报告分析期间（17:46–17:50），工作区发生了一次完整的 TD 构建，
结果是不收敛的。这比任何优化方案都更紧急。**

| 时点 | 快照 | LUT | Slices | Setup WNS | 违例端点 | Hold WNS | 结论 |
|---|---|---:|---:|---:|---:|---:|---|
| 已放行基线 | `OPT_R1_mul_v1`（HEAD `0828f4f`，seed 5 / area_prior） | 16062 | **8723 / 89.01%** | **+31 ps** | **0** | +11 ps | ✅ 合格 |
| **刚才的构建** | `prj/VinylFPGA_Runs`（默认 manhattan / 默认 seed） | **16936** | **9609 / 98.05%** | **−1125 ps** | **54** | **−41 ps** | ❌ **不收敛** |

**这不是"资源紧张"，这是"当前工作区已经跑不过时序"。**

## 0.1 根本原因：工作区有 16 个文件已偏离 R1 基线，且未提交

我对 `OPT_R1_mul_v1/inputs.sha256.json` 做了 103 个文件的 SHA256 全量复核：

```
checked=103   drift=16   missing=0
```

| 类别 | 数量 | 文件 |
|---|---:|---|
| 已修改未提交 | 15 | `top_tf_hdmi_audio.v`、`fat32_media_loader.v`、`sd_card_bmp.v`、`play_ctrl.v`、`wav_stream_player.v`、`video_fade_transition.v`、`expansion_integration.v`、`ui_event_bridge.v`、`health_monitor.v`、`media_supervisor.v`、`browse_fsm.v`、`thumbnail_controller.v`、`osd_overlay_24.v`、`status_osd_overlay.v`、`mv_stream_player.v`、`debounce_filter.v` |
| **新增未提交 RTL** | **3** | `src/SD/media_probe.v`(37行)、`src/audio/stream_session.v`(26行)、`src/io/cover_navigation.v`(48行) |
| 新增未提交工具 | 1 | `tools/verify_s7_acceptance.py` |

改动量：`+438 / −352` 行，其中 `top_tf_hdmi_audio.v` 单文件 `+128/−97`。

**这些新模块已通过 `` `include`` 内联进顶层并参与综合**（沿用 S1 建立的
"源码在 top 顶部 include 内联、`.al` 文件列表不完整也不会黑盒"的做法），
所以它们**确实消耗了资源**，不是摆设。

### 新增功能引入了什么

| 新模块 | 行数 | LUT | 功能意图 | 归属阶段 |
|---|---:|---:|---|---|
| `media_probe` | 37 | 40 | 客户端空闲 1 秒后发一次 LBA0 只读 CMD17，探测拔卡 | S7-02 媒体恢复 |
| `stream_session` | 26 | 17 | 切歌时停 FIFO 两端、排空不可抢占事务、换代次 | S7-06 传输控制 |
| `cover_navigation` | 48 | 27 | 转场期间的封面目标累加器，保证在飞 bank 不被覆盖 | 浏览健壮性 |

> **判断**：这 3 个模块本身很省（合计 84 LUT / 58 FF），**不是资源问题来源**。
> 但它们改动了 `play_ctrl`(+96行)、`wav_stream_player`(+59行)、
> `top_tf_hdmi_audio.v`(+128行) 等既有模块，**这些改动引发了 1526 LUT 的净增和时序塌陷**。

## 0.2 LUT 净增 1526 的分布（逐模块对比 R1）

`OPT_R1_mul_v1/gate.area`（15410）vs `VinylFPGA_Runs/syn_1/…_gate.area`（16936）：

| 模块 | R1 | 新 | Δ | 归属 |
|---|---:|---:|---:|---|
| `top`（顶层胶水逻辑） | 13875 | 14241 | **+366** | 新增实例连线与控制 |
| `ir_nec_decoder` | 290 | 434 | **+144** | 红外白名单/repeat 判定 |
| `expansion_integration` | 3028 | 3138 | +110 | 上层集成 |
| `expansion_io_hub` | 1239 | 1322 | +83 | — |
| `vinyl_renderer` | 41 | 123 | **+82** | 黑胶层（改动后） |
| `hdmi_tx_controller_wrapper` | 1042 | 1118 | +76 | 厂商核（随整体漂移） |
| `hdmi_1_4b_transmitter_core_wrapper` | 1255 | 1326 | +71 | 厂商核 |
| `hdmi_video_source` | 62 | 129 | +67 | — |
| `promax_audio_waveform` | 125 | 184 | +59 | — |
| `s6_video_layer` | 554 | 607 | +53 | — |
| `param_menu_controller` | 267 | 318 | +51 | — |
| `osd_overlay_24` / `status_osd_overlay` | 6 | 49 | +43 each | OSD 增强 |
| **`media_probe`** | 0 | 40 | +40 | **新增** |
| `thumbnail_view_reader` | 297 | 327 | +30 | — |
| **`cover_navigation`** | 0 | 27 | +27 | **新增** |
| `brightness_contrast_adjust` | 27 | 54 | +27 | — |
| `exp_echo_reporter` | 854 | 879 | +25 | — |
| `fat32_volume_scanner` | 795 | 818 | +23 | — |
| **`stream_session`** | 0 | 17 | +17 | **新增** |
| 其余 60 余个小模块 | — | — | 各 +3~+21 | — |

> **注意两个"反常"信号**：
> 1. **连厂商 HDMI 核都涨了**（+71 / +76）——说明这不是某几个模块写大了，
>    而是**全局资源压力导致的整体膨胀**（布线资源紧张迫使 TD 采取更保守的打包）。
> 2. **`video_fade_transition.v` 净减 99 行**（+89/−188）——
>    说明这轮改动**做了实质性的逻辑简化**，但简化后反而让时序更紧
>    （模块变小 → 周围密度变化 → 拥塞重排）。这是拥塞主导设计的典型症状。

## 0.3 25 条违例路径的归属（`phy_1/final_timing.rpt`，已修正解析含负值）

| 起点模块 | 条数 | 最差 | 时钟域 |
|---|---:|---:|---|
| `frame_fifo_write_m0` → `thumbnail_view_reader/burst_base_mem_reg[11].ce` | 9 | **−1.125 ns** | `ext_mem_clk` |
| `fat32_media_loader_m0`（`mult1_syn_3` 起） | 10 | **−0.791 ns** | `sd_card_clk` |
| `read_buf` FIFO 复位 | 2 | −0.041 ns | `ext_mem_clk` |
| `u_thmb_fifo` | 1 | −0.528 ns | `ext_mem_clk` |
| `u_hdmi_edid_wrapper` / `tx_controller` / `param_menu` | 各 1 | −0.012 ~ −0.020 ns | 跨域 |

**最差路径（−1.125 ns）：**
```
frame_read_write_m0/frame_fifo_write_m0/rdusedw_r_reg[1]
  → u_thumbnail_view_reader/burst_base_mem_reg[11].ce        [ext_mem_clk, 125 MHz]
```

**次差路径族（−0.791 ns，10 条，全部同一根）：**
```
fat32_media_loader_m0/mult1_syn_3
  → pixel_byte_cnt_reg[16].ce / pixel_end_reg[3..5].ce / lt4_syn_104.ce
```

> ⚠️ **重要澄清**：我核对了 `src/SD/fat32_media_loader.v`，
> **R1 的几何常量提前寄存优化仍然在位**（`:277-282` 的 `expected_pixel_count_q` /
> `required_pixel_bytes_q` / `pixel_geom_ready` 完整存在，未被回退）。
> `mult1_syn_3` 是**已寄存化乘法器的输出端**，不是被重新引入的组合乘法链。
> 所以这批违例 **不是"优化被回退"，而是"密度上升导致寄存器间布线拉长"**。

## 0.4 立即处置建议（按优先级）

| 序 | 动作 | 理由 |
|---:|---|---|
| **0** | **先决定这 16+3 个未提交改动的去留** | 当前状态既无回归记录、也不收敛，不具备任何交付资格 |
| **1** | 若保留 → 补跑三套回归 + 用 `seed 5 / area_prior` 重建（当前是 manhattan 默认模式，**不是** R1 的已验证参数） | map_mode 不同本身就会改变结果 |
| **2** | 若无法立即判定 → `git stash` 回到 R1 已验证态，先恢复"能收敛"的基线 | 有一个可回退的合格版本在手 |
| 3 | 补 S7-00 板验记录（S6 MV/黑胶） | 至今无任何板级验收基线 |
| 4 | 再执行本文档第二、三章的优化批次 | 顺序不能颠倒 |

> **我必须明确反对的做法**：在未收敛状态下去"再试几个 seed"。
> R1↔R2↔R3 已经证明该设计的 seed 收益极不稳定，**在 98% Slices 下试 seed 是浪费构建机时间**。

---

# 第一章：设计约束与不可改动项

| 约束 | 内容 | 来源 |
|---|---|---|
| 器件 | EG4S20BG256；LUT/REG 19600，BRAM9K 64，BRAM32K 16，DSP 29，PLL 4，GCLK 16 | `final.area` |
| 时钟体系 | **仅 2 个 PLL**：`clk` 50M（板级输入）、`sd_card_clk` 100M、`ext_mem_clk` 125M(+sft)、`video_clk` 25M、`hdmi_5x_clk` 125M | `constraints/timing.sdc` |
| 跨域策略 | 全部用 2FF 同步器 / gray-code 异步 FIFO / toggle 握手；五个时钟域已声明 `set_clock_groups -asynchronous` | `timing.sdc` §6 |
| 不可改动 | 6 位数码管、4 曲上限、48 kHz 单声道 PCM、MV 10 fps / 320×240、J2 实测引脚映射、DIP1 在场约定、EXT1=蜂鸣反馈 | S7 方案 §2/§3.3 |
| 验收门槛 | Setup/Hold 均非负、TNS=0、违例端点=0；**Slices 目标 ≤88%，88~90% 先减负，>90% 暂停加重型功能** | S7 方案 §3.3 |
| 本轮行为约束 | **零功能行为改变**。事件时序、红外/DIP 行为、对外接口时序不得变动 | 本次任务要求 |

## 1.1 关键时钟约束（`timing.sdc` 实际内容）

| 约束 | 值 | 评价 |
|---|---:|---|
| `create_clock clk` | 20 ns (50 MHz) | 板级输入 |
| `rename_clock sd_card_clk` | 派生自 `sys_pll_m0/plkc[0]` | 100 MHz |
| `rename_clock video_clk` | 派生自 `video_pll_m0/plkc[0]` | 25 MHz |
| `set_clock_groups -exclusive {video_clk} {hdmi_5x_clk}` | — | ✅ 正确 |
| `set_clock_groups -asynchronous` 五组 | — | ✅ 已在 S7-02 显式声明，消除了伪跨域违例 |
| `set_false_path -from [get_ports rst_n]` | — | ✅ 复位异步进入 |
| `set_false_path -to [get_regs -hier {*/s1}]` | — | ✅ 同步器首级 |
| `set_max_delay hdmi_5x_clk → HDMI 差分口` | 8.000 ns | ✅ 实测 8 条路径全 dominated，SWNS 5.427 ns |
| **Input/Output delay** | **全部空白** | ⚠️ 时序报告提示 5 输入 / 23 输出未设 IO delay |

> **时序例外是干净的**：`final.exceptions` 只有 1 条约束（HDMI max-delay 8 条路径，100% dominated），
> 没有遗留的宽泛 false path。**这排除了"靠约束掩盖问题"的可能**——当前 54 条违例是真实的。

---

# 第二章：资源占用全景与瓶颈诊断

## 2.1 已放行基线 `OPT_R1_mul_v1` 总量

| 资源 | 已用 | 总量 | 使用率 | 剩余 | 状态 |
|---|---:|---:|---:|---:|---|
| LUT | 16062 | 19600 | 81.95% | 3538 | ⚠️ |
| REG | 10152 | 19600 | 51.80% | 9448 | ✅ |
| **LE** | 16840 | — | — | — | — |
| **Slices** | **8723** | 9800 | **89.01%** | **1077** | 🔴 **已越过 88% 阈值** |
| BRAM9K | 46 | 64 | 71.88% | 18 | ⚠️ |
| BRAM32K | 0 | 16 | 0.00% | 16 | ✅ |
| DSP | 16 | 29 | 55.17% | 13 | ✅ **不是瓶颈** |
| IO | 71 | 188 | 37.77% | 117 | ✅ |
| PLL | 2 | 4 | 50.00% | 2 | ✅ |
| GCLK | 2 | 16 | 12.50% | 14 | ✅ |

> `Slices 89.01%` 已越过 S7 方案 §3.3 自己设定的 88% 减负阈值，进入"减负评估"区间。
> 按该节规定 **>90% 必须暂停加重型功能**——刚才那次构建的 98.05% 已远超该红线。

## 2.2 时钟域资源分布（`final.area` → Report Clock Domain Luts）

| 域 | 频率 | LUT(逻辑) | LUT(DRAM) | BRAM | DSP | LUT 占比 |
|---|---:|---:|---:|---:|---:|---:|
| **`sd_card_clk`** | **100 MHz** | **3509** | 0 | 10 | 1 | **27.8%** |
| `video_clk` | 25 MHz | 1817 | 44 | 44 | 14 | 14.8% |
| `clk` | 50 MHz | 1599 | 36 | 0 | 0 | 13.0% |
| `ext_mem_clk` | 125 MHz | 307 | 0 | 6 | 1 | 2.4% |
| `hdmi_5x_clk` | 125 MHz | 16 | 0 | 0 | 0 | 0.1% |

**这是本报告最有价值的一张表**：
`sd_card_clk` 只占 5 个域中的一个，却吃掉 **27.8% 的 LUT**，且是**唯一由 100 MHz 约束的非 PLL 域**（10 ns 预算，全设计最紧的非 PLL 约束）。
**降低 LUT 的边际收益在该域最高**——同一份释放既减 Slices，又直接缓解最拥塞域。

## 2.3 LUT 占用 Top-12（累计值，顶层合计 13875）

| 排名 | 实例 | 模块 | LUT | 占比 | 时钟域 | 可动性 |
|---:|---|---|---:|---:|---|---|
| 1 | `sd_card_bmp_m0` | sd_card_bmp | **4552** | **32.8%** | sd_card_clk | ✅ 主战场 |
| 2 | `u_expansion_integration` | expansion_integration | **3028** | **21.8%** | clk 50M | ✅ 主战场 |
| 3 | `u_hdmi_1_4b_transmitter_core_wrapper` | HDMI 核 | 1255 | 9.0% | hdmi_5x | ❌ 厂商 IP |
| 4 | `u_lrc_osd` | lrc_osd（含字库 424） | 634 | 4.6% | video_clk | ⚠️ 需确认 |
| 5 | `u_video_rgb_to_axis_640x480` | 像素打包 | 579 | 4.2% | video_clk | ❌ 接口规格决定 |
| 6 | `u_s6_video_layer` | MV/黑胶合成 | 554 | 4.0% | video_clk | ✅ |
| 7 | `frame_read_write_m0` | SDRAM 帧缓冲 | 470 | 3.4% | ext_mem_clk | ❌ 双缓冲必需 |
| 8 | `u_wav_stream_player` | 音频 FIFO | 313 | 2.3% | sd/video | ⚠️ 受 4096 样本语义约束 |
| 9 | `u_thumbnail_view_reader` | 缩略图读 | 297 | 2.1% | ext_mem_clk | ⚠️ **当前时序靶点** |
| 10 | `u_param_menu_controller` | 母板菜单 | 267 | 1.9% | clk 50M | ✅ S7-04 将替换 |
| 11 | `u_media_supervisor` | 媒体监督 | 125 | 0.9% | sd_card_clk | ✅ |
| 12 | `u_wav_stream_player`→`thmb_fifo` | rfifo | 64 | 0.5% | ext_mem_clk | ❌ |

**前两名合计 54.6%。**

## 2.4 LE 占用排序（LE 才是 Slices 占用的真实代理）

> `final.area` 的 `le` 列是布线后真实聚合数，比 `lut` 更能反映 Slice 压力。

| 排名 | 模块 | **LE** | LUT | ripple | FF | BRAM | DSP |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `sd_card_bmp` | **5412** | 4834 | 260 | 3890 | 0 | 1 |
| 2 | `fat32_media_loader` | **4856** | 4339 | 221 | 3569 | 0 | 1 |
| 3 | `expansion_integration` | **3577** | 3095 | 456 | 1677 | 0 | 0 |
| 4 | HDMI 核 | 1776 | 1494 | 149 | 1474 | 16 | 0 |
| 5 | **`song_index_db`** | **1544** | 1391 | 14 | **1405** | 0 | 0 |
| 6 | `expansion_io_hub` | 1499 | 1234 | 257 | 724 | 0 | 0 |
| 7 | `hdmi_tx_controller_wrapper` | 1492 | 1254 | 111 | 1307 | 14 | 0 |
| 8 | **`fat32_volume_scanner`** | **1340** | 1160 | 67 | **1050** | 0 | 0 |
| 9 | `exp_echo_reporter` | 928 | 896 | 23 | 377 | 0 | 0 |
| 10 | `key_dip_monitor`(×2) | 885+312 | 706+256 | 173+52 | 426+196 | 0 | 0 |
| 11 | `lrc_osd` | 655 | 641 | 13 | 87 | 0 | 0 |
| 12 | `video_rgb_to_axis_640x480` | 621 | **621** | **0** | 103 | 0 | 0 |

### ripple-carry（进位链）重量排名

| 模块 | ripple | 含义 |
|---|---:|---|
| `expansion_integration` | **456** | 消抖计数器 + 事件总线算术 |
| `sd_card_bmp` | 260 | — |
| `expansion_io_hub` | **257** | 27 个消抖计数器主战场 |
| `fat32_media_loader` | 221 | 32 位计数器群 |
| `key_dip_monitor` | 173 | — |
| `encoder_monitor` | 66 | AB 相位计数 |

> **`expansion_io_hub` 的 ripple 达 257**，几乎全部来自 27 个 20 位消抖计数器（§3.2 B 组）。

## 2.5 第二层展开：两个巨头内部

**`sd_card_bmp_m0` = LUT 4552 / LE 5412 / FF 3890**

| 子实例 | LUT（累计） | LUT（独占） | LE | FF |
|---|---:|---:|---:|---:|
| `fat32_media_loader_m0` | 4036 | **~1303** | 4856 | 3569 |
| └ **`u_song_index_db`** | **1231** | 1231 | **1544** | **1405** |
| └ **`u_volume_scanner`** | 795 | 795 | **1340** | **1050** |
| └ `u_file_streamer` | 546 | 546 | 569 | 289 |
| `sd_card_top_m0`（SD 协议栈） | 241 | 241 | 286 | 174 |
| └ `u_sd_sector_adapter` | 161 | 161 | 118 | 73 |
| 自身（加载 FSM + 像素打包） | ~190 | ~190 | ~250 | ~200 |

> **loader 自身独占约 1303 LUT，是全设计单一逻辑体量最大的模块。**

**`u_expansion_integration` = LUT 3028 / LE 3577 / FF 1652**

| 子实例 | LUT | LE | FF | 备注 |
|---|---:|---:|---:|---|
| `u_expansion_io_hub` | 1239 | 1499 | 743 | 含 27 个消抖器 |
| `u_exp_echo_reporter` | **854** | 928 | 358 | 串口上报 |
| `u_key_dip_monitor`(母板 7 个) | 267 | 312 | 187 | — |
| `u_ui_event_bus` | 166 | ~190 | 71 | S7-03 事件积位图 |
| `u_ui_command_router` | 127 | ~150 | 65 | S7-03 命令路由 |
| `u_health_monitor` | 117 | ~162 | 100 | S7-01 遥测 |
| `u_buzzer_feedback` | 200 | ~220 | 80 | — |
| 自身 | ~9 | — | — | 几乎为 0 |

## 2.6 FF / 寄存器占用排序（Top-8）

| 排名 | 模块 | FF | 占 10153 | 备注 |
|---:|---|---:|---:|---|
| 1 | `sd_card_bmp` | **3890** | **38.3%** | — |
| 2 | `expansion_integration` | 1677 | 16.5% | — |
| 3 | HDMI 核 | 1474 | 14.5% | ❌ 不可动 |
| 4 | **`song_index_db`** | **1405** | **13.8%** | ⭐ 本轮第一靶子 |
| 5 | `fat32_volume_scanner` | 1050 | 10.3% | 已核实为 TD 裁剪后 |
| 6 | `sdram` | 362 | 3.6% | ❌ 硬 IP |
| 7 | `hdmi_island_data_assemble` | 373 | 3.7% | ❌ 厂商核 |
| 8 | `frame_read_write` | 388 | 3.8% | ❌ 双缓冲 |

**`song_index_db` 一个模块占 13.8% 的全设计寄存器。**

## 2.7 BRAM 占用（46/64 = 71.88%）——32 块不可压缩

| 实例 | BRAM | 归属 | 可压缩性 |
|---|---:|---|---|
| `u_boot_layer` → `u_boot_logo_rom` | **16** | 开机 Logo ROM（134×149×16 色） | ❌ 固化资产，S2 已板验 |
| HDMI 核 | **16** | tx_controller 14 + EDID 2 | ❌ 厂商 IP |
| `u_wav_stream_player` | 8 | 音频环形 FIFO | ⚠️ 受 4096 样本语义约束 |
| `hdmi_island_data_gen` | — | 音频岛 FIFO 11（在 HDMI 核内） | ❌ |
| `frame_read_write_m0` | 4 | 读/写 FIFO 各 2 | ❌ 双缓冲必需 |
| `u_thumbnail_view_reader` | 2 | `u_thmb_fifo` | ⚠️ 可评估 |

**BRAM 46 块中 32 块（69.6%）不可压缩。剩余 18 块。**
方案 §3.3 的后续预算：控制 0~1、歌词 ≤4、FFT ≤4、Flash ≤1、**预留 ≥8**。
→ **当前 18 块仍够，但没有任何挥霍空间。任何"用 BRAM 换 LUT"必须先过预算关。**

## 2.8 DSP 占用（16/29 = 55.17%）——明确不是瓶颈

| 实例 | DSP |
|---|---:|
| `u_s6_video_layer`（含 `mv_frame_scheduler`） | 4 |
| `u_boot_layer` | 3 |
| `u_brightness_contrast_adjust` | 3 |
| `u_video_transition_apply` | 2 |
| `sd_card_bmp` / `pcm_media_tone` / `pcm_volume_fade` / `thumbnail_view_reader` | 各 1 |

**余量 13 个。本报告所有方案均不动 DSP。**

---

# 第三章：瓶颈成因清单（逐模块 + 源码位置）

## 【A】`song_index_db` — LUT 1231 / **FF 1405 / LE 1544**｜全设计第 5 大 LE、第 4 大 FF

**这是本轮最有价值的目标，且第一轮完全遗漏。**
它只是解析 512 字节的 INDEX.BIN，却持有 1405 个寄存器，占全设计 13.8%。

| # | 成因 | 源码位置 | 性质 | 预估释放 |
|---|---|---|---|---|
| **A1** | **`song_cover0..3` / `song_audio0..3` 共 8 个 64 位输出寄存器 = 512 FF，是 `e_cov_by[k]/e_cov_cl[k]` 与 `e_aud_by[k]/e_aud_cl[k]` 的纯拷贝** | `song_index_db.v:49-56`（端口）、`:319-326`（P_FIN 赋值） | **纯冗余**。同文件 `:124-127` 的 `song_mv0..3` **已用 `assign` 直连 `e_mv[]`**——同文件内已验证的等价写法 | **FF −512**<br>LUT −80~150 |
| **A2** | **`song_flags[15:0]` 计算后从未被消费** | 计算于 `:315-318`；唯一连接点 `fat32_media_loader.v:175` 声明 wire、`:518` 连接，**全工程零读取** | 纯死逻辑 | FF −16<br>LUT −40~70 |
| **A3** | **`hdr_max[15:0]` 解析后从不参与任何校验** | 声明 `:79`，加载 `:242-243`，复位 `:173/:205`；`fin_err` 全部分支 `:269-287` 与 `chk_ok` `:129-133` 均未引用 | 死逻辑 | FF −16 |
| **A4** | **`busy` 输出端口悬空** | 端口 `:42`，赋值 `:152/:193/:222/:291/:302`；`fat32_media_loader.v:509` 以 `()` 连接 | 死逻辑 | FF −4<br>LUT −10~25 |
| **A5** | `e_has_audio[3:0]` 随 A2 一并失效 | `:89/:192/:210/:256`，唯一消费者是 `song_flags` | A2 连带项 | FF −4 |
| **A6** | `crc32_byte` 8 轮 32 位移位异或 | `:136-147` | 真逻辑，可保守优化（§4.2 P8） | LUT −100~200 |

### A1 等价性论证（**已用仿真实测验证**，结论：安全）

```
现状：song_cover0 在 P_FIN 拍一次寄存器（:319）
     源 e_cov_by[0]/e_cov_cl[0] 在 P_STREAM 期间即已稳定
消费者：fat32_media_loader 只在 index_mode 拉高后才读 sel_cluster*/sel_size*（:531-538）
     而 index_mode 与 valid 同拍置位（:656）
```

> ⚠️ **第一版论证是有缺陷的**：我最初判断"直接 `assign` 即可，因为消费者只在
> `index_mode` 拉高后才读"。**仿真实测推翻了这一点**——
> 不加门控的 `assign` 会在 P_STREAM 期间把**移位中的中间值**暴露到输出端口，
> 实测 717 拍中 888 处失配（例：`cover0=0000000000000003` → `3600000000000003`）。
>
> **正确写法必须带 `valid` 门控**：
> ```verilog
> assign song_cover0 = valid ? {e_cov_by[0], e_cov_cl[0]} : 64'd0;
> ```
> 这样输出与"输出寄存器"实现在**每一个时刻**逐位相同：
> `valid` 之前恒 0；P_FIN 那拍随 `valid` 同时有效；之后 `e_*` 已稳定。
>
> **这正是"先仿真再综合"的价值**——若直接上综合，P1 会成为一个
> "仿真能过、功能在 P_STREAM 窗口出错"的隐性回归。

## 【B】27 个 `debounce_filter` — LUT ≈ 1026 / FF 648 / ripple ≈ 257

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| B1 | 每实例一个 20 位计数器 | `debounce_filter.v:15` `reg [19:0] stable_cnt;` | 27 实例 = **540 FF 纯计数器** |
| B2 | `DEBOUNCE_CYCLES=400_000` 与 20 位宽不匹配 | `:4` 参数、`:36` `== DEBOUNCE_CYCLES - 1` | `$clog2(400000)=19`，**多 1 位** |
| B3 | 逐拍 +1 与常数比较 | `:44` | 20 位加法器 ×27 = `expansion_io_hub` 的 ripple 257 主因 |

**27 个实例分布**（`expansion_integration` 内）：
- `u_key_dip_monitor`：12 KEY + 6 DIP = 18
- `u_board_key_sw_monitor`：3 KEY + 4 DIP = 7
- `u_encoder_monitor`：2 个 SW

> **⚠️ 第一轮已实测过 B2**：LUT −109 / Slices −64，但 **WNS 从 +31 掉到 −291 ps**。
> **这不代表 B2 无效**，而是证明在 Slices 89% 下动这 27 个实例会引发全局布局重排。
> 本报告**不重复 R2**，改列为需确认的架构级方案 F2。

## 【C】`fat32_media_loader` 自身 — 独占 LUT ≈ 1303（单模块之最）

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| **C1** | **`header_byte_cnt` 声明 `[5:0]`，但全部比较/赋值用 32 位字面量** | 声明 `:219`；复位 `:699`(`32'd0`)；case 项 `:761-792`（`32'd0`~`32'd33`）；比较 `:795`(`==32'd53`)；自增 `:807`(`+32'd1`) | 6 位寄存器配 32 位常数，TD 生成 32 位比较/加法再截断。**R1 关键路径 `rgb_byte_cnt[2]→pixel_end[26].ce` 就落在这段** |
| C2 | `width`/`height` 各 32 位，仅 `[15:0]` 参与比较 | `:212-213`，比较 `:284-285` | 高 16 位**只写不读**= 纯死逻辑（与 C3 不同，**这个可安全收窄**） |
| C3 | `dib_size` / `compression` 各 32 位 | `:211/:216`，比较 `:283/:288` | ❌ **不可收窄**：原语义是 32 位无符号比较，截断会翻转判定（第一轮判定正确） |
| C4 | `pixel_byte_cnt`/`pixel_count`/`file_len`/`data_offset`/`pixel_end` 全 32 位 | `:206/:210/:220/:221` | `file_len` 是外部 32 位量不可收窄；其余需逐一论证 |

## 【D】`fat32_volume_scanner` — LUT 795 / **FF 1050 / LE 1340**

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| D1 | `sector_buffer[0:511]` 名义 4096 FF | `:70` | ✅ **已被 TD 自动裁剪**：只保留被 `le16(11/14/17/22)`、`le32(32/36/44/454)`、`[0/13/16/450/510/511]` 读到的元素，实测仅 1050 FF。**无优化空间**（见 §4.3 假靶点） |
| D2 | `le16`/`le32` 函数用 `integer offset` 作可变下标 | `:100-113` | 每个 offset 是常量调用，TD 已展开 |

## 【E】`exp_echo_reporter` — LUT 854 / LE 928

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| E1 | `msg[0:95]` 96 字节缓冲 + 可变下标写入 | `:70-72`；写 `msg[msg_len]=b`(`:150`)；读 `msg[tx_index]`(`:543`) | 96 路 × 8 位写译码器 = LUT 854 主因 |
| E2 | 12 个互斥 `fmt_*` task 各自展开 `put_byte` | `:209-372` | TD 合成为大 mux |
| E3 | `put_dec2` 含两次 8 位除法/取模（`/10`、`%10`） | `:187-193`，唯一调用点 `:242` | ✅ **已核实输入恒 ≤12**：`ui_event_bus.v:112` `arb_arg = i`，`i < KEY_COUNT=12`。除法可展开为常量小 mux |

> `q_arg[8]`/`q_aux[8]`（8 深度 × 32 位 = 256 FF）是 **S7-03 验收项**（事件不丢失 + 溢出可见），**不可减深度**。

## 【F】`lrc_osd` / `lrc_font_rom` — LUT 634（字库 424）

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| F1 | `lrc_font_rom` 用纯组合 `case` 实现 1024×16 ROM | `lrc_font_rom.v:8-…`（1024 条） | 综合成 424 LUT，值仅 375 种不同 |
| F2 | 字库读出后立即组合选位 | `lrc_osd.v:61-63`、`col_pix = dx12[3:0]`(`:143`) | 改同步 BRAM 需加一级流水 → **改变 OSD 像素时序**（需确认，F1） |

## 【G】`video_rgb_to_axis_640x480` — 67 行占 579 LUT

| # | 成因 | 源码位置 | 说明 |
|---|---|---|---|
| G1 | 24 位 `O_video_data <= I_rgb` 逐像素无条件搬运 | `video_rgb_to_axis_640x480.v:38` | `O_video_data` 已被 `OREG` 吸收进 PAD（`final.area`：`oreg=28/ireg=32`），但 24 位通道仍占 621 LUT。**ripple=0**，说明全是纯 LUT/走线，**属接口规格决定，优化空间极小** |

---

# 第四章：优化方案

## 4.1 第一梯队：死逻辑清理（零行为风险，建议成组实施）

> **建议 4 项作为一批（`song_index_db` 死逻辑清理）一次做完一次综合**——
> 它们同属一个模块，分批做会浪费 4 次 PnR 循环。

| # | 改动 | 文件 / 行号 | 预估释放 | 推导依据 | 难度 | 风险 |
|---:|---|---|---|---|---|---|
| **P1** | `song_cover0..3`/`song_audio0..3` 由输出寄存器改 `assign` 直连，**必须带 `valid` 门控** | `song_index_db.v:49-56`（`output reg`→`output wire`）、`:319-326`（删 P_FIN 与复位赋值） | **FF −512**<br>LUT −80~150 | 8×64=512 FF 直接计数 | 低 | **低**。✅ **已仿真实测 5/5 用例通过（717 拍 0 失配）**，见 §5.1 |
| **P2** | 删除 `song_flags` 输出与计算 | `song_index_db.v:47`、`:315-318`；`fat32_media_loader.v:175/:518` | **FF −16**<br>LUT −40~70 | 全工程 grep 确认零读取 | 低 | **低**。接口变更但仅内部 |
| **P3** | 删除 `hdr_max` | `song_index_db.v:79/:173/:205/:242-243` | **FF −16** | 从不参与任何校验分支 | 低 | **低** |
| **P4** | 删除 `busy` 端口与 `e_has_audio` | `song_index_db.v:42/:152/:193/:222/:291/:302`；`:89/:192/:210/:256`；`fat32_media_loader.v:509` | **FF −8**<br>LUT −10~25 | `busy` 悬空；`e_has_audio` 唯一消费者是 P2 删的 `song_flags` | 低 | **低** |

**合计：FF −552，LUT −130~245，Slices 预估 −60~120。全部位于 `sd_card_clk` 拥塞域（3509 LUT / 27.8%），边际收益最高。**

> ⚠️ **纪律**：第一轮 R2/R3 证明——这类改动虽能降 LUT，**但可能因布局重排使 WNS 变差**。
> 因此**必须整体实施后统一综合**；若 WNS 恶化则**整批回退，不拆分抢救**。

## 4.2 第二梯队：位宽/逻辑等价收敛

| # | 改动 | 文件 / 行号 | 预估释放 | 依据 | 难度 | 风险 |
|---:|---|---|---|---|---|---|
| **P5** | `header_byte_cnt` 32 位字面量改 6 位 | `fat32_media_loader.v:699/:761-792/:795/:807` | **LUT −20~50** + 缩短当前关键路径 | 声明已 `[5:0]`，取值 0~54 < 64，逐位等价 | 低 | **低**。仿真可完全覆盖 |
| **P6** | `width`/`height` 收窄 16 位 | `fat32_media_loader.v:212-213`、`:776-783` | **FF −32** | 高 16 位**只写不读**（与 C3 的 `dib_size` 不同，**可安全收窄**） | 低 | **低**。⚠️ R3 捆绑时 WNS −615，本轮**单独做** |
| **P7** | `put_dec2` 去两次除法 | `exp_echo_reporter.v:187-193` | **LUT −30~70** | 已核实 `arb_arg=i<12`（`ui_event_bus.v:112`），值域恒 ≤12。加 `initial` 断言自检 | 低 | **低** |
| **P8** | `crc32_byte` 保守优化（保持组合单拍，只优化 8 轮展开） | `song_index_db.v:136-147` | LUT −100~200 | 反射多项式 8 轮可展开为常量 XOR 树 | 中 | ⚠️ **不用查表法**（会改时序依赖且吃 BRAM） |
| **P9** | `msg` 缓冲缩窄 | `exp_echo_reporter.v:70` | LUT −20~40 | 最长报文 `STAT` 约 54 字节，`MSG_MAX=96` 有余量 | 中 | 收益有限 |

## 4.3 已核实的"假靶点"（避免下轮重复劳动）

| 模块 | 疑点 | 核实结论 |
|---|---|---|
| `fat32_volume_scanner` | `sector_buffer[0:511]` 4096 FF？ | ❌ **不是**。TD 已按常量下标读取裁剪到 **1050 FF**。**无优化空间** |
| `e_cov_cl` 的 7 字节移位入 | `entry_off 1..7` 移入 32 位，多移 3 次 | ❌ **不是冗余**。布局 `flags@0, cluster@4..7`，靠移位把 flags 的 3 个零字节推出、保留 cluster。结果逐位正确（已对照 `song_index_defs.vh` 与 `vinyl_packer.py:359-366` 核算） |
| `song_index_db` 的 `e_mv[0:3]` | 64 位×4 = 256 FF | ❌ **不是冗余**。MV 描述符确实占条目 56~63 共 8 字节，`e_has_mv`/`e_mv` 被 `mv_metadata` 真实消费 |
| `ir_nec_decoder` 32 位移位比较 | LUT 290 | ❌ **不是冗余**。NEC 帧必须逐位移入做反码校验 |
| DSP 16/29 | 是否用 DSP 换 LUT | ❌ **不动**。余量 13 个 |
| `video_rgb_to_axis` 的 579 LUT | 逻辑极简却很大 | ❌ **不是冗余**。ripple=0，全是 24 位数据通道走线，属接口规格决定 |

## 4.4 需确认的架构级方案（**未经你确认不动**）

| # | 方案 | 涉及变更 | 为什么需要你确认 | 备选方案 |
|---|---|---|---|---|
| **F1** | 字库改同步 BRAM | `lrc_font_rom.v` + `lrc_osd.v:61-63` 加一级流水 | **改变 OSD 像素时序**。方案 §3.2 要求"每新增一级给出延迟表和像素边界测试" | 保持组合 ROM。P1~P7 若已把 Slices 带回 88% 以下，则不急 |
| **F2** | 27 路消抖合并为共享计数服务 | `debounce_filter.v` 架构 | 改变消抖**实现架构**。540 FF 是 FF 第三大来源。B2 已实测：位宽推导 LUT −109 却令 WNS −291 ps | 本方案**不依赖 F2** 即可达成主要收益 |
| **F3** | `expansion_integration` 上报路径串行化 | `exp_echo_reporter.v` 队列 | 改变 UART 上报时序；8 深度队列与溢出可见性是 **S7-03 已验收项** | 只做 P7，不动队列 |
| **F4** | Logo 与字库共用 BRAM | `boot_logo_rom.v` / `lrc_font_rom.v` | 改变 boot/歌词资源独立性；Logo 是 S2 **已板验**资产 | 保持独立。BRAM 剩 18 块尚够 S7-05~07 |
| **F5** | 降低 MV 帧率/分辨率 | `mv_frame_scheduler` | **直接改变用户可见功能**，方案已冻结 10 fps / 320×240 | **不建议**。DSP/BRAM 均非瓶颈，降规格换不来 LUT |
| **F6** | 关闭 `ECHO_ENABLE` 省 854 LUT | `exp_echo_reporter.v:27` | **删除 S7-01B 的 `STAT`/`ERR` 遥测**——那是 S7-01 验收项，也是本轮所有优化的**唯一板上观测手段** | **强烈不建议**。为省 5.3% LUT 放弃可观测性，得不偿失 |
| **F7** | **处置当前 16 个未提交改动** | 决定保留/改造/回退 | **当前工作区时序不收敛**（−1125 ps / 54 违例），且用的是 manhattan 默认模式而非已验证的 seed 5 / area_prior | 见 §0.4 |

---

# 第五章：验证与推进

## 5.1 P1 等价性验证（**已实测通过，5/5 用例**）

我搭建了双实例逐拍对比环境，**并实际跑通了全部 5 个用例（含 4 个负例）**：

| 文件 | 用途 |
|---|---|
| `sim/tb_p1_equiv.v` | 双实例逐拍对比：REF(现状) vs GOLD(P1 后)，比对 `valid/err/song_count/cover×4/audio×4/mv×4` |
| `sim/song_index_db_p1.v` | P1 优化副本（**仅**改 8 个输出的驱动方式，内部逻辑完全照抄） |

### 实测结果

| 用例 | 输入 | REF 最终状态 | 失配数 | 判定 |
|---|---|---|---:|---|
| **GOOD** | 真实 `index_only.hex` | `valid=1 err=00 count=4 cov0=0000033600000003 aud0=000008000000000c` | **0** | ✅ PASS |
| **neg_magic** | 首字节改 `00` | `valid=0 err=30`(SIDX_ERR_MAGIC) | **0** | ✅ PASS |
| **neg_crc** | 条目区字节改 `ff` | `valid=0 err=34`(SIDX_ERR_CRC) | **0** | ✅ PASS |
| **neg_trunc** | 条目区清零 | `valid=0 err=34`(CRC 先失败) | **0** | ✅ PASS |
| **neg_count** | song_count 改 5 | `valid=1 err=00 count=4`（CRC 先失败，count 未生效） | **0** | ✅ PASS |

每个用例 **717 拍逐拍比对，errors=0**。
且 4 个负例确实走到**不同错误分支**（err=30 / err=34 / valid=0），
证明测试不是"全部命中同一路径"的假通过。

### 复现命令

```bash
cd D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA
iverilog -g2005 -Isrc -Isrc/include -Isrc/SD -Isim -s tb_p1_equiv \
  -o /tmp/p1.vvp sim/tb_p1_equiv.v src/SD/song_index_db.v sim/song_index_db_p1.v
vvp /tmp/p1.vvp +blob=sim/s4_fixture/index_only.hex
```
负例 blob 由 `%TEMP%/p1neg/neg_*.hex` 提供（生成脚本见分析目录 `mkneg.py`）。

> **结论**：P1 **可以进入综合**，但**必须带 `valid` 门控**（见 §3 A1 修正后的写法）。
> 这 512 FF 的释放是**零行为风险**的，但前提是写法正确。

> ⚠️ **说明**：这两个文件是**验证脚手架**，不是产品 RTL。
> 我**未**修改 `src/` 下任何文件。若你决定不采纳 P1，删除这两个 sim 文件即可。

## 5.2 成组实施顺序（每组一次完整 PnR）

```
【前置】F7：处置当前 16 个未提交改动 → 回到可收敛状态
   │
   ├─ 批次 M1：song_index_db 死逻辑清理（P1+P2+P3+P4）
   │           FF −552 / LUT −130~245 / Slices −60~120
   │           全部在 sd_card_clk 拥塞域 → 边际收益最高
   │           └─ 若 WNS 恶化 → 整批回退，不拆分抢救
   │
   ├─ 批次 M2：位宽收敛（P5 + P6 + P7）
   │           LUT −80~170 / FF −32，并缩短 C1 关键路径
   │
   └─ 批次 M3（可选，视 M1/M2 后 Slices 落点）
               P8 crc32 保守优化 / P9 msg 缩窄
```

## 5.3 每个批次必须执行的验证链

```powershell
# 1) 冻结源码 + 约束 + 哈希
python tools/resource_opt_round.py OPT_M1_deadlogic_v1

# 2) 综合 + 布局布线（**必须用已验证参数：seed 5 / area_prior**）
python tools/build_verified_round.py OPT_M1_deadlogic_v1 --seed 5 --map-mode area_prior

# 3) 三套回归（全绿才继续）
python tools/verify_s0_s5_fixes.py     # 含 tb_fat32_index_loader / tb_song_index_db
python tools/verify_s6.py              # 8 个 S6 定向台
python tools/verify_resource_opt.py    # 含 FAT32 1543 有序事务等价
python tools/verify_s7_acceptance.py   # 新增（当前未提交）

# 4) 达标才生成 bit
python tools/release_verified_round.py OPT_M1_deadlogic_v1
```

### 放行门槛（缺一不可）

| 门槛 | 阈值 |
|---|---|
| Setup WNS | ≥ 0 |
| Hold WNS | ≥ 0（**注意：当前工作区已是 −41 ps，必须先修复**） |
| Setup/Hold TNS | = 0 |
| 违例端点 | Setup 0 / Hold 0 |
| **Slices** | **必须下降**（当前 8723 / 89.01%） |
| 三套回归 | 全 PASS，**功能行为零改变** |
| 交付物 | 新增 LUT/REG/BRAM/DSP、最差路径、遗留约束告警对照表 |

---

# 第六章：四轮优化 + 当前状态的完整对照

| 轮次 | map 模式 | LUT | REG | Slices | BRAM | DSP | place WNS | **route WNS** | 布线损失 | Setup 违例 | Hold WNS | 回归 | 结论 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| `OPT_A_base_v1` | area_prior | 16034 | 10165 | 8697 | 46 | 16 | +2556 ps | **−1 ps** | 2557 | 2 | +12 ps | — | ❌ |
| **`OPT_R1_mul_v1`** | area_prior | 16062 | 10152 | **8723** | 46 | 16 | +2719 ps | **+31 ps** | 2688 | **0** | +11 ps | 全 PASS | ✅ **当前放行** |
| `OPT_R2_deb_v1` | area_prior | **15953** | 10121 | 8659 | 46 | 16 | +2244 ps | −291 ps | 2535 | 12 | — | 全 PASS | ❌ 回退 |
| `OPT_R3_cmp_v1` | area_prior | 15990 | — | 8654 | 46 | 16 | +2509 ps | −615 ps | 3124 | 96 | — | 全 PASS | ❌ 回退 |
| **`VinylFPGA_Runs`(未提交改动)** | **manhattan 默认** | **16936** | 10120 | **9609** | 46 | 15 | −2112 ps | **−1125 ps** | 1993 | **54** | **−41 ps** | 未跑 | ❌ **不收敛** |

## 6.1 三条硬结论

**① `place` 阶段普遍有正裕量，瓶颈在布线。**
R1 的 `place` WNS 是 **+2719 ps**，route 后变成 **+31 ps**——布线吃掉 2688 ps。
`OPT_A_base_v1` 同样：place +2556 → route −1。
**综合后的逻辑深度从来不是瓶颈，绕线与拥塞才是。**

**② `route` 结果与 LUT 非单调，seed 收益不可靠。**
R2 的 LUT 最低（15953）、Slices 最小（8659），布线损失却与基线相当；
R3 的 LUT 只比基线多 −44，布线损失却最大（3124 ps）、违例最多（96）。
同一份源码在 `S7_03_v5` 是 +104 ps、在 `base_v1` 是 −1 ps。
→ **在 Slices 未降到安全线前，试 seed 是浪费构建机时间。**

**③ map_mode 本身就能改变 ±886 Slices。**
R1 用 `area_prior`（seed 5）得 8723 / 89.01%；刚才那次用默认 `manhattan` 得 **9609 / 98.05%**。
**同一份源码仅因 map 模式不同，Slices 差 886（+10.2%），Setup WNS 从 +31 ps 变成 −1125 ps。**
→ **必须把 `seed 5 / area_prior` 作为固定、可追溯的构建参数**，不可依赖 TD 默认值。

## 6.2 最差路径画像（R1 基线 vs 当前工作区）

| | R1（已放行） | 当前工作区（未收敛） |
|---|---|---|
| **最差路径** | `rgb_byte_cnt[2] → pixel_end_reg[26].ce` | `frame_fifo_write/rdusedw_r_reg[1] → thumbnail_view_reader/burst_base_mem_reg[11].ce` |
| **时钟域** | `sd_card_clk`（100 MHz） | `ext_mem_clk`（125 MHz） |
| **Slack** | **+0.031 ns** | **−1.125 ns** |
| **Logic Level** | 7（LUT5×5, LUT4×2） | — |
| **Data Path** | 9.689 ns = **cell 3.116 (32%) + net 6.573 (68%)** | — |
| **性质** | 拥塞主导（net 占 68%） | 拥塞主导 + 密度上升 |
| **R1 最差路径分布** | reset/sync 起点 12/100；FIFO gray 终点 10/100 | `fat32_media_loader` 起点 10/25；`frame_fifo_write` 9/25 |
| **最差域** | `video_clk` +0.011 ns | `video_clk` +0.003 ns |

> **重要观察**：R1 的 100 条最差路径中，**只有 7 条起点在 `fat32_media_loader`**，
> 12 条起点是复位同步寄存器，10 条终点在 FIFO gray 端口。
> → **最差路径的主体是复位分发与 FIFO 跨域，不是数据通路算术。**
> 这解释了为什么反复优化 BMP/FAT32 算术对时序帮助有限。

---

# 附录 A：器件余量速查（R1 已放行基线）

| 资源 | 已用 | 总量 | 使用率 | 剩余 |
|---|---:|---:|---:|---:|
| LUT | 16062 | 19600 | 81.95% | 3538 |
| REG | 10152 | 19600 | 51.80% | 9448 |
| LE | 16840 | — | — | — |
| **Slices** | **8723** | 9800 | **89.01%** | **1077** 🔴 |
| BRAM9K | 46 | 64 | 71.88% | 18 |
| BRAM32K | 0 | 16 | 0.00% | 16 |
| DSP | 16 | 29 | 55.17% | 13 |
| IO | 71 | 188 | 37.77% | 117 |
| PLL | 2 | 4 | 50.00% | 2 |
| GCLK | 2 | 16 | 12.50% | 14 |

## 附录 B：时序例外状态（干净，无遗留宽泛例外）

```
MCP/SMD Summary
  Max Check: Total 8, Dominated 8 (100%), Shadowed 0, Ignored 0
  约束: set_max_delay hdmi_5x_clk → HDMI_CLK_P/D0_P/D1_P/D2_P  8.000ns
  实测 SWNS 5.427 ns / STNS 0 / 违例 0

Min Check: 无
```

→ **没有靠约束掩盖时序的迹象。** 当前 54 条违例是真实的逻辑/布线问题。

## 附录 C：IO 时序约束缺口（需后续补，非本轮范围）

`timing.sdc` 中 **Input/Output delay 全部空白**（§7 自述"保持空白"）。
5 路输入（`exp_ir_rx`、`exp_enc*_a/b`、`exp_enc*_sw_n`）与 23 路输出无量化约束。
`expansion_io_hub` 内部已做逐路 2FF 同步，所以不影响内部时序收敛；
但按 S7 方案 §S7-01A 的要求，**"不因旧报告通过而宣称所有板外时序已覆盖"**，
后续新增 J2 端口时必须重新检查约束质量，**不能用假路径掩盖真实问题**。

## 附录 D：证据文件清单（可复核）

| 用途 | 路径 |
|---|---|
| 已放行基线 | `prj/resource_opt_verified_20261005/OPT_R1_mul_v1/` |
| ├ 层次分解 | `gate.area`（综合后 LUT/ripple/FF/BRAM/DSP） |
| ├ 布线后总量 | `final.area`（含 `le` 与时钟域分布） |
| ├ 布线后时序 | `final.timing`（100 条最差路径 + 例外） |
| ├ QoR 摘要 | `final.qor`（Setup/Hold WNS/TNS、Slices） |
| ├ 路由状态 | `route.status`（各阶段耗时） |
| └ 输入哈希 | `inputs.sha256.json`（103 文件，本轮已全量复核，drift=16） |
| **当前未收敛构建** | `prj/VinylFPGA_Runs/`（`syn_1/gate.qor`、`phy_1/route.qor`、`phy_1/final_timing.rpt`） |
| 前一轮分析 | `doc/开发资料/VinylFPGA_S7-04_资源占用分析与优化方案_第二轮_20261006.md` |
| 早期分析（已被本文取代） | `doc/开发资料/优化方案/VinylFPGA_S7-03_资源诊断与优化方案_20261006.md`（基于 `S6_mv_v5`，其中"reset_sync 扇出 2443 吃掉 9.075ns"等归因已被 TD 的 `set_clock_groups -asynchronous` 消解，结论已过时） |

---

*本报告为分析与方案文档。**未修改 `src/` 下任何产品 RTL，未综合，未烧录。**
新增文件仅两个验证脚手架：`sim/tb_p1_equiv.v`、`sim/song_index_db_p1.v`。*