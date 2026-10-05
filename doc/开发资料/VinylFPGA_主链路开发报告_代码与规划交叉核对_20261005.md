# VinylFPGA 主链路开发报告（代码与规划交叉核对版）

> 日期：2026-10-05  
> 工程：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`  
> 器件：安路 `EG4S20BG256`，顶层模块 `top`，工程文件 `prj/VinylFPGA.al`  
> 原则：本报告把用户请求作为执行要求，把附带 Markdown 作为规划与参考；文档和 RTL/约束冲突时，以当前 RTL、当前约束和可追溯构建产物为准。

## 0. 核查范围与结论

已交叉核对：

- `doc/开发资料/J2扩展板引脚按键映射标定.md`
- `doc/开发资料/开发方案.md`
- `doc/开发资料/开发阶段.md`
- `doc/开发资料/产品交互.md`
- `doc/开发资料/开发方案思维导图.md`
- 主工程 `src/top_tf_hdmi_audio.v`、`src/SD/*`、`src/audio/*`、`src/display/*`、`src/io/*`
- 主工程 `constraints/pin.adc`、`constraints/timing.sdc`
- J2 标定工程 `资源/Expansion_Board_Test/src/*`、`资源/Expansion_Board_Test/constraints/top.adc`
- 正式构建快照 `prj/resource_opt_verified_20261005/p05_s5/`

结论先行：

1. 当前 `VinylFPGA` 主工程已经具备“SD/FAT32 扫描与 BMP 四 bank 缓存、HDMI 640×480、单路 PCM 音频、转场、缩略图选择、参数 OSD、音频波形”的可运行地基；最新快照 `p05_s5` 的综合回归全部通过，路由时序为 Setup WNS `+53 ps`、Hold WNS `+3 ps`。
2. J2 标定工程与主工程是两个独立工程。J2 的物理契约已经在 `资源/Expansion_Board_Test` 中完成，但主工程当前 `top` 没有任何 `exp_*` 端口，`constraints/pin.adc` 也没有 J2 约束；J2 业务移植尚未开始。
3. 当前主工程没有 `STATE_BOOT/STATE_BROWSE/STATE_PLAY` 顶层业务 FSM，也没有统一 `ui_event_bus`。现有 `state_code` 只是当前图片编号 `1~4`，不能当作产品状态机。
4. 规划中的 QSPI Logo、曲目索引、多曲音频、歌词、MV、黑胶、母板系统外设和长稳容错均未在主工程完成。必须按 S0→S7 顺序逐阶段编译、下载、人工验收，上一阶段未通过不得引入下一阶段。

### 0.1 S1 阶段完成记录（2026-10-05 更新，v5 含操作反馈音）

- 已实现：J2 输入驱动逐字节移植（`sync_bit` / `debounce_filter` / `key_dip_monitor` / `quadrature_decoder` / `encoder_monitor` / `ir_nec_decoder`）+ `expansion_io_hub` + `ui_event_bus` + `exp_echo_reporter` 硬件回显；顶层新增 `exp_*` 与 `uart_tx` 端口；`constraints/pin.adc` 追加 J2 36 路 + `uart_tx` 共 37 条约束。
- v2 收尾：① 串口改为**事件驱动**，删除每 250 ms 的 `EXP KEY ...` 周期行，按键只在动作时输出一行最简 `KEY nn DOWN` / `KEY nn UP`（静止时无输出）；② 修复 `expansion_integration ... is a black box`：S1 源码在 `top` 顶部 include 内联，13 个文件加模块级包含保护，无论 `.al` 文件列表是否完整都不会再出现黑盒。
- v5 追加**操作反馈音**：逐字移植 `buzzer_feedback`，母板蜂鸣器 `board_buzzer_n`(H11，PNP 低有效，硬件 SW5 通断) 直接发声；同一波形送到 J2 `exp_ext_o[0]`(EXT1) 供拓展板外接蜂鸣器。触发源含母板 `key1/key2`+新增 `key3`(B1)、新增拨码 `sw1~sw4`(C8/C7/C6/C5)，以及拓展板按键/拨码/编码器/红外。软件总开关 `BUZZER_FEEDBACK_ENABLE`（默认开）。拓展板本体无蜂鸣器器件（`4_GPIO.pdf` 无 BUZ 网络；《产品交互.md》原文"扩展板无蜂鸣器，为母板独有"）。
- 构建快照：`prj/resource_opt_verified_20261005/S1_j2_io_v5/`（`resource_opt_round.py` → `build_verified_round.py --seed 7 --map-mode area_prior`；seed 5 因既有 100 MHz FAT32 路径未收敛，改用扫描通过的 seed 7）
- 时序：Setup WNS `+140 ps` / TNS `0 ps` / 违例端点 `0`；Hold WNS `+4 ps` / TNS `0 ps` / 违例端点 `0`（基线 p05_s5 为 +53 / +3）
- 资源：LUT `10477/19600 = 53.45%`，REG `7173/19600 = 36.60%`，BRAM9K `30/64`，DSP `10/29`，Slices `5859 = 59.79%`，IO `71/188`
- bit：`S1_j2_io_v5/VinylFPGA_optimized.bit`，SHA256 `957de8939b50f36994f108205a796afbde658297eeabde46eb7a0359a5467290`
- 仿真：`sim/tb_expansion_s1.v` `TEST_PASS`（含 `idle silent`、`board SW feedback tone`、`buzzer feedback on key press`）；J2 原版 TB ×5 `TEST_PASS`（含 `tb_buzzer_feedback`）；`verify_counter_opt.py keys|menu|header|pcm` PASS；`verify_resource_opt.py` 全 PASS
- 事件编码 / 串口格式 / J2 约束片段 / 差异说明见 `doc/开发资料/S1_拓展板移植集成_交付说明_20261005.md`
- **上板人工验收：已完成（用户实测）**。烧录运行、按键/编码器/拨码/红外/LED 通路与主链路画面音频均通过；v2 仅改串口输出方式与编译加固，不改变已验收的物理通路行为（详见交付说明第 7 节）。

### 0.2 S2 阶段完成记录（2026-10-05 更新，v2 换透明背景图源 + 配置 Flash 固化）

- 已实现：最小 `STATE_BOOT`（`src/boot/boot_layer.v`）+ 片上调色板 Logo ROM（`src/boot/boot_logo_rom.v`，由 `tools/gen_boot_logo.py` 从 `doc/资源/开机logo透明背景.png` 生成）+ 固定周期呼吸 + 事件跳过 + 首图自动交接 + 8 s 兜底超时。
- 图层位置：像素链**最末端**（波形之后、`RGB->AXIS` 之前）纯像素替换；不改 `de/vs/hs`，不动 HDMI 核与音频数据岛调度；`boot_active=0` 时 `final_rgb` 等于 S1 的 `waveform_rgb_out`。
- 事件/CDC：`expansion_integration` 新增 `ui_ev_valid`（J2 统一事件 + 母板 KEY1-3 按下）；`clk`→`video` 用翻转电平 + 两级同步 + 边沿检测，一次事件只消费一次；状态跳转只在 `frame_start` 提交。
- 图源与编码：透明背景 PNG → alpha 求内容盒 `x[194,445] y[96,376]`，外扩 8 像素后 2 倍欠采样存 `134×149`，16 色、4bit 索引 2 像素/字打包；盒外纯黑。整屏还原 PSNR 24.77 dB。
- 构建快照：`prj/resource_opt_verified_20261005/S2_boot_v4/`（seed 7 / area_prior；`S2_boot/` 旧 JPG 首版、`S2_boot_v2/` vs 极性 bug 版、`S2_boot_v3/` 上电假事件 bug 版，仅留对比）
- 时序：Setup WNS `+111 ps` / TNS `0 ps` / 违例端点 `0`；Hold WNS `+3 ps` / TNS `0 ps` / 违例端点 `0`。最紧路径仍是既有 `sd_card_clk`(100 MHz) 域，S2 逻辑全在 25 MHz video 域。
- 资源：LUT `10682/19600 = 54.50%`，REG `7247/19600 = 36.97%`，BRAM9K `46/64 = 71.88%`，DSP `12/29 = 41.38%`，IO `71/188`（相对 S1：LUT +205、REG +74、BRAM +16、DSP +2）
- bit：`S2_boot_v4/VinylFPGA_optimized.bit`，SHA256 `ccd057775073db3ad72dcbed4eb6cc529cf2e96b013cbaeffb5d528d7d3fb0f8`
- 仿真：新增 `sim/tb_boot_s2.v` `TEST_PASS`（Logo 渲染/盒外纯黑/帧边界跳过/事件只消费一次/首图自动交接）；`verify_resource_opt.py` 全 PASS
- **配置 Flash 固化：已完成**。板载配置 Flash 实测为 `W25Q16`（JEDEC `EF 40 15`，MSPI 上电自启芯片，与《产品交互.md》一致；第六讲文档所写 `W25Q64` 实为另一颗用户数据 SPI Flash）。用 `tools/program_flash_s2_boot.tcl`（BitWizard：`bit_to_vec` → `program_spi` → `verify_spi`）写入，`program_spi` 实测 2.79 s 完成且无报错。
- **根因记录（用户反馈"开机不显示 Logo"）**：此前只做易失 SRAM 下载，未写配置 Flash，断电重上电后仍运行 Flash 内 S1 老镜像；Logo 逻辑本身无问题（对照实验：把 ROM 初值全换同常量后 RAM 数 46→34，证明 TD 采用了 `initial` 初值）。
- **第二个根因（已修复）**：`color_bar.v` 在 640×480 下 `VS_POL=0`（**场同步低有效**，vs 只在场同步 2 行拉低、其余 523 行保持高），而 `boot_layer` 最初用 `if (vs) pixel_y<=0` 清行计数，导致行计数被压在 0、永远进不了 Logo 的 Y 范围 `[88,385]` → 整屏黑。修复：改用与主链路同一判据的 `frame_start`（`vs_q & ~vs`），与极性无关；`tb_boot_s2` 同步改为真实低有效 vs（修复前 `nonblack=0`，修复后 `nonblack=43236`）。
- **第三个根因（上板仍黑屏的真正原因，已修复）**：`sync_bit`/`debounce_filter` 上电初值均为 1，上电后若某路输入真实为 0（J2 拨码拨在 "0" 位、编码器静止相位为低、按键被按住、母板 key1/key2 内部 `PULLTYPE=NONE`），消抖 8 ms 到点会报一次"变化"；S2 的 `ui_ev_valid` 原本把它当成用户跳过请求，于是上电约 8 ms 就把 `boot_active` 清 0 → Logo 从未显示。修复（`expansion_integration`）：① 明确排除 `EV_DIP_CHANGE`（拨码是静态配置、不是操作）；② 增加 500 ms 上电保护窗。新增 `sim/tb_s2_boot_guard.v` 复现并回归：修复前 `FAIL power-on settling produced 1 skip event`，修复后 `PASS no power-on skip event` + `PASS real key press after guard still reported`。
- 事件编码 / 串口格式 / J2 约束片段（零新增）/ 参数开关 / 人工验收清单见 `doc/开发资料/S2_开机Logo_交付说明_20261005.md`
- **上板人工验收：待用户断电重启确认**（断电后应出现金色黑胶唱盘 + VinylFPGA 字样的开机画面，约 4 s 后自动切首图）。

### 0.3 S3 阶段完成记录（2026-10-05，主界面选歌事件迁移）

- 已实现：选曲业务入口从母板 `key1/key2` 迁移到 `ui_event_bus`。新增 `src/io/ui_event_bridge.v`（clk 域把 EC1 旋转/方向键/EC1 按压/KEY07 解码成四路电平翻转）与 `src/io/browse_fsm.v`（sd 域 3FF 同步 + 边沿还原，按 `view_mode` 路由成既有控制脉冲）；`expansion_integration` 引出只读 `ui_event_*`；`sd_card_bmp` 仅新增 `prev_event` 一条端口与一条 `prev_req_pending` 置位（与既有 KEY2 长按"上一张"同分支）。
- **保持不变**：`thumbnail_controller`/`thumbnail_layout`/`thumbnail_view_reader`、2×2 缩略图布局、四 bank 预加载、`select_req/select_ack` 握手、转场在 `frame_start` 边界提交，均一行未改。母板 KEY1/KEY2 全行为仍是并联兜底通路（`S3_J2_BROWSE_ENABLE=0` 可整体旁路事件侧）。
- 事件映射：全屏 EC1 顺/逆 = 下一张/上一张；缩略图 EC1 顺/逆 = 焦点±1；EC1 按压/KEY02 = 全屏进缩略图、缩略图确认；KEY07 = 进出缩略图；KEY01/03/04/05 方向键同向映射。EC2/红外不参与 S3。
- 串口格式与 J2 约束：**均无变化**（115200 8N1 事件驱动；`pin.adc`/`timing.sdc` 零改动，IO 仍 `71/188`）。
- 构建快照：`prj/resource_opt_verified_20261005/S3_browse_v1/`（`resource_opt_round.py` → `build_verified_round.py --seed 1 --map-mode area_prior` → `release_verified_round.py`）
- 时序：Setup WNS `+106 ps` / TNS `0 ps` / 违例端点 `0`；Hold WNS `+4 ps` / TNS `0 ps` / 违例端点 `0`（基线 S2 为 +111 / +3）
- 资源：LUT `10885/19600 = 55.54%`，REG `7267/19600 = 37.08%`，BRAM9K `46/64`，DSP `12/29`，IO `71/188`（相对 S2：LUT +203、REG +20、BRAM +0、DSP +0、IO +0）
- bit：`S3_browse_v1/VinylFPGA_optimized.bit`，SHA256 `0bcb7bbaccbabffb5e5414cc9074df211a33d8f4177f22286befe549b9ae5f4e`
- 仿真：新增 `sim/tb_browse_fsm.v`（路由/兜底/回滚）与 `sim/tb_s3_browse_integration.v`（真实 J2 正交+按键整链）；`python tools/verify_resource_opt.py` 全 PASS
- 种子说明：seed 7 下 Setup `-850 ps`、2 违例端点，**全部落在既有 `sd_card_bmp_m0/fat32_media_loader_m0`（100 MHz）内部**，不在 S3 新逻辑上；复用同一 `gate.db` 扫描种子后 seed 1 收敛。未使用假路径或放宽约束。过程快照 `S3_browse/`（失败证据 + gate.db）、`S3_browse_s1/`（种子扫描产物）。
- 交付说明：`doc/开发资料/S3_主界面选歌_交付说明_20261005.md`
- **上板人工验收：待用户确认**（见交付说明第 7 节）

### 0.4 S4 阶段完成记录（2026-10-05，SD 卡体系：定长曲目索引）

- 已实现：新增 PC 工具 `tools/vinyl_packer.py`（解析 FAT32 BPB+根目录、走 FAT 簇链解析物理 LBA 运行段、算 CRC32/SHA256、生成并写回 512 B `INDEX.BIN`、输出 `INDEX.json`、做回读校验）；新增 `src/SD/song_index_db.v`（**sd_card_clk 域**流式解析/校验索引：magic/版本/条目长度/曲目上限/entries_crc32/簇号范围）；`fat32_volume_scanner` 增加根目录 `INDEX.BIN` 匹配与 `index_valid/cluster/size` 输出；`fat32_media_loader` 增加 `USE_INDEX_BIN` 参数与 `SP_SCAN/SP_INDEX/SP_EMIT` 三态，**复用同一 `fat32_file_streamer`** 读索引（不新增扇区仲裁端口），索引有效时封面/音频定位改由索引给出。
- **实际改动面小于规划**：取数路径已被 `fat32_media_loader` 封装，因此 `sd_card_bmp.v` 与 `top_tf_hdmi_audio.v` **一行未改**（四 bank 预加载、`select_req/select_ack` 握手、转场边界、音频 FIFO 语义全部不动）。
- 关键不变量：条目只存 `first_cluster`，封面复用已验证的流读取器走 FAT 链 → **封面天然支持碎片**（PC 侧同时把物理 LBA 运行段写进报告）；索引固定 512 B（1 扇区）；根目录首扇区（16 项）限制由工具强制校验；`song_count>4` 工具与 RTL 双边拒绝，绝不静默越界；音频在本阶段要求物理连续（`wav_stream_player` 逐扇区 +1，碎片音频属 S5），工具默认拒绝碎片音频。
- 回退：索引缺失/损坏 → `valid=0` → 自动回退 `PIC1~4 + AUDIO.PCM`；`USE_INDEX_BIN=0` 完全旁路回 S3。
- 串口与约束：**均无变化**（`pin.adc`/`timing.sdc` 零改动，IO 仍 `71/188`，新增逻辑全在既有 100 MHz 域）。
- 构建快照：`prj/resource_opt_verified_20261005/S4_index_v3/`（`resource_opt_round.py` → `build_verified_round.py --seed 5 --map-mode area_prior` → `release_verified_round.py`）
- 时序：Setup WNS `+47 ps` / TNS `0 ps` / 违例端点 `0`；Hold WNS `+3 ps` / TNS `0 ps` / 违例端点 `0`（基线 S3 为 +106 / +4）
- 资源：LUT `12040/19600 = 61.43%`，REG `8106/19600 = 41.36%`，BRAM9K `46/64`，DSP `12/29`，IO `71/188`，Slices `6638 = 67.73%`（相对 S3：LUT +1155、REG +839、BRAM/DSP/IO +0）
- bit：`S4_index_v3/VinylFPGA_optimized.bit`，SHA256 `eb43d2f324ab98a15b0ed578c73e3dd8825792ed2a62cd4b405f4784a049c646`
- 仿真：PC 侧自测 22/22 PASS（含碎片封面 LBA 分段、CRC/超限/越界/碎片音频负例）；新增 `sim/tb_song_index_db.v`（6 用例）与 `sim/tb_fat32_index_loader.v`（4 集成用例，含"封面只能来自索引"与"坏索引回退/报错"）；`python tools/verify_resource_opt.py` 全 PASS；`verify_counter_opt.py menu/keys/header/pcm` 4 组全 PASS
- 时序收敛说明：首版索引解析器把 `fat32_file_streamer.file_byte_offset`（32 位减法器，S0~S3 一直悬空可裁剪）引用成活信号、并把 4 路簇号范围检查做成宽组合树，route 曾失败；改为"解析器自带字节计数 + 逐拍条目校验 + 删除冗余 32 位比较器/发 found 路径 mux"后 seed 5 收敛。未使用假路径或放宽约束。过程快照 `S4_index/`、`S4_index_v1/`、`S4_index_v2/`。
- 工具适配：`tools/verify_counter_opt.py` 的等价性比对现在容忍"被测模块新增端口而冻结基线参考没有该端口"（S3 加 `prev_event` 后该套件原本无法运行），只过滤端口段、不动参数覆盖段。
- 交付说明：`doc/开发资料/S4_SD卡体系构建_交付说明_20261005.md`
- **上板人工验收：待用户确认**（见交付说明第 8 节）

### 0.5 S5 阶段完成记录（2026-10-05，音频播放与歌词渲染）

- 已实现：索引驱动的**多曲播放**（缩略图确认第 N 格 → 进播放态并从该曲目起播）；`src/audio/timebase_48k.v` 建立**全工程唯一 48 kHz 毫秒时基**（48 拍=1 ms，暂停冻结、切曲清零）；`src/audio/play_ctrl.v`（sd_card_clk 域）负责播放/暂停、EC1 正反转切曲（回绕）、KEY04/05 音量（`[32,255]` 饱和钳位）、KEY07 退出；`src/display/lrc_osd.v` + `tools/gen_lrc_assets.py` 生成 16×16 点阵字库与歌词行表，按 `cur_time_ms` 显示单行歌词。
- 关键约束落实："只允许一个 48 kHz 源"——歌词只认 `timebase_48k.cur_time_ms`，自身不计数；暂停时门控采样节拍冻结播放位置与时基，同时音量压 0 + `force_arpeggio` 维持 48 kHz 静音流避免 HDMI 音频饿死；切曲时松开 `play_enable` 12 拍让播放器按新 `start_lba` 重播，并在 video 域复位时基。
- 字库预算：只收录歌词真正用到的字符（演示 60 字形/1920 字节），字形按包围盒自适应缩放居中；综合后 **BRAM 仍为 46/64**（未新增），BRAM 余量留给后续 MV/黑胶。
- 交互：浏览/缩略图行为与 S3 完全一致；播放态由 `browse_fsm.mode_play` 抑制导航脉冲；`ui_event_bridge` 新增 EC1 正反转与 KEY04/05 四路"原始"事件。母板兜底仍作用于浏览态。
- 串口与约束：**均无变化**（`pin.adc`/`timing.sdc` 零改动，IO 仍 `71/188`；新增逻辑落在既有 100 MHz/25 MHz 域）。
- 构建快照：`prj/resource_opt_verified_20261005/S5_play/`（`resource_opt_round.py` → `build_verified_round.py --seed 5 --map-mode area_prior` → `release_verified_round.py`；**seed 5 一次通过，未做种子扫描**）
- 时序：Setup WNS `+94 ps` / TNS `0 ps` / 违例端点 `0`；Hold WNS `+19 ps` / TNS `0 ps` / 违例端点 `0`（基线 S4 为 +47 / +3）
- 资源：LUT `13596/19600 = 69.37%`，REG `8678/19600 = 44.28%`，BRAM9K `46/64`，DSP `12/29`，IO `71/188`，Slices `7443 = 75.95%`（相对 S4：LUT +1556、REG +572、BRAM/DSP/IO +0）
- bit：`S5_play/VinylFPGA_optimized.bit`，SHA256 `bf163c48d2b50464b755bec2334872eb42255316d36c7e98f8bd43915323b443`
- 仿真：新增 `sim/tb_s5_play.v`（时基 48 拍=1 ms / 冻结 / 清零；播放态进入/暂停/切曲回绕/音量双向钳位/退出；歌词在 t=0、11.5 s、超末行三处都点亮字形像素）；`python tools/verify_resource_opt.py` 全 PASS；`verify_counter_opt.py keys/header` 全 PASS
- 工具：`tools/verify_resource_opt.py` 子进程改 UTF-8 容错解码（非 ASCII 仿真输出不再让回归工具自身抛异常掩盖真实失败）；fourbank 里的 loader 桩模块补齐新端口
- 交付说明：`doc/开发资料/S5_音频播放与歌词渲染_交付说明_20261005.md`
- **上板人工验收：待用户确认**（见交付说明第 7 节）

### 0.6 S6 阶段进展记录（2026-10-05，视频播放/黑胶；**未完成，未放行**）

**已完成并通过仿真**：

- 新增 `src/display/vinyl_renderer.v`：纯像素黑胶转盘层（盘体 / 同心纹路用距离平方位带、越靠外越密 / 暖红中央标签 / 外圈 / **8 向旋转高光**）。旋转用"主导轴 + 象限"比较实现，**不引入额外乘法器**（整层只保留 d2 的 2 个乘法器）。该层不读 SD/SDRAM，因此结构上不会与音频抢带宽，满足"无 MV 曲目显示黑胶、不黑屏"。
- 新增 `sim/tb_vinyl_renderer.v`：盘外透传 / 盘面与标签与纹路存在 / **相位改变同一像素颜色变化（在转）** / enable·de 关闭不覆盖 → `TEST_PASS vinyl_renderer_s6`，已纳入 `verify_resource_opt.py` 全量回归。

**未放行的原因（如实记录）**：把该层接入顶层像素链（KEY08 切换、相位取自 S5 的 `cur_time_ms` 以便暂停时同步停转）后，综合在 seed 1/2/3/4/5/6/7 上的 Setup WNS 为 -469/-470/-415/-44/-334/-33/-340 ps，**违例全部落在既有 100 MHz `fat32_file_streamer` 的 LBA 加法链上**（与 S1/S3/S4 同类的布局敏感问题）。默认关闭该层（`S6_VINYL_ENABLE=1'b0`）后 seed 5 仍为 -267 ps —— 少量新增控制寄存器已足以改变布局。因此本轮把 `top_tf_hdmi_audio.v` 与 `ui_event_bridge.v` **回退到 S5 已放行版本**，只保留上表两个已单测通过的模块，主线维持 S5 时序：快照 `prj/resource_opt_verified_20261005/S6_vinyl_v4/`，Setup WNS `+94 ps` / Hold `+19 ps` / 违例端点 `0`（与 `S5_play` 一致，已复核复现）。

**S6 尚未开始的部分**：

- `mv_stream_player.v`：320×240 RGB565、10~12 fps、SDRAM 三帧环形缓冲、欠载冻结；
- 媒体仲裁（音频 FIFO 水位硬门控视频）、`song_index_db` 增加 `has_mv`/帧起始 LBA/帧数；
- 视频资源打包格式与欠载冻结验收记录。

**下一步建议**（按报告 S6 的依赖顺序）：先量化 SD 有效带宽与 SDRAM 三帧地址余量，再做仲裁与三帧缓冲；黑胶层的顶层集成与 MV 通道一起做一次面积/时序收敛（需要更宽的种子扫描或结构性减负），不要单独为视觉层反复扫描种子。

## 1. 当前工程现状（以代码为准）

### 1.1 顶层接口与实际约束

当前顶层 `src/top_tf_hdmi_audio.v` 的端口只有：

| 类别 | 端口 | 当前事实 |
|---|---|---|
| 时钟/复位 | `clk`, `rst_n` | `clk` 约束到 `R7` 50 MHz；`rst_n` 约束到 `A2` |
| 母板按键 | `key1`, `key2` | `key1=B2`、`key2=C1`，当前用于切图、缩略图、自动轮播和参数菜单组合键 |
| 数码管 | `seg_sel[5:0]`, `seg_data[7:0]` | 实际只有 6 位位选，不是规划文档写的 8 位 |
| HDMI | `HDMI_CLK_P`, `HDMI_D0_P`, `HDMI_D1_P`, `HDMI_D2_P`、DDC | 当前生效引脚为 `K1/F5/E3/B3`、DDC `P2/R2` |
| TF/SPI | `sd_ncs`, `sd_dclk`, `sd_mosi`, `sd_miso` | `A12/A14/A13/B14` |
| J2 | 无 | 当前没有任何 `exp_*` 端口 |

`constraints/pin.adc` 中被注释的旧 HDMI、I2S、VGA、`I_key_in` 约束不产生作用，不能作为当前网表能力引用。

### 1.2 已具备能力

| 能力 | 代码证据 | 当前边界 |
|---|---|---|
| 多时钟与复位 | `sys_pll`、`video_pll`、3 个 `reset_sync`、`sync_2ff` | `sd_card_clk`、`video_clk`、`ext_mem_clk`、`hdmi_5x_clk` 分域；跨域已局部同步，但还没有产品级事件总线 |
| HDMI 视频 | `video_timing_data` → `video_delay` → `video_rgb_to_axis_640x480` → HDMI 1.4b 核 → `hdmi_phy_wrapper` | 640×480@60，显示器兼容性仍需板上验收 |
| SDRAM 帧缓存 | `frame_read_write`、`frame_fifo_read/write`、`sdram_rd_arbiter`、四 bank 地址常量 | 当前用于封面/缩略图，不是 MV 三帧播放器 |
| TF/SPI 与 FAT32 | `spi_master`、`sd_card_sec_read_write`、`fat32_volume_scanner`、`fat32_file_streamer`、`fat32_media_loader` | 根目录扫描、固定识别 `PIC1.BMP~PIC4.BMP` 与 `AUDIO.PCM`；仍是教学型资源布局 |
| BMP 解码与预加载 | `sd_card_bmp`，`SCAN_TARGET_COUNT=4`，四 bank 就绪标志 | 4 张图预加载、整帧提交，未按曲目索引扩展 |
| 封面切换与转场 | `video_fade_transition(FADE_FRAMES=16)`、`video_transition_apply` | 有 fade/wipe 路径；业务入口仍是母板 `key1/key2` |
| 缩略图选歌雏形 | `thumbnail_controller`、`thumbnail_layout`、`thumbnail_view_reader` | 2×2 缩略图；KEY1 长按进出、KEY1/KEY2 移动、KEY2 长按确认 |
| PCM 音频 | `wav_stream_player`、`pcm_volume_fade`、`audio_source_mux`、`hdmi_pcm_source_bridge`、`audio_arc_calculate` | 模块名为 WAV，但实际输入是 PC 预处理后的裸 `16-bit signed LE PCM/48 kHz/mono`；FPGA 不解析 WAV 头 |
| 音频时基 | `top_tf_hdmi_audio.v` 中 25 MHz→48 kHz 分数累加器 | 已驱动音频采样；尚未广播产品级 `cur_time_ms` 给歌词/MV |
| 参数 OSD | `param_menu_controller`、`osd_overlay_24`、`brightness_contrast_adjust` | 仅母板两键组合入口；已有亮度/对比度寄存器与像素流水线 |
| 音频可视化 | `promax_audio_waveform` | 波形/峰值条，不是规划中的 256 点 FFT 频谱 |
| 自动验证 | `sim/tb_*.v`、`tools/verify_resource_opt.py`、`tools/verify_counter_opt.py` | 当前回归可验证 RTL 子系统，不等同于 J2 板级验收 |

### 1.3 当前媒体资源

`tf_card_stage/` 当前放置：

```text
PIC1.BMP
PIC2.BMP
PIC3.BMP
PIC4.BMP
AUDIO.PCM
```

`AUDIO.PCM` 为单路原始 PCM，当前工程没有“每首歌一个目录 + 索引条目 + 歌词/MV 物理 LBA”的完整曲库体系。

### 1.4 基线构建证据

正式快照：`prj/resource_opt_verified_20261005/p05_s5/`

- 器件：`EG4S20BG256`
- 顶层：`top`
- Setup WNS `+53 ps`，TNS `0 ps`，违例端点 `0`
- Hold WNS `+3 ps`，TNS `0 ps`，违例端点 `0`
- LUT `7827/19600 = 39.93%`
- REG `5920/19600 = 30.20%`
- BRAM9K `30/64 = 46.88%`
- DSP `10/29 = 34.48%`
- 生成 bit：`p05_s5/VinylFPGA_optimized.bit`
- SHA256：`8d6a4d3dd22e7b50c31ef1d97ee70e202794c9d2f5a9435af31a2e2288380f7c`
- `inputs.sha256.json` 与当前 `src/`、`constraints/` 逐项比对一致
- `tools/verify_resource_opt.py` 本次复跑结果：全部 PASS

时序报告仍提示当前工程没有为 5 个输入端口和 23 个输出端口设置 IO delay，并列出 4 组 dummy node；这不否定当前内部时序通过，但后续新增 J2 端口时必须重新检查约束质量，不能用假路径掩盖真实问题。

## 2. J2 扩展板硬约束

### 2.1 约束来源与电平原则

J2 硬件契约以以下三者交集为准：

1. `资源/Expansion_Board_Test/constraints/top.adc`
2. `资源/Expansion_Board_Test/src/expansion_board_test_top.v` 及配套驱动
3. `J2扩展板引脚按键映射标定.md` 的实测记录

统一原则：

- J2 为 IDC40，接母板 `J2/GPIOB`；排线不能反插。
- 按键、拨码、编码器 SW 为板内上拉输入；`*_n` 按键和 SW 低有效。
- 编码器 A/B 为正交相位输入，不能用普通慢速电平消抖代替格雷码解码。
- J2 LED 为低有效点亮。
- DIP 实测语义为“上拨=1、下拨=0”，软件直接把 `1` 当作功能打开，不再二次取反。
- 红外为 NEC，实测遥控命令字恒为 `FF`，业务判键使用高 8 位地址。
- `EXT1~EXT6` 当前只是 6 路裸输出，标定工程固定为 0，不能假设已有业务联动。

### 2.2 J2 信号完整表

| J2 脚 | FPGA | 顶层端口 | 功能/编号 | 方向与电平 |
|---:|---|---|---|---|
| 1 | P4 | `exp_enc1_a` | EC1 左播控 A 相 | IN，正交 |
| 2 | N4 | `exp_enc1_b` | EC1 左播控 B 相 | IN，正交 |
| 3 | N3 | `exp_enc1_sw_n` | EC1 按压 | IN，低有效 |
| 4 | M5 | `exp_enc2_a` | EC2 右播控 A 相 | IN，正交 |
| 5 | M3 | `exp_enc2_b` | EC2 右播控 B 相 | IN，正交 |
| 6 | M4 | `exp_enc2_sw_n` | EC2 按压 | IN，低有效 |
| 7 | L3 | `exp_dip_n[0]` | DIP1，拓展2 | IN，上拨=1 |
| 8 | J3 | `exp_dip_n[1]` | DIP2，拓展1 | IN，上拨=1 |
| 9 | J4 | `exp_dip_n[2]` | DIP3，指示灯 | IN，上拨=1 |
| 10 | H4 | `exp_dip_n[3]` | DIP4，屏幕消隐 | IN，上拨=1 |
| 11 | — | — | +5 V | PWR |
| 12 | — | — | GND | PWR |
| 13 | N1 | `exp_key_n[0]` | KEY1，左 | IN，低有效 |
| 14 | M2 | `exp_key_n[1]` | KEY2，中间确定 | IN，低有效 |
| 15 | M1 | `exp_key_n[2]` | KEY3，右 | IN，低有效 |
| 16 | L1 | `exp_key_n[3]` | KEY4，上 | IN，低有效 |
| 17 | H2 | `exp_key_n[4]` | KEY5，下 | IN，低有效 |
| 18 | H1 | `exp_key_n[5]` | KEY6，歌词动效 | IN，低有效 |
| 19 | G1 | `exp_key_n[6]` | KEY7，切歌模式 | IN，低有效 |
| 20 | G3 | `exp_key_n[7]` | KEY8，播控方式 | IN，低有效 |
| 21 | L4 | `exp_key_n[8]` | KEY9，切歌动效 | IN，低有效 |
| 22 | L5 | `exp_key_n[9]` | KEY10，WS 灯效 | IN，低有效 |
| 23 | K6 | `exp_ir_rx` | NEC 红外接收 | IN，脉冲信号 |
| 24 | H3 | `exp_led_n[0]` | LED1 | OUT，低有效点亮 |
| 25 | H5 | `exp_led_n[1]` | LED2 | OUT，低有效点亮 |
| 26 | F3 | `exp_led_n[2]` | LED3 | OUT，低有效点亮 |
| 27 | E2 | `exp_led_n[3]` | LED4 | OUT，低有效点亮 |
| 28 | J11 | `exp_ws2812_data` | 8 颗 WS2812 串行数据 | OUT，800 kHz NRZ/GRB |
| 29 | — | — | +3.3 V | PWR |
| 30 | — | — | GND | PWR |
| 31 | J12 | `exp_key_n[10]` | KEY11，拓展1 | IN，低有效 |
| 32 | K11 | `exp_key_n[11]` | KEY12，拓展2 | IN，低有效 |
| 33 | K14 | `exp_dip_n[4]` | DIP5，红外接收使能位 | IN，上拨=1 |
| 34 | L12 | `exp_dip_n[5]` | DIP6，WS 总控使能位 | IN，上拨=1 |
| 35 | M12 | `exp_ext_o[0]` | EXT1 | OUT，当前固定 0 |
| 36 | M11 | `exp_ext_o[1]` | EXT2 | OUT，当前固定 0 |
| 37 | N12 | `exp_ext_o[2]` | EXT3 | OUT，当前固定 0 |
| 38 | P14 | `exp_ext_o[3]` | EXT4 | OUT，当前固定 0 |
| 39 | P12 | `exp_ext_o[4]` | EXT5 | OUT，当前固定 0 |
| 40 | R12 | `exp_ext_o[5]` | EXT6 | OUT，当前固定 0 |

### 2.3 按键、编码器、红外软件映射硬约束

- 方向键物理位置不能按编号顺序推断：`KEY04=上`、`KEY05=下`、`KEY01=左`、`KEY03=右`、`KEY02=中间确定`。
- 功能键为 `KEY06=歌词动效`、`KEY07=切歌模式`、`KEY08=播控方式`、`KEY09=切歌动效`、`KEY10=WS 灯效`、`KEY11/12=拓展预留`。
- EC1 左转计数递减、右转计数递增；EC2 同构。上电计数必须在业务层显式清零，不能依赖标定初值。
- NEC 地址映射：`BA` 上一首、`B9` 下一首、`B8` 播放/暂停、`BB` 音量+、`BF` 音量−、`BC` 息屏、`F8` 进度+、`EA` 进度−、`F6` 重播、`E9` 重启、`E7/AD/F7/A5` 方向上/下/左/右、`E3` 确认。

## 3. 顶层架构与数据流（当前实际状态）

### 3.1 时钟与复位

```text
clk(R7, 50 MHz)
  ├─ sys_pll_m0 → sd_card_clk(100 MHz)
  │                 ext_mem_clk / ext_mem_clk_sft
  └─ video_pll_m0 → video_clk(像素/音频域)
                    hdmi_5x_clk(TMDS串行域)

rst_n + 两个 PLL lock
  → ext_rst_n
  → reset_sync(sd_card_clk/ext_mem_clk/video_clk)
```

`constraints/timing.sdc` 使用 `create_clock`、`derive_clocks`、PLL 输出重命名、HDMI 5×时钟 `set_max_delay`、复位 false path 和 SDRAM 移位时钟 false path。未为新增 J2 端口预留任何约束。

### 3.2 当前显示/存储数据流

```text
TF SPI
  → sd_card_bmp
    → fat32_volume_scanner / fat32_media_loader / fat32_file_streamer
    → BMP BGR→RGB 像素流
    → frame_read_write 写 SDRAM BUF0~BUF3
    → frame_fifo_read + sdram_rd_arbiter
    → video_delay
    → video_transition_apply
    → osd_overlay_24
    → promax_audio_waveform
    → video_rgb_to_axis_640x480
    → HDMI 1.4b transmitter + LVDS PHY
```

缩略图模式在帧边界锁存 `view_mode/focus_index`，关断整帧读取，改由 `thumbnail_view_reader` 以 128 字突发读取源图；退出时等待新的整帧读握手，避免半帧错位。

### 3.3 当前音频数据流

```text
AUDIO.PCM 元数据
  → sd_card_bmp/fat32_media_loader 给出 start_lba/total_sectors
  → wav_stream_player（跨 sd_card_clk/video_clk 的 Gray 指针缓冲）
  → pcm_volume_fade（固定音量 200/255 + 转场增益）
  → audio_source_mux（WAV 与媒体提示音）
  → hdmi_pcm_source_bridge
  → audio_arc_calculate(N=6144)
  → HDMI 音频岛
```

当前 `wav_stream_player` 名称沿用教程，但注释和实现都表明输入是裸 PCM；其 `sample_counter` 尚未连接歌词或视频帧调度。

### 3.4 当前控制流

```text
母板 key1/key2
  → param_menu_controller + key_press_hold/key_press_debounce
  → sd_card_bmp / thumbnail_controller / video_fade_transition
  → state_code(当前图片1~4)、auto_play_en_out、显示与音频
```

当前不存在：

- J2 输入同步、消抖、EC1/EC2 正交解码、NEC 解码；
- `expansion_io_hub` 或 `ui_event_bus`；
- `STATE_BOOT/STATE_BROWSE/STATE_PLAY` 顶层状态机；
- 曲目索引数据库、歌词时间轴、MV 帧播放器、黑胶渲染器。

## 4. 文档与代码差异清单（代码优先）

| 编号 | 文档说法 | 当前代码/约束/实测事实 | 处理结论 |
|---|---|---|---|
| D1 | 部分旧文档写扩展板接 J1/GPIOA | 标定、原理图、J2 `top.adc` 三方一致为 J2/GPIOB | 主工程只按 J2/GPIOB 集成；旧 J1 字样视为笔误 |
| D2 | 《产品交互.md》写扩展板 LED 高电平点亮 | 标定和 `expansion_board_test_top.v` 为 `exp_led_n` 低有效点亮 | RTL/约束按低有效 |
| D3 | 《产品交互.md》《开发方案.md》把 DIP 写成低电平有效且旧编号 | 实测上拨=1；DIP1/2/3/4/5/6 分别是拓展2/拓展1/指示灯/屏消隐/红外/WS | 业务层直接使用高电平功能位，不按旧语义取反 |
| D4 | 规划文档将 KEY1~KEY5 按“上/下/左/右/中”顺序书写 | 标定实际编号是 KEY04/05/01/03/02 | 所有业务事件按端口/编号显式映射 |
| D5 | 规划写 8 位共阳数码管 | 当前顶层和 `pin.adc` 只有 `seg_sel[5:0]` | S0~S6 按 6 位实现；扩展到 8 位只能作为独立阶段 |
| D6 | 规划已有 `boot_player`、`browse_fsm`、`song_index_db`、`lrc_osd`、`mv_stream_player`、`vinyl_renderer`、QSPI Logo | 当前 `src/` 中均不存在对应产品模块 | 只能按阶段新建，禁止在前置阶段假装已完成 |
| D7 | 规划称 WAV 播放 | 当前资源是 `AUDIO.PCM`，`wav_stream_player` 不解析 WAV 头 | S4/S5 的索引和工具必须明确采用裸 PCM 或新增 WAV 解析，不能混称 |
| D8 | 规划称有 256 点 FFT 频谱 | 当前实例是 `promax_audio_waveform` 波形/峰值条 | 频谱属于后续优化，当前能力按波形描述 |
| D9 | 规划称 J2 拔掉后仅业务不可用且系统继续运行 | 主工程尚未有 J2 端口，因此该行为尚未被主工程验证 | S1 必须加入拔插/上拉验证；不得提前宣称通过 |
| D10 | 规划称 W25Q64 0x100000 Logo 可在无 TF 时启动 | 主工程无 W25Q64/QSPI 用户数据通路 | S2 先做不依赖新硬件的 Boot 占位/动画；离线 Flash Logo 放 S7 |
| D11 | 规划称母板 KEY1~KEY4、SW1~SW4、板载 LED、蜂鸣器已定义并可用 | `pin.adc` 当前只约束 `key1/key2/rst_n`，其余未接入 | S7 逐脚确认后独立接入 |
| D12 | 规划称 30 秒固化、参数掉电记忆 | 当前没有 `config_journal`，也没有用户参数非易失写入 | S7 单独交付，不能作为 S5/S6 前置能力 |
| D13 | 规划称五层图层混合 | 当前实际为背景/转场→OSD→波形的已实现链路 | 歌词层、MV/黑胶层新增后再重新定义合成顺序 |
| D14 | 旧报告把正式 bit 写在 `prj/VinylFPGA_Runs/best_result` | 可追溯正式快照是 `prj/resource_opt_verified_20261005/p05_s5/` | 后续阶段统一使用 `resource_opt_verified_20261005/<阶段名>` |
| D15 | 《开发阶段.md》把 J2 中枢、8 位数码管呼吸/30 秒固化、WS2812 律动和后续 Boot 逻辑捆在早期阶段 | 当前主工程只有 6 位数码管、无固化/WS 音频律动/QSPI 通路 | 按用户要求拆开：S1 只做 J2 物理通路与回显，WS 律动/固化/板载外设放 S7 |

## 5. 主链路细化与输入事件边界

业务侧不得直接读取 `exp_key_n`、`exp_enc*_a/b`、`exp_ir_rx`。S1 只建立硬件适配层和事件总线，后续业务只消费事件：

```text
J2 原始输入
  → 同步/消抖/正交解码/NEC 解码
  → expansion_io_hub
  → ui_event_bus
  → top_fsm / browse_fsm / play_ctrl / menu_ctrl
```

建议事件最小集合：

| 事件 | 来源 |
|---|---|
| `ev_prev`, `ev_next` | EC1 左/右；KEY01/KEY03；红外 BA/B9 |
| `ev_confirm`, `ev_play_pause` | EC1 按压、KEY02；红外 E3/B8 |
| `ev_up`, `ev_down`, `ev_left`, `ev_right` | KEY04/05/01/03；红外 E7/AD/F7/A5 |
| `ev_vol_up`, `ev_vol_down` | 后续业务映射由 KEY04/05 和红外 BB/BF 定义 |
| `ev_mode`, `ev_lrc`, `ev_transition`, `ev_ws` | KEY08、KEY06、KEY09、KEY10 |
| `ev_ir_repeat` | NEC 长按重复帧 |
| `dip_level[5:0]` | DIP1~6 上电采样/稳定状态 |
| `enc1_delta`, `enc2_delta` | EC1/EC2 正交计数步进 |

事件编码和具体业务绑定必须在每个阶段的验收前冻结；S1 不得提前实现播放控制、歌词、MV 等后续业务。

## 6. 分阶段实施方案

### S0：基线冻结与回滚准备

**目标与交付物**

- 锁定当前可运行主工程和 `p05_s5` 构建快照。
- 归档 bit、SHA256、RTL/约束哈希、回归日志、板级观察记录。
- 形成后续阶段唯一回滚点。

**需新增或修改的模块与约束**

- RTL、约束不改。
- 新增阶段归档：`doc/开发资料/board_acceptance_S0.md`（建议）、阶段 manifest 和人工验收记录。

**前置依赖与上阶段遗留检查**

- 检查 `p05_s5/inputs.sha256.json` 与工作树一致。
- 检查 TF 卡为 `PIC1~4.BMP + AUDIO.PCM`。
- 检查 HDMI 640×480 显示器、HDMI 音频提取器、母板按键可用。
- 不把 J2 标定工程的 bit 当成主工程基线。

**编译、烧录与自动检查**

```powershell
cd D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA
python tools/verify_resource_opt.py
python tools/verify_counter_opt.py menu
python tools/verify_counter_opt.py keys
python tools/verify_counter_opt.py header
python tools/verify_counter_opt.py pcm
D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe prj/resource_opt_verified_20261005/p05_s5/release_download.tcl
```

若不重新布局布线，直接使用已有 `p05_s5/VinylFPGA_optimized.bit` 进行 JTAG SRAM 下载，并保存新的下载日志。

**人工验收清单**

- 上电后 HDMI 出现首张 BMP，无持续黑屏、花屏或撕裂。
- `key1` 短按切换图片，转场完整；`key2` 自动轮播开关有效。
- `key1` 长按进入缩略图；`key1/key2` 移动焦点，`key2` 长按确认返回目标图。
- HDMI 音频可听见，切图时提示音/淡入淡出行为与现有基线一致。
- 数码管有状态显示，底部波形/峰值条随音频变化。

**回滚要点**

- 回到 `p05_s5` bit 和当前 Git 提交 `7c338a7`。
- 不在 S0 修改业务 RTL。

**主要风险**

- 现有板级记录不是 J2 主链路验收；只能作为主工程基线。
- 把 `resource_history` 的复制产物误当作当前可复现入口；后续统一以 `resource_opt_verified_20261005` 脚本目录为准。

### S1：拓展板移植集成

**目标与交付物**

- 将 J2 标定工程的输入驱动移植到主工程，建立 `expansion_io_hub` 与 `ui_event_bus`。
- 只验证输入/输出物理通路，不接切歌、播放、歌词、MV 业务。
- 交付：新增 `exp_*` 顶层端口、J2 约束、事件总线、硬件回显测试模式。

**需新增或修改的模块与约束**

- 新增/整理：`src/io/exp_sync.v`、`exp_key_debounce.v`、`quadrature_decoder.v`、`ir_nec_decoder.v`、`expansion_io_hub.v`、`ui_event_bus.v`。
- 可复用并审查：`资源/Expansion_Board_Test/src/key_dip_monitor.v`、`encoder_monitor.v`、`event_reporter.v`、`quadrature_decoder.v`、`ir_nec_decoder.v`、`ws2812_driver.v`。
- 修改 `src/top_tf_hdmi_audio.v`：加入表 2.2 的 J2 端口，J2 输出默认安全态。
- 修改 `constraints/pin.adc`：逐条加入 36 路 J2 信号；输入启用 PULLUP，LED/WS/EXT 为输出；不得与现有 SD/HDMI/SDRAM 复用。
- 修改 `prj/VinylFPGA.al`：登记新增源文件，保持编译顺序明确。

**前置依赖与上阶段遗留检查**

- S0 下载和人工验收通过。
- 核对 J2 第 1 脚方向、+5 V、+3.3 V、GND；先不接业务线。
- 对照 `资源/Expansion_Board_Test/constraints/top.adc` 与标定表，逐脚签字。
- 确认 EC1/EC2 计数方向、KEY 编号、DIP 上拨语义和 LED 低有效。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S1_j2_io
python tools/build_verified_round.py S1_j2_io --seed 5 --map-mode area_prior
python tools/verify_counter_opt.py keys
python tools/release_verified_round.py S1_j2_io --program-sram
```

此阶段不要求运行后续曲库、歌词或 MV 回归；必须保留 S0 的全量回归结果作为比较基线，并检查新增 IO 无未约束/重复 LOCATION。

**人工验收清单**

- KEY01~KEY12 逐个按下，事件显示的编号与表 2.2 一致；特别核对上/下/左/右/中并非 01~05 顺序。
- EC1、EC2 顺/逆时针计数方向正确，快速旋转不丢步；按压能产生独立事件。
- DIP1~DIP6 上拨显示 1、下拨显示 0；不得出现软件二次取反。
- 红外 15 个按键逐个触发，地址字节与标定表一致，长按可观察重复帧。
- LED1~LED4 低有效点亮；WS2812 只做静态 TEST/全灭回显，DIP6 可关闭 WS 输出。
- 拔下或插回 J2 时，主工程画面和音频不挂死；输入恢复后回显重新生效。

**回滚要点**

- 仅保留 S1 的独立回显分支时，用宏关闭 `ui_event_bus` 到业务侧的连接。
- 若约束或顶层端口出错，整组撤销 `pin.adc` J2 段并恢复 S0 bit；不修改已验证 SD/HDMI/音频路径。

**主要风险**

- 排线反插导致全量错位；先用单键和单 LED 验证，不允许一次接入全部业务。
- 编码器用慢速去抖会丢步；必须保留正交状态机。
- J2 输出低有效、DIP 高电平功能位、红外地址判键三个语义同时弄反。
- 新增端口可能使时序/IO 约束报告恶化；按阶段报告保存差异。

### S2：开机 Logo/动画

**目标与交付物**

- 在已有显示链路上建立最小 `STATE_BOOT`，上电后先显示稳定的 Logo/启动画面，任意已确认的 J2 事件可跳过到浏览态。
- 由于主工程当前没有 W25Q64 用户 SPI 通路，本阶段先交付不依赖新 Flash 的片上/逻辑生成 Logo 和呼吸动画；“TF 拔出仍能显示的 W25Q64 Logo”延期到 S7。
- 交付：`src/boot/boot_fsm.v`、`boot_logo_rom.v` 或等效小 ROM、`logo_breathe_fx.v`、顶层状态切换。

**需新增或修改的模块与约束**

- 修改 `top_tf_hdmi_audio.v`：增加 `STATE_BOOT` 与 `STATE_BROWSE` 最小状态寄存器；不引入 PLAY 业务。
- 新增启动图层，优先复用现有 `video_timing_data` 和像素链，不改 HDMI 时序。
- 无新增管脚约束；只新增必要的时序寄存器和跨域事件同步。

**前置依赖与上阶段遗留检查**

- S1 事件总线已经能稳定产生单拍；J2 拔插不影响显示/音频。
- S0 的首图、转场、音频回归仍必须保持通过。
- 不引入 SD 索引、歌词、MV、QSPI 用户 Flash。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S2_boot
python tools/build_verified_round.py S2_boot --seed 5 --map-mode area_prior
python tools/release_verified_round.py S2_boot --program-sram
```

**人工验收清单**

- 复位后屏幕先显示 Logo/启动图，画面不出现未初始化的随机像素。
- 不操作时亮度按固定周期平滑呼吸；不得改变 HDMI 同步和音频时钟。
- 按任一已确认 J2 按键、旋钮或红外后，在下一帧边界跳到浏览态；事件只消费一次。
- J2 不接或拔掉时系统仍能从 Boot 进入浏览态，不死机。

**回滚要点**

- 将顶层初始状态固定为 `STATE_BROWSE`，旁路 Logo/呼吸图层即可回到 S1。
- 保留 S1 的事件回显和 S0 的媒体路径。

**主要风险**

- 呼吸乘法器造成视频时序下降；先用移位/查表，再考虑 DSP。
- Boot 跳转跨域重复消费；只允许同步后的事件单拍驱动。
- 不应把“片上 Logo”误写成“QSPI 离线 Logo”。

### S3：主界面选歌

**目标与交付物**

- 在 S2 的浏览态中使用 J2 EC1/方向键选择当前封面；保留现有 2×2 缩略图和四 bank 预加载。
- 业务入口从母板 `key1/key2` 迁移到 `ui_event_bus`，母板按键只作临时兜底。
- 交付：`browse_fsm.v` 或对 `thumbnail_controller` 的业务包装、事件映射、浏览态 UI 验收记录。

**需新增或修改的模块与约束**

- 修改 `thumbnail_controller.v` 或新增 `browse_fsm.v`，消费 `ev_prev/ev_next/ev_confirm`。
- 修改 `top_tf_hdmi_audio.v`：EC1 旋转驱动切换，EC1/KEY02 确认；转场请求仍在 `frame_start` 边界提交。
- 不新增 J2 管脚，不新增 SD 索引，不新增歌词/MV。

**前置依赖与上阶段遗留检查**

- S2 Boot 跳过稳定，S1 输入回显无错位。
- 100 次连续切图回归仍通过；确认 `thumb_select_pending`/`select_ack` 没有丢请求。
- 明确 S3 只操作 4 张现有图片，不宣称多曲库。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S3_browse
python tools/build_verified_round.py S3_browse --seed 5 --map-mode area_prior
python tools/verify_resource_opt.py
python tools/release_verified_round.py S3_browse --program-sram
```

**人工验收清单**

- EC1 右转显示下一张、左转显示上一张，切换在整帧边界完成。
- 连续快速旋转至少 100 次，画面无撕裂、花屏、卡死。
- 缩略图四格与 bank0~3 对应，焦点边框不会错位。
- 确认当前焦点后返回中心图，转场完整；母板按键兜底仍可用。
- 自动轮播开关行为与基线一致；不引入播放态。

**回滚要点**

- 将 `browse_fsm` 输入切回母板 `key1/key2`，保留 J2 回显。
- 若缩略图改动影响 SDRAM，恢复 S2 bit，不回滚 S1 物理映射。

**主要风险**

- EC1 事件速率高于 SD/转场握手；必须用保持请求和 `select_ack`。
- bank 映射和焦点索引不一致；每次切换都要人工对照四张已知图片。

### S4：SD 卡体系构建

**目标与交付物**

- 在 S3 四图稳定后，将固定 `PIC1~4 + AUDIO.PCM` 升级为定长 `INDEX.BIN` 曲目索引。
- 先支持 4 首歌，确认索引、LBA、扇区数和碎片 FAT 链正确，再扩大曲库。
- 交付：PC 侧 `tools/vinyl_packer.py`、FPGA `song_index_db.v`、索引格式文档、带坏索引回退的验收记录。

**需新增或修改的模块与约束**

- 新增 `tools/vinyl_packer.py`：输出封面、裸 PCM、可选歌词/MV 的物理 LBA/扇区数和 SHA256。
- 新增 `src/SD/song_index_db.v`：先以 64 B 定长条目、有限歌曲数实现 BRAM 查询。
- 修改 `fat32_volume_scanner.v`/`fat32_media_loader.v`/`fat32_file_streamer.v`：在不破坏现有根目录路径的前提下增加索引文件读取和簇链校验。
- 修改 `sd_card_bmp.v`、`top_tf_hdmi_audio.v`：封面和音频起始 LBA 来自索引查询。
- 无新增管脚；必要时只增加 SD 域状态寄存器和错误码。

**前置依赖与上阶段遗留检查**

- S3 100 次切图通过；S0/S3 FAT32 与 SDRAM 回归通过。
- 先固定 64 B 条目、4 首上限；索引超限必须报错或拒绝加载，不能静默越界。
- 先验证 PC 侧扇区读回，再验证 FPGA 侧显示/音频。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S4_index
python tools/build_verified_round.py S4_index --seed 5 --map-mode area_prior
python tools/verify_counter_opt.py header
python tools/verify_resource_opt.py
python tools/release_verified_round.py S4_index --program-sram
```

**人工验收清单**

- PC 工具生成 `INDEX.BIN` 后，卡根目录资源和条目 SHA256 可追溯。
- 选择第 N 首时，屏幕中心封面确为第 N 首；不会因为 bank/索引错位回到 PIC1~4 循环。
- 断电重插后索引能重新加载；索引缺失、CRC 错、条目越界时有可见错误并回退，不挂死。
- 使用碎片化 FAT 链测试，封面和音频仍能定位。
- 播放时拔卡不破坏浏览态；错误码可观察。

**回滚要点**

- 保留 `USE_INDEX_BIN=0` 或等效旁路，切回 S3 固定四图/单 `AUDIO.PCM`。
- TF 卡恢复为 S3 资源布局后重烧 S3 bit。

**主要风险**

- LBA/簇号换算、根目录限制和索引物理布局同时出错；每个条目必须有 PC/FPGA 双边证据。
- BRAM 容量不足；先限制曲目数，禁止为扩容提前牺牲音频/视频时序。

### S5：音频播放与歌词渲染

**目标与交付物**

- 按 S4 索引播放指定曲目的裸 PCM，建立统一 48 kHz 毫秒时基。
- 先交付“播放/暂停、上一首/下一首、音量、单行歌词”，再在本阶段内部逐步增加滚动和整行高亮；逐字变色留给 S7。
- 交付：`play_ctrl.v`、`timebase_48k.v`、`lrc_osd.v` 或等效模块、歌词资源格式和同步验收记录。

**需新增或修改的模块与约束**

- 修改 `wav_stream_player.v` 接入索引条目的 `start_lba/total_sectors`，不重写已验证 FIFO 结构。
- 新增 `timebase_48k.v`，输出 `sample_counter` 与 `cur_time_ms`；所有歌词时间只认此时基。
- 新增 `lrc_osd.v`，先支持有限行表/当前行与相邻行；字库容量必须先做 BRAM 预算。
- 修改 `top_tf_hdmi_audio.v`、`audio_source_mux` 控制入口；保留现有提示音与音量安全路径。
- 无新增管脚；约束只补实际新增时钟/跨域关系。

**前置依赖与上阶段遗留检查**

- S4 已证明音频 LBA、扇区数、FAT 簇链正确。
- S0/S3 音频回归、HDMI 音频桥回归继续通过。
- 歌词先用 1~2 首短曲和少量中文字符；不得在第一版同时塞入全字库、逐字动画和 MV。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S5_audio_lrc
python tools/build_verified_round.py S5_audio_lrc --seed 5 --map-mode area_prior
python tools/verify_counter_opt.py pcm
python tools/verify_resource_opt.py
python tools/release_verified_round.py S5_audio_lrc --program-sram
```

**人工验收清单**

- 浏览态确认曲目后进入播放态，声音从正确曲目开始，无爆音。
- EC1 按压暂停/恢复；暂停期间音频和歌词时间都停止。
- EC1 旋转切曲，音频淡入淡出，不能把 SD 读错误传成连续噪声。
- KEY04/KEY05 或约定事件改变音量，边界有钳位。
- 单行歌词随 `cur_time_ms` 出现和切换；抽测时间偏差目标不超过 100 ms。
- 拔卡/SD 超时后音频停止或静音，界面有错误提示且不死机。

**回滚要点**

- 关闭 `lrc_osd`，保留 S4 的按索引音频；若音频回归，回退 `play_ctrl` 入口而不是修改 FIFO。
- 不能把 S5 未完成的歌词模块留在默认编译路径。

**主要风险**

- 时基跨域或歌词表读取不一致造成漂移；只允许一个 48 kHz 源。
- 字库占 BRAM、SD 带宽与音频争用；音频 FIFO 水位优先级高于歌词。

### S6：视频播放（MV/黑胶）

**目标与交付物**

- 在 S5 音频、歌词稳定后增加 MV/黑胶视觉层。
- 第一版采用 320×240 RGB565、10~12 fps、三帧环形缓冲；无 MV 曲目先显示静态封面或黑胶贴图。
- 交付：`mv_stream_player.v`、`vinyl_renderer.v`、视频资源打包格式、欠载冻结验收记录。

**需新增或修改的模块与约束**

- 新增 `src/video/mv_stream_player.v`、`src/display/vinyl_renderer.v`。
- 修改 `song_index_db.v` 增加 `has_mv`、帧起始 LBA、帧数/帧率。
- 修改 `sdram_rd_arbiter.v`、`fat32_file_streamer.v` 或新增媒体仲裁器；音频读请求优先。
- 修改 `top_tf_hdmi_audio.v` 与显示 mux；换帧只在帧边界提交。
- 无新增外部管脚；只增加真实时钟和跨域约束。

**前置依赖与上阶段遗留检查**

- S5 已通过音频、歌词、暂停/恢复和切曲验收。
- 已量化 SD 有效带宽、SDRAM 三帧地址和 BRAM/SDRAM 余量。
- 不在 S6 同时加入 WS2812 律动、QSPI Logo、参数持久化。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S6_mv
python tools/build_verified_round.py S6_mv --seed 5 --map-mode area_prior
python tools/verify_resource_opt.py
python tools/release_verified_round.py S6_mv --program-sram
```

**人工验收清单**

- 有 MV 曲目在左侧 320×240 窗口以 10~12 fps 播放，音频连续。
- 暂停时 MV 冻结，歌词和音频时间同步停止；恢复后从当前点继续。
- 无 MV 曲目显示静态封面或黑胶贴图，不黑屏。
- KEY08/约定事件切换 MV/黑胶，音频不中断。
- 人为降低 SD 读取速度时画面冻结当前帧，不花屏、不撕裂；数据恢复后继续。
- 连续 10 分钟播放无明显音画漂移。

**回滚要点**

- 旁路 MV/黑胶层，固定显示 S5 封面/歌词画面；音频必须保持可用。
- 不因 MV 欠载修改已验证的音频 FIFO 语义。

**主要风险**

- SD/SDRAM 带宽不足导致 MV 抢占音频；必须以音频 FIFO 水位硬门控视频。
- 三帧缓冲地址、帧边界和跨域指针错误导致撕裂；所有切换只在场/帧边界提交。
- 320×240 方案仍可能超过时序预算；先完成小规格，再考虑更高分辨率。

### S7：优化迭代与补充拓展功能

**目标与交付物**

S7 不是一个大合并提交，拆成独立可回滚子阶段：

- S7-A：错误码、拔卡重试、蜂鸣器/板载 LED（仅在引脚核对后）
- S7-B：WS2812 音频律动/进度灯、红外完整业务映射
- S7-C：W25Q64 离线 Logo、参数持久化、完整 OSD
- S7-D：长稳、演示模式、最终资源和时序优化

**需新增或修改的模块与约束**

- 可能新增：`board_status_io.v`、`buzzer_feedback.v`、`ws2812_vu_controller.v`、`qspi_logo_rd.v`、`config_journal.v`、`demo_fsm.v`。
- 修改 `constraints/pin.adc` 前，先根据母板原理图确认 KEY3/KEY4、SW1~SW4、板载 LED、蜂鸣器、W25Q64 用户 SPI 引脚；当前文档地址不能直接当已生效约束。
- 新增每个外设的真实时钟/CDC 约束；不把 QSPI 用户 Flash 与 MSPI 配置 Flash 混为同一接口。

**前置依赖与上阶段遗留检查**

- S6 主链路完整通过。
- 复核音频、歌词、MV/黑胶的已知缺陷和资源余量。
- S7 每个子阶段必须独立快照、独立 bit、独立验收；任何子阶段失败只回滚该子阶段。

**编译、烧录与自动检查**

```powershell
python tools/resource_opt_round.py S7A_fault
python tools/build_verified_round.py S7A_fault --seed 5 --map-mode area_prior
python tools/verify_resource_opt.py
python tools/release_verified_round.py S7A_fault --program-sram
```

S7-B/S7-C/S7-D 使用不同阶段名重复执行；确认所有 RAM 下载验收通过后，才考虑 MSPI 固化。不得因为“能生成 bit”就跳过人工验收。

**人工验收清单**

- 不插/拔 TF、坏索引、坏文件、SD 超时时，错误码可见，系统不挂死，重插可恢复。
- WS2812 受 DIP6 总控；音频律动和进度灯模式切换正确；不会影响音频输出。
- 母板外设只有在已确认引脚和硬件档位后才验收：数码管、板载 LED、蜂鸣器、KEY3/KEY4、SW1~SW4。
- W25Q64 Logo 在拔 TF 时仍可显示；读失败时能跳过而不阻塞启动。
- 参数修改、保存、掉电重启后的恢复符合已冻结规格；未实现时必须明确标为缺口。
- 连续 1 小时、再 24 小时运行无花屏、爆音、死锁；记录温度、卡状态、输入序列和错误码。

**回滚要点**

- 每个 S7 子阶段保留前一阶段 bit；QSPI、配置写入、板载 IO 任一失败都可单独旁路。
- 长稳发现源阶段问题时，回到对应 S5/S6 bit 修复，不在 S7 用永久性补丁掩盖。

**主要风险**

- 新增板载引脚与现有网表冲突；先核原理图、再写约束、最后写 RTL。
- QSPI 用户 Flash、MSPI 配置 Flash、SD 三套存储语义混淆。
- 资源优化侵入主链路；每次优化必须保留等价回归和人工可见验收。

## 7. 阶段门禁（强制）

每个阶段都必须满足以下条件，才允许进入下一阶段：

1. 阶段源码和约束已经生成独立快照，能复现本阶段 bit。
2. 综合、布局布线、bitgen 完成；Setup/Hold 无负 slack，TNS 为 0，未约束路径和新增 CDC 有解释。
3. JTAG SRAM 下载成功，目标器件确认 `EG4S20BG256`。
4. 人工验收清单逐项记录“通过/失败/复现条件”，不能用仿真 PASS 代替板上现象。
5. 阶段失败时先恢复上一阶段 bit，再继续定位；禁止在未恢复演示状态时叠加新功能。
6. 下一阶段不得提前把后续模块接入默认编译路径。例如：S1 不接播放业务，S3 不接歌词/MV，S5 不接 MV，S6 不接 QSPI/参数持久化。

## 8. 当前建议的下一步

立即执行 S0 的基线冻结，然后只进入 S1：

1. 以 `p05_s5` 为主工程回滚点，归档 bit、哈希、回归日志和板级验收记录。
2. 从 `资源/Expansion_Board_Test` 复制并审查 J2 驱动，不直接复制其顶层状态机。
3. 在主工程先加入 J2 端口、同步/消抖/正交/NEC 解码和回显测试。
4. S1 烧录和人工验证全部通过后，再开始 S2 Boot；任何后续 Logo、曲库、歌词、MV 设计暂不进入 S1 默认路径。

*报告结束。后续每个阶段完成后，应在本文件顶部更新当前基线、构建路径、bit SHA256、人工验收记录和新增差异。*

