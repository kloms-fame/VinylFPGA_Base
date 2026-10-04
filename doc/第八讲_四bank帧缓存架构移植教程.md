# 第八讲 四bank帧缓存架构移植教程

## 一、本讲目标

本讲对应完赛系列：

```text
第八讲：四bank帧缓存架构
```

移植目标是让四张 BMP 图片分别常驻 SDRAM 的四个固定 bank：

```text
Bank0 -> PIC1.BMP
Bank1 -> PIC2.BMP
Bank2 -> PIC3.BMP
Bank3 -> PIC4.BMP
```

切换图片时只修改读地址索引 `disp_buf_idx`，不再为了普通切换重新读取 TF 卡。

本讲保留以下既有功能：

```text
KEY1 短按下一张
KEY2 短按自动轮播开关
KEY2 长按上一张
自动轮播
切图音效
HDMI 音频
FAT32 文件系统扫描
Flash 上电自启接口
```

## 二、移植原则

当前工程已经完成第七讲的 FAT32 加载链路，并且现有 `frame_read_write` 已经具备：

```text
4 组读写基地址接口
write_addr_index/read_addr_index
异步 FIFO
128 字突发写
垂直翻转写地址
SDRAM 控制器接口
```

因此本讲采用“小范围扩展 bank 调度”的方式，而不是全量替换成参考工程的
`media_frame_loader/media_frame_reader/media_player_control`。

这样做的原因是：

1. 当前 FAT32、按键、音效、HDMI 音频和 Flash 启动功能已经验证可用；
2. SDRAM 控制器、HDMI 发射器和 PLL 都是高风险链路；
3. 现有 `frame_read_write` 已经具备四组基地址，不需要为了接入四个 bank
   重写跨时钟域 FIFO 和视频读链路；
4. 采用最小改动可以同时获得四 bank 常驻和低回归风险；
5. 本讲没有修改任何加密 IP、引脚约束和视频时序参数。

## 三、顶层改动

文件：

```text
src/top_tf_hdmi_audio.v
```

### 3.1 新增 Bank2/Bank3 基地址

```verilog
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 24'd2;
parameter BUF3_ADDR     = FRAME_PIXELS * 24'd3;
```

地址映射：

```text
Bank0 = 0
Bank1 = 307200
Bank2 = 614400
Bank3 = 921600
```

每张图片 640×480=307200 个 32 位字。

### 3.2 写端口四个 Bank

```verilog
.write_addr_0      (BUF0_ADDR),
.write_addr_1      (BUF1_ADDR),
.write_addr_2      (BUF2_ADDR),
.write_addr_3      (BUF3_ADDR),
.write_addr_index  (write_buf_idx),
```

### 3.3 读端口四个 Bank

```verilog
.read_addr_0       (BUF0_ADDR),
.read_addr_1       (BUF1_ADDR),
.read_addr_2       (BUF2_ADDR),
.read_addr_3       (BUF3_ADDR),
.read_addr_index   (disp_buf_idx),
```

`write_buf_idx` 和 `disp_buf_idx` 都是 2 位，分别选择当前写入 bank 和当前显示 bank。

## 四、四 Bank 调度改动

文件：

```text
src/SD/sd_card_bmp.v
```

### 4.1 新增状态

```verilog
reg [2:0] preload_idx;      // 后台预加载顺序：0~3，4 表示全部处理完
reg [3:0] image_ready;      // bit n 表示 PIC(n+1) 已加载到 Bank n
reg       load_is_preload;  // 当前加载是否由后台预加载发起
reg       load_for_display; // 当前加载完成后是否切换显示
```

`image_ready[3:0]` 是四 bank 调度能否零延迟切换的核心标记。

### 4.2 预加载与显示切换

扫描完成后：

1. `preload_idx=0`，先加载 Bank0；
2. Bank0 写完成且此前没有画面时，立即提交显示；
3. 后台继续顺序加载 Bank1、Bank2、Bank3；
4. 后续普通切换只在已加载 bank 之间修改索引；
5. 只有目标 bank 尚未准备好时，才重新发起 FAT32 读取。

核心代码：

