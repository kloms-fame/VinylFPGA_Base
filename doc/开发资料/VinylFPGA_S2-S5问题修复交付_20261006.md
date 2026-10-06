# VinylFPGA S2–S5 问题修复交付

日期：2026-10-06。以本次用户问题、J2 实测标定、实际 RTL 和测试结果为准；原主链路报告已完整阅读，S0–S5 验收记录仅辅助参考。原报告中的后续操作建议不作为本次执行指令。

## 1. 修复结果与范围

修改 11 个 RTL 文件和 1 个 ADC 约束文件，保留现有时钟、复位、SDRAM/HDMI/FIFO 主链路。没有修改 SDC，没有下载 FPGA、写 Flash 或改写 SD 卡镜像。用户原有 `.al`、packer 和参考文档改动保留。

| 阶段/问题 | 代码定位与根因 | 本次处理 |
|---|---|---|
| S2 Logo 不可见 | 原自动显示下限 1500 ms，可能早于显示器完成锁定；用户事件还可提前退出 | 顶层自动保持 6000 ms，用户跳过至少等待 4000 ms，无首图最迟 8000 ms 退出；只在帧边界退出，沿用 ROM |
| S2 DIP 假事件/错觉编号 | 消抖器初值为高，上电低电平收敛被当成操作；同拍多路 DIP 变化只选一路 | 初始化窗口不产生操作事件；pending 位图逐项排出变化；输出原始电平和固定编号 |
| S2 插拔检测 | 全上拉时空插座与全高输入无法区分 | 按用户约定将 DIP1 上拨作为在位声明；L3 改弱下拉；上电/热插入稳定后允许 J2 业务操作，母板操作独立 |
| S3 旋转方向 | 原上一张绕过转场，下一张手动转场没有方向 | 前后切换统一经过淡出/提交/擦入；逆时针左→右，顺时针右→左 |
| S3 当前图确认黑屏 | `select_req` 等同步 ACK 期间连续被接收，abort toggle 在 SD 域翻转两次，video 域漏掉；控制器 active_index 也可能落后于实际显示 bank | 请求接收加 `!select_ack`；用实际 `disp_buf_idx` 判同图；同图直接退缩略图并播放，不进入黑场；有效确认同时供显示和播放控制 |
| S4 开机短暂琵琶音 | SD/播放状态尚未就绪时，音源选择器回退内置音 | Boot、暂停、缩略图及已有音频的等待阶段发送零 PCM；保留原采样节奏，Boot 后无可用媒体仍保留内置音 |
| S4 info/verify 无串口 | 教程命令原本是 PC packer 命令，工程只有事件 TX 上报 | 增加自动 INFO/VERIFY 状态行，不增加 RX 命令解释器；补报繁忙期间的 BOOT DONE |
| S4 坏索引音频回退失败 | `scanner_done && !idx_take` 才恢复旧 AUDIO.PCM 元数据；索引校验失败时该时机已过去 | 增加 `idx_done && !idx_valid` 回退条件；封面与旧音频同步回退 |
| S4 错误码被隐藏 | 无封面时未启动 BMP load，索引错误没进入 OSD；成功加载又会清除错误 | 保留完整扫描/索引错误字节，成功回退后仍显示索引诊断；无图有错时提供暗红背景和 OSD |
| S5 KEY7 需按两次且发琵琶音 | browse_fsm 用同拍旧 play_active 屏蔽 mode；播放停止后触发内置音源回退 | KEY7 一次同时退出 PLAY、打开缩略图；缩略图保持零 PCM，确认后恢复正常播放 |

Logo 时间从 video 域复位释放起算，含显示器锁定耗时。工程没有 HDMI HPD/显示器 ready 输入，因此这是可调时间预算，不能保证任意慢启动显示器都看到完整 6 秒 Logo。原灰闪现象可能包含显示器锁定过程，须用新 bit 冷启动复测，不能仅凭仿真断言物理 HDMI 灰闪已消失。无卡 8 秒后没有可显示图片，黑底本身不等于死机；有已诊断错误时显示暗红背景和错误码。

## 2. 修改后的 RTL 清单

以下路径均相对于工程 `D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/`。

