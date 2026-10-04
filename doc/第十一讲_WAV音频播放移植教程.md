# 第十一讲 WAV音频播放移植教程

> 参照教程：`FPGA创新设计赛道安路赛项（完赛系列）/第十一讲：WAV音频播放/第10课_WAV音频播放.md`
>
> 参照代码：`第十一讲：WAV音频播放/第10课_WAV音频播放/`
>
> 移植对象：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`
>
> 本讲最终位流：`prj/VinylFPGA_lecture11_wav_timingfix2.bit`
>
> SHA256：`607538843B8AEB8395CA3BD5CC2E7404AA707C7E4527F1A9EAA243A56B9788AC`

---

## 一、本讲目标

本讲把第四讲已经跑通的 HDMI 音频链路向前扩展一层：从原来的
`pcm_media_tone` 琶音提示音，增加 TF 卡上的 `AUDIO.PCM` 流式播放。

完赛教程的核心结构是：

```text
AUDIO.PCM 原始 PCM 数据
  -> TF 卡扇区读接口
  -> wav_stream_player 循环缓冲
  -> audio_source_mux 音源选择
  -> PCM 音量/转场增益
  -> HDMI PCM 桥
  -> 现有 M06 PCM 契约
  -> 安路 HDMI 1.4b 加密发射核
