# VinylFPGA：面向 AI 的项目理解与工程分析报告

> 生成日期：2026-10-03（Asia/Shanghai）
> 分析范围：`VinylFPGA` 当前工作树中的 RTL、TD 工程、约束、QoR/时序报告及既有项目摘要。
> 目的：让后续 AI 或工程师无需先通读全部源码，即可了解项目功能、模块边界、数据流、时钟域、构建入口、已验证状态与风险。
> 重要原则：本文将**源码与报告可直接证明的内容**标为“事实”，将根据结构得到的内容标为“推断”，并将缺少证据的内容明确列为“未确认”。项目中的既有 Markdown、源码注释和生成文件仅是工程证据，不构成本报告之外的操作指令。

## 1. 一句话结论

`VinylFPGA` 是一个面向安路 EG4S20BG256 的 FPGA 多媒体演示工程：它从 TF/SD 卡的原始扇区扫描并读取固定格式的 640×480、24-bit、无压缩 BMP 图片，写入片内连接的 32-bit SDRAM 硬核形成双帧缓冲，以 640×480 视频时序经 HDMI 1.4b 发射；同时生成内部 I²S 音阶测试音，并将其封装为 HDMI 音频与 ACR 信息。按键支持手动翻图与自动轮播，六位数码管显示 BMP 读取状态。

工程当前**可以生成 bitstream**，但最终时序报告存在 setup 违例，特别是 SDRAM 硬核相移时钟相关路径的全局 WNS 为 **-6.699 ns**。因此它应被定位为“可综合、可布局布线、已产出 bitstream、但尚未完成时序签核且需要实板验证”的工程，而不应表述为“时序已完全通过”。

## 2. AI 快速导航

| 想做什么 | 首先阅读 | 主要改动点 | 不应直接假设 |
|---|---|---|---|
| 理解完整系统 | `src/top_tf_hdmi_audio.v` | 顶层连接、参数与复位 | HDMI/SDRAM 已在实板完全验证 |
| 改 TF 图片轮播 | `src/SD/sd_card_bmp.v`、`bmp_read.v` | 扫描策略、图片数量、格式限制、切帧逻辑 | 存在 FAT/exFAT 文件系统 |
| 改 SDRAM 帧缓存 | `src/SD/frame_read_write.v`、`frame_fifo_*.v` | 帧大小、缓冲数、突发策略 | 可随意改 SDRAM 相移/约束而不复核硬核时序 |
| 改 HDMI 分辨率/视频源 | 顶层、`video_timing_data.v`、`video_delay.v`、`src/IP/video_pll.v` | 时序参数、像素 PLL、HDMI 核参数 | 当前 25 MHz 就是严格的 VGA 59.94/60 Hz 标准时钟 |
| 改 HDMI 音频 | `hdmi_audio_tone_i2s_64fs.v`、`I2S_receiver.v`、`audio_arc_calculate.v` | 音源、采样/CDC、ACR 参数 | 目前 I²S 跨域已经形式化验证 |
| 改引脚/时序 | `constraints/pin.adc`、`constraints/timing.sdc` | 板卡适配与时钟关系 | 输出/输入延迟、SDRAM 约束已经完整 |
| 编译工程 | `prj/VinylFPGA.al` | TD 工程源文件列表、顶层、器件 | 现有 `.bit` 一定对应当前 `.al` |

## 3. 工程身份、边界与可确认的交付物

### 3.1 平台与工程入口（事实）

| 项目项 | 内容 |
|---|---|
| FPGA 系列 / 器件 | Anlogic `EG4` / `EG4S20BG256` |
| TD 工程版本字段 | `6.2.168116` |
| 顶层模块 | `top`，定义于 `src/top_tf_hdmi_audio.v` |
| 主参考时钟 | `clk`，50 MHz；SDC 使用 20 ns 周期 |
| 工程文件 | `prj/VinylFPGA.al` |
| 约束文件 | `constraints/pin.adc`、`constraints/timing.sdc` |
| 生成物 | `prj/VinylFPGA.bit`（629,624 B）、`prj/VinylFPGA_inst.bid`、`prj/final_timing.rpt`、`*.qor` |
| Verilog 源清单 | TD 工程列入 36 个 Verilog 文件；其中若干为 AutoExcluded 的备用/重复文件 |
| 仿真资产 | 当前 `sim/` 目录没有可见测试平台或仿真脚本 |

