# 第九讲 OSD字幕叠加移植教程

> 本讲最终位流：`prj/VinylFPGA_lecture9_osd_final.bit`

> SHA256：`6D889AD1F1C3146C39D8610ED0CD14F4D3BE3CEE77E55CA10C3647F414C16323`

## 一、本讲目标

本讲对应完赛系列：

```text
第九讲：OSD字幕叠加
```

在现有 HDMI 视频链路上增加状态 OSD，屏幕左上角显示四个字符：

```text
图片编号  自动/手动  错误码高4位  错误码低4位
   1         A/E          0-9/A-F      0-9/A-F
```

例如：

```text
1E00    图片1、手动模式、无错误
3A44    图片3、自动模式、错误码44
```

颜色规则：

```text
error_code == 0    黄色
error_code != 0    红色
```

教程正文里有一处把 `12'hff0` 写成“绿色”，但源码和实际颜色值是：

```text
12'hff0    R=F, G=F, B=0    黄色
12'hf44    R=F, G=4, B=4    红色
```

本讲保留以下既有功能：

```text
KEY1 短按下一张
KEY2 短按自动轮播开关
KEY2 长按上一张
自动轮播
切图音效
HDMI 音频
FAT32 文件系统扫描
四 bank 帧缓存
Flash 上电自启接口
```

## 二、移植原则

现有工程的视频链路已经验证可用。本讲不在主链路里重写视频时序，也不碰
SDRAM、HDMI 发射器、HDMI PHY、DDC/EDID、PLL 和引脚约束。

新增 OSD 的位置是：

```text
video_delay
  -> 首图提交前黑屏屏蔽
  -> osd_overlay_24
  -> video_rgb_to_axis_640x480
  -> HDMI 发射器
```

OSD 只替换像素颜色，不改变 `vs`、`de`、视频时钟和 AXIS 数据节拍。

## 三、新增文件

### 3.1 `src/display/status_osd_overlay.v`

作用：12 位 RGB 的 OSD 渲染核心。

主要接口：

```verilog
module status_osd_overlay #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [1:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  error_code,
    input  wire        in_de,
    input  wire [11:0] in_rgb,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    output reg  [11:0] out_rgb,
    output reg         out_de,
    output wire        osd_pixel
);
```

核心行为：

1. 5 乘 7 点阵字体，支持 `0-9`、`A`、`E`、`F`。
2. 四个字符占用 `32` 乘 `8` 像素，默认位置 `(8,8)`。
3. `frame_start` 锁存 `active_index/auto_enabled/error_code`，避免一帧内撕裂。
4. 区域外像素原样透传。
5. `error_code == 0` 显示黄色，有错误显示红色。

### 3.2 `src/display/osd_overlay_24.v`

作用：24 位 RGB 封装和行坐标重建。

主要接口：

```verilog
module osd_overlay_24 #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire [1:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  error_code,
    output wire [23:0] rgb_out,
    output wire        de_out,
    output wire        osd_active
);
```

行坐标重建沿用完赛教程：

```verilog
if (!vsync)
    line_y <= 12'd0;
else if (de_q && !de)
    line_y <= line_y + 1'b1;
```

24 位和 12 位颜色转换：

```verilog
.in_rgb({rgb_in[23:20], rgb_in[15:12], rgb_in[7:4]})
```

```verilog
assign rgb_out = osd_hit ?
    {osd_rgb12[11:8], osd_rgb12[11:8],
     osd_rgb12[7:4],  osd_rgb12[7:4],
     osd_rgb12[3:0],  osd_rgb12[3:0]} : rgb_in;
```

## 四、`sd_card_bmp` 只读状态输出

原工程已经在 `sd_card_bmp` 内部维护自动轮播和错误状态。为了不给轮播状态机
增加新逻辑，本讲只增加三个输出：

