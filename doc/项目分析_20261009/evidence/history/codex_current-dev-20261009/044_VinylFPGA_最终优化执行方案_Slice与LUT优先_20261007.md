# VinylFPGA 最终优化执行方案：Slice / LUT 优先，衔接 X3A—X8

> 日期：2026-10-07，北京时间。工程：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`。  
> 当前源码：`66da60f`；器件：EG4S20BG256；顶层：`src/top_tf_hdmi_audio.v` 中的 `top`。  
> 文档性质：资源审计、功能裁剪设计与实施任务书。本次未修改生产 RTL、约束、原方案，未布线、生成位流或烧录。  
> 本次实际执行：读取四份指定资料和相关历史，检查 Git/RTL/报告，重算 112 项输入哈希；通过 SynthPilot MCP 对独立快照重新综合至 `opt_gate`，导出资源、时钟、参数和约束报告。  
> 给后续执行者：按本文件逐轮实施并更新实测记录；可使用 subagent-driven-development / executing-plans，但本文生成不代表任何优化任务已实现或板验通过。

**目标**：去除用户明确不要的 UART 遥测、母板 KEY1/KEY2 旧交互及长按菜单、左上角调试字符；通过共享消抖时基和 BRAM 字库腾出 Slice/LUT，保留 J2 交互、X1 状态反馈、X2 Seek 与音视频主链，继续既定拓展路线。

**架构**：生产输入统一由 J2 和保留的母板 KEY3/SW 进入；旧母板 KEY1/2 消费链整条撤销。消抖仍在 50 MHz 域，BRAM 字库优先采用提前读字形行的方式保持像素输出接口时序。移除串口传输与文本格式化，保留媒体恢复和精简故障观测。

**工具栈**：Verilog、Anlogic TD 6.2.168116、SynthPilot 1.4.0 Anlogic MCP、工程现有 Python 构建/回归工具、Icarus Verilog。所有资源结论必须标注综合或实现阶段。

## Chunk 1：事实基线、全量盘点与裁剪边界

### 1. 最终决策

推荐顺序：**O0 冻结证据 → O1 删除 UART 传输并拆分健康状态 → O2 删除母板 KEY1/2 全部旧入口 → O3 删除三行旧 OSD → O4 保留输入共享消抖时基 → O5 歌词字库 BRAM → O6 清理工程与回归入口 → O7 集成验收与后续预算准入**。

这里“删除母板 KEY1/KEY2”包括其短按、长按、组合按压、Boot 跳过与按键提示音来源；**不包括 J2 的 KEY01/KEY02**。母板 KEY3、SW1–SW4、J2 KEY01–12、EC1/EC2、IR、DIP1–6保留。J2 不接时将失去原母板两键导航兜底，这是本次明确裁剪后的产品行为，必须写入操作手册。

用户已经明确选择的删除项无需重新做产品取舍：UART、母板两键旧功能、1E00/E0F0/BxxCyy 显示均列入实施。需确认后删除的仅是**超出这些范围**的功能，例如琶音测试音、Logo、MV/黑胶、LED/WS/蜂鸣、KEY3/SW。本文不把资料中的“立即执行、烧录、冻结”语句当作本次操作指令。

资源目标分三层，不能互相替代：

| 阶段目标 | Slice 上限 | 从当前 9288 至少回收 | 含义 |
|---|---:|---:|---|
| 解除 90% 高占用区 | 8820（90%） | 468 | 仅应急线；继续新增功能仍不够 |
| 本轮最低开发门禁 | 8624（88%） | 664 | 仅允许预算已闭合的小步开发 |
| 本轮优先目标 | 8232（84%） | 1056 | 给后续核心功能留出一定余量 |
| 核心产品保守预算目标 | 7834（79.94%） | 1454 | 可容纳后文 X3A/X4/X5/X6/X8 的暂估上限 790 Slice |

最后一项目标尚无优化后构建证据，不能承诺必达。LUT 同时争取下降约 1800–2800；Slice 不按 LUT/2 换算，必须以最终布线 QoR 为准。

### 2. 证据与可复核性

附件目录：`doc/开发资料/优化项目/最终优化方案核验附件_20261007/`。

| 证据 | 用途与结论 |
|---|---|
| `input_hash_audit.json` | 当前 src/constraints 共112项，与 `X2_r15s5_20261007/inputs.sha256.json` **112/112 一致** |
| `git_history.txt` | 本地全部可见提交与工作树快照；未 fetch，不推断服务器状态 |
| `document_manifest.json` | 指定资料及相关方案的路径、行数、SHA256；清单不是所有资料结论均获认可的声明 |
| `baseline_gate.area`、`baseline_final.area/.qor/.timing/.constraints` | 原始快照报告的复制，防止被根目录临时报告替代 |
| `source_inventory.json`、`全量RTL逐项清单.md` | 109个RTL/头文件逐项职责、定义行、生产状态和处理建议 |
| `source_instance_edges.json` | 126条静态源码例化边；保留内联前关系，不代替 elaboration |
| `hierarchy_area.csv/.json`、`完整综合实例树.md` | 原 `gate.area` 全部194行层次统计，含 top、54个直接子实例及IP子层次 |
| `excluded_dependencies.json` | 11个 AutoExcluded 文件的源码/测试/脚本引用，用于避免误删回归资产 |
| `synthpilot_calls.json`、`opt_plan_audit_20261007_*` | 本次 MCP 综合与分析结果；单独标注默认 auto 映射策略 |
| `audit_inventory.py` | 可重复执行的只读核查脚本，输出仅写入附件目录 |

本报告中 `src/...:行号`、`constraints/...:行号` 均对应 `66da60f` 当前源码；层次数字对应附件复制的原始 `gate.area`。后续修改后引用行号会移动，应以哈希、实例名和信号名重新定位。

#### 2.1 四份指定资料的处理

| 资料 | 核查与修正 |
|---|---|
| `VinylFPGA_资源占用盘点与优化分析_20261007.md` | 全局 9288 Slice / 17415 LUT 正确；若干模块表混入别的映射结果，例如 reporter 943 应为本基线860、menu269应267、Seek297应337。不能直接沿用逐模块收益。 |
| `VinylFPGA_src_全量模块详解_20261007.md` | 可用于职责索引，但标题基于9848757、资源节仍是旧S7基线。audio_mclk/第三PLL不属于当前有效设计；目录数量和“所有板验通过”不能直接继承；当前输入WAV为单声道并送HDMI双声道接口。 |
| `第1课_从官方例程到完赛工程_架构认知与FPGA思维框架.md` | 教学/对照资料，包含官方例程及另一ProMax工程，不是当前网表。当前SDRAM为125MHz，当前两PLL、六个约束时钟，不照搬旧100MHz/三PLL。保留分层、CDC、单变量验证思路。 |
| `11111VinylFPGA_最终执行方案_代码与资料综合核对_20261007.md` | 原基线a357339已过期，X0R/X1/X2已有后续提交。本次在X2后插入O0–O7；原X5“保留母板组合键菜单”和UART验收条件被本次需求取代。X3A–X8产品路线保留。 |

#### 2.2 Git 演进与不可重复计算的收益

| 提交 | 意义 |
|---|---|
| `51dbe1a`（10月3日） | 早期母板按键/自动轮播 |
| `1004043`（10月4日） | 旧状态OSD |
| `868f622`、`705d8b9`（10月5日） | 缩略图与母板亮度/对比度菜单；本轮裁剪来源 |
| `76ba2a7`、`57f5933` | J2串口回显与健康遥测 |
| `636db9b`、`ead2ee0`、`1c0a962` | 媒体逻辑瘦身、Logo BRAM分组；失败CRC/UART/位宽候选回退 |
| `a357339` | J2 KEY07/KEY11 语义修复，必须保留 |
| `ece989d`、`e9f2faa` | X0R、X1：LED/WS/数码管已不是旧空挂逻辑 |
| `1d80349`至`66da60f`（10月7日） | X2 Seek/结束策略及100MHz路径流水；保留三级流水与媒体就绪寄存 |

`song_index_db` 输出寄存器直连、BMP头字段收窄、Logo少6块BRAM等已经在现代码中；不得再次记作本轮收益。历史M5 UART格式微调资源和时序更差，M6仅改计数位宽也没有最终放行；本轮采用用户授权的删功能和结构共享，不再凭“源码更短”认定获益。

### 3. 资源与时序盘点

#### 3.1 实现基线（匹配当前源码，尚不证明当前板上就是此位流）

来源：`prj/resource_opt_verified_20261005/X2_r15s5_20261007/final.area:4–29`、`final.qor:6–24`。

| 资源 | 使用/容量 | 使用率 | 余量 | 优化意义 |
|---|---:|---:|---:|---|
| **Slice** | **9288/9800** | **94.78%** | **512** | 首要约束 |
| **LUT** | **17415/19600** | **88.85%** | **2185** | 第二目标 |
| FF/REG | 10527/19600 | 53.71% | 9073 | 不需专门牺牲流水去省FF |
| BRAM9K | 40/64 | 62.50% | 24 | 可用少量块RAM换LUT |
| BRAM32K | 0/16 | 0% | 报告标称16 | 不与BRAM9K余量直接相加作独立容量承诺；需核物理映射 |
| DSP | 17/29 | 58.62% | 12 | 保留现乘法映射 |
| IO | 71/188 | 37.77% | 117 | 输入35、输出35、双向1 |
| PAD | 75/188 | 39.89% | 113 | 与IO口径不同，不能相加 |
| PLL | 2/4 | 50% | 2 | 无需删时钟 |
| GCLK | 2/16 | 12.50% | 14 | 非瓶颈 |

LE为17982，其中LUT-only7455、REG-only567、LUT&REG9960。Slice使用率高于LUT使用率表明应重视打包和物理实现；仅凭比例不能证明某一具体拥塞根因。

原综合 `gate.area:18–35` 为 LUT16768、REG10472、BRAM40、DSP17。层次表 top 行为 LUT14944、ripple1824、seq10530：**14944+1824=16768**。seq层次数与全局REG口径略有不同，按各列原值报告，不混称严格可加的最终FF。最终实现相对原综合增加647 LUT、55 REG，说明只看综合不足以判断可装入。

#### 3.2 主要资源来源（同一份原综合层次表）

| 直接子实例 | 累计LUT | ripple | seq | BRAM | DSP | gate.area行 |
|---|---:|---:|---:|---:|---:|---:|
| sd_card_bmp_m0 | 3997 | 260 | 3367 | 0 | 0 | 53 |
| u_expansion_integration | 3268 | 517 | 1768 | 0 | 0 | 73 |
| u_hdmi_1_4b_transmitter_core_wrapper | 1248 | 149 | 1503 | 16 | 0 | 155 |
| u_s6_video_layer | 628 | 131 | 312 | 0 | 4 | 201 |
| u_lrc_osd | 623 | 13 | 88 | 0 | 0 | 184 |
| u_video_rgb_to_axis_640x480 | 597 | 0 | 26 | 0 | 0 | 223 |
| frame_read_write_m0 | 471 | 115 | 357 | 4 | 0 | 42 |
| u_wav_stream_player | 448 | 69 | 292 | 8 | 0 | 225 |
| u_seek_controller | 337 | 27 | 230 | 0 | 0 | 207 |
| u_thumbnail_view_reader | 294 | 65 | 246 | 2 | 1 | 213 |
| u_param_menu_controller | 267 | 41 | 168 | 0 | 0 | 196 |
| u_ui_event_bridge | 203 | 45 | 54 | 0 | 0 | 220 |
| u_sync_fade_gain | 165 | 0 | 101 | 0 | 0 | 211 |
| u_media_supervisor | 145 | 28 | 62 | 0 | 0 | 187 |
| u_boot_layer | 142 | 40 | 53 | 10 | 3 | 67 |

SD/FAT32与扩展集成合计7265，占层次LUT14944的48.6%。SD域最大不等于应先重写FAT32：扩展板遥测和旧母板交互是本次更明确、更低功能风险的减负入口。

| 深入热点 | LUT/ripple/seq | 判断 |
|---|---|---|
| fat32_media_loader_m0 | 3491/221/3060 | 包含scanner792、index715、streamer550；父子不能相加 |
| u_exp_echo_reporter | 860/23/358 | 包含baud/tx；可明确删除 |
| u_expansion_io_hub/u_key_dip_monitor | 738/198/432 | 18路J2键/DIP消抖 |
| u_board_key_sw_monitor | 267/52/187 | 3键+4SW；删KEY1/2后还剩5路，不能整个删掉 |
| u_health_monitor | 112/43/100 | UART计数/定时可裁；err_code仍驱动LED4 |
| u_key_next_transition + u_key_thumb_left_confirm | 169/26/110 | 两个母板短长按识别器 |
| sd_card_bmp_m0/u_key_auto | 36/6/24 | 100MHz下母板KEY2再消抖 |
| u_lrc_osd/u_font_rom | 424/0/0 | 组合字库，适合BRAM替换 |
| u_osd_overlay_24（含u_osd） | 6/5/19 | 不能据此断言整层删除只省6LUT；部分组合逻辑可能移至下游 |

尤其注意：`video_rgb_to_axis_640x480` 源码很短，综合行却有597 LUT；`final.constraints` 有多处 `u_video_rgb_to_axis_640x480/I_rgb[12]_syn_*`，而旧OSD仅记6LUT。**跨模块优化造成归属迁移是合理推断，尚非精确拆分结果**。不得据这597直接提出“AXIS能省100–250LUT”，也不能将该597再叠加到OSD删除收益；应做关闭旧OSD的整机差分确认。

BRAM40的顶层分配：HDMI16、Logo10、WAV8、帧读写4、缩略图2。DSP17的分配：S6视频4、Logo3、画质3、转场3、时基2、缩略图1、PCM增益1。各项按同级层次相加；不动现有音频FIFO深度，不缩掉防欠载容量。

#### 3.3 时钟与时序

| 时钟 | 频率 | 主要消费者 |
|---|---:|---|
| clk | 50MHz | J2输入、事件、UART、LED/WS/蜂鸣 |
| sd_card_clk | 100MHz | SD/FAT32/媒体/播放/Seek/母板旧交互 |
| ext_mem_clk | 125MHz | SDRAM接口与帧FIFO |
| ext_mem_clk_sft | 125MHz相移 | SDRAM硬IP采样 |
| video_clk | 25MHz | 像素/歌词/Logo/PCM时基/HDMI核 |
| hdmi_5x_clk | 125MHz | TMDS串化 |

原 `final.timing`：Setup WNS **+0.048ns**，Hold WNS **+0.024ns**，TNS均0、违例端点均0。最紧Setup在FAT32像素计数相关路径。此结论只对当前约束下的该候选成立。

`native_build.log:2281` 明确记录占用超过90%导致route内建hold修复跳过；`2294–2299`记录+48ps/-12ps，随后独立 `fix_hold`，`2475–2481`才为+48ps/+24ps。故 `final_timing.rpt` 与 `final.timing` 不是同一时点，应认后者及匹配的最终数据库。显式fix_hold是物理修复，不是false-path豁免；不应一概禁止，但也不能把一次窄裕量通过写成稳定性充分证明。

原约束检查：no clock=0、invalid constraint=0、comb loops=0、no path constraints=0；dummy node检查项3、PLL/clock buffer检查项2、no input delay35、no output delay36。STA coverage 99.95%不代表外部接口全约束，也不表示完成全PVT/板级验证。

#### 3.4 本次 SynthPilot MCP 实测边界

已先执行 `curl.exe -sL https://www.synthpilot.dev/llms.txt`，核对运行时真实工具列表。调用连接检查/许可查询后，对独立 `OPT_PLAN_AUDIT_20261007` 快照执行 `td_build(end_step="opt_gate")`，用时约75.7秒，成功完成器件加载、展开、RTL优化、门级优化、物理实例合法化与重新读SDC。

