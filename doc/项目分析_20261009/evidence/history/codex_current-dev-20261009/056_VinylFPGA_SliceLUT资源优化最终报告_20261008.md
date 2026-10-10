# VinylFPGA Slice / LUT 资源优化最终报告

- 项目：VinylFPGA（FPGA 黑胶风格媒体播放器）
- 目标器件：安路 Anlogic **EG4S20BG256**（19,600 LUT / 19,600 REG / 9,800 Slice / 64×BRAM9K + 16×BRAM32K / 29 DSP / 4 PLL）
- 工具链：TD 6.2.168116（综合/布局布线/位流）、Icarus Verilog（仿真）
- 报告日期：2026-10-08
- 结论口径：本报告严格区分 **【已确认】**（读到源码/报告原文）与 **【估算/待验证】**（需重新综合或打包核对）。

---

## 0. 一页结论（先看这里）

1. **《优化.md》里几乎所有"低风险结构性 LUT 优化"在当前源码中都已经做完了。** 逐条核对其 9 项措施：**6 项已在源码中实现**、**2 项与 `prj/r0_opt` 已否决的试验重叠或被证伪**、**仅 1 项（`lrc_cache` 减容）真实可做，且其收益在 BRAM 而不在 LUT**。
2. 因此，**"靠这批微调 −595 LUT、把 LUT 从 17,110 压到 ≤16,500"在当前源码上不成立**。《优化.md》的总账是把"已完成项"当成"待做项"重复计了一次收益。
3. 当前真正的物理矛盾是 **Place Slices ≈ 99%、布线拥塞（Net Delay 占比高）**，LUT 站点口径 17,110（87.30%），距门禁 16,500 缺 **约 610**。这个缺口**靠位宽收窄类微调补不上**，现实只有三条路：
   - **① FAT32 栈深度重构**（最大 LUT 块 `fat32_media_loader` 3,695 LUT；潜在收益最大，但**从未验证、高风险**，必须先做 spike）；
   - **② 精简"非常驻/非核心"显示功能**（功能取舍，确定可降 LUT/Slice）；
   - **③ 换更大容量器件**（独立立项，周期最长但最彻底）。
4. **但 C4（背景+MV 组合取像）眼下真正的硬卡点是 BRAM：58/64（90.62%），C4 行缓存还需约 6 块。`lrc_cache` 字形减容是本报告核实的、性价比最高、可立即执行的 −6~8 BRAM 优化**，应最先做。
5. **推荐顺序**：版本卫生 + 干净基线 → `lrc_cache` 减容（拿 BRAM）→ `ui_asset_loader` CRC 打拍（拿时序）→ 重跑一次干净 Place/Route 看**真实**余量 → 据此在"FAT32 重构 / 功能精简 / 换器件"中拍板 → **之后才开始写 C4/U3**。

---

## 1. 资源现状（含"两个 LUT 数字"的口径澄清）

### 1.1 资源占用总表

数据来源：`prj/r0_signoff/closeout_gate/gate_latest.area`（旧源码基线；当前源码仅 `fat32_media_loader.v` 一个文件与之不同，故下表对当前为"上界参考"）。

| 资源 | 实测占用 | 器件上限 | 占用率 | 门禁要求 | 判定 |
|---|---|---|---|---|---|
| LUT（站点利用率口径 `#lut`） | **17,110** | 19,600 | **87.30%** | ≤ 16,500 | 超 **610** |
| LUT（物理映射组合逻辑 `#Total_luts`） | 13,568 | 19,600 | 69.2% | — | 参考口径 |
| REG | 11,986 | 19,600 | 61.15% | — | 健康 |
| BRAM9K | **58** | 64 | **90.62%** | ≤ 60（为 C4 预留） | 仅剩 6 块 |
| DSP | 17 | 29 | 58.62% | — | 充裕（余 12） |
| Slices（Place，seed5） | **9,727** | 9,800 | **99.26%** | ≤ 90%（88% 健康） | 拥塞窒息 |
| Hold WNS（Place seed5） | −0.011 ns（11 端点） | ≥ 0 | — | TNS=0 | 不收敛 |
| Route（最新完整构建 phy_1） | Setup −4.013 ns / TNS −1027 ns / 708 端点 | 0 违例 | — | 0 overflow | 失败、不可烧录 |

> 补充：U2 配置在 Place 阶段被 TD 直接拒绝（错误 **PHY-9009**，MSlice 5223 > 4900），因此 U2 没有 route/timing/bitgen 结果。