### 3.2 板卡信息（未确认）

仓库没有 README、原理图、BOM、板名、SDRAM 型号/走线信息或 HDMI 连接说明。因此可确认的是器件与顶层引脚位置，**无法仅凭该仓库锁定具体开发板**。后续 AI 不应把旧 IP 文件路径中的 `HX4S20`、`I2S` 或示例工程名称当作本板硬件身份。

SDRAM 子系统实例化了 `EG_PHY_SDRAM_2M_32` 硬核；顶层没有普通 SDRAM 外部端口，控制/数据引脚由该硬核连接。这意味着 SDRAM 平台基线是“EG4S20BG256 + `EG_PHY_SDRAM_2M_32` 硬核”，而不是普通 GPIO SDRAM 方案。更换板卡、器件或 SDRAM 类型时必须重新确认硬核适配，而不是仅修改 ADC 引脚。

### 3.3 顶层物理接口（事实）

| 类别 | 顶层端口 | 约束摘要 |
|---|---|---|
| 参考时钟/复位 | `clk`、`rst_n` | `clk=R7`，`rst_n=A2`，LVCMOS33 |
| 用户按键 | `key1`、`key2` | `B2`、`C1`；代码假设按下为低电平 |
| TF/SD（SPI） | `sd_ncs`、`sd_dclk`、`sd_mosi`、`sd_miso` | A12、A14、A13、B14，LVCMOS33 |
| HDMI TMDS 单端正端 | `HDMI_CLK_P`、`HDMI_D0_P`、`HDMI_D1_P`、`HDMI_D2_P` | C3、G5、F1、E1，LVDS33；负端由 PHY/器件资源处理 |
| HDMI DDC | `HDMI_DDC_SCL`、`HDMI_DDC_SDA` | P2、R2，LVCMOS33，带 PULLUP |
| 六位数码管 | `seg_sel[5:0]`、`seg_data[7:0]` | 已完整分配，LVCMOS33 |

`pin.adc` 中保留了被注释掉的 VGA、旧 I²S 与旧 HDMI 引脚例子；它们**不是当前顶层的有效连接**。

## 4. 系统架构

### 4.1 数据与控制流

```text
               key1 / key2
                    │
                    ▼
  SD 卡 SPI ──► sd_card_bmp ──► bmp_read ──► 写异步 FIFO ─┐
       ▲           │ 扫描 / 选择 / 双缓冲                  │
       │           └──► 数码管状态                         ▼
  sd_card_top ◄──────────────────────────────────── frame_fifo_write
                                                          │
                                                     SDRAM 写端口
                                                          ▼
                                            EG_PHY_SDRAM_2M_32 硬核
                                                          ▲
                                                     SDRAM 读端口
                                                          │
  640×480 时序 ◄── video_timing_data ◄── frame_fifo_read ┘
       │                         │
       └────────► video_delay ───┴──► RGB/DE
                                          │
                                        AXI-Stream
                                          │
 内部 I²S 测试音 ─► I2S_receiver ─► ACR 计算 ─┤
                                                ▼
                               HDMI 1.4b 加密发射核 ─► TMDS 10-bit
                                                        │
                                            LVDS 10:1 PHY ─► HDMI
```

### 4.2 顶层工作阶段（事实与推断）

1. 外部 `rst_n` 释放且音频 PLL 锁定后，`rst_all` 解除。`rst_all = ~rst_n | ~audio_pll_lock`。
2. SD 控制器执行卡初始化；`bmp_read` 只有在 `sd_init_done=1` 后才开始工作。
3. `sd_card_bmp` 自动扫描扇区 0 到 131071，寻找最多 4 个符合格式的 BMP 起始扇区。
4. 找到至少一张图后，首图写入 SDRAM buffer 0；写完成事件经 toggle 同步回 SD 域后，`display_valid` 才置位，视频从黑屏切换到该缓冲区。
5. `key1` 请求下一张；`key2` 在找到至少两张图时切换自动播放。自动播放周期由 100 MHz 域计数器控制，目标约为 1 秒。
6. 读取逻辑每帧向 SDRAM 请求当前显示 buffer 的 640×480 像素，产生 RGB、同步和 DE，并通过 HDMI 核发送。
7. 音频链路持续生成 do/re/mi/fa/so/la/si/do 的方波测试音；该 I²S 流被接收并作为 HDMI 音频输入。