随后执行 `td_report_area`、`td_all_clocks`、`td_report_param`、`td_update_timing(mode="basic")`、`td_report_timing_summary`、`td_check_timing`。

| 项目 | 本次MCP | 历史匹配基线 |
|---|---|---|
| 映射策略 | `auto`，由本次参数报告确认 | `area_prior`，由原native_build.tcl确认 |
| 阶段 | 综合/合法化，未place/route | 综合并完成place/route/fix_hold |
| 综合LUT/REG | 18332 / 10473 | 原综合16768 / 10472 |
| BRAM/DSP | 40 / 17 | 40 / 17 |
| 时钟 | 六个，与上表相符 | 六个 |
| 综合basic WNS | setup+0.128ns、hold+0.471ns | 不与最终布线WNS作优劣比较 |
| 约束警告 | 两个PLL反馈路径本地网络USR-6135 | 需结合最终实现与IP契约审阅 |

**这不是优化后结果，也不是当前源码退化的证据；它证明相同输入在不同映射策略下数字会变。** 本次公开MCP目录没有可直接设置map_mode/seed/fix_hold的工具，不伪造调用、不用原始Tcl绕过MCP限制。后续同策略多seed构建采用已存在的项目原生脚本；MCP可继续用于结构化分析。

### 4. 全模块与依赖清单