### 1.2 为什么有 13,568 和 17,110 两个 LUT 数字（已确认，非造假）

`gate_latest.area` 同时给出两行：

- `#Total_luts = 13568`（= `#lut4` 11,731 + `#lut5` 1,837）：这是**技术映射后真正的组合 LUT 数**；
- `#lut = 17110 out of 19600 = 87.30%`：这是**器件 LUT 站点利用率**，除组合 LUT 外还包含 **ripple/进位链等占用的 LUT 站点**（分层表中每个模块都有独立的 `ripple` 列，Top ripple=1,747）。

两者统计口径不同。**项目门禁采用 `#lut=17110（87.30%）这一行**；13,568 仅用于观察纯组合逻辑规模。报告中凡提"LUT 超标 610"，均指 17,110 对 16,500。

---

## 2. 优化点逐条核查（对《优化.md》9 项 + 《优先盘点》M1~M7）

下表"核查结论"中的证据均为本次直接读取当前源码所得。

| 编号 | 措施（《优化.md》） | 核查结论 | 证据（文件 : 行） |
|---|---|---|---|
| O1 | `song_index_db` 消除 512 个冗余 FF（−150 LUT/−552 FF） | **✅ 已在当前源码完成，收益不成立** | `song_cover0..3/song_audio0..3` 已是 `output wire`（`src/SD/song_index_db.v:50-57`），用组合 `assign ... valid ? {...} : 64'd0` 直连（`:132-139`）；注释明确"no second 512-bit output bank is needed"（`:128-131`） |
| O2a | 扇区仲裁打拍（−95 LUT，改善 100MHz 时序） | **🟡 改动已在工作区但未提交、未做全流程验证** | `src/SD/fat32_media_loader.v`（git 未提交，仲裁"请求/LBA 快照 + 单拍物理命令 + cooldown"重写，+101/−27 行）；新测试台 `sim/tb_r0_sector_arbitration.v` 也未提交 |
| O2b | `quadrature_decoder` 稳定计数器 32 位 → 动态位宽 | **✅ 已完成** | `src/io/quadrature_decoder.v:21` 已用 `COUNT_W=$clog2(STABLE_CYCLES+1)`，`:24` 为 `reg [COUNT_W-1:0] stable_count`；注释"R0-B…原实现固定 32bit"（`:19-20`） |
| O3 | `video_rgb_to_axis` 计数器/比较器收窄（−30 LUT） | **⚠️ 收益被严重夸大** | `S_x_cnt` 已为 11 位、比较 `==11'd639`（`src/video_rgb_to_axis_640x480.v:18,58`）；639 只需 10 位，收 1 位实际仅省几个 LUT，**不是 30**。该模块 365 LUT 主要是 24 位数据/控制通路，非计数器 |
| O4 | `ui_asset_loader` 比较器合并 / 流式解包（−150~300 LUT） | **🟡 一半真实**：CRC 打拍是**时序**优化（见 §3 P1-A）；"解析器合并省 200 LUT"**无证据**，且 r0_opt 同名试验 **+211 LUT** | CRC 组合链见 `src/SD/ui_asset_loader.v:130-157,359,431`；已否决试验 `prj/r0_opt/ui_asset_loader/`（gate #lut 17,321） |
| O5 | `fat32_volume_scanner` 寻址位宽/目录匹配（−80~150 LUT） | **❌ 与已否决试验重叠，方向不成立** | r0_opt `volume_scanner_fields` 实测 **17,196（+86）**，不降反升；见 `prj/r0_opt/volume_scanner_fields/` |
| O6 | `fat32_media_loader` 消除 32 位常量扩展、width/height 收窄（−40~80 LUT） | **✅ 已完成** | `width/height` 已是 `reg [15:0]`（`src/SD/fat32_media_loader.v:334-335`）；`header_byte_cnt` 已是 `reg [5:0]`（`:341`），case 全部用 `6'd18/6'd52/6'd53`、`+6'd1`（`:1080-1127`） |
| O7 | **`lrc_cache` 容量 255→128 字形（−6~8 BRAM）** | **🟢 真实可做，本报告首要落地项** | 现 `glyph_mem [0:4095]`（256 字形×16 行）、地址 12 位（`src/display/lrc_cache.v:23,37`）；上限 `UI_MAX_GLYPHS=255/UI_GLYPH_SLOTS=256`（`src/include/ui_asset_defs.vh:104-105`）。详见 §3 P0-B |
| O8 | `boot_layer` Logo ROM 紧凑（−2~4 BRAM，备选） | **🟡 备选，收益为估算** | 现 `boot_logo_rom` 占 10 BRAM（`gate_latest_hier.area`）；需重跑 `tools/gen_boot_logo.py` 调欠采样/包围盒 |
| O9 | 27 路独立消抖器合并为单时基（−300~450 LUT） | **✅ 架构已重构完成，收益不成立** | `key_dip_monitor` 只例化 **1 个** `debounce_tick` + **1 个** `debounce_bank`（`src/io/key_dip_monitor.v:38,59`）；`debounce_bank` 各路仅在 tick 时累加、计数器位宽 `$clog2(STABLE_TICKS+1)`（`src/io/debounce_bank.v:18,40-51`）；不存在 27 个 19 位独立计数器 |