```verilog
output wire        auto_play_en_out,   // 自动轮播状态，A/E显示
output reg  [7:0]  osd_error_code,     // 错误码，0=正常
output reg         osd_error_toggle    // 跨时钟域捆绑数据更新标志
```

自动状态直接引出：

```verilog
assign auto_play_en_out = auto_play_en;
```

错误码只在既有 `load_error` 恢复路径里锁存：

```verilog
if (load_error && !load_error_seen) begin
    osd_error_code   <= {4'b0000, bmp_error};
    osd_error_toggle <= ~osd_error_toggle;
    // 原有稳定性恢复逻辑保持不变
end
```

下一次成功写完整帧后清除错误码，并再次翻转 toggle：

```verilog
if (osd_error_code != 8'd0) begin
    osd_error_code   <= 8'd0;
    osd_error_toggle <= ~osd_error_toggle;
end
```

这里没有修改 `key_next_press`、`key_auto_press`、`auto_play_en`、
`load_busy`、重试状态机和四 bank 切换仲裁。

## 五、顶层接线

文件：`src/top_tf_hdmi_audio.v`

### 5.1 保持原有黑屏屏蔽

```verilog
assign vout_data = display_valid ? vout_data_raw : 24'd0;
```

### 5.2 在像素时钟域重建 X 坐标

当前工程的 `video_timing_data` 没有输出横坐标。本讲不改视频时序模块，
而是在 OSD 输入前用已延迟对齐的 `de` 重建 X 坐标：

```verilog
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        osd_pixel_x <= 10'd0;
    else if (!de)
        osd_pixel_x <= 10'd0;
    else
        osd_pixel_x <= osd_pixel_x + 10'd1;
end
```

这与 `video_rgb_to_axis_640x480` 的行内计数方式一致。

### 5.3 插入 OSD

```verilog
osd_overlay_24 #(
    .OSD_X(8),
    .OSD_Y(8)
) u_osd_overlay_24 (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (vs),
    .de           (de),
    .rgb_in       (vout_data),
    .pixel_x      (osd_pixel_x),
    .active_index (media_id),
    .auto_enabled (auto_enabled_sync2),
    .error_code   (osd_error_code_frame),
    .rgb_out      (osd_rgb_out),
    .de_out       (osd_de_out),
    .osd_active   (osd_active)
);
```

最终把 `video_rgb_to_axis_640x480.I_rgb` 从 `vout_data` 改为
`osd_rgb_out`。

## 六、状态跨时钟域处理

`sd_card_clk` 是 100 MHz，`video_clk` 是 25 MHz。图片编号继续使用原来的
两级同步。本讲额外同步：

```text
auto_play_en_out     单 bit，两级同步
osd_error_code       8 bit，使用 toggle 作为捆绑数据更新标志
osd_error_toggle     单 bit，两级同步
```

错误码更新流程：

```text
sd_card_clk 域更新 error_code 和 toggle
  -> video_clk 域两级同步 toggle
  -> 检测 toggle 变化并置 pending
  -> 下一拍再提交 error_code_sync2
  -> status_osd_overlay 在 frame_start 锁存
```

这样避免多位错误码在同一拍跨域时被视频域采到中间值。

## 七、仿真验证

新增：

```text
sim/tb_osd_overlay.v
```

编译和运行：

```powershell
D:\iverilog\bin\iverilog.exe -g2012 -Wall `
  -o sim\tb_osd_overlay.vvp `
  src\display\osd_overlay_24.v `
  src\display\status_osd_overlay.v `
  sim\tb_osd_overlay.v

D:\iverilog\bin\vvp.exe sim\tb_osd_overlay.vvp
```

验证覆盖：

```text
OSD区域外像素原样透传
图片1 + 手动E + 错误码00 -> 黄色
图片3 + 自动A + 错误码44 -> 红色
字符间距不误点亮
消隐期不叠加
```

实际结果：

```text
PASS: tb_osd_overlay all checks passed
```

四 bank 回归仿真也保持通过：