`src`共105个`.v`、4个`.vh`；`.v`包含加密IP和仅宏定义文件，不能把105叫作105个有效逻辑模块。静态识别106个module定义（含生成FIFO子模块、同文件辅助模块）；完整有效映射层次见附件194行实例树。`sim`的testbench、`tools`的Python/Tcl、`prj`的历史源码快照不计入生产RTL数量。

| 目录 | 职责 | 本轮边界 |
|---|---|---|
| src根目录 | top/PLL接线、同步复位、HDMI PHY、RGB→AXIS | top裁旧接线；PHY/AXIS保留 |
| src/SD | SD协议、FAT32、索引、媒体监督、帧缓冲、数码管、旧母板控制 | 只先裁旧KEY/轮播来源；FAT/SDRAM时序不重构 |
| src/audio | WAV、play/Seek/session、PCM桥、音量、时基 | 保留X2行为与三级流水 |
| src/video | MV流/调度/仲裁/S6层 | 保留PCM优先与完整扇区所有权 |
| src/display | 旧OSD/歌词/波形/转场/画质/缩略图/数码管业务 | 删除旧三行OSD；字库BRAM；其余留接口 |
| src/io | J2驱动/事件/路由、母板监控、UART、反馈 | 删除UART和母板两键；共享消抖 |
| src/boot | Logo层与ROM | 保留已优化分组BRAM |
| src/IP、src/include、HDMI加密目录 | PLL/FIFO/SDRAM核/参数 | 黑盒接口保留；旧排除项单独清单 |
| constraints | pin.adc、timing.sdc | 同步移除退出端口约束；时钟关系另审 |
| sim、tools | 回归与生成/构建/发布工具 | 用新需求替换旧正例，保持主链回归 |
| prj、doc | 构建快照、报告与历史资料 | 保留证据；不以清磁盘声称节约Slice |

完整每文件功能、定义行、保留/删除/重构建议位于附件`全量RTL逐项清单.md`，而不是仅列“核心模块”。生成IP内部子模块及加密可见层次位于`完整综合实例树.md`。

主要依赖如下；箭头表示数据/控制关系，不表示所有模块串接成同一时钟流水：

```text
top
 ├─ sys_pll/video_pll → 各域reset_sync
 ├─ sd_card_bmp → fat32_media_loader → volume_scanner / song_index_db / file_streamer
 │             └→ sd_card_top → sd_card_cmd / sd_card_sec_read_write / spi_master
 ├─ media_supervisor / media_probe → SD恢复、探测、错误状态
 ├─ frame_read_write → 写/读FIFO → sdram(U3)；thumbnail_reader经读仲裁共享SDRAM
 ├─ WAV/MV扇区仲裁 → wav_stream_player / mv_stream_player
 ├─ play_ctrl → seek_controller / stream_session → 音频代次、MV重定位
 ├─ expansion_integration
│   ├─ expansion_io_hub → 键/DIP消抖 / encoder_monitor（内含两个正交解码器）/ NEC
 │   ├─ ui_event_bus → ui_command_router → 顶层ui_event_bridge → browse/play
 │   ├─ board_key_sw_monitor → KEY3页面、SW、Boot/蜂鸣（旧KEY1/2待撤）
 │   ├─ health_monitor → LED故障；exp_echo_reporter → baud/tx（待撤）
 │   └─ LED / WS effects→driver / buzzer_feedback
 ├─ video_delay → 转场/画质 → 旧OSD → 波形 → S6 → 歌词 → Logo/消隐 → AXIS
 └─ PCM source mux→volume/fade→PCM契约桥、ACR→HDMI加密核→PHY
```

纠正旧资料的串联误解：health_monitor没有串行驱动所有状态显示；数码管直接消费`media_err_code`，旧屏幕OSD消费视频域`media_err_code_frame`，LED4消费health的`err_code`。移除UART不能切断这三者共用或相关的错误来源。

### 5. 删除与保留的结构化判定

#### 5.1 确定纳入删除范围（用户已明确选择，需按任务回归后合入）