### 2.1 另外两处《优化.md》的事实错误（需纠正，避免白做）

- **`audio_source_mux` 不是死代码。【已确认】** 它在顶层被真实例化并连接 WAV/琶音音源与 HDMI 桥（`src/top_tf_hdmi_audio.v:2526-2543`）。其 0 LUT 是因为纯组合选择被相邻逻辑吸收，而非未使用。《优化.md》把它列入"13 个待删死代码"是错误的。
- **不需要用 acceptance 的 666 行 `.al` 去"补齐 30+ 缺失条目"。【已确认】** 顶层 `top_tf_hdmi_audio.v:9-75` 用 54 条 `` `include `` 文本包含子模块，且每个子模块带模块级包含保护；`.al` 显式列出 69 个 `.v`、去重后 115 个设计文件。**裁剪 `.al` 显式条目不会得到缺模块固件**（include 机制兜底）。
- 已常量关闭的 UART/诊断模式**不能再计面积收益**；仅删文件名、换 seed 也不能证明降利用率。

### 2.2 `prj/r0_opt` 结构试验结果（全部未低于基线 17,110，禁止重走）

| 试验目录 | gate `#lut` | 相对基线 |
|---|---|---|
| `arb_prereg` | 17,101 | −9 |
| `volume_scanner_fields` | 17,196 | +86 |
| `packio` | 17,259 | +149 |
| `arb_input_reg` | 17,264 | +154 |
| `ui_asset_loader` | 17,321 | +211 |
| `songidx_input_pipe` | 17,460 | +350 |
| `songidx_case_mutex` | 17,779 | +669 |
| `songidx_payload_regs` | 18,219 | +1,109 |

> 结论：**"给输入/载荷加寄存器、改 case 互斥、字段拆分"这一类微结构改动，在本工程上要么无效要么反而增 LUT。** 原因是这些路径本就被时序约束推着走，额外打拍只是把组合逻辑换成等量寄存器+选择器。

---

## 3. 真正可落地的优化方案（动作 / 收益 / 风险 / 验证）

### P0-A 版本卫生与干净基线（前置，0 逻辑风险）

当前没有一份"对应当前源码、时序收敛"的位流：最新完整位流（`prj/VinylFPGA_Runs/phy_1`、`best_result/VinylFPGA.bit`，16:25）**时序失败**；最后确认可用的是 `prj/VinylFPGA_C2_corelink_20261008.bit`（但不含 U2，不能代表当前网表）。

- **动作**：
  1. 固化工作区已通过定向测试的 `fat32_media_loader.v`（仲裁重写）与 `quadrature_decoder.v`，并提交新测试台 `sim/tb_r0_sector_arbitration.v`；
  2. 先跑 `python tools/verify_core_acceptance.py`（14 项基线），确认 **14/14 PASS**；
  3. 对当前源码做**一次干净的 gate → place → route 全流程**，得到"当前真实基线"，后续每项优化都与它对比。
- **收益**：0 LUT，但这是所有收益数字可信的前提。
- **风险**：极低。

### P0-B `lrc_cache` 字形减容 —— BRAM 核心突破口【本报告最高优先级功能改动】

