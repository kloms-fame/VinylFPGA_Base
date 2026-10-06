# VinylFPGA 方案执行详情 —— 代码交叉核对分析（2026-10-06）

> 核对对象：`VinylFPGA_主链路开发报告_代码与规划交叉核对_20261005.md`（含 0.1~0.6 各阶段追加记录）
> 核对方法：以当前 `src/`、`constraints/`、`prj/resource_opt_verified_20261005/` 快照、Git 历史与文件 SHA256 逐项比对，文档说法一律让位于代码事实。

## 1. 总体结论

**当前工作树代码与报告"最新可放行状态"完全一致：即 S5 已放行版本 + S1~S5 全部集成逻辑，S6 黑胶层仅存模块未接顶层。**

决定性证据（SHA256 级）：

| 文件 | 当前工作树哈希 | S6_vinyl_v4/inputs.sha256.json 记录 | 一致 |
|---|---|---|---|
| `src/top_tf_hdmi_audio.v` | `8a0c2b6a…373a170` | `8a0c2b6a…373a170` | ✅ |
| `constraints/pin.adc` | `51329518…4bb68` | 同 | ✅ |
| `constraints/timing.sdc` | `a5b82442…f0b6f8` | 同 | ✅ |
| `src/io/ui_event_bridge.v` / `io/browse_fsm.v` | 同 json | 同 | ✅ |
| `src/SD/song_index_db.v` / `audio/play_ctrl.v` / `boot/boot_layer.v` | 同 json | 同 | ✅ |
| `src/display/vinyl_renderer.v` | 同 json | 同 | ✅ |

- `git status` 干净，HEAD 为 `a165f9a`"黑胶视觉层模块（S6 部分），顶层集成待收敛"——与"保留已测模块、回退顶层集成"的记录精确对应。
- S0 回滚点提交 `7c338a7`（"音频资源优化"）存在，可回溯。
- `S6_vinyl_v4/final.qor` 实测：Setup WNS +94 / TNS 0 / 违例 0，Hold WNS +19 / TNS 0 / 违例 0，Slices 7443（75.95%），RAM 46，DSP 12 —— 与报告 0.6"主线维持 S5 时序、已复核复现"逐字一致（注意：快照构建日志时间戳为 2026-10-06 01:18，即复现跑发生在 10-06 凌晨）。

## 2. 逐阶段执行详情核对

### S0 基线冻结 —— 执行到位
- `p05_s5/` 快照存在且含 bit；报告声称的 `inputs.sha256.json` 比对机制在后续每个阶段快照中被实际沿用（本节第 1 条即其成果）。
- 阶段命名规范 `resource_opt_verified_20261005/<阶段名>` 被 S1~S6 全程遵守，且每个返工版本（S1 v2~v5、S2 v2~v4、S3、S4 v1~v3、S6 v1~v4）都独立留档，失败证据（如 `S3_browse/`、`S4_index/`、种子扫描目录 `S4_index_s*`、`S6_vinyl_s*`）未删除，可审计性好。