| 项 | 代码落点/依据 | 删除闭包 | 禁止误删 |
|---|---|---|---|
| UART遥测 | `io/expansion_integration.v:323`；`exp_echo_reporter.v:72,108–126` | reporter、报文缓存/格式化/队列、专用baud/tx、专用遥测状态CDC | ui_event_bus、router、IR、媒体错误恢复 |
| 母板KEY1/2菜单 | `top:701–721`，`param_menu_controller.v:24–152` | combo/hold/idle/debounce、menu输出及旧配置副本 | 未来EC2/CSR协议；画质默认值与管线时延 |
| 母板KEY1/2短长按 | `top:1020–1046,1226–1229,1276–1282` | 两个key_press_hold、thumb锁、browse中的mb_*入口 | J2 KEY01/02、KEY07/KEY11、EC1 |
| 母板KEY2自动轮播/长按上一张 | `SD/sd_card_bmp.v:421–459,527–548,651–660` | key_auto消抖、long_press/auto计数与唯一旧触发分支 | prev_event/next_event、帧提交、四bank预加载；X2 E2自动下一曲 |
| 母板监控中的KEY1/2 | `io/expansion_integration.v:364–379,411–430` | 两路50MHz消抖、Boot skip/蜂鸣中的这两键来源 | KEY3和4路SW消抖、上电保护窗 |
| 左上角三行字符 | `display/status_osd_overlay.v:92–145`；`top:1632–1653` | 1E00、E0F0、BxxCyy、私有行计数/字模/菜单快照 | end_mode/effect_mode实际行为、数码管错误、消隐/重启处理 |
| 已不可达的注释和私有线 | 如`cfg_menu_*`、`ui_modes_v1/v2`仅供旧OSD显示的副本 | 逐条查所有消费者后清理 | `adjusted_pixel_x`、`media_id`等仍供歌词/S6/音源的公共信号 |

“确定纳入删除范围”表示功能取舍已经确定，不表示当前仍可直接删文件而不改调用端。生产删除、测试迁移、约束清理必须同一阶段闭环。

#### 5.2 已排除文件：生产面积收益为零

11项：`src/hdmi_audio_tone_i2s_64fs.v`、`I2S_receiver.v`、`video_source_test.v`、`SD/ax_debounce.v`、`SD/bmp_read.v`、`SD/video_define.v`、`IP/PLL_HDMI_AUDIO.v`、`IP/sdram.v`、`audio/hdmi_pcm_audio_bridge.v`、`display/frame_blend.v`、`display/bilinear_8q8.v`。

**可确定从生产清单移除**，但不可统一称“物理文件可直接删除”：至少`bmp_read`被`sim/tb_bmp_read_stability.v:73`例化、`hdmi_pcm_audio_bridge`被对应TB例化、`bilinear_8q8`被`sim/tb_bilinear_8q8.v:23`例化。先把这些测试标为legacy组并迁移依赖或保留归档。其余文件在本次src/sim/tools文本扫描未见引用，不等于外部课程脚本或所有历史快照都不引用。

主线不需要的`DIAG_SDRAM_PATTERN=0`、`DIAG_LOCAL_PATTERN=0`代码已经常量裁剪，删文本主要改善维护，不能再记大额硬件收益。`color_bar`的彩条输出可裁，但它的扫描时序仍在使用，模块不得整个删除。`lrc_lines_rom`等未保留独立层次行可因内联而消失，不能按“未例化”删除。

#### 5.3 需确认后删除，或本轮明确保留

| 项目 | 决定 | 理由 |
|---|---|---|
| Logo、MV/黑胶、歌词、LED/WS/蜂鸣 | 保留；若仍超资源，另做产品取舍 | 属于用户后续开发目标，不是冗余 |
| `pcm_media_tone`/非WAV测试琶音 | 需确认后删除 | 当前仍例化且约15层次LUT，不应默认认作死码 |
| 母板KEY3、SW1–4 | 保留 | KEY3显示项、SW1使能、SW3诊断、SW4未来demo；SW2暂非核心但仍有反馈语义 |
| `health_monitor`全部功能 | 不整块盲删 | LED4使用当前错误锁存，后续验收需非UART的最小故障观测 |
| `media_supervisor`、超时、probe | 保留 | 音频静音、恢复、SD复位代次等生产功能依赖 |
| CRC校验/文件校验/FIFO保护 | 保留 | 坏卡/损坏文件容错；历史删改收益未证明 |
| 时钟同步器与复位链 | 保留 | 功能使用者退出后仅删该支路私有CDC；不统一减少同步级数 |
| 历史bit、输入哈希、下载/板验日志 | 保留；额外磁盘清理另定范围 | 当前快照是回滚与可复核资产 |

### 6. 收益/风险排序

以下为**规划区间，不是实测承诺**。LUT区间指全局报告可望下降的量，包含可能的ripple/映射变化；模块层次数字只作规模锚点。各轮在上一已接受版本上测净增量，不能把重叠子模块收益相加。

| 优先级/轮次 | 优化 | 规模依据 | 暂估净LUT收益 | FF/BRAM/DSP影响 | 风险 |
|---|---|---|---:|---|---|
| 1 / O1 | 删除UART；保留精简故障状态 | reporter860+ripple23；health112+ripple43中部分可裁 | 750–1000 | 数百FF下降；BRAM/DSP不计划增加 | 中低：需保留LED错误与验证观察口 |
| 2 / O2 | 删除母板KEY1/2完整旧链 | menu267、hold169、key_auto36、母板两路约70，另有计数与CDC | 550–850 | 约300–500FF下降；画质常量化可能附带减DSP但不预算永久收益 | 中：旧轮播与J2路径容易误连删 |
| 3 / O3 | 三行调试OSD删除 | 层次行6 LUT，但可能归入RGB输出级 | 0–250 | 少量FF下降；BRAM/DSP不增 | 中低：保持像素旁路和错误替代观测 |
| 4 / O4 | 剩余25路开关量共享时基 | 27路通用消抖，减去母板KEY1/2两路 | 250–500 | 约250–380FF净下降；无BRAM/DSP目标 | 中：稳定窗口、热插拔、初始化语义 |
| 5 / O5 | 字库同步BRAM+提前取行 | 字库424 LUT，15360有效bit | 280–400 | +2 BRAM9K为首选目标；少量预取寄存器 | 中：字库映射和像素边界 |
| 6 / O6 | 生产源清单/旧注释/测试整理 | AutoExcluded等 | 0 | 0 | 低，但不能弄坏回归 |
| 条件项 | 稳定后再做FAT字段/算术共享、SD接口只读精简 | 大模块仍有存储/仲裁开销 | 未证明，不计预算 | 依具体实验 | 高：会碰100MHz与媒体可靠性 |

O1/O2是主要回收点。O3的收益必须差分测量，不能同时计入AXIS所谓额外收益。O4按O2之后25路预算，不能再按27路满额。O2将画质设默认可能让画质DSP自然裁剪，但X5启用动态BRI/CON后可能回来；这部分属于暂时收益，必须进入X5增量预算。

区间简单相加只是候选规模参考；保守工作目标取净LUT约1800–2800，Slice约800–1400作为试验预期，**没有统计置信区间或保证**。是否达到84%甚至79.94%，最终取决于整机PnR。若只省800Slice，则约8488/9800=86.61%，只满足小步开发；不能据此承诺X4/X5全装下。

#### 6.1 全量复核发现的后续合并候选（不计入本轮确定收益）