“约为 1 秒”和“首图安全切换”来自代码计数器和双缓冲握手；是否在目标卡、显示器和实际 SDRAM 上成功运行，仍需实板验证。

## 5. 时钟、复位与时钟域

### 5.1 时钟计划（事实）

| 名称 | 源 | 频率 | 主要消费者 | 说明 |
|---|---|---:|---|---|
| `clk` | 板级输入 | 50 MHz | PLL、数码管 | SDC `create_clock` |
| `sd_card_clk` | `sys_pll.clk0` | 100 MHz | SD 卡、BMP 读取、写侧 FIFO | SPI 高速参数为 0 时，理论 SCLK 为 sysclk/4 ≈ 25 MHz |
| `ext_mem_clk` | `sys_pll.clk1` | 125 MHz | SDRAM 用户控制器、FIFO 内存侧 | SDRAM 控制主时钟 |
| `ext_mem_clk_sft` | `sys_pll.clk2` | 125 MHz，180° | SDRAM 相移时钟/硬核 | 没有在顶层 SDC 中重新命名，但被 `derive_clocks` 识别 |
| `video_clk` | `video_pll.clk0` | 25 MHz | 视频时序、HDMI 核、I²S 接收 | 640×480 输出时钟 |
| `hdmi_5x_clk` | `video_pll.clk1` | 125 MHz | HDMI LVDS 10:1 PHY | 视频时钟的 5× |
| `audio_mclk` | `PLL_HDMI_AUDIO.clk2` | 12.295082 MHz | I²S 音源 | 源码注释中写 12.288 MHz，实际 IP 参数为 12.295082 MHz |

### 5.2 视频与音频速率推导（推断，直接由参数计算）

- HDMI 时序为 800×525，像素时钟为 25 MHz，因此帧率约为 `25,000,000 / (800×525) = 59.52 Hz`。VIC=1 通常对应 640×480p60（标称 25.175 MHz），所以当前配置接近而不是严格符合该常见标称时钟。
- I²S 发生器在每个 `audio_mclk` 边沿翻转 BCLK，并在 64 个 BCLK 上升沿后切换 LRCK。按实现推算，立体声帧率约为 `12.295082 MHz / (2×128) = 48.03 kHz`，接近 HDMI 核参数中的 `48K`。
- `startup_pulse` 在 `video_clk` 域计数 100,000 周期，约 4 ms 后向 HDMI 核发出一次 EDID 读取触发。

### 5.3 复位和 CDC 审核重点

| 交叉 | 当前实现 | 判断 |
|---|---|---|
| `video_clk` 请求 SDRAM 读 | 请求、长度与 buffer index 被同步到 `ext_mem_clk`，读数据走异步 FIFO 回 video 域 | 有架构意图；应以仿真/CDC 工具确认请求期间的总线稳定性 |
| `sd_card_clk` 写入 SDRAM | 写数据走异步 FIFO，写请求同步到 `ext_mem_clk` | 有架构意图；应检查 FIFO reset 与握手时序 |
| SDRAM 写完成 → SD 域 | `frame_write_finish` 在内存域翻转 toggle，SD 域三拍同步并异或成脉冲 | 相比单周期脉冲跨域更可靠，是当前双缓冲提交的关键机制 |
| `audio_mclk` I²S → `video_clk` | `I2S_receiver` 对 BCLK/LRCK/DOUT 分别三拍同步，再按检测到的 BCLK 上升沿采样 | STA 被设为异步；功能上仍有多比特采样一致性/亚稳态风险，未见异步 FIFO 或专门 I²S CDC 证明 |
| 视频像素 → HDMI 核 | AXI-Stream 输出没有使用 `axis_s_ready` 回压 | 需确认加密 HDMI 核在该模式下是否始终 ready；否则潜在丢像素 |

复位只显式依赖 `rst_n` 与**音频 PLL lock**，`sys_pll` 和 `video_pll` 的 lock 没有引入复位条件。若硬件上三个 PLL 锁定先后关系不稳定，SDRAM/视频链路可能在各自 PLL 稳定前提前离开复位；这是启动可靠性的待验证项。