### S1 拓展板移植 —— 代码证据齐全
- 顶层端口：`exp_key_n[11:0]`、`exp_dip_n[5:0]`、EC1/EC2 三相、`exp_ir_rx`、`exp_led_n[3:0]`、`exp_ws2812_data`、`exp_ext_o[5:0]`、`uart_tx` 全部存在（top 第 71~84 行），另有母板 `key3`、`sw1~sw4`、`board_buzzer_n`。
- 驱动模块：`io/sync_bit / debounce_filter / key_dip_monitor / quadrature_decoder / encoder_monitor / ir_nec_decoder / expansion_io_hub / ui_event_bus / exp_echo_reporter / buzzer_feedback / expansion_integration` 全部在 `src/` 且按报告所述**由 top 顶部 `include 内联**（top 第 16~38 行），杜绝黑盒的机制属实。
- 约束：J2 36 路逐脚核对与报告表 2.2 完全一致（P4/N4/N3/M5/M3/M4、N1~L5、J12/K11、L3~H4、K14/L12、K6、H3/H5/F3/E2、J11、M12~R12），输入 PULLUP、输出 DRIVESTRENGTH=8，语义正确。
- ⚠️ 小出入：0.1 节写"pin.adc 追加 J2 36 路 + uart_tx 共 37 条"——这是 v2 时点的数字；v5 加蜂鸣器后实际新增为 **42 条**（另有 `board_buzzer_n`=H11、`key3`=B1、`sw1~sw4`=C8/C7/C6/C5，且 H11/C8 等与报告 0.1 的引脚描述逐字一致）。报告该句未按 v5 更新，属记录滞后而非代码问题。

### S2 开机 Logo —— 三个根因修复均有代码实证
- `boot/boot_layer.v` + `boot/boot_logo_rom.v` 存在，top 第 1652~1689 行确认图层挂在像素链末端、`boot_active=0` 时透传 `waveform_rgb_out`（`final_rgb = (s2_boot_on && boot_active) ? boot_rgb : lrc_rgb`）。
- 第三根因修复实证：`expansion_integration.v` 第 242~263 行确有 `EV_DIP_CHANGE` 排除 + `SKIP_GUARD_CYCLES = CLK_FREQ_HZ/2`（500 ms 上电保护窗）。
- CDC 方案实证：top 第 1866~1876 行为翻转电平 `boot_skip_toggle_clk` + `boot_active` 两级同步回 clk 域，与"一次事件只消费一次"的设计一致。
- `tools/program_flash_s2_boot.tcl` 存在，Flash 固化通路有交付物。
- 状态：**S2_boot_v4 bit 已生成**（SHA256 前缀 ccd05777…），上板验收待用户断电重启确认。

### S3 主界面选歌 —— 与记录一致
- `io/ui_event_bridge.v`（clk 域四路翻转）+ `io/browse_fsm.v`（sd 域 3FF 同步+边沿还原）均存在并被 top 实例化（第 849~851 行），参数 `S3_J2_BROWSE_ENABLE=1'b1` 可整体旁路，与"母板 KEY1/KEY2 并联兜底"的说法一致。

### S4 SD 卡索引体系 —— 与记录一致
- `tools/vinyl_packer.py`、`tools/test_vinyl_packer.py`、`src/SD/song_index_db.v` 存在；`fat32_media_loader.v` 中 `USE_INDEX_BIN`/`SP_INDEX`/`index_valid` 共 8 处命中，三态+旁路属实。
- 时序代价如实：S4 后 Setup WNS 从 +106 掉到 +47 ps，为全链路最紧的一档，且首版失败的 LBA 加法链问题按记录通过删 32 位比较器收敛（种子扫描目录 `S4_index_s2~s12` 共 11 个为过程证据）。

### S5 音频播放与歌词 —— 与记录一致
- `audio/timebase_48k.v`、`audio/play_ctrl.v`、`display/lrc_osd.v` + `lrc_font_rom.v`/`lrc_lines_rom.v`、`tools/gen_lrc_assets.py` 均存在并实例化；BRAM 保持 46/64 的说法由 S5/S6_vinyl_v4 QoR 反证成立。
- ⚠️ 验收前置缺口：`tf_card_stage/` 仍是 `PIC1~4.BMP + AUDIO.PCM`，**没有 `INDEX.BIN` 和歌词资产**。S4/S5 的上板验收必须先运行 `vinyl_packer.py`（及 `gen_lrc_assets.py` 产物）重新打包 TF 卡，报告未在第 8 节"下一步"中明示这一点。

### S6 视频/黑胶 —— 记录诚实、回退干净
- `src/display/vinyl_renderer.v` 存在（"只保留已单测模块"属实），但 **top 全文无任何 `vinyl` 实例、无 `S6_VINYL_ENABLE`、无 KEY08 播控方式路径**——回退声明与代码状态逐字吻合。
- `mv_stream_player.v` 不存在；`song_index_db` 未见 `has_mv` 扩展 —— "尚未开始"的声明同样属实。
- ⚠️ 最重要出入：**`S6_vinyl_v4/` 目录内没有 `VinylFPGA_optimized.bit`**（全部 .bit 检索确认：p05_s5、S1×3、S2×4、S3×2、S4_v3、S5_play 有 bit，S6_vinyl_v4 只有 gate/route 数据与 QoR）。该快照只是"复现 S5 时序"的路由证据，**当前实际可烧录的最新 bit 仍是 `S5_play/VinylFPGA_optimized.bit`**。报告 0.6 的表述容易让读者误以为 S6_vinyl_v4 有交付 bit，建议补一句说明。
- ⚠️ 流程性风险：0.6 节记录 seed 1~7 全负（-469~-33 ps）、默认关闭仍 -267 ps，与报告 1.4 中"违例全落在既有 100 MHz `fat32_file_streamer` LBA 加法链"合起来看——**这条链已四次引发阶段级危机**（S1 seed5、S3 seed7、S4 首版、S6 全灭）。它不是 S6 的 bug，而是 S0 时代就埋下的技术债，且随 LUT 用到 69~76% 后布局自由度收缩，只会越来越难收敛。报告"下一步建议"方向正确，但建议把 `fat32_file_streamer` LBA 加法链**打拍流水线化**列为一轮独立的专项收敛（等价回归可用现有 `tb_fat32_file_streamer` + cluster_offset 等价 bench），在 MV 三帧缓冲接入**之前**做，而不是"与 MV 一起做"。