| 候选 | 当前源码证据 | 后续处理 |
|---|---|---|
| 数码管独立播放计时与媒体时基重复 | `display/seg_business_mux.v:91–154`另建ms/秒/BCD计数，且display_enable=0时停止；top:1392–1398未给它接媒体时间或Seek目标 | 原资料“数码管已共用timebase_48k”不成立。交X2补验/X6统一，以低频一致快照接入媒体时间，保留临时参数定时器；验证关闭显示后重开、暂停、Seek、99:59边界。跨域与BCD换算有成本，不能预承诺减面积。 |
| sync_fade_gain的跨域外观与本顶层实际同域 | `top:2149–2160`的pix_clk和aud_clk均为video_clk；该模块仍有frame锁存、变化检测、回255等状态 | 可单独评估同域特化，约165层次LUT只是归属规模；不能直接删两级寄存器，需保持增益逐拍/淡出结束行为。当前SYNC_STAGES参数未实际决定同步级数，注释应澄清。 |
| 小型毫秒/等待分频多处重复 | 输入、router、蜂鸣、WS、数码管各有局部定时 | O4先只共享同一50MHz输入域时基；其他同域计时可后续集中clock-enable，不跨域共享脉冲，不合并不同复位生命周期计数。 |

这三项说明“共用一个媒体时基”和“共用通用慢速tick”是不同问题。不能为了省计数器改变播放时间、Seek定位或蜂鸣/WS物理协议时序。

## Chunk 2：可直接执行的任务、验证与后续衔接

### 7. O0：冻结基线与工具口径

**文件/产物**：保持`src/`、`constraints/`；新建各轮`prj/resource_opt_verified_20261005/O*_...`快照；更新本目录阶段差分表。

- [ ] 记录当次HEAD、工作树业务改动、112项输入哈希；重新确认仍以本报告输入为起点。现有文档移动、`.lock.f`和临时脚本不得被reset/clean覆盖。
- [ ] 保存当前通过快照的源、约束、final报告、routed.db；若要回滚下载，另核对应bit哈希和下载日志，不能仅靠文件时间判身份。
- [ ] 固定生产构建`area_prior`、首选seed5及对照seed7；将本次MCP auto报告标为“综合参考”，不填入release差分基线。
- [ ] 跑当前生产相关仿真，记录逐项PASS/FAIL及已知警告；旧母板/UART正例此时仍应通过。冻结结果作为O1–O5比较起点。

**放行**：输入一致、回归清单明确、基线报告可重算。若当前HEAD已变，先重新差分，不对新代码盲套行号。

### 8. O1：UART完全退出生产，健康状态与传输分离

**修改**：`src/io/expansion_integration.v`、`src/top_tf_hdmi_audio.v`、`src/io/health_monitor.v`、`src/display/seg_business_mux.v`、`prj/VinylFPGA.al`；按最终引脚选择修改`constraints/pin.adc`。旧`exp_echo_reporter/exp_uart_tx/exp_baud_tick`移出生产依赖。测试落点：`sim/tb_echo_telemetry.v`、`tb_health_monitor.v`、`tb_expansion_s1.v`、数码管业务TB和新`tb_opt_no_uart.v`。

- [ ] 新增顶层/集成负例：复位、按键/IR、Boot结束、媒体错误都不产生UART发送；J2命令输出与O0一致。
- [ ] 删除reporter实例及专用include/baud/tx依赖，禁止只在输出端mask而把格式化状态机继续运行。`ECHO_ENABLE=0`可作初步对照，但最终以网表无reporter/baud/tx为准。
- [ ] 删除`report_valid`、只供INFO/STAT/ERR的快照稳定检测和私有CDC；逐根检查消费者，`io_ready/exp_actions_ready/present_count`仍服务DIP在场与热插拔，不能误删。
- [ ] 将health拆为“当前错误寄存器+必要故障标志”，移除STAT计时、版本输出和只供串口的饱和计数/队列溢出来源。当前错误在有效零码到来时必须清零，不能回退成永久sticky错误。
- [ ] 保留已有`merged_err_valid/merged_err_code`到LED4的语义；`media_supervisor`与数码管`media_err_code`链不动。具体最小观察建议：欠载/视频失败/业务事件overflow/低水位各一个sticky标志，仅复位或显式新测试会话清除。
- [ ] 在SW3已有诊断页增加这些4bit标志的紧凑显示或复用既有诊断页空位；它们在50MHz域独立锁存，跨到100MHz数码管域分别两级同步，允许各独立标志有1拍显示差异，不把4bit当原子编码。若以后扩成关联计数快照，改用保持至ACK邮箱。注入一个故障后页面必须改变，证明观测逻辑未被综合裁掉。仅仿真中读内部计数不能代替实板观察。
- [ ] `uart_tx`建议保留物理输出并固定`1'b1`（串口空闲态），保留D12约束，避免接收器悬空；若最终完全移除端口，同时删`pin.adc:96`，并记录外接串口行为。固定高保留1个IO不影响主目标。
- [ ] 独立综合/PnR，对比O0；更新旧UART测试为“静默且其他业务正常”，历史串口格式测试归legacy而非伪造PASS。

**检查陷阱**：`expansion_integration.v:7–17`头注释仍写LED镜像/WS常0，与X1代码不符，应更新。删除UART**不应**关闭LED/WS/蜂鸣。`health_monitor.v`头注释写sticky但`err_code`实现已允许0恢复，保留实现语义。

**验收变化**：后续11111方案中“每两秒STAT、UART记录UR/BL/VF/OV”要求作废；改为可读故障标志、故障注入、实机画面/声音及脚本仿真统计。静态无故障标志只能证明本次复位后没锁存对应故障，不能声称最小FIFO水位或最大等待已量化；若需要量化另做非生产诊断版，单独列资源和证据。

### 9. O2：撤销母板KEY1/KEY2旧交互，消除重复消抖根源

**修改**：`top_tf_hdmi_audio.v`、`io/expansion_integration.v`、`io/browse_fsm.v`、`SD/sd_card_bmp.v`、`.al`、`pin.adc`；删除生产使用的`io/param_menu_controller.v`、`SD/key_press_hold.v`。测试：更新所有例化上述模块的TB；新增`sim/tb_opt_board_keys_removed.v`，保留`tb_s7_browse_semantics`等J2回归。