| 文件 | 关键差异与必要性 |
|---|---|
| `src/top_tf_hdmi_audio.v` | Boot 时间参数；缩略图确认门控与实际 bank 判断；前后转场方向；静音策略；诊断跨域同步和 OSD 背景。显式 include 已有且带 include guard 的 song_index_db、lrc_lines_rom、lrc_font_rom，修复当前 GUI 工程列表缺项导致的黑盒综合失败 |
| `src/boot/boot_layer.v` | 增加 SKIP_MIN_MS，默认 HOLD_MS=6000；原帧边界提交保留 |
| `src/io/key_dip_monitor.v` | 上电稳定窗口屏蔽 DIP 假事件，不屏蔽稳定电平读取 |
| `src/io/ui_event_bus.v` | DIP pending/电平缓存；修正 DIP 打包宽度为明确 16 位 |
| `src/io/expansion_integration.v` | DIP1 在位声明与插入稳定窗口；无板时隔离 J2 操作；接入状态上报 |
| `src/io/exp_echo_reporter.v` | INFO/VERIFY、在位和初始化快照；修复队列同拍进出计数；BOOT DONE pending |
| `src/io/browse_fsm.v` | KEY7 mode 不再被旧播放状态压掉 |
| `src/display/video_fade_transition.v` | 请求锁存方向并同步；手动切换使用方向擦入，自动下一张从右侧擦入 |
| `src/display/video_transition_apply.v` | reverse 时使用 `639-pixel_x` 决定擦入区域 |
| `src/SD/fat32_media_loader.v` | 坏索引恢复旧音频元数据；输出 media_status 和完整 media_error；文件流入口锁存首簇/长度与启动脉冲，将源选择和首簇地址计算分拍，增加 10 ns 启动延迟以改善 100 MHz 时序 |
| `src/SD/sd_card_bmp.v` | select ACK 接收保护；传播诊断，不用成功加载覆盖持久索引错误 |

未修改 `play_ctrl.v`、`wav_stream_player.v`、`audio_source_mux.v`、`thumbnail_controller.v`。动画仍是原单显示源的淡出/黑场/新图擦入，没有引入双帧混合。

## 3. DIP1 映射、在位约定与 J2 约束

**DIP1＝拓展2＝`exp_dip_n[0]`＝GPIOB_6＝J2.7＝FPGA L3＝`DIP 1 0/1`。** DIP2＝拓展1＝`exp_dip_n[1]`＝GPIOB_7＝J2.8＝J3。不能按“拓展1/拓展2”丝印重排 DIP 编号。

用户承诺 DIP1 一直上拨：上拨读 1，报告 PRESENT；下拨或拔板读 0，报告 ABSENT。DIP1 下拨也会禁用 J2 业务动作，属于该在位声明协议。`VINYL EXPHUB S1` 只是软件启动横幅。

唯一电气约束改动为 L3 PULLUP→PULLDOWN，使未连接时具有明确低电平。该方案依赖扩展板外部上拉在上拨时能压过 FPGA 弱下拉；原标定文档的“板内上拉”描述不足以证明电阻值和电压裕量，本次没有做电压实测。必须在新 bit 上验证“插板+DIP1上拨=1；拔板=0”。若实板上拨仍为 0，应检查扩展板是否只有开关接地而无外部上拉；需要补充合适的外部上拉/独立在位接线，不能靠软件反相解决。

```tcl
# DIP1 拓展2 / GPIOB_6 / J2.7；用户固定上拨作为在位声明
set_pin_assignment { exp_dip_n[0] } { LOCATION = L3; IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }
# DIP2 拓展1 / GPIOB_7 / J2.8；以下映射、电气设置沿用
set_pin_assignment { exp_dip_n[1] } { LOCATION = J3; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[2] } { LOCATION = J4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[3] } { LOCATION = H4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[4] } { LOCATION = K14; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[5] } { LOCATION = L12; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
# KEY7 切歌模式 / GPIOB_16 / J2.19
set_pin_assignment { exp_key_n[6] } { LOCATION = G1; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
# EC1 / GPIOB_0..2 / J2.1..3
set_pin_assignment { exp_enc1_a } { LOCATION = P4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc1_b } { LOCATION = N4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc1_sw_n } { LOCATION = N3; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
# 板载 UART，不占 J2
set_pin_assignment { uart_tx } { LOCATION = D12; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
```

完整 J2 约束见 `constraints/pin.adc`。在位判断经现有同步/消抖后工作，插入再等待 `DEBOUNCE_CYCLES + AB_STABLE_CYCLES + 16` 拍；UART 输出另有排队延迟。

## 4. 事件编码格式