- **机理【已确认】**：`lrc_cache` 为双时钟缓存，写侧在 sd 域、读侧在 video 域。其字形库 `glyph_mem` 按 **256 字形 × 16 行 × 16 位 = 4096×16** 满配，独占 **18 块 BRAM**（全场第一大 BRAM 消耗者）。写端口在顶层被 **UIRES（`ui_asset_loader`，上限 255 字形）与 VLRC（`lyric_loader`，上限仅 64 字形）互斥复用**（`src/top_tf_hdmi_audio.v:1335-1344`），按 UIRES 上限取尺寸。
- **真实去重字形数【待验证】**：单张专辑 4 首歌词去重后的汉字+标点通常在 80~120；**必须先用打包结果核对**，不能直接假设。
- **改动清单（把字形槽从 256 收到 128）**：
  1. `src/include/ui_asset_defs.vh`：`UI_MAX_GLYPHS 255→127`、`UI_GLYPH_SLOTS 256→128`（`:104-105`）；
  2. `src/display/lrc_cache.v`：`glyph_mem [0:4095]→[0:2047]`（`:37`），`glyph_wr_addr` 与 `glyph_rd_addr` 由 `[11:0]→[10:0]`（`:23,:31`）；
  3. `src/SD/ui_asset_loader.v`：字形写地址 `ui_glyph_wr_addr` 及字形索引字段同步收窄；
  4. 顶层 `cache_glyph_rd_addr` 等读侧地址由 12 位收 11 位（`src/top_tf_hdmi_audio.v:1418-1419`）；
  5. UIRES 打包器（`tools/` 下生成 UIRES 的脚本，字形槽上限）改为 128，**重新生成资产**；
  6. VLRC 回退路径 `LYRIC_MAX_GLYPHS=64`（`src/include/lyric_asset_defs.vh:51`）本就 ≤128，无需改。
  - 查找全部受影响信号：在 `src/` 下检索 `glyph_wr_addr|glyph_rd_addr|UI_GLYPH_SLOTS|UI_MAX_GLYPHS`，逐一对齐位宽，避免隐式补位。
- **收益【估算，需 gate 确认】**：`lrc_cache` BRAM **18 → 10~12，即 −6~8 块 BRAM9K**；LUT 基本不变。释放的 6 块恰好 1:1 对冲 C4 `playback_line_buffers` 的 6 块预算。
- **风险【中】**：① 若实际去重字形 >127 会装不下，需以打包器 `glyph_count` 为准（必要时取 160 等中间值）；② 跨多文件位宽一致性，漏改会产生隐式扩展。
- **验证**：重跑打包并记录 UIRES 头 `glyph_count ≤ 127` → gate 复核 BRAM → 跑歌词相关仿真（歌词加载/五路 OSD）→ 上板看歌词显示无缺字。

### P1-A `ui_asset_loader` CRC 打拍/流水 —— 主要收益在时序

- **机理【已确认】**：`crc32_byte` 函数把 CRC 内层 **8 轮循环在单拍内全部展开**（`src/SD/ui_asset_loader.v:130-141`），`crc_calc_next=crc32_byte(...)`（`:157`）为纯组合，且同拍还要做最终异或+32 位比较（`:431`）。路径为 `crc_calc → 8 轮 CRC → 异反 → 32 位比较 → hdr_crc_ok`，是 gate 报告最差路径（约 9 级逻辑、−1.229 ns）。
- **动作（择一，建议先做最简单的）**：
  1. **先把"比较"后移一拍**：CRC 结果先打一拍再与期望值比较（切断"CRC→宽比较"这段），改动最小；
  2. 若仍不达标，**把 8 轮 CRC 拆成 2 段（每段 4 轮）**，中间加流水寄存器；CRC 窗口每槽/头仅 4 字节，允许用 valid/ready 或局部停顿换 2 拍/字节的吞吐；
  3. 兜底：改成逐位（bit-serial）CRC 小引擎，8 拍/字节，面积最小但吞吐最低，仅在装载期可停顿时使用。
- **收益【估算】**：主要是**时序 WNS/TNS 改善**；LUT 可能略增（流水寄存器）或略降，**不要把它计成 LUT 收益**。
- **风险【中】**：需保证 CRC 字节计数与流水延迟对齐，否则校验错位。
- **验证**：`tb_uires_*`/UIRES 校验类仿真必须全绿（含故意损坏 CRC 的反例），再看 gate 最差路径是否移出 CRC。

### P1-B 端口小清理（降噪，收益极小）

- **【已确认】** `song_index_db` 的 `.busy()` 在 loader 处悬空（`src/SD/fat32_media_loader.v:649`），综合已裁剪；`song_flags` 则**被真实读取**（`:281 idx_lyric_shifted`），**不可删**。
- **动作**：可移除悬空的 `busy` 端口及其内部赋值；保留 `song_flags`。
- **收益**：约 1 个 FF 级别，仅为接口整洁，**不计入资源账**。