- [ ] 先写测试：母板两键单击、长按1s、组合按压/松开、上电按住，均不能改变曲目、view、auto、亮度/对比度、Boot跳过或蜂鸣；J2对应键仍正常。
- [ ] 移除top中的param_menu实例、两个key_press_hold、key1_eff_n/key2_eff_n、key2_thumb_lock_sd和旧菜单事件/CDC副本。
- [ ] 将`browse_fsm.mb_next/mb_mode/mb_left/mb_confirm`从接口与内部OR/分支中删除，保留J2的prev/next/confirm/mode/home同步器和KEY07/11路径。不要把“上一项”和“缩略图确认”业务本身删掉。
- [ ] 移除sd_card_bmp的原始按键输入和内部u_key_auto；清理KEY2 long_press状态、auto_play_en/auto_cnt/auto_tick及仅由该键开启的图片轮播分支。保留`prev_event`、`next_event`、select请求/ACK、首图/预加载/坏图重试。
- [ ] `u_key_next`原本接常量未留下有效层次实例，源码清理可做，但资源收益不得再次计算。文件内`key_press_debounce`在生产无调用后可归legacy，更新引用测试。
- [ ] 母板`key_dip_monitor.KEY_COUNT`由3改1，仅传key3；KEY3 fall位索引从[2]改[0]，Boot/蜂鸣只保留KEY3来源；DIP_COUNT仍4。**不把50MHz脉冲直连到100MHz域**，KEY3仍走已有toggle同步。
- [ ] 删除top物理key1/key2端口时同步删`pin.adc:21–22`；保留key3=B1与rst_n=A2，不因“第三个键”误删复位。若过渡版保留端口，明确无内部消费者，最终清理掉无效约束。
- [ ] O2到X5之间画质默认`brightness=255`、`contrast=128`，旧菜单不可进入。保留转场/画质模块接口和原像素流水时延；`brightness_contrast_adjust`当前输出寄存一级，不能因常量旁路而手工跳过这一拍，其他像素级延迟分别核对。
- [ ] 所有测试顶层端口和层次引用同步更新；母板兜底正例改成删除负例，J2控制、Seek、切曲、缩略图、EOF回归必须仍通过。

**关键裁决**：“合并母板KEY重复消抖”在本任务中不应实现为继续把KEY1/2送回SD域；用户已要求删除这两个输入的功能，最有效方式是删掉其所有消费者。保留KEY3/SW用唯一输入引擎。原KEY2图片定时轮播退出，**X2 end_mode=E2的歌曲EOF自动下一曲保留**，X8自动演示未来走统一命令接口。

### 10. O3：删除1E00、E0F0与旧调参字符，保持像素对齐

**修改**：top、`display/osd_overlay_24.v`、`display/status_osd_overlay.v`、`.al`；测试`sim/tb_opt_osd_bypass.v`及既有OSD/视频层TB。

- [ ] 明确三个显示来源：第一行`index+1 / A或E / error高低位`；第三行`E+end_mode / F+effect_mode`；第二行仅菜单开启时`BxxCyy`。它们不是字体资源名或错误码常量，不要只搜索字符串“1E00”。
- [ ] 去掉整个旧overlay生产实例，以原`rgb_in`表达式直接送原`rgb_out`消费者；保留或明确沿用“首图未就绪且媒体错误时背景色”策略，不改变DE/VS/像素时刻。
- [ ] 删除仅用于OSD的ui_modes视频同步副本、auto_enabled同步副本、menu_active帧锁存和私有行计数；`play_end_mode/effect_mode`仍被play/transition使用，保留。
- [ ] 保留`adjusted_pixel_x`：它还供waveform、S6、歌词、Logo；保留`media_id`：它还供非WAV音源等。`osd_error_code`名称含OSD但仍供挂载判断与supervisor，不按名字全删。
- [ ] 整帧比较旁路RGB，包含原字幕区域、首末像素、DE=0、VS翻转、出错/恢复。分别验证KEY09仍切F0/F1/F2、KEY12仍切E0/E1/E2，屏幕不再显示旧状态码。
- [ ] 保留故障恢复、LED4及数码管错误提示；当前旧错误屏幕字符一起删除，后续X3A若需要系统级错误提示，单独用简洁层，不恢复常驻调试字符。
- [ ] PnR整机差分记录OSD删除净收益，并检查AXIS归属变化，拒绝双重记账。

### 11. O4：25路开关量共享消抖时基

**修改/新增**：新增`src/io/debounce_tick.v`、`src/io/debounce_bank.v`；修改`key_dip_monitor.v`、`encoder_monitor.v`、`expansion_io_hub.v`、`expansion_integration.v`及顶层include/工程源表；保留`quadrature_decoder.v`初版不变。新增`sim/tb_debounce_bank.v`，更新`tb_io_startup_dip`、`tb_s7_ir_encoder`、输入事件集成测试。

统计口径：原27个通用debounce_filter = J2键/DIP18 + 母板3键4SW共7 + 两编码器按压2。O2后为25。**两个编码器A/B稳定状态机另算，不包含在27个通用消抖器里**；不得把A/B也改成8ms低速采样。

推荐首版选择“共享100µs clock-enable + 每通道连续稳定状态”，而非一开始做RAM式集中轮询器：

1. clk=50MHz，统一5000周期tick，13bit分频计数。tick是单拍使能，不能作为新时钟。
2. 每个物理输入保留独立两级同步器；每通道保留level、candidate/armed及7bit稳定计数（8ms=80个100µs完整区间）。
3. 同步值每50MHz周期检查；任一不连续/返回已确认电平立即使本通道计数和armed失效。不能仅100µs采一次而看漏两个tick间毛刺。
4. 候选变化后第一个tick只建立计时起点，不计一个完整区间；再累积80个完整区间才提交。这样稳定窗口至少8ms，额外等待小于100µs（另加同步延迟）。计数饱和并产生一次fall/rise脉冲。
5. level初值沿用原1，按键低有效、DIP上拨=1不二次取反。各通道独立状态，不共享一只“任意键变化就归零”的计数器。
6. `key_dip_monitor`初始化抑制、`PRESENT_SETTLE`和热插拔恢复窗必须改成新最坏稳定时间+同步裕量或显式全部初始化完成；原DEBOUNCE_CYCLES+8可能早于新窗口，不能照搬。
7. 500ms Boot跳过保护保留，初值收敛不是用户操作。同时按多个键/拨多个DIP不能互相饥饿；保持event_bus逐源pending。

**这不是逐周期完全等价修改**：允许事件最多增加约100µs量化延迟，但不提前到8ms之前，不新增/丢失合格操作。此接口容差要写进测试，而不是让旧逐拍比较一直失败或随意放宽。

- [ ] 定向测试门限1、小参数、真实8ms、复位中按住、<8ms毛刺、tick之间毛刺、两次短毛刺、按下/松开边界和25路并发。
- [ ] 测全tick相位或覆盖所有计数相位的参数缩放模型；真实5000周期分频再测代表性边界。事件输出每次恰好1拍。
- [ ] 热插拔DIP1、DIP上电配置、消隐首键吞掉、Boot保护、EC1/EC2按压与快速正反转、IR并发回归。
- [ ] 一次综合/PnR比较25路原实现与共享实现；若选择集中引擎作为第二候选，另起轮次，计入状态RAM读写和通道mux成本，不将小数组必映BRAM作假设。
- [ ] A/B `quadrature_decoder.stable_count`的32位→参数位宽优化若要做，单独候选；原1ms合法四相序列和方向计数必须保持。先不改A/B滤波算法。

### 12. O5：字库转BRAM，给X4留下可复用读接口

**修改**：`tools/gen_lrc_assets.py`、生成的`src/display/lrc_font_rom.v`、`src/display/lrc_osd.v`、必要的`src/include/lrc_geom.vh`；测试`sim/tb_lrc_font_bram_equiv.v`、`tb_lrc_pixel_equiv.v`。原生成器是源头，不能只手改生成结果。