```

本工程没有替换第四讲已经验证过的 HDMI 音频包封装链路，而是在它前面
插入 WAV 流播放器。这样保留旧音源、切图提示音和 HDMI 输出链路，同时
增加整段音乐播放能力。

本讲最终保留以下功能：

```text
KEY1 短按下一张
KEY2 短按自动轮播开关
KEY2 长按上一张
3 秒自动轮播
切图提示音
第四讲已有 HDMI 音频
FAT32 扫描 PIC1.BMP ~ PIC4.BMP
四 bank 帧缓存
第九讲状态 OSD
第十讲图片转场特效
```

## 二、移植原则与边界

### 2.1 最小侵入原则

本讲没有重写 `sd_card_bmp.v` 的按键、轮播、四 bank 调度和错误恢复
状态机，也没有替换 HDMI 音频包封装。新增音频数据流只在现有媒体
加载完成之后启动，不参与上电扫描和图片预加载阶段。

这样处理的原因：

1. 第二讲到第十讲的功能已经经过多次上板修复，直接替换上层状态机
   容易重新引入黑屏、按键卡死和自动轮播失效。
2. 第四讲已经确认 HDMI 音频包链路可用，只需要在 PCM 源前面增加
   选择器，不需要改 HDMI 加密核。
3. `AUDIO.PCM` 播放只需要起始 LBA 和扇区数，不需要改动视频时序、
   SDRAM 控制器和 TMDS 输出。

### 2.2 不可修改清单

以下内容属于本工程的高危或已验收链路，本讲没有改动：

```text
src/hdmi1.4b_transmitter_core/ 下的 HDMI 1.4b 加密发射核
src/include/*.enc.v 下的 SDRAM 加密核和初始化核
HDMI PHY、TMDS、DDC、EDID 链路
SDRAM 控制器、视频时序和四 bank 显示链路
constraints/pin.adc 管脚约束
constraints/timing.sdc 时钟和 IO 时序约束
PLL、复位同步和上电自启链路
KEY1、KEY2 的原有按键语义
自动轮播计时和切图音效
```

### 2.3 音频链适配方式

教程里的 `media_hdmi_audio_bridge` 把 PCM 直接接到教程自己的
HDMI 音频包链。本工程已经有一套第四讲验证过的 M06 契约和安路
HDMI 加密核，因此没有照搬教程的 symbol/TMDS 输出路径。

本工程实际落点为：

| 教程层次 | 本工程落点 |
|---|---|
| WAV 流播放器 | 新增 `src/audio/wav_stream_player.v` |
| 音源选择 | 新增 `src/audio/audio_source_mux.v` |
| 音量与转场增益 | 新增 `src/audio/pcm_volume_fade.v` |
| 转场 alpha 跨域同步 | 新增 `src/audio/sync_fade_gain.v` |
| PCM 到 M06 契约桥 | 新增 `src/audio/hdmi_pcm_source_bridge.v` |
| FAT32 扫描器 | 扩展 `src/SD/fat32_volume_scanner.v` |
| 媒体加载兼容层 | 扩展 `src/SD/fat32_media_loader.v` |
| 播放使能和扇区仲裁 | 扩展 `src/SD/sd_card_bmp.v` |
| 顶层音频连接 | 扩展 `src/top_tf_hdmi_audio.v` |

旧文件 `src/audio/hdmi_pcm_audio_bridge.v` 在本讲中不再是顶层实际
使用的音频桥，保留在工程源列表中并标记为排除，不参与本讲新增链路。

## 三、TF 卡准备

### 3.1 文件系统要求

TF 卡必须保持第七讲要求的 FAT32：

```text
文件系统：FAT32
目录位置：根目录
图片文件：PIC1.BMP、PIC2.BMP、PIC3.BMP、PIC4.BMP
音频文件：AUDIO.PCM
文件名：8.3 大写短文件名
```

图片仍然是 640x480、24 位、无压缩 BMP。音频文件必须满足：

```text
格式：原始 PCM，没有 WAV 头
位深：16 bit signed
字节序：little-endian
声道：mono，单声道
采样率：48000 Hz
```

### 3.2 把 WAV 转成 AUDIO.PCM

完赛教程使用 `tools/make_audio_corpus.py`。本工作区没有随附该脚本，
因此使用等价的 FFmpeg 命令：

```powershell
ffmpeg -y -i input.wav -ac 1 -ar 48000 -sample_fmt s16 -f s16le AUDIO.PCM
```

参数含义：

```text
-ac 1                    单声道
-ar 48000                48 kHz
-sample_fmt s16          16 bit signed
-f s16le                 little-endian
```

生成后把文件复制到 TF 卡根目录，文件名必须是：

```text
AUDIO.PCM
```

### 3.3 连续存放要求

本讲的 `wav_stream_player` 按 `start_lba + 连续扇区号` 读取音频，
不遍历 `AUDIO.PCM` 的 FAT 链。因此 `AUDIO.PCM` 必须在 TF 卡上
连续存放。

推荐操作顺序：

```text
1. 用 SD Card Formatter 重新格式化 TF 卡为 FAT32。
2. 先复制 PIC1.BMP ~ PIC4.BMP。
3. 再复制 AUDIO.PCM。
4. 复制完成后不要再频繁删除、覆盖和重新复制大文件。
5. 安全弹出 TF 卡。
```

如果上板后图片正常，但音频播放到中途变成噪声或跳到错误内容，
优先检查 `AUDIO.PCM` 是否碎片化。最稳妥的办法是重新格式化后
一次性复制全部文件。

### 3.4 当前自动写入状态

当前执行环境已经检测到 `E:` 盘为 FAT32 可移动卷。首次写入时卷被
Windows 标记为 `Full Repair Needed`，并且在 LBA 0x1600 出现一次
USB 存储控制器 I/O 重试。执行 `chkdsk E: /f` 后脏位清除，卷状态恢复
为 Healthy / OK，随后重新写入成功。

`E:` 根目录当前已经写入并通过 SHA256 回读校验：

```text
PIC1.BMP
PIC2.BMP
PIC3.BMP
PIC4.BMP
AUDIO.PCM
```

工程内同时保留一套可直接复制到 TF 卡根目录的 staging 包：

```text
VinylFPGA/tf_card_stage/
  PIC1.BMP
  PIC2.BMP
  PIC3.BMP
  PIC4.BMP
  AUDIO.PCM
  Copy-ToTfCard.ps1
  README.txt
```

其中四张 BMP 已核对为 `640x480`、24 位、无压缩；
`AUDIO.PCM` 由 `资源/音频/wav/rick.wav` 转换成 48 kHz、16 bit signed、
单声道、little-endian 原始 PCM，并补齐到 512 字节扇区边界，避免最后
一扇区带入文件尾之后的数据形成尾部杂音。

如果以后需要重新写卡，插卡后确认盘符为 `E:`，可运行：

```powershell
powershell -ExecutionPolicy Bypass -File `
  D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\tf_card_stage\Copy-ToTfCard.ps1 `
  -DriveLetter E
```

如果卡不是 FAT32，脚本会拒绝复制。只有在确认盘符无误、并且接受
清空整张卡的情况下，才使用：

```powershell
powershell -ExecutionPolicy Bypass -File `
  D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\tf_card_stage\Copy-ToTfCard.ps1 `
  -DriveLetter E -Format -Force
```

上板前仍需人工确认以下检查：

```text
1. E: 盘已识别为 FAT32。
2. 根目录有 PIC1.BMP ~ PIC4.BMP。
3. 根目录有 AUDIO.PCM。
4. AUDIO.PCM 是 48 kHz、16 bit signed、单声道、little-endian。
5. AUDIO.PCM 已补齐到 512 字节整数倍并连续存放。
```

## 四、新增源码

### 4.1 `src/audio/wav_stream_player.v`

本模块是本讲核心。写侧工作在 `sd_card_clk` 域，从 SD 扇区接口
读取 512 字节，按小端序拼成 16 bit PCM 样本，写入 4096 x 16 bit
BRAM 循环缓冲。读侧工作在 `video_clk` 域，在 `sample_tick` 到来时
按 48 kHz 消费一个样本。

关键实现：

```text
1. 写指针和读指针使用格雷码加两级同步。
2. 缓冲高水位暂停下一扇区请求，避免 TF 读得比音频消费快导致覆盖。
3. 预填充达到 256 个样本后才开始输出真实 PCM。
4. 下溢时输出 0 但保持 sample_valid，避免 HDMI 音频链停顿爆音。
5. 播放结束后先把 BRAM 残余样本排空，再释放音源。
```

模块接口：

```verilog
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer SAMPLES_PER_SECTOR = 256
) (
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,
    input  wire [31:0] start_lba,
    input  wire [31:0] total_sectors,
    output wire        sd_req,
    output reg  [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,
    output reg  signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,

    output reg  [31:0] sample_counter,
    output wire        stream_active,
    output wire        stream_end,
    output wire        buffer_low
);
```

### 4.2 `src/audio/audio_source_mux.v`

音源选择器在 WAV 和原琶音之间二选一：

```text
wav_active = 1 且 force_arpeggio = 0
  -> 选择 WAV

否则
  -> 选择原 pcm_media_tone 琶音
```

`ready` 只回给被选中的音源。未被选中的音源不推进握手，避免切换时
丢样本。本工程没有接拨码开关强制音源，`force_arpeggio` 固定为 0。

### 4.3 `src/audio/pcm_volume_fade.v`

对 WAV 样本同时施加用户音量和转场淡入淡出增益：

```text
输出样本 = 输入样本 * volume / 255 * fade_gain / 255
```

本工程 `audio_volume` 固定为 `8'd200`。转场增益来自
`sync_fade_gain`。该模块只作用于 WAV，不会改变原有切图提示音。

### 4.4 `src/audio/sync_fade_gain.v`

第十讲转场模块产生的 `alpha` 在像素域按帧边界变化。本模块先把
`alpha` 在 `frame_start` 锁存，再用两级同步器送到音频时钟域，
最后作为 WAV 的淡入淡出增益。

这样做可以避免一帧内 alpha 突变造成音频爆音，同时让音乐淡出
和图片转场同步。

### 4.5 `src/audio/hdmi_pcm_source_bridge.v`

本模块把 16 bit PCM 源接回本工程第四讲已经验证的 M06 契约：

```text
16 bit PCM
  -> m06_pcm_contract_adapter
  -> 24 bit HDMI 音频数据
  -> 安路 HDMI 1.4b 加密核
```

它替换了教程中面向另一套 HDMI 音频包链的 `media_hdmi_audio_bridge`。
底层 HDMI 加密核、TMDS 和视频链路没有改动。

### 4.6 `sim/tb_wav_stream_player.v`

仿真覆盖：

```text
16 bit little-endian 字节组装
256 样本预填充
4096 x 16 bit 循环缓冲
格雷码读写指针同步
播放结束残余样本排空
stream_active / stream_end 握手
```

运行结果：

```text
PASS: wav stream player little-endian/prefill/drain/end
```

## 五、修改文件

### 5.1 `src/SD/fat32_volume_scanner.v`

扫描根目录时增加 `AUDIO.PCM` 的 8.3 短文件名匹配，新增输出：

```verilog
output reg         audio_valid,
output reg  [31:0] audio_cluster,
output reg  [31:0] audio_size,
```

匹配条件是根目录项前 11 字节等于：

```text
AUDIO   PCM
```

其中前 8 字节是 `AUDIO   `，后 3 字节是 `PCM`。扫描到后记录首簇和
文件大小。找不到 `AUDIO.PCM` 时 `audio_valid` 保持 0，WAV 播放器
不启动，原有琶音和按键功能不受影响。

### 5.2 `src/SD/fat32_media_loader.v`

本模块新增音频元数据和音频扇区客户端：

```verilog
output wire        audio_file_valid,
output wire [31:0] audio_start_lba,
output wire [31:0] audio_total_sectors,
input  wire        audio_sec_req,
input  wire [31:0] audio_sec_lba,
output wire        audio_sec_busy,
output wire        audio_sec_valid,
output wire [7:0]  audio_sec_byte,
output wire [8:0]  audio_sec_byte_index,
output wire        audio_sec_done,
output wire [7:0]  audio_sec_error
```

扫描完成后计算：

```text
audio_start_lba =
    data_start +
    (audio_cluster - 2) * sectors_per_cluster

audio_total_sectors =
    (audio_size + 511) / 512
```

扫描结果在 `scanner_done` 时锁存到寄存器，再驱动 WAV 播放器。
这一步是为了切断扫描器组合逻辑到音频缓冲控制的长路径。

音频扇区请求与图片流读取共用 `sd_sector_adapter`。仲裁规则是：
音频请求优先级最高，但每次只占用一个扇区；扇区完成后图片流读取
可以继续获得总线。WAV 只在图片预加载完成后启动，因此不会和四张
图片的初始加载抢占总线。

### 5.3 `src/SD/sd_card_bmp.v`

新增音频元数据和播放使能输出：

```verilog
output wire        audio_file_valid,
output wire [31:0] audio_start_lba,
output wire [31:0] audio_total_sectors,
output wire        audio_play_enable,
```

播放条件：

```verilog
audio_play_request =
    audio_file_valid &&
    scan_done_eff &&
    preload_done;
```

`audio_play_request` 在 `sd_card_clk` 域寄存一拍后输出
`audio_play_enable`。这样不会改变原图片扫描、预加载和轮播状态机，
同时避免组合调度信号直接扇入 WAV 播放器形成长路径。

### 5.4 `src/top_tf_hdmi_audio.v`

顶层新增第十一讲实例：

```text
u_wav_stream_player
u_sync_fade_gain
u_pcm_volume_fade
u_audio_source_mux
u_hdmi_pcm_source_bridge
```

WAV 采样节拍为 48 kHz：

```verilog
if (wav_tick_acc >= (32'd25_000_000 - 32'd48_000)) begin
    wav_tick_acc <= wav_tick_acc + 32'd48_000 - 32'd25_000_000;
    wav_sample_tick <= 1'b1;
end
```

音源优先级：

```text
WAV 播放中
  -> WAV

WAV 未播放或已结束
  -> 原 pcm_media_tone 琶音
```

切图提示音仍由原 `pcm_media_tone` 产生，因此第十讲原有的切图音效
不需要改。

### 5.5 `prj/VinylFPGA.al`

头文件列表恢复并保留第十讲显示模块：

```text
46  src/display/status_osd_overlay.v
47  src/display/osd_overlay_24.v
48  src/display/video_transition_apply.v
49  src/display/video_fade_transition.v
50  src/display/frame_blend.v
```

追加第十一讲音频模块：

```text
51  src/audio/hdmi_pcm_source_bridge.v
52  src/audio/wav_stream_player.v
53  src/audio/audio_source_mux.v
54  src/audio/pcm_volume_fade.v
55  src/audio/sync_fade_gain.v
```

`m06_pcm_contract_adapter.v` 不在本讲中被排除，因为新的
`hdmi_pcm_source_bridge.v` 会实例化它。

## 六、完整数据流

```text
TF 卡根目录
  ├─ PIC1.BMP ~ PIC4.BMP
  │    -> fat32_volume_scanner
  │    -> fat32_file_streamer
  │    -> fat32_media_loader
  │    -> sd_card_bmp 四 bank 调度
  │    -> frame_read_write
  │    -> video_transition_apply
  │    -> osd_overlay_24
  │    -> HDMI 视频
  │
  └─ AUDIO.PCM
       -> fat32_volume_scanner 记录首簇和文件大小
       -> fat32_media_loader 计算连续起始 LBA 和扇区数
       -> wav_stream_player 循环缓冲
       -> pcm_volume_fade 音量与转场增益
       -> audio_source_mux 与原琶音二选一
       -> hdmi_pcm_source_bridge
       -> M06 PCM 契约
       -> HDMI 音频
```

音频播放的启动时序：

```text
SD 初始化
  -> 扫描 FAT32 根目录
  -> 找到 PIC1~PIC4 和 AUDIO.PCM
  -> 预加载四张图片
  -> preload_done = 1
  -> audio_play_enable = 1
  -> wav_stream_player 开始预填充
  -> WAV 播放
  -> 播放结束后回到原琶音
```

## 七、工程构建

本次使用安路 TD `6.2.168116` 执行完整流程：

```text
import_device
  -> open_project
  -> elaborate
  -> read_adc
  -> read_sdc
  -> optimize_rtl
  -> optimize_gate
  -> legalize_phy_inst
  -> read_sdc_post_gate
  -> place
  -> route
  -> update_timing
  -> bitgen
```

构建参数：

```text
AL：D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al
ADC：D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/constraints/pin.adc
SDC：D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/constraints/timing.sdc
Device DB：eagle_s20.db
Package：EG4S20BG256
Top：top
End Step：bitgen
```

最终产物：

```text
prj/VinylFPGA_lecture11_wav_timingfix2.bit
SHA256：607538843B8AEB8395CA3BD5CC2E7404AA707C7E4527F1A9EAA243A56B9788AC
```

## 八、验证结果

### 8.1 仿真回归

以下仿真全部通过：

```text
tb_wav_stream_player          PASS
tb_wav_stream_player_flow     PASS
tb_fat32_volume_scanner       PASS
tb_fat32_media_loader         PASS
tb_sd_card_bmp_fourbank       PASS
tb_video_fade_transition      PASS
```

其中 `tb_wav_stream_player_flow` 是本轮新增的多扇区流控回归，
用 12 个连续扇区强制写侧进入 `WS_WAIT` 高水位状态，并逐样本核对
3072 个样本的顺序、循环缓冲回卷和结束排空。它覆盖了单扇区测试
无法触及的高水位暂停路径。

其中 `tb_sd_card_bmp_fourbank` 额外检查了图片四 bank 预加载完成后
`audio_play_enable` 才会拉高，并核对 `AUDIO.PCM` 起始 LBA 和扇区数
元数据能够正确传到 WAV 播放器。

### 8.2 最终时序

路由后时序：

```text
Setup WNS：-0.057 ns
Setup TNS：-0.304 ns
Setup 违反端点：12

Hold WNS：-0.008 ns
Hold TNS：-0.023 ns
Hold 违反端点：6
```

这比第十一讲第一次构建时 `Setup WNS = -4.927 ns` 已大幅收敛。
剩余负裕量很小，主要来自现有 `sd_card_clk` 媒体路径和 WAV BRAM
内部读写控制；没有发现组合环、无时钟或无效约束。

### 8.3 资源占用

```text
LUT：16551 / 19600，84.44%
BRAM：20 / 64，31.25%
DSP：7 / 29，24.14%
Mslice：4420 / 4900，90.20%
Lslice：4464 / 4900，91.10%
PLB：2432 / 2450，99.27%
```

资源仍然可以在 EG4S20BG256 内完成布局布线，但 PLB 和 slice
余量已经不大。后续如果要继续增加音频可视化、播放列表或更大缓存，
需要先重新评估资源。

## 九、上板验证步骤

1. 按第三节把 `VinylFPGA/tf_card_stage/` 中的五份文件复制到 FAT32
   TF 卡根目录，确认根目录包含四张 BMP 和 `AUDIO.PCM`。
2. 烧录 `prj/VinylFPGA_lecture11_wav_timingfix2.bit`。
3. 上电后观察数码管从 `4` 变化到 `1`，然后显示第一张图片。
4. 图片预加载完成后，HDMI 应输出 `AUDIO.PCM` 的声音。
5. WAV 播放结束后，如果短时间回到原琶音音源，这是正常行为。
6. 按 KEY1，确认图片切换、转场特效和切图提示音都正常。
7. 短按 KEY2，确认自动轮播开启和关闭。
8. 长按 KEY2，确认切换到上一张图片。
9. 等待 3 秒，确认自动轮播周期仍然生效。

如果 TF 卡中没有 `AUDIO.PCM`：

```text
图片、KEY1、KEY2、自动轮播和切图提示音仍应正常；
音频链回到原 pcm_media_tone 琶音；
不会因为缺少音频文件而黑屏或卡死。
```

## 十、常见问题排查

| 现象 | 优先检查 |
|---|---|
| 完全没有 WAV 声音 | `AUDIO.PCM` 是否在根目录、是否 8.3 文件名、TF 卡是否 FAT32 |
| 有琶音但没有 WAV | `audio_file_valid` 是否为 1，`AUDIO.PCM` 文件大小是否非 0 |
| WAV 声音是噪声 | 是否 16 bit signed little-endian、是否 48 kHz 单声道 |
| WAV 中途卡顿或爆音 | `AUDIO.PCM` 是否碎片化，TF 卡读取速度是否足够 |
| WAV 与图片切换互相影响 | 确认构建使用的是 `timingfix2.bit`，并确认 `.al` 中 46~55 号源文件齐全 |
| 图片不显示或按键失效 | 检查 `.al` 中第十讲显示模块 46~50 是否被误删，重跑本讲构建 |
| 自动轮播不启动 | 确认 WAV 播放没有长期占用 SD 总线，确认四张图片预加载完成 |
| 上电黑屏 | 先按第五讲和第六讲的黑屏排查流程检查 SD 初始化、复位和图片目录 |

## 十一、本讲结论

本讲完成了从固定琶音到 TF 卡 PCM 流式播放的移植，同时保留了
第二讲到第十讲的图片切换、自动轮播、切图音效、HDMI 音频、四 bank
帧缓存、OSD 和转场特效。

新增音频链路与原有媒体链路的耦合点只有三个：

```text
1. 共享 SD 扇区接口，按扇区仲裁。
2. WAV 在图片预加载完成后启动。
3. WAV 与琶音通过 audio_source_mux 二选一。
```

因此本讲没有改动 HDMI 加密核、PLL、SDRAM 控制器、TMDS 输出和
管脚约束。下一步只需要准备 TF 卡并上板验证。