### P2 FAT32 栈深度重构 —— LUT 最大块，高风险，必须 spike 先行

- **现状【已确认】**：`sd_card_bmp` 全家桶 4,036 LUT，其中 `fat32_media_loader` 3,695 LUT / 3,391 REG，是全场最大单体；它把"卷扫描 + 索引/流解析 + 扇区仲裁 + BMP/音频头解析"多职责耦合在一个模块里。
- **方向【待验证，非承诺收益】**：按职责拆分为"卷扫描 / 索引库 / 文件流 / 头解析 / 扇区适配"更小且可复用的子模块，合并重复的 32 位地址/大小通路，静态描述符解析后即释放。
- **重要警告**：这是**唯一可能贡献数百 LUT 级收益**的方向，但 r0_opt 已证明"想当然的局部打拍/字段改动"普遍失败。**必须先开一个独立 spike 分支**，只做一条最小可综合路径并 gate 量面积，**用数据证明收益后再投入全量重构**；否则极易投入大量时间却增 LUT。
- **风险【高】**：牵动 SD 主链路（开机/封面/音频都依赖它），回归面最大。
- **验证**：spike gate 对比 → 14 项回归 + 定向 SD/FAT 仿真 → 干净 place/route → 上板跑开机到播放全流程。

### P3 `boot_layer` Logo ROM 紧凑（备选 BRAM）

- 若 P0-B 后 BRAM 仍紧张，重跑 `tools/gen_boot_logo.py`，把裁剪包围盒欠采样倍数调高或略收 Margin，**估算** Logo ROM 10 → 6~8 块 BRAM（−2~4）。
- 风险：Logo 观感下降，需目检确认。

### P4 架构 / 器件取舍（《优先盘点》M7，需用户拍板）

当 P0/P1 做完、拿到干净 place/route 的真实余量后，若 LUT/Slice 仍过不了门禁，需要在三者中决策：

| 方案 | 内容 | 优点 | 代价 |
|---|---|---|---|
| A | 保留器件 + 全功能，主攻 FAT32 重构 | 不换硬件、功能完整 | 长周期、高风险，收益不确定 |
| B | 保留器件 + **精简非常驻非核心显示**（如非播放态常驻的特效/OSD/灯效做条件驻留或下线） | 确定降 LUT/Slice，较快 | 牺牲部分功能/观感 |
| C | **换更大容量器件** | 最彻底，后续 C4/U3/U4 余量充足 | 改管脚/工程/PCB，独立立项、周期最长 |

> 本报告**推荐**：先做 P0/P1（高性价比、确定收益），用真实数据再定；若重构 spike 证明 FAT32 能腾出 ≥600 LUT 站点则走 A，否则在 B（优先砍非核心常驻显示）与 C（若产品定位允许换料）间选择。

---

## 4. 收益与门禁对照（已验证 / 估算分列）

| 项 | LUT 站点 | BRAM9K | 时序 | 状态 |
|---|---|---|---|---|
| 当前基线（`#lut` 口径） | 17,110 | 58 | 不收敛 | 已确认 |
| P0-B `lrc_cache` 减容 | ≈ 0 | **−6 ~ −8（→50~52）** | 中性 | 收益为**估算**，需 gate |
| P1-A CRC 打拍 | ≈ 0（可能略增） | 0 | **改善 WNS/TNS** | 机制已确认，收益**待验证** |
| P2 FAT32 重构 | **潜在数百级（唯一 LUT 大头）** | 可能略降 | 改善 | **未验证/高风险**，spike 决定 |
| P3 Logo 紧凑 | 0 | −2 ~ −4（备选） | 中性 | 估算 |
| 《优化.md》宣称总账 −595 LUT / −6~8 BRAM | — | — | — | **不成立**：其中 LUT 项多为已完成/被证伪 |

**诚实结论**：确定能拿到手的是 **BRAM −6~8（P0-B）+ 时序改善（P1-A）**；**LUT 610 的缺口无法靠这批微调闭合**，必须由 P2（重构，需 spike 证明）或 P4（功能/器件取舍）来解决。

---

## 5. 保姆级执行顺序与验证闸门

> 纪律：一次只改一个模块，每步都"回归 → gate/place → 与上一步对比"，反弹立即回退。

1. **Step 1 基线固化**
   - 提交 `fat32_media_loader.v`、`quadrature_decoder.v`、`sim/tb_r0_sector_arbitration.v`；
   - `python tools/verify_core_acceptance.py` → 要求 **14/14 PASS**；
   - 跑一次干净 gate/place/route，存档为"当前真实基线"。