```text
PASS: four-bank scheduler preload/switch/long-press/auto
```

## 八、TD 全流程

工程参数：

```text
AL:        D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\prj\VinylFPGA.al
ADC:       D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\constraints\pin.adc
SDC:       D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\constraints\timing.sdc
DEVICE DB: eagle_s20.db
PACKAGE:   EG4S20BG256
TOP:       top
END STEP:  bitgen
```

构建结果：

```text
elaborate        成功
optimize_rtl      成功
optimize_gate     成功
place             成功
route             成功
update_timing     成功
bitgen            成功
```

## 九、时序和资源结果

最终布线后时序：

```text
Slow: SWNS = +0.052ns, STNS = 0.000ns
Fast: HWNS = +0.011ns, HTNS = 0.000ns
0 个 setup/hold 违例端点
```

主要时钟：

```text
video_clk        25.000 MHz
sd_card_clk     100.000 MHz
ext_mem_clk     125.000 MHz
hdmi_5x_clk     125.000 MHz
clk              50.000 MHz
ext_mem_clk_sft 125.000 MHz
```

布线后 QoR：

```text
Setup WNS       52 ps
Setup TNS        0
Hold WNS        11 ps
Hold TNS         0
违例端点         0
```

资源占用：

```text
LUT     6109 / 19600    31.17%
REG     4735 / 19600    24.16%
BRAM      20 / 64       31.25%
DSP        2 / 29        6.90%
PLL        2 / 4         50.00%
```

## 十、上板验证步骤

1. 烧录：

```text
D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\prj\VinylFPGA_lecture9_osd_final.bit
```

2. 上电后确认左上角出现状态字符。

3. 正常无错误时，状态字符应为黄色，例如：

```text
1E00
```

4. KEY1 短按下一张，OSD 的图片编号应随显示图片更新。

5. KEY2 短按切换自动轮播，第二个字符应在 `A` 和 `E` 之间变化。

6. KEY2 长按回到上一张，图片编号应回退。

7. 自动轮播、切图音效和 HDMI 音频应保持原有行为。

8. 如果 TF 卡图片损坏导致加载错误，错误码区域应变为红色；下一次成功完整
   写入一帧后，错误码恢复为 `00`，颜色恢复黄色。

## 十一、Flash 固化提醒

第九讲位流增加了 OSD，如果板子使用 Flash 上电自启，必须把新的第九讲位流
重新固化到 Flash。只通过 JTAG 临时下载，断电重启后仍然会运行 Flash 里旧的
第八讲位流，不会显示本讲的 OSD。

## 十二、回退方法

软件回退到第八讲：

```text
D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\prj\VinylFPGA_lecture8_fourbank_final.bit
```

代码回退前请确认没有需要保留的本地改动。本讲新增文件为：

```text
src/display/osd_overlay_24.v
src/display/status_osd_overlay.v
sim/tb_osd_overlay.v
```

本讲修改文件为：

```text
src/top_tf_hdmi_audio.v
src/SD/sd_card_bmp.v
prj/VinylFPGA.al
```

## 十三、没有改动的部分

本讲没有修改：

```text
SDRAM 控制器和初始化 IP
HDMI 1.4b 加密发射核
HDMI PHY、TMDS、DDC、EDID
两个 PLL
顶层端口和引脚约束
640x480 视频时序参数
HDMI 音频链路
四 bank 帧缓存地址映射
KEY1/KEY2 原有调度状态机
```

## 十四、扩展内容说明

完赛配套目录还提供：

```text
promax_text_overlay.v
timestamp_osd.v
subtitle_uart_controller.v
subtitle_frame_commit.v
```

这些属于讲义中的扩展内容：Alpha 混合、滚动字幕、时间戳和 UART 文本下发。
本讲核心目标是状态 OSD，因此没有把扩展模块接入主链路，避免增加不必要的
资源和时序风险。需要继续做扩展要求时，应在当前状态 OSD 通过上板验证后再
单独接入。