## 6. 模块分层与职责

### 6.1 顶层与应用编排

| 文件 / 模块 | 职责 | 关键接口或行为 |
|---|---|---|
| `src/top_tf_hdmi_audio.v` / `top` | 系统集成 | 实例化 3 个 PLL、SD/BMP、帧缓存、SDRAM、音频、HDMI 核、PHY、数码管 |
| `src/startup_pulse.v` | 一次性延时脉冲 | 触发一次 EDID 读取 |
| `src/video_rgb_to_axis_640x480.v` | RGB/DE 到视频 AXI-Stream | `user`=帧首、`last`=第 640 像素；未使用 ready |
| `src/video_source_test.v` | 1080p 测试视频源 | 已 `AutoExcluded`，未在当前顶层使用 |

### 6.2 TF/SD、BMP 与 UI

| 模块 | 职责 | 重要事实 |
|---|---|---|
| `sd_card_bmp` | 应用状态机、双缓冲选择、按键去抖、扫描和加载调度 | 默认找 4 张图；首图 buffer0，后续写非显示 buffer；确认整帧 SDRAM 写完才翻转显示 buffer |
| `bmp_read` | 按扇区扫描 BMP 头并连续输出像素 | 仅接受 `BM`、640×480、24bpp、compression=0；读取 BMP header 的文件长度、像素偏移、宽高等字段 |
| `sd_card_top` | SPI 信号、命令与扇区读写的集成 | 当前只使用读路径；写端口在顶层连接为常量/悬空 |
| `sd_card_sec_read_write` | CMD0/CMD8/CMD55/ACMD41/CMD16/CMD17/CMD24 流程 | SD 初始化与单扇区读写状态机 |
| `sd_card_cmd`、`spi_master` | SD 命令/块传输与字节级 SPI | 卡初始化低速分频 248，高速分频 0 |
| `seg_decoder`、`seg_scan` | 6 位数码管显示 | 最后一位显示 `bmp_read.state_code`；其余位熄灭 |
| `ax_debounce` | 旧按键去抖模块 | 已 `AutoExcluded`；当前实际使用 `sd_card_bmp.v` 内的 `key_press_debounce` |

#### BMP/存储格式约束（极其重要）

当前实现不是 FAT 文件系统：它从原始扇区扫描 BMP 文件头，遇到匹配格式便以 `file_len` 推算下一个候选扇区。卡中数据必须满足以下条件：

- 图片为 BMP，文件头以 `BM` 开始；
- 宽 640、高 480；
- 24 bits per pixel，压缩字段为 0；
- 使用代码读取到的 `pixel_offset` 作为像素开始位置；
- 每像素按 BMP 的 B、G、R 字节接收，再重排为 SDRAM 中的 `[31:8]=R:G:B`；
- 写控制器启用逐行垂直翻转，意图修正常规 BMP 的 bottom-up 行顺序；
- 最大扫描扇区为 131071，最多缓存 4 个候选图片起始扇区。

不支持或未实现的能力包括：目录遍历、文件名选择、FAT/exFAT、PNG/JPEG、RLE BMP、任意分辨率、透明度和超过四张图的索引缓存。由于扫描从扇区 0 开始而不是解析分区/文件系统，镜像制作流程必须作为项目外部规范补充；当前仓库没有这份规范。

### 6.3 SDRAM 与帧缓存

| 模块 | 职责 | 实现特征 |
|---|---|---|
| `frame_read_write` | 读写总控 | 将读写请求分配给两个异步 FIFO 与读/写 FSM；写优先级通过 busy 信号协调 |
| `frame_fifo_write` | 写侧调度 | 512 word FIFO、水位触发、256 word burst；支持 `WRITE_V_FLIP=1` 的逐行反向地址 |
| `frame_fifo_read` | 读侧调度 | 512 word FIFO、128 word burst；视频时序每帧请求当前显示 buffer |
| `IP/afifo_16_32_256.v` | 写异步 FIFO | 实际模块名 `wfifo_32_32_512`，32-bit×512 |
| `IP/afifo_32_16_256.v` | 读异步 FIFO | 实际模块名 `rfifo_32_32_512`，32-bit×512 |
| `SD/sdram.v` | 当前采用的 SDRAM wrapper | 将用户接口接入 `sdr_as_ram`，再实例化 `EG_PHY_SDRAM_2M_32` |
| `include/sdr_as_ram.enc.v` 等 | 加密 SDRAM 控制核心 | 32-bit 数据、21-bit 地址、4-bit DM、11-bit row、2-bit bank，125 MHz 基线 |
| `IP/sdram.v` | 备用/旧 SDRAM wrapper | 在 `.al` 中 `AutoExcluded`，不可与 `SD/sdram.v` 同时启用 |