50 MHz `clk` 域，`ev_valid` 单拍；`ev_code[3:0]`、`ev_arg[15:0]`、`ev_aux[15:0]`。编号均为硬件位索引，UART 显示编号再加 1。

| code | 事件 | arg | aux |
|---|---|---|---|
| 0 | NONE | 0 | 0 |
| 1 | KEY_DOWN | 按键索引 0..11 | 0 |
| 2 | KEY_UP | 按键索引 0..11 | 0 |
| 3 | DIP_CHANGE | `{12'b0, level, index[2:0]}`，index=0..5 | 0 |
| 4 | ENC_STEP | 16 位回绕计数 | `{14'b0, enc_id, direction}`；enc_id=0/1；direction=0 顺时针递增、1 逆时针递减 |
| 5 | ENC_SW | bit0=0 按下、1 释放 | `{14'b0, enc_id, 1'b0}` |
| 6 | IR_FRAME | NEC 帧低 16 位 | NEC 帧高 16 位 |
| 7 | IR_REPEAT | 保留帧低 16 位 | 保留帧高 16 位 |

ENC_SW 表格按实际 RTL 和串口行为编写；旧头文件相关注释存在 pressed 极性/aux 位号歧义，不应按旧注释反向修改已验证链路。IR 拼接为 `{aux,arg}`，沿用既有帧顺序和按键映射。

DIP 同拍变化按索引依次发出；同一位尚未发出时再变化会合并为最新状态。UART 队列仍为深度 8，不能保证任意高速持续输入绝不丢事件；正常机械消抖速率按现有设计处理。

## 5. 串口格式

115200、8N1、每行 CRLF；无空闲周期刷屏。示例：

```text
VINYL EXPHUB S1
BOOT LOGO
EXPHUB PRESENT
DIP INIT 000001
INFO DONE=1 IDX=1 PIC=F AUD=1
VERIFY IDX=00 FS=00 PRES=1
BOOT DONE
KEY 07 DOWN
KEY 07 UP
DIP 1 0
EXPHUB ABSENT
DIP 1 1
EXPHUB PRESENT
ENC1 + 0001
ENC1 - 0000
ENC1 SW DOWN
ENC1 SW UP
IR BA45FF00 CMD FF
IR REPEAT
```

示例不承诺异步事件与诊断行的相对顺序。`DIP INIT` 从左至右为 DIP6..DIP1，只报告初始快照，不伪造 6 条拨动事件。

| 行/字段 | 含义 |
|---|---|
| INFO DONE | 媒体扫描完成标志 |
| INFO IDX | 是否使用通过校验的索引模式 |
| INFO PIC | 4 位封面资源掩码，十六进制；F=4 个资源均存在，不代表已全部加载进 SDRAM |
| INFO AUD | 当前音频元数据有效；不等于此刻正在播放 |
| VERIFY IDX | 索引解析错误码，00=当前无错误 |
| VERIFY FS | 根目录/卷扫描器错误码 |
| VERIFY PRES | **找到 INDEX.BIN 目录项**，不是扩展板在位状态 |
| EXPHUB PRESENT/ABSENT | DIP1 在位声明 |

INFO/VERIFY 在扫描完成/状态变化时自动输出；Boot 退出但扫描尚未完成也可输出 DONE=0。因此 DONE=0、IDX=00 不能解读为已通过全部校验。硬件 VERIFY 校验索引 CRC/解析及扫描状态，不表示已经校验全部封面和 PCM payload CRC/SHA；完整资源校验仍使用 PC `vinyl_packer.py verify`。

## 6. 四张 SD 镜像与错误码

实际 PC 校验：card_A、card_SONG 退出码 0；两张 broken 均退出码 2，原因相同：entries_crc32 文件值 `0xD0074075`，重算 `0xA4655CE1`。它们是**索引 CRC 损坏**，不能按辅助报告当作 PCM 损坏或 FAT 结构损坏。

| 镜像 | 修复后应有行为 | 关键诊断 |
|---|---|---|
| card_A.img | 索引模式封面正常；正常播放控制；开机无前导琵琶音 | IDX=1，PIC=F，VERIFY IDX=00 |
| card_A_broken.img | 索引拒绝，恢复 PIC1..4 和旧 AUDIO.PCM；保留可用界面与播放控制 | IDX=0，PIC=F，VERIFY IDX=34；OSD 保留 34 作为回退原因 |
| card_SONG.img | 虽无 PIC，合法索引仍找到 SONG1..4，正常播放控制 | IDX=1，PIC=F，VERIFY IDX=00 |
| card_B_broken.img | 索引拒绝且无 PIC，不接受无效缩略图确认；暗红背景显示错误；无可用图曲时保留内置音 | IDX=0，PIC=0，VERIFY IDX=34；OSD 通常为 1E34 |