## 3. 报告内部结构性矛盾（建议修订）

报告正文第 1~3 章（"当前工程现状"、"顶层端口只有…J2 无"、"当前不存在 expansion_io_hub / ui_event_bus / browse_fsm / song_index_db / lrc_osd / vinyl_renderer"）是 **S1 动手之前的视图**，而 0.1~0.6 追加记录描述的正是这些内容的已完成状态。两半互相矛盾，虽然末尾"报告结束"有更新约定，但正文未加"（以下为 S0 时点历史视图）"之类的标记，交叉核对时极易误读。建议在正文 1.1/1.2/3.4 各节标题处加一行"⚠ 本节为 2026-10-05 S1 前基线视图，最新状态见 0.1~0.6"。

## 4. 阶段门禁符合性

| 门禁项 | S1 | S2 | S3 | S4 | S5 | S6 |
|---|---|---|---|---|---|---|
| 独立快照+bit 可复现 | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠ 快照无 bit（有意回退） |
| Setup/Hold 无负 slack | ✅ +140/+4 | ✅ +111/+3 | ✅ +106/+4 | ✅ +47/+3 | ✅ +94/+19 | ✅（=S5） |
| 仿真回归 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅（仅模块级） |
| 上板人工验收 | ✅ 用户实测通过 | ⚠ 待断电重启确认 | ⚠ 待确认 | ⚠ 待确认（且需先打包 INDEX.BIN） | ⚠ 待确认 | ⛔ 未放行 |

严格按第 7 节"上一阶段未通过不得引入下一阶段"，**S6 的尝试发生在 S2~S5 人工验收完结之前，形式上越了门禁**。但团队的处置是合规的：失败即回退、不放行、如实记录、主线保持在可烧录的 S5。真正需要提醒的是：**下一步的第一优先级不是 S6，而是把 S2~S5 的板上验收走完**——尤其是 S2 的断电重启（Flash 固化后从未验证过冷启动现象）和 S4/S5 依赖的 INDEX.BIN 重新打包，这两项是串联的：断电重启如果看到的仍是旧 S1 画面，说明固化流程或 SW5/JTAG 档位有问题，后面全部验收都不可信。

## 5. 资源与时序趋势（供 S6/MV 决策）

```text
阶段      Setup WNS   Hold WNS   LUT%     Slices%   BRAM   DSP
p05_s5    +53 ps      +3 ps      39.93    —         30     10
S1_v5     +140        +4         53.45    59.79     30     10
S2_v4     +111        +3         54.50    —         46     12
S3_v1     +106        +4         55.54    —         46     12
S4_v3     +47         +3         61.43    67.73     46     12
S5        +94         +19        69.37    75.95     46     12
S6尝试    -469~-33    —          （未收敛，回退）
```

- LUT 每阶段 +200~1600，S5 已 69.4%；MV 三帧缓冲若需新增 BRAM 仅剩 18 块，SDRAM 地址空间要为三帧 320×240×2B 预留。
- Hold 侧始终安全（≥+3 ps）；风险高度集中在 100 MHz SD 域，符合"结构负债 + 面积挤压"的判断。
- 建议 S6 收敛路径：① 先做 streamer LBA 链打拍的专项技术债回合；② 黑胶层 + MV 一次性集成时考虑 `bump_up_num`/更高种子扫描宽度之外的结构性减负（如 lrc 字库 ROM 与 vinyl 复用评估、缩略图读路径复用）；③ 若仍不收敛，按报告既有纪律回退并保持 S5 bit 为可交付主线。

*分析结束。方法：文件哈希比对 + 顶层/约束/模块源码 grep 实证 + Git 历史 + 快照 QoR/bit 检索；未重跑综合布线，时序数字引自快照 QoR 文件。*