容量实算：`lrc_geom.vh`为60字形、16行/字、16bit/行，**60×16×16=15360bit**；10位地址按1024×16组织则16384bit。未经压缩至少需要2块BRAM9K，旧“+1 BRAM”估计错误。建议用两个512×16bank或TD验证可映射的等价同步ROM，目标+2 BRAM9K；超出2块要解释布局/端口组织并重算收益。

本工程`boot_logo_rom.v`已存在初始化数组+同步读并映成BRAM的成功先例，因此`param_menu_controller.v`注释“TD不认initial ROM”不能作为全局限制。选TD实际可识别模板；`rom_style`等Vivado属性不能未经验证直接当安路支持的控制手段。

首选接口：`clk, addr[9:0] → row[15:0]`，读延迟明确为1拍，不复位整个存储数组。有效960行与原case逐地址相同，960–1023地址保持原default=0语义；若以后字形容量增加，由生成器显式检查而不是地址截断。

**推荐像素方案：提前取字形行，不改变整条RGB/DE流水。** 当前字宽16px、起始x=96，足够在字边界前发出下一字形行地址。按“ROM读延迟+下游寄存采样”确定提前量（常见实现约2拍），缓存next_row，字边界提交active_row并保持16px；每行第一个字同样在左边界前预取。实际拍数由仿真确定，不能凭文字假定同步ROM输出在发地址同拍可用。

备选为整束RGB/DE/VS/x和hit延迟一级，但必须同时重算后级BOOT/消隐、AXIS和音频数据岛所用坐标关系；本轮优先避免扩大影响。禁止只延迟font_row而不对齐in_box/col_pix/背景RGB。

- [ ] 生成新ROM和golden字模数据，对1024地址顺序、随机、bank边界511/512、末有效959、越界960–1023逐拍比对。
- [ ] 将现组合字库冻结为测试参考，整帧逐像素对照：9行歌词、字边界x=96+16k、末像素、空格、第一/最后扫描行、时间换行、暂停、Seek、enable切换。
- [ ] 在现DE/VS约定下证明hit和背景对齐；enable=0时输出逐bit等于输入，不能遗留一列或一拍字形。
- [ ] 工具重新生成资产应可复现；把任何mem/init外部文件加入快照与hash清单，不能让仿真读当前路径、综合读旧路径。
- [ ] 原综合字库424LUT应明显下降，BRAM增加应可定位到字库实例；重新PnR，不仅以“推断到ROM”或源码属性认定完成。

**X4衔接**：保留同步row-reader接口和像素预取契约。未来多曲歌词当前曲字库/行表缓存替换本静态ROM，不能把当前+2与X4目标+4机械相加；X4阶段应报告“撤旧2、加新字库2+行表2”的净资源及控制增量，具体映射实测。O5若与X4立即连续开发，可合并字库接口设计，但O5仍需独立验收当前歌词显示。

### 13. O6：无硬件收益的工程卫生与约束清理

- [ ] 按附件全量清单，移除退出生产的源登记/include和无调用私有模块；保留兼容源时放入明确legacy目录，不在生产glob中扫描。
- [ ] 更新`tools/verify_s7_acceptance.py`、`verify_resource_opt.py`等实际引用旧功能的入口：legacy测试另组，生产回归不能因未定义模块失败，也不能用忽略缺失模块选项掩盖删除错误。
- [ ] 更新顶层、expansion、browse、health、SD旧注释；列出原教学功能对应Git提交，历史教程作为历史文档不逐一重写为当前接口。
- [ ] 生产key1/key2端口退出时清B2/C1约束；UART若固定高则保留D12。不删除key3、SW、PLL或复位约束来“减少警告”。
- [ ] 删除唯一消费者退出的reset/sync分支；保留所有仍驱动功能模块的同步释放。不得全局替换异步复位或缩短同步链以求Slice。
- [ ] 审阅`timing.sdc:53–55`的exclusive与77–82的asynchronous重复覆盖；这些PLL输出实际同时工作，不能仅凭“不同PLL/时钟树”证明完全异步。须核IP契约与真实CDC，再建立单独约束变更候选，不在面积轮次悄悄改时序例外。
- [ ] 异步按键/IR不是必须虚构同步input delay；按接口类型说明异步同步器边界。SD/HDMI/SDRAM等有时序契约的接口依据板级时序补约束；未取得外部参数就列未闭合项。
- [ ] `set_false_path -to */s1`匹配范围、PLL本地反馈警告、dummy node逐条审查。减少警告不等于面积优化；不能以no path=0替代CDC审计。
- [ ] 不自动删除历史构建目录、原bit或用户未跟踪临时脚本。若后来安排磁盘归档，先验证完整归档及目标绝对路径范围，再执行独立清理任务。

### 14. O7：逐轮验证、可复现命令与验收门禁

#### 14.1 阶段差分表（实施时填实测，不填估计值冒充完成）

| 轮次 | 唯一变化 | 基准/候选hash | Slice | LUT | REG | BRAM/DSP | Setup/Hold WNS | TNS/违例 | 回归/板验 |
|---|---|---|---:|---:|---:|---|---|---|---|
| O0历史基线 | area_prior seed5，匹配112项 | 66da60f / X2_r15s5 | 9288 | 17415 | 10527 | 40/17 | +48/+24ps | 0/0 | 本报告不重开历史板验 |
| MCP核查 | 同RTL，auto综合 | OPT_PLAN_AUDIT | 不适用 | 18332 | 10473 | 40/17 | basic +128/+471ps | 0/0 | 未route，不能作为候选发布 |
| O1–O7 | 按任务卡逐轮填写 | 实施时生成 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | 待执行 |

本行“待测”是明确的未来执行记录，不是本次审计未完成的事实项。

#### 14.2 构建与仿真命令

以下仅为未来执行指令，工作目录`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`。快照名必须全新，失败也不覆盖旧报告。

```powershell
$env:PATH = 'D:\iverilog\bin;' + $env:PATH
python tools/verify_s7_acceptance.py
python tools/verify_s0_s5_fixes.py
python tools/verify_s6.py
python tools/test_vinyl_packer.py
python tools/resource_opt_round.py O1_uart_removed_20261007_s5
python tools/build_verified_round.py O1_uart_removed_20261007_s5 --seed 5 --map-mode area_prior
python tools/resource_opt_round.py O1_uart_removed_20261007_s7
python tools/build_verified_round.py O1_uart_removed_20261007_s7 --seed 7 --map-mode area_prior
```

每条命令检查退出码，失败不得顺序继续。O1/O2/O3改变了产品行为，先按上文迁移相应断言再跑生产回归，不能把旧菜单/UART测试“必然失败”作为可忽略失败。构建脚本明确执行route后fix_hold；同时核查TNS、违例端点、约束、资源，不只看其退出码。

新单元TB可按现Icarus命令格式独立运行：

```powershell
iverilog -g2005 -I. -Isrc -Isrc/include -Isrc/SD -y src -y src/io -y src/display -y src/audio -y src/SD -s tb_debounce_bank -o sim/opt_debounce.vvp sim/tb_debounce_bank.v
vvp sim/opt_debounce.vvp
```

须记录编译/运行两次退出码和显式PASS标志。全顶层含厂商加密IP时，逻辑仿真覆盖控制契约，不能声称代替硬IP和真实视频链验证。本文不新增或执行下载命令；实施阶段在选中候选、回归与时序审核完成后才进入既有发布/板验流程。