```verilog
if (ready_lut(next_from_current)) begin
    img_idx      <= next_from_current;
    disp_buf_idx <= next_from_current;
end else if (bmp_ready) begin
    load_idx         <= next_from_current;
    load_index       <= next_from_current;
    write_buf_idx    <= next_from_current;
    load_start_pulse <= 1'b1;
    load_busy        <= 1'b1;
    load_is_preload  <= 1'b0;
    load_for_display <= 1'b1;
end
```

写完成提交：

```verilog
image_ready[load_idx] <= 1'b1;

if (!display_valid || load_for_display) begin
    img_idx       <= load_idx;
    disp_buf_idx  <= load_idx;
    display_valid <= 1'b1;
end
```

### 4.3 保持按键和轮播优先级

调度优先级保持如下：

```text
1. KEY1 下一张
2. KEY2 长按上一张
3. 自动轮播
4. 后台四 bank 预加载
```

手动操作优先于后台预加载，因此不会出现后台加载占住总线后按键没有反应的问题。

KEY2 短按只切换 `auto_play_en`，不会清空已经加载的 bank。

## 五、时序修复

文件：

```text
src/SD/frame_fifo_write.v
```

第八讲第一次完整布线后出现：

```text
ext_mem_clk -> ext_mem_clk
Setup WNS = -0.013ns
Setup TNS = -0.013ns
违规端点 = 1
```

违例路径为：

```text
frame_read_write_m0/write_buf/rd_addr_reg
  -> frame_fifo_write_m0/App_wr_en_r
```

原因是异步 FIFO 的 `rdusedw` 直接参与 21 位加法和比较，在 125 MHz 下差
0.013 ns 收敛。

本讲只给突发判定水位增加一级寄存器：

```verilog
reg [9:0] rdusedw_r;

always @(posedge mem_clk or posedge rst) begin
    if (rst)
        rdusedw_r <= 10'd0;
    else
        rdusedw_r <= rdusedw;
end

assign into_burst =
    (((write_len_latch <= (rdusedw_r + write_cnt)) ||
      rdusedw_r > BURST_SIZE) && ~App_rd_busy);
```

该修改只可能让“启动突发”最多晚一拍，FIFO 数据不会被丢弃，写地址、突发长度、
四个 bank 基地址和 SDRAM 接口均未改变。

## 六、仿真验证

### 6.1 四 bank 调度仿真

文件：

```text
sim/tb_sd_card_bmp_fourbank.v
```

覆盖内容：

```text
Bank0 -> Bank1 -> Bank2 -> Bank3 预加载顺序
首图加载完成后立即显示
KEY1 已加载 bank 零重新加载切换
KEY2 长按返回上一张
KEY2 短按打开自动轮播
自动轮播只切 bank 索引，不重新读卡
```

运行：

```powershell
D:\iverilog\bin\iverilog.exe -g2012 -Wall `
  -o sim\tb_sd_card_bmp_fourbank.vvp `
  src\SD\sd_card_bmp.v `
  sim\tb_sd_card_bmp_fourbank.v

D:\iverilog\bin\vvp.exe sim\tb_sd_card_bmp_fourbank.vvp
```

通过结果：

```text
PASS: four-bank scheduler preload/switch/long-press/auto
```

### 6.2 写突发回归

文件：

```text
sim/tb_frame_fifo_write.v
```

覆盖内容：

```text
水位达到阈值后启动一次 128 字突发
写地址连续递增
最终产生 write_finish
```

运行：

```powershell
D:\iverilog\bin\iverilog.exe -g2012 -Wall `
  -o sim\tb_frame_fifo_write.vvp `
  src\SD\frame_fifo_write.v `
  sim\tb_frame_fifo_write.v

D:\iverilog\bin\vvp.exe sim\tb_frame_fifo_write.vvp
```

通过结果：

```text
PASS: frame_fifo_write registered-level burst
```

### 6.3 既有回归

第八讲执行后仍保留以下通过项：

```text
PASS: sd sector adapter
PASS: FAT32 volume scanner
PASS: FAT32 fragmented FAT chain
PASS: FAT32 media loader scan/load/pixel pipeline
PASS: 48kHz PCM count=4800, amplitude/error checks clean, blip active
```

## 七、安路 TD 构建结果

工程：

```text
prj/VinylFPGA.al
```

器件：

```text
EG4S20BG256
```

顶层：

```text
top
```

约束：

```text
constraints/timing.sdc
constraints/pin.adc
```

完整流程：