2. **Step 2 拿 BRAM（P0-B）**
   - 先重跑 UIRES 打包，确认 `glyph_count ≤ 127`（>127 则上调容量或精简歌词）；
   - 按 §3 P0-B 清单逐文件改位宽 → 回归 → gate；
   - 闸门：**BRAM ≤ 52**、歌词仿真全绿、上板无缺字。
3. **Step 3 拿时序（P1-A）**
   - 先做"比较后移一拍"，gate 看最差路径；不足再拆 4+4 流水；
   - 闸门：UIRES 校验正反例全绿，CRC 路径不再是最差路径。
4. **Step 4 干净 Place/Route 全流程（多 seed）**
   - 用 seed 扫描跑完整 place/route；
   - 放行门禁：**Setup WNS ≥0、Hold WNS ≥0、TNS=0、Slices ≤90%、Route overflow=0、BRAM ≤60**。
5. **Step 5 决策点**
   - 若 Step4 全绿且余量充足 → 直接进入 C4/U3 开发；
   - 若 LUT/Slice 仍卡 → 启动 **P2 FAT32 spike**；spike 无收益则按 **P4 方案 B/C** 拍板。
6. **Step 6 才开始 C4（组合行取像）/ U3（EC2 浮窗）/ U4（全页转场）**，并各自复用上述回归+门禁闭环。

---

## 6. 风险与阻塞点清单

- **无"当前源码 + 时序收敛"的位流**：在 Step1/Step4 完成前，任何面积/进度判断都建立在旧基线上。
- **Place Slices ≈99% 的布线拥塞是主矛盾**：单纯降组合 LUT 若不改变布局密度，route 仍可能失败；降 Slices/BRAM、改善时序要协同看。
- **FAT32 重构高风险**：SD 主链路依赖面最大，无 spike 数据前不应大规模改。
- **lrc_cache 减容的字形数假设**：必须以真实打包 `glyph_count` 为准，否则歌词缺字。
- **版本卫生**：13 个已跟踪文件改动未提交、34 个本地提交未推送 origin/main；建议尽快形成可追溯节点，避免优化与历史改动混在一起无法定位。

---

## 7. 结论：已确认事实 vs 推测 / 待验证

### 7.1 已确认事实（直接读到源码/报告）

1. 器件 EG4S20BG256；旧基线 gate：`#lut` 站点 **17,110（87.30%）**、`#Total_luts` 13,568、REG 11,986、**BRAM 58**、DSP 17；Place Slices seed5 **9,727（99.26%）**；最新完整 route 时序失败。
2. `song_index_db` 的 512 FF 拷贝**已消除**（wire+assign，`:132-139`）；`quadrature_decoder` 计数器**已按 clog2 收窄**（`:21`）；`fat32_media_loader` 的 width/height 与 header_byte_cnt 位宽**已收窄**（`:334-341`）；消抖**已重构为单 tick + bank**（`key_dip_monitor.v:38,59`）。
3. `prj/r0_opt` 8 个结构试验**没有一个 LUT 低于基线**；`volume_scanner_fields`、`ui_asset_loader` 等不降反升。
4. `audio_source_mux` 是**在用模块**（顶层 `:2526-2543`），不是死代码；`.al` 靠 `` `include `` 兜底，**不需要补齐 666 行**。
5. `lrc_cache` 现按 256 字形满配、占 **18 BRAM**，写端口由 UIRES(255)/VLRC(64) 互斥复用；`song_flags` 被读取、仅 `busy` 悬空。

### 7.2 推测 / 待验证（需重新打包或综合确认）

1. `lrc_cache` 减容到 128 字形可 **−6~8 BRAM**，以及实际去重字形是否 **≤127**——需打包器 `glyph_count` 与 gate 共同确认。
2. CRC 打拍能把最差路径移出 CRC、带来多少 WNS 改善——需实现后 gate 量测；LUT 可能略增。
3. FAT32 栈重构能贡献"数百 LUT 级"收益——**目前无任何验证数据**，须以 spike gate 结果为准，不应提前计入收益。
4. 方案 B（精简非常驻显示）/ 方案 C（换更大器件）的最终余量与周期——需在 Step4 真实余量基础上评估。

---

*本报告基于当前工作区源码与 12 份项目文档逐条核对生成；所有标注"估算/待验证"的收益，均须以重新综合（gate）与回归/上板结果为最终依据。*