#### 14.3 必须覆盖的功能矩阵

| 类别 | 验证项 | 通过标准 |
|---|---|---|
| 已删除行为 | 母板KEY1/2单/长/组合、旧菜单、三行字符、UART | 所有状态下均不恢复旧功能；串口恒空闲；旧字符区域为正常画面 |
| 输入 | 12键各100次、EC1/EC2正反各100格、DIP每项20次、IR合法/非法/重复 | 无多发/丢合格事件；DIP极性/消隐首键/热插拔保持 |
| 保留母板 | KEY3/SW1/SW3；SW2/SW4反馈与预留行为 | 页切换、使能和诊断不丢失 |
| 媒体控制 | KEY07/KEY11、KEY09、KEY12、EOF三策略、±Seek/重播 | X1/X2语义保持；Seek在途不泄漏旧代次 |
| 显示 | Logo、四bank、缩略图、MV/黑胶、波形、歌词、消隐 | 首末像素、帧边界、逐像素旁路无错位 |
| 音频 | 连续播放、暂停/恢复、切曲/Seek、坏卡拔插 | 不新增稳定播放欠载；故障检测能触发且恢复可清 |
| 故障观测 | 注入UR/VF/OV/低水位及媒体错误再恢复 | 非UART诊断能观察；当前错误可清，历史标志保持定义 |
| 物理实现 | 同策略至少seed5与7 | 至少两候选满足阶段资源/时序门禁；失败seed记录、不挑结果隐去失败 |
| 板验 | 1h交叉操作、切换/Seek各100次、冷启动 | 记录视频/声音/状态，不用仿真PASS代替 |

全局门禁：最终setup/hold WNS≥0、TNS=0、违例端点=0；实际Slice≤该阶段预算且至少回到88%以内；BRAM9K≤64、DSP≤29，时钟/IO无错误约束或无解释的新增警告。可设setup≥0.1ns、hold≥0.05ns为工程努力目标，未达到时报告实际裕量，不把数值目标伪装成器件规范，也不放宽时钟掩盖问题。

回滚按独立提交/快照恢复上一已通过版本。每轮应有输入清单、单变量说明、报告差分、仿真日志、风险和板验状态；恢复旧RTL后不能沿用新RTL的bit/资源报告。

### 15. 与11111后续开发方案的正式衔接

继续路线：

`当前X2代码 → O0–O7资源优化与补验 → X3A图层/转场 → X4多曲歌词 → G-EXT → X5 EC2浮窗/CSR → X6参数字典 → [可选X7] → X8演示发布`

X0R/X1/X2不重新从零开发；以实际RTL、构建和板验记录分别确认完成状态。原文a357339/8412Slice、X1执行器不存在、Seek尚未实现等描述已过期，不能作为本轮回退目标。

| 原方案条款 | 优化后替代约定 |
|---|---|
| X5保留param_menu_controller及母板组合键 | 删除。BRI/CON先固定默认，X5只从EC2/统一param_csr恢复动态调节，不重新引入母板菜单 |
| UART STAT/ERR为阶段验收必需 | 改为O1非UART最小观察+定向仿真+板验，需计量指标时用单独诊断版本 |
| 当前8412Slice、DSP15、余量14DSP | 替换为O7最终报告；优化前当前为9288Slice、DSP17、余量12DSP |
| 左上角E/F状态显示 | 取消常驻调试字符；E/F行为保留，必要临时反馈在后续统一OSD设计预算内实现 |
| 母板两键兜底 | 产品不再支持。操作依赖J2/IR，KEY3仅既有显示项；说明J2缺席时功能范围 |
| X4字库/行表缓存 | 复用O5同步字库读接口，撤掉旧固化资产后按净增量预算 |
| X3A图层顺序 | 重新冻结：背景/封面→MV或黑胶→波形→歌词→knob→必要系统提示→BOOT→消隐；当前实际顺序与此不完全相同，交X3A而非混进O3重排 |
| X8自动演示 | 走统一命令入口，不能重新启用旧KEY2图片定时器 |

#### 15.1 从“X2已存在”的当前位置重算累计预算

原方案预算是从X0R后算X1/X2，不能重复加已实现的X1/X2。以下仅为剩余工作规划额度，不是综合结果：

| 剩余阶段 | 暂估净增Slice | 说明 |
|---|---:|---|
| X3A | 10–50 | 收口图层，不加整屏双读 |
| X4 | 120–250 | 一次仅驻留当前曲；字库/行表BRAM与O5置换后算净值 |
| X5 | 200–400 | EC2五项浮窗/CSR/画质动态逻辑恢复均计入；若实测更大重预算 |
| X6 | 0–30 | 参数字典/统一控制 |
| X8 | 20–60 | 小型demo复用命令 |
| **核心剩余合计** | **350–790** | 无X7/FFT/中文增强 |
| X7可选 | 100–220 | 硬件准入后另计 |
| 含X7合计 | 450–1010 | 不保证可装入 |

守住88%（8624）时：核心上限790要求优化后基线≤7834；含X7上限1010要求≤7614（77.69%）。如果仅达84%即8232，剩余392Slice，只覆盖核心区间的低端，不能据此放行完整X4/X5。

逐阶段硬公式：**当前最终实测Slice + 下一阶段小样实测增量/保守上限 ≤8624**。不满足就继续定向减负或缩小该阶段实现；不削弱音频、文件校验、CDC、媒体恢复。FFT、中文字模/复杂alpha、歌词动画、无硬件准入的X7仍按原方案降级顺序处理，需改变用户核心功能时另行确认。

BRAM：O5后目标42/64；X4若用2字库+2行表替换O5的2，则目标净增约2，约44/64，而不是机械写46；实际端口组织和附加缓冲可能改变数字，应报告实测。DSP临时省出的画质乘法资源不视为永久余量，X5恢复动态控制时重算。

### 16. 最终执行清单与结论

- [ ] O0：原始报告、Git、输入哈希和回归基线固定。
- [ ] O1：UART生产逻辑退出，LED当前故障和非UART诊断可验证。
- [ ] O2：母板KEY1/KEY2所有旧交互/消抖/长按/menu退出，J2和SW保留。
- [ ] O3：三行旧字符完全消失，E/F业务保留，视频旁路逐像素正确。
- [ ] O4：25路开关量共享clock-enable，独立同步与连续稳定窗口得到验证。
- [ ] O5：字库同步BRAM实映，容量/地址/延迟/像素全部闭合。
- [ ] O6：生产清单、约束和回归引用完成清理，历史证据保留。
- [ ] O7：至少两个seed通过、达到资源预算、板验有记录；回填真实净收益再放行后续阶段。

**最终判断**：用户选定的优化方向成立，最值得优先实施的是UART删除和母板KEY1/KEY2整条旧交互撤销。共享消抖和BRAM字库负责进一步回收。当前没有依据把大型FAT32/HDMI/SDRAM功能整体称为冗余，也没有依据保证一次达到“完美”资源结果；本方案以可验证的删除边界、逐轮差分和后续累计预算作为完成标准。

本次交付完成的是分析与执行方案。尚未发生任何生产功能裁剪，所有预计收益仍待O1–O7实施验证。