帧大小为 `640×480=307,200` 个 32-bit word。顶层两个 buffer 基地址分别为 0 和 307,200，因此仅像素存储约为 `2×307,200×4 = 2,457,600` B；地址空间为 21 bit word（约 8 MiB），容量上有余量。实际可用容量仍取决于 `EG_PHY_SDRAM_2M_32` 的设备定义，不能仅用 RTL 地址宽度替代硬核资料。

### 6.4 视频与 HDMI

| 模块 | 职责 | 说明 |
|---|---|---|
| `SD/color_bar.v` | 生成 640×480 同步/DE | 当前只使用其时序输出，色条 RGB 输出未连接 |
| `SD/video_timing_data.v` | 发起每帧 SDRAM 读请求 | 对同步信号延迟两拍，检测场同步边沿请求读帧 |
| `SD/video_delay.v` | 对齐读数据与视频时序 | 使用 21 拍移位链：`read_en=de` 延迟 18 拍，数据在 19 拍取样，输出同步/DE 在 20 拍 |
| `hdmi_1_4b_transmitter_core_wrapper.enc.v` | HDMI 1.4b 发射核 wrapper | 加密文件，内部不可从仓库审阅；顶层配置为 RGB、VIC 1、48K 音频、800×525 时序 |
| `hdmi_phy_warpper.v` | HDMI PHY wrapper | 连接 10-bit TMDS 字与 `lane_lvds_10_1` |
| `lane_lvds_10_1.v` | 10:1 LVDS 串化 | 负责物理 TMDS 正端输出 |

HDMI 视频源不是内置色条：`color_bar` 仅提供同步/有效区，像素由 SDRAM 的 `vout_data_raw` 提供。首图完成前，`display_valid=0` 会强制输出黑色，以避免显示未初始化缓冲区。

### 6.5 音频

| 模块 | 职责 | 说明 |
|---|---|---|
| `hdmi_audio_tone_i2s_64fs` | 内部测试音 I²S 发射 | 8 音阶方波，左右声道复用同一样本，24-bit 左对齐到 64-bit 时隙 |
| `I2S_receiver` | I²S 接收 | 在 `video_clk` 域过采样 BCLK/LRCK/DOUT，输出 24-bit 左右样本和有效脉冲 |
| `audio_arc_calculate` | HDMI ACR | 固定 `ACR_N=6144`，每 `N/128=48` 个音频有效样本输出一次 CTS/N |
| `PLL_HDMI_AUDIO` | 音频时钟 | `clk2_out=12.295082 MHz`；顶层用 `extlock` 参与全局复位 |

当前音频是**自激励测试音**，不是外接 I²S 输入。`pin.adc` 中的旧 I²S 输入注释不属于当前顶层功能。

## 7. 当前 TD 源文件组织

`prj/VinylFPGA.al` 的 include path 为 `../src/include`。当前被 AutoExcluded 的文件有：

- `src/video_source_test.v`：备用测试图案源；
- `src/SD/ax_debounce.v`：未使用的旧去抖器；
- `src/SD/video_define.v`：宏定义 include 文件，需由 `color_bar.v` 的预处理 include 使用；
- `src/IP/sdram.v`：旧 SDRAM wrapper，避免与当前 `src/SD/sdram.v` 同名模块冲突。

现有项目摘要记录了一次最小工程修复：将 `src/SD/sdram.v` 与 3 个加密 SDRAM 子文件正确纳入工程，并移除它们的 `AutoExcluded`，以避免 `U3` 被综合为黑盒。后续 AI 在整理工程文件时必须维持此互斥关系：**保留 `SD/sdram.v`，不要同时启用 `IP/sdram.v`**。