原 `1E00` 是四个 OSD 字符：图片编号 `1`、自动模式关闭标记 `E`、错误字节 `00`。**不是 16 位错误码 0x1E00**。有索引但 CRC 坏应显示末两位 34；封面回退成功不应再把诊断抹成 00。换卡后按现有冷启动/复位扫描流程重测，不声称增加了 SD 热插拔重新扫描。

| 错误码 | 含义 |
|---|---|
| 30/31/32/33 | 索引 magic/version/entry length/count 错误 |
| 34/35/36/37 | 索引 CRC/簇范围/索引文件流/缺失封面错误 |
| 10/20/21/22 | 扫描扇区错误/启动签名错误/不支持 BPB/缺少资源 |
| 01/02/03/04 | 原 BMP 路径的头错误/超时/数据不足/无资源 |

文件流内部 23..26（链循环、簇越界、提前 EOF、访问上限）不是全部直接出现在 VERIFY FS 中；此字段明确连接卷扫描器错误，索引流错误映射为 36。

## 7. 验证证据与复现

日志目录：`sim/fix_20261006/`。

- 修复前后对照：`tb_sd_card_bmp_fourbank_before.log` 复现同图 ACK 双接收，`tb_fat32_index_loader_before.log` 复现音频回退丢失，`tb_browse_fsm_before.log` 复现首次 KEY7 不进入缩略图；修复后相应测试通过。
- 全量既有回归 `regression.log`：末行 `PASS: all resource optimization regressions`。覆盖 FAT 链、FIFO/刷新节奏、音频等价、Logo/OSD、S1/S3/S5、缩略图读取等。
- 定向回归 `focused.log`：9 个 testbench 全部通过；覆盖 Logo 时间窗、DIP 初始化及同拍变化、UART 实际字符、插拔声明、方向擦入、当前图/不同图选择、单次 KEY7 静音、暂停续播、无卡回退。
- 顶层控制测试 `sim/integration/tb_top_control.v`：使用 Icarus `-i` 跳过加密/vendor 数据通路，驱动时钟、存储和音频边界，验证真实顶层控制连接。它不是完整 HDMI/SDRAM 电气仿真，更不是人工上板验证。
- 四张真实镜像 PC 校验日志：`card_A_verify.log`、`card_SONG_verify.log`、`card_A_broken_verify.log`、`card_B_broken_verify.log`。

在工程根目录复现（Icarus 工具需在 PATH 中）：

```powershell
python -u tools/verify_s0_s5_fixes.py
python -u tools/verify_resource_opt.py
python -X utf8 tools/vinyl_packer.py verify --image doc/资源/sd卡/card_A.img --width 640 --height 480
```

### TD 综合与物理实现

使用本机 Tang Dynasty 6.2.168116、EG4S20BG256、既有 ADC/SDC。构建在隔离快照目录，不改用户 `.al`。**最终 v4 综合、布局布线、时序检查及 bitgen 均通过**，原生构建/发布脚本退出码均为 0。

最终目录：`prj/resource_opt_verified_20261005/S0_S5_fix_20261006_v4/`，seed=5、map_mode=area_prior。

| 指标 | 原 S5_play 基线 | 本次 v4 最终布线结果 |
|---|---:|---:|
| LUT | 13596 | 13990 / 19600（71.38%，增加 394） |
| REG | 8678 | 8934 / 19600（45.58%，增加 256） |
| BRAM | 46 | 46 / 64 |
| DSP | 12 | 12 / 29 |
| IO | 71 | 71 / 188 |
| slices | 7443 | 7593（77.48%） |
| Setup WNS | +94 ps | **+114 ps** |
| Hold WNS | +19 ps | **+3 ps** |
| Setup/Hold TNS、违例终点 | 0 | **全部 0** |

v4 综合 gate 阶段为 LUT 13457、REG 8877；表中使用经过布线/hold 修复后的最终面积，避免混用两个阶段的数字。STA coverage=99.94%，Slow/Fast 双角；Hold 裕量为正但很小，结论限定于当前器件模型和现有约束。`final.constraints` 仍列出 35 个无 input delay、36 个无 output delay，以及 PLL/原语 dummy node 等既有约束检查事项；本次没有补写板外接口时序约束，不能宣称所有接口完成了完整时序签核。