```text
import_device
open_project
elaborate
read_adc
read_sdc
optimize_rtl
optimize_gate
legalize_phy_inst
read_sdc_post_gate
place
route
update_timing
bitgen
```

最终布线后时序：

```text
Slow corner: SWNS +0.103ns, STNS 0.000ns
Fast corner: HWNS +0.003ns, HTNS 0.000ns

ext_mem_clk: SWNS +0.549ns, HWNS +0.011ns, Fmax 134.210MHz
sd_card_clk: SWNS +0.103ns, HWNS +0.105ns, Fmax 101.041MHz
video_clk:  SWNS +28.984ns, HWNS +0.003ns
```

所有时钟域均无负裕量端点。

资源占用：

```text
mslice: 1902 / 4900   38.82%
lslice: 1906 / 4900   38.90%
LUT:    5932 / 19600  30.27%
REG:    4692 / 19600  23.94%
BRAM:   20 / 64       31.25%
DSP:    2 / 29         6.90%
PLL:    2 / 4         50.00%
```

## 八、最终位流

文件：

```text
D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\prj\VinylFPGA_lecture8_fourbank_final.bit
```

SHA256：

```text
65F8A025567C0C30068AB1AFE14934F649F26696FFAC0778D9EDF55231619FF4
```

计算哈希：

```powershell
Get-FileHash -Algorithm SHA256 `
  'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\prj\VinylFPGA_lecture8_fourbank_final.bit'
```

注意：

1. 最终位流包含第八讲四 bank 调度和时序修复；
2. 如果使用 Flash 上电自启，必须重新固化本讲位流；
3. 老的第七讲位流不包含本讲 bank 调度，不能用于验证四 bank 功能。

## 九、上板验证

### 9.1 TF 卡准备

1. TF 卡必须为 FAT32；
2. 图片放在根目录；
3. 文件名必须是：

```text
PIC1.BMP
PIC2.BMP
PIC3.BMP
PIC4.BMP
```

4. 每张图片必须是 640×480、24 位、无压缩 BMP；
5. 不能使用索引色 BMP 或带压缩的 BMP。

### 9.2 上电流程

1. 烧录 `VinylFPGA_lecture8_fourbank_final.bit`；
2. 上电后先等待首图加载完成；
3. 首图显示后，后台继续预加载剩余三个 bank；
4. 数码管应显示当前图片编号 1~4；
5. HDMI 应显示当前图片；
6. 按下 KEY1，切换到下一张，并播放切图音效；
7. KEY2 短按打开自动轮播，每 3 秒切换一次；
8. KEY2 长按约 1 秒返回上一张。

### 9.3 Flash 固化

如果板卡已经做过第六讲 Flash 固化，请用第八讲最终位流重新执行一次固化流程。
只烧录 SRAM 不更新 Flash，断电重启后仍然运行旧位流。

## 十、禁止改动的部分

本讲没有改动以下高风险模块，后续开发也不应为了四 bank 功能修改它们：

```text
HDMI 1.4b 加密发射核
SDRAM 加密核及初始化核
HDMI PHY/TMDS
DDC/EDID
顶层端口和引脚约束
PLL 时钟树
640×480 视频时序参数
HDMI 音频链路
```

## 十一、常见现象判断

### 只显示第一张，按键无反应

优先检查：

```text
PIC1~PIC4 文件名是否完全一致
TF 卡是否为 FAT32
BMP 是否为 640×480、24 位、无压缩
重新扫描是否完成
第八讲位流是否真正下载到 FPGA/Flash
```

### 能显示图片但没有切图音效

优先检查：

```text
KEY1/KEY2 是否有效触发
state_code 是否随图片编号变化
audio 链路是否使用了当前位流
```

### 上电后黑屏

优先检查：

```text
SDRAM 初始化是否完成
FAT32 扫描是否成功
首图提交前是否被 display_valid 拉成黑屏
TF 卡是否插稳
```

## 十二、结论

第八讲完成后，工程具备：

```text
四 bank 固定图片映射
首图完成后立即显示
后台顺序预加载
已加载 bank 零重新读卡切换
KEY1/KEY2/长按/自动轮播兼容
切图音效兼容
FAT32/Flash/HDMI 音频兼容
布线后所有时钟域正裕量
```

最终上板必须使用本讲重新生成的位流，并在需要断电自启时重新固化 Flash。