## 8. 约束、构建和已验证状态

### 8.1 约束内容（事实）

`timing.sdc`：

- 为 50 MHz `clk` 建立主时钟并执行 `derive_clocks`；
- 命名 `sd_card_clk`、`ext_mem_clk`、`video_clk`、`hdmi_5x_clk`、`audio_mclk`；
- 将 `video_clk` 与 `hdmi_5x_clk` 设置为 `exclusive`；
- 将 `audio_mclk` 与视频/串行/SD/SDRAM 域设置为 `asynchronous`；
- 没有普通 IO input/output delay；
- SD、SDRAM、video 域之间的可选异步分组被注释，故当前仍分析到若干跨域路径。

### 8.2 构建状态（事实）

现有 `doc/stage-S4-summary.md` 记录：某次 SynthPilot/TD 流程已通过 elaborate、综合、place、route、bitgen，生成了 `prj/VinylFPGA.bit`，且编译错误为 0。最新日志仅显示两条未定宽字面量警告：

- `src/include/sdr_init_ref.enc.v:47`；
- `src/include/sdr_wrrd.enc.v:283`。

它们属于加密/参考 SDRAM 控制文件中的拼接警告，尚未在本文中修改。

### 8.3 时序状态（事实，优先级高）

`prj/final_timing.rpt` 的全局结果为：

| 指标 | 当前值 | 含义 |
|---|---:|---|
| Setup WNS | **-6.699 ns** | 未闭合 |
| Setup TNS | **-296.441 ns** | 存在累计 setup 违例 |
| Hold WNS | +0.003 ns | 通过但余量极小 |
| Hold TNS | 0 ns | 无 hold 违例 |

主要 setup 问题如下：

| 路径组 | WNS | 违例端点 | 说明 |
|---|---:|---:|---|
| `sys_pll...clkc[2] → ext_mem_clk` | -6.699 ns | 32 | SDRAM 读回硬核 DQ 到 `ext_mem_clk` 采样路径；相移时钟与硬核 IO 时序 |
| `ext_mem_clk → sys_pll...clkc[2]` | -2.799 ns | 32 | SDRAM 写数据到硬核 DQ 路径 |
| `ext_mem_clk → ext_mem_clk` | -0.398 ns | 6 | `frame_fifo_write` 与 FIFO 地址处理逻辑 |
| `ext_mem_clk → sd_card_clk` | -0.190 ns | 3 | 写请求/清 FIFO 控制相关跨域路径 |
| `sd_card_clk → sd_card_clk` | -0.119 ns | 1 | `bmp_read` 的 `file_len` 到扫描完成控制路径 |

因此，已有 bitstream 的存在只能证明工具接受并完成了 bitgen；它不构成对 SDRAM、帧缓存或整体系统时序可靠性的签核。对 SDRAM 硬核路径尤其不应通过简单的 false path 或宽松约束来“消除”违例，必须先核实该硬核所需的时钟、相位、板级绑定和 TD 的约束建议。

### 8.4 资源与拥塞（事实）

`route.qor` 显示：2,759 slices（28.15%）、20 RAM、0 DSP，且没有超过 100% 利用率的 tile。既有阶段摘要还记录为 LUT 4028/19600、REG 3790/19600、BRAM 20/64、PLL 3/4。两份报告处于不同汇总层级，数值口径并不完全相同；用于决策时优先引用同一次 TD run 的完整 QoR 与 timing 报告。

### 8.5 生成物可追溯性（事实）

文件时间戳显示：`VinylFPGA.bit`、`final_timing.rpt` 和 QoR 文件生成于 2026-10-03 18:58 左右，而当前 `VinylFPGA.al` 的最后写入时间是 2026-10-03 20:23。虽然现有摘要声称该 bitstream 对应修复后的工程，但从时间戳无法严格证明它与当前 `.al` 完全同源。

**在下载当前工程前，建议重新执行完整 TD Compile/Run，并保存新的 bitstream、final timing report 和构建日志。**

### 8.6 Git 工作树快照（事实）

生成本报告时，Git 工作树并不干净。除本报告文件外，`src/SD/sd_card_bmp.v` 已有未提交改动，且 `prj/VinylFPGA_Runs/` 下有大量已修改或删除的 TD run 产物；另有一个未跟踪的 `prj/log/td_2026-10-03_19-40-25.logw`。这些状态在本次分析开始前已经存在，本报告没有修改 RTL、约束、工程 XML 或 run 产物。