检查证据：`native_build.log`、`gate.status`、`gate.db`、`place.db`、`routed.db`、`route.status`、`final.area`、`final.qor`、`final.timing`、`final.exceptions`、`final.constraints`。构建使用原生 Tcl 脚本，完成标记为 `VERIFIED_ROUND_COMPLETE`，并非 GUI run 的 `.end.f`。

已放行至 bitgen 并完成 `bitgen → setup_debugger → export_bitgen_param`，`release_bitgen.log` 含 `VERIFIED_BITGEN_COMPLETE`，无 ERROR/FATAL；本轮 `.bit`、`top_inst.bid`、`.bitgen_param.f` 均存在。未传入 compress/security/cfg_file/probe 特殊选项，沿用导入数据库配置。该原生脚本不生成 GUI `.bitgen.end.f`；以脚本退出码、完成标记、日志与新产物交叉确认闭环。

- 上板复测文件：`prj/resource_opt_verified_20261005/S0_S5_fix_20261006_v4/VinylFPGA_optimized.bit`（648248 字节，2026-10-06 10:53 生成）。
- SHA-256：`f0633520daecaea7348e6244663c15b7c6a1e2af44662caf278cdc7727ba2f72`。
- `inputs.sha256.json` 记录全部 src/constraints 输入哈希，发布脚本逐项核对与当前源码一致；`bitstream.sha256` 记录 bit 哈希。
- 允许放行到后续下载调试。本次只生成文件，未执行 SRAM/Flash 下载；仍需第 8 节实板复测。

本轮实际执行命令如下。重新构建应换用新的快照名，脚本会拒绝覆盖已有构建/发布产物：

```powershell
python tools/resource_opt_round.py S0_S5_fix_20261006_v4
python tools/build_verified_round.py S0_S5_fix_20261006_v4 --seed 5 --map-mode area_prior
python tools/release_verified_round.py S0_S5_fix_20261006_v4
```

首轮快照 v1 暴露 GUI 工程列表遗漏的三个 S4/S5 模块，已通过顶层 include 修复；v2/v3 综合通过，但 seed 5/1 的布线 Setup WNS 分别为 -298/-341 ps，不作为发布输入。关键路径含源选择、簇减法、移位和 LBA 加法，因此在已有 `fat32_media_loader.v` 中给文件流请求增加一拍寄存；其后的 v4 使用重新综合的结果，不能复用旧 gate.db。没有通过降频、扩大 false path 或改动时钟约束掩盖问题。

旧 S5 基线也有 vendor FIFO 未驱动 bea/beb、加密 SDRAM 模型和 UART msg 位警告，以及两个 PLL feedback local network 的 USR-6135。最终 DRC 未发现多驱动或异常时序路径，但仍保留 `ext_mem_clk_sft → SDRAM_CLK` 使用 local routing 的 PHY-5079。它们与最终报告一起保留，不能把 STA 数字解释为完成了硬件电气验收。

## 8. 新 bit 最小上板复测

1. DIP1 拓展2固定上拨，冷启动正常卡：Logo 在显示器锁定后可见、无前导琵琶音；记录 BOOT LOGO/DONE 与实际显示时刻。慢屏可增大顶层 BOOT_HOLD_MS/BOOT_SKIP_MIN_MS，并同步设置 TIMEOUT_MS。
2. 核对在位电平：插板上拨 PRESENT，拔板 ABSENT；DIP1 单独操作只产生 DIP 1，DIP2 只产生 DIP 2，初始配置只有 DIP INIT。
3. 开机长按进入缩略图，确认当前 bank0；再切到 bank1 进入缩略图确认当前图；都应退出并继续响应。另选不同图验证转场提交链路。
4. EC1 逆时针左→右擦入，顺时针右→左擦入；暂停/续播、音量、歌词沿原功能复测。
5. 播放时单按 KEY7：一次进入缩略图、HDMI 音频静音，确认歌曲恢复播放；再反复进入/退出。
6. 分别冷启动四张镜像，按第 6 节检查界面、回退音频、INFO/VERIFY 与 OSD；无卡检查 Boot 超时后内置音仍可用。

以上为待用户实板复测清单，本次没有把仿真通过写成人工上板通过。