因此，后续 AI 在比较实现结果或准备提交时，应先区分“用户正在进行的 RTL/运行目录改动”和“本报告新增文档”，不要用重置或清理工作树的方式覆盖现有内容。

## 9. 风险清单与推荐验证顺序

### P0：影响结论/上线的风险

1. **SDRAM 时序未闭合。**先锁定板卡、器件封装、SDRAM 硬核型号和相移 PLL 关系，再根据官方硬核要求复核 constraint/clock relationship；不要仅修改 HDL 消除报表。
2. **当前 bitstream 与工程文件时间戳不一致。**重新构建并归档匹配的报告后才使用该 bitstream 做验证依据。
3. **缺少实板验证证据。**必须分别验证：SD 卡初始化、BMP 扫描、首图黑屏→显示切换、手动/自动双缓冲切换、SDRAM 稳定性、EDID/DDC、HDMI 图像、HDMI 音频。

### P1：功能可靠性风险

1. **I²S CDC。**目前是把 BCLK/LRCK/DOUT 独立同步至 25 MHz 视频域；应做波形仿真和 CDC 审查，必要时改用 audio 域解析 + async FIFO 传样本。
2. **AXI-Stream backpressure 被忽略。**`axis_s_ready` 未反馈给视频源；确认 HDMI wrapper 永远 ready，或增加 ready-aware 像素保持/同步策略。
3. **视频标准匹配。**25 MHz 输出下帧率约 59.52 Hz，但 HDMI 配置为 VIC 1；应在目标显示器上验证兼容性，若追求标准时序则重新生成 25.175 MHz 及相关串行时钟。
4. **PLL lock 时序。**全局复位仅等待音频 PLL；需评估 `sys_pll`、`video_pll` 锁定前使用逻辑的安全性。
5. **SD 卡兼容性。**扇区地址的使用方式、CMD16 流程与不同 SD/SDSC/SDHC 卡的兼容性没有测试材料；应以目标卡实测。

### P2：可维护性风险

1. 没有 board/SDRAM/SD 卡镜像/HDMI 接线文档；需要补充 README 和验证记录。
2. 有多个历史/备用源文件和加密核，缺乏“使用中 / 备用 / 生成物”的明确标识。
3. `timing.sdc` 的 `video_clk` 与 `hdmi_5x_clk` 被标为 exclusive，且 audio 域被切为 asynchronous；这些例外需要依据 HDMI PHY 和 CDC 设计意图复核，避免掩盖真实路径。
4. 没有自动化仿真、lint、CDC 或回归测试。

## 10. 建议的后续工作流

### 如果目标是先让现有工程可靠运行

1. 在 TD 6.2.168116 打开 `prj/VinylFPGA.al`，重新完整编译；归档新的 `.bit`、`final_timing.rpt`、QoR 和日志。
2. 对照 `EG_PHY_SDRAM_2M_32` 官方使用说明审查相移输出和 TD SDRAM 约束；优先处理 P0 SDRAM 路径。
3. 制作并记录一张可复现的 SD 卡镜像：至少放置一张符合上述格式的 BMP，并记录其分区与起始扇区是否会被原始扫描找到。
4. 先验证 HDMI 黑屏、EDID/DDC 和测试图/首图，再验证多图、按键和自动播放；最后做连续轮播稳定性测试。
5. 记录显示器型号、TF/SD 卡型号、上电/复位方式、照片/串口（如有）和异常现象。

### 如果目标是继续开发

- **改 UI/图片源**：先抽象一个明确的“图像索引/文件定位”接口，再决定是否引入 FAT；不要在当前原始扫描逻辑中直接堆叠文件系统功能。
- **改分辨率**：同时修改 BMP 接受条件、帧大小/缓冲基址、视频时序、像素 PLL、HDMI 核 timing/VIC、SDRAM 带宽评估和验证用例。
- **改音频**：先定义音频主域、采样率、位宽与 HDMI ACR 关系；之后把 CDC 做成样本级异步 FIFO，而非仅依赖独立单比特同步。
- **改板卡**：将其作为新的平台基线，重新锁定器件、封装、DDR/SDRAM 硬核、ADC、PLL、HDMI 对与时序约束。

## 11. 后续 AI 的操作约束

1. 默认将 `src/top_tf_hdmi_audio.v`、`constraints/` 与 `prj/VinylFPGA.al` 视为当前集成入口；先检查工程源文件列表，再增删 RTL。
2. 不要同时启用两个名为 `sdram` 的 wrapper；当前生效的是 `src/SD/sdram.v`。
3. `src/IP/*.v` 中的 PLL/FIFO 及 HDMI 加密核是供应商生成或加密 IP；修改前应优先通过 TD IP 配置重新生成，并保留版本与参数记录。
4. 不要把 `AutoExcluded` 文件当成当前设计的一部分；如果启用它们，先处理模块同名、include 宏和顶层连接。
5. 不要因为 bitgen 成功就宣称硬件通过；必须检查 `final_timing.rpt` 和实板结果。
6. 任何波及 SDRAM 相移时钟、时序例外或硬核绑定的变更，都需要重新审查完整时序，而不是只观察综合是否成功。
7. 文件中没有外部用户数据或凭据的证据；不过 SD 卡内容、显示器兼容性和目标板卡均是外部依赖，变更/测试时应单独记录。

## 12. 固定阶段摘要（供自动化/AI 快速读取）

```yaml
current_stage: post-build analysis / timing-closure and hardware-validation required
goal: 从 TF/SD 原始扇区中的 640x480x24bpp BMP 实现双缓冲 HDMI 视频播放，并输出内部 48 kHz 级 I2S 测试音至 HDMI
confirmed_constraints:
  device: EG4S20BG256
  tool_project: TD 6.2.168116
  top: top
  ref_clock: 50 MHz
  video: 640x480 timing, 25 MHz pixel clock, 125 MHz serial clock
  storage: EG_PHY_SDRAM_2M_32 hard-IP with 32-bit user data interface
  image: BMP BM, 640x480, 24bpp, compression=0, max 4 indexed images
artifacts:
  project: prj/VinylFPGA.al
  constraints: [constraints/pin.adc, constraints/timing.sdc]
  bitstream: prj/VinylFPGA.bit
  timing_report: prj/final_timing.rpt
decision: 工程可构建但不可视为时序签核完成；先重建并处理 SDRAM/SD 域 setup 违例，再进行系统实板验证
blocking_reason: 最终 setup WNS -6.699 ns；板卡、SDRAM/SD 卡镜像和实板验证证据缺失
next_action: 重新完整编译当前 .al，核对硬核 SDRAM 相移时序并建立可复现的 SD 卡与 HDMI 实板验证记录
```

## 13. 关联文件索引

- 顶层集成：`src/top_tf_hdmi_audio.v`
- SD/BMP 应用：`src/SD/sd_card_bmp.v`、`src/SD/bmp_read.v`
- SD SPI 协议：`src/SD/sd_card_top.v`、`src/SD/sd_card_sec_read_write.v`、`src/SD/sd_card_cmd.v`、`src/SD/spi_master.v`
- 帧缓存：`src/SD/frame_read_write.v`、`src/SD/frame_fifo_write.v`、`src/SD/frame_fifo_read.v`
- SDRAM：`src/SD/sdram.v`、`src/include/global_def.v`、`src/include/sdr_*.enc.v`
- 视频：`src/SD/color_bar.v`、`src/SD/video_timing_data.v`、`src/SD/video_delay.v`、`src/video_rgb_to_axis_640x480.v`
- HDMI：`src/hdmi_phy_warpper.v`、`src/lane_lvds_10_1.v`、`src/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v`
- 音频：`src/hdmi_audio_tone_i2s_64fs.v`、`src/I2S_receiver.v`、`src/audio_arc_calculate.v`
- 生成 IP：`src/IP/sys_pll.v`、`src/IP/video_pll.v`、`src/IP/PLL_HDMI_AUDIO.v`、`src/IP/afifo_*.v`
- 工程/实现记录：`prj/VinylFPGA.al`、`prj/final_timing.rpt`、`prj/gate.qor`、`prj/place.qor`、`prj/route.qor`、`doc/stage-S4-summary.md`

