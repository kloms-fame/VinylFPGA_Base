# 第六讲 第5课：Flash固化与上电自启 —— VinylFPGA 工程移植教程

> 参照教程：`FPGA创新设计赛道安路赛项（完赛系列）/第六讲：Flash固化与上电自启/第5课_Flash固化与上电自启.md`
> 参照代码：`第六讲：Flash固化与上电自启/第5课_Flash固化与复位/`
> 移植对象：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`
> 移植前基线：`ba7771d 修复上电黑屏与按键失效：SD超时改为按扇区计时，加固坏图快跳越界`
> 本讲最终位流：`prj/VinylFPGA_lecture6_flash_v2.bit`

---

## 一、目标与边界

### 1.1 本讲目标

第六讲解决的是“工程已经能跑，但上电顺序和复位释放不够可靠”的问题。官方例程和此前工程存在以下隐患：

1. 外部复位异步释放，释放沿与各时钟沿竞争，可能产生 recovery/removal 违例。
2. 两个 PLL 的 `reset` 原本固定接 `1'b0`，复位按键不能真正复位 PLL。
3. PLL 还没有锁定，业务模块就可能退出复位。
4. TF 卡扫描没有等待 SDRAM 初始化完成，首图写入可能撞上 SDRAM 初始化。
5. 复位同步器缺失时，不同时钟域可能在不同的时钟沿退出复位。
6. Flash 固化与长稳测试没有形成完整的操作和验收流程。

本讲严格采用教程的“最小改动”方案，并针对当前工程的实际双 PLL 架构做了必要适配：

| 优化项 | 类型 | 本工程落点 |
|---|---|---|
| 复位同步器 | 必做 | 新增 `reset_sync.v`，三个实际时钟域各一个实例 |
| PLL 锁定参与复位 | 必做 | `sys_pll`、`video_pll` 引出 `locked`，并接入复位源 |
| SDRAM 初始化后就绪 | 必做 | `sync_2ff.v` 同步 `Sdr_init_done`，`sd_card_bmp` 等待该信号 |
| 时序约束完善 | 选做 | 增加复位、同步器、HDMI ODDR、SDRAM 移位时钟约束 |
| Flash 固化与长稳测试 | 必做 | 生成位流后按本文章节烧写并验收 |

### 1.2 本工程与教程参考工程的差异

教程参考工程最终收敛为单 PLL，但本工程目前是已经验证可用的双 PLL：

- `sys_pll`：输出 `sd_card_clk`、`ext_mem_clk`、`ext_mem_clk_sft`
- `video_pll`：输出 `video_clk`、`hdmi_5x_clk`
- 第3课起音频复用 `video_clk`，本工程没有 `audio_mclk`，也没有独立音频 PLL

因此本次没有照搬教程里的 `audio_pll_lock`、`audio_mclk`、`u_audio_reset`，而是按实际时钟域实现：

```verilog
assign ext_rst_n = rst_n & sys_pll_lock & video_pll_lock;
```

这是本讲最重要的工程适配原则。不能为了“逐字一致”而虚构一个不存在的音频 PLL。

### 1.3 不可修改清单

以下内容属于当前工程的高危或已验证链路，本讲没有改动：

- HDMI 1.4b 加密发射核
- HDMI PHY 和 TMDS 串化链路
- SDRAM 加密核 `src/include/*.enc.v`
- 视频时序、视频数据通路、双缓冲显示链路
- 第四讲修好的 `write_req_ack` 两级同步逻辑
- KEY1/KEY2 长短按语义、自动轮播 3 秒、数码管图号显示
- HDMI 音频和切图音效

---

## 二、代码移植

### 2.1 新增 `src/reset_sync.v`

本模块实现“异步复位、同步释放”。复位按下时立即生效，复位释放时经过两个本域时钟沿才生效。

```verilog
`timescale 1ns / 1ps
module reset_sync (
    input  wire clk,
    input  wire ext_rst_n,
    output wire rst_n_sync
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= 1'b1;
            s2 <= s1;
        end
    end

    assign rst_n_sync = s2;

endmodule
```

### 2.2 新增 `src/sync_2ff.v`

`Sdr_init_done` 位于 `ext_mem_clk` 域，`sd_card_bmp` 位于 `sd_card_clk` 域。虽然两个时钟同源，仍按教程的严谨方案做两级同步。

```verilog
`timescale 1ns / 1ps
module sync_2ff #(
    parameter RESET_VAL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= RESET_VAL;
            s2 <= RESET_VAL;
        end else begin
            s1 <= async_in;
            s2 <= s1;
        end
    end

    assign sync_out = s2;

endmodule
```

### 2.3 修改 `top_tf_hdmi_audio.v`

#### 2.3.1 复位源与复位同步器

原来的 `rst_all = ~rst_n` 已替换为两个 PLL 锁定与外部复位共同控制，并为三个实际时钟域分别同步释放。

```verilog
wire sys_pll_lock;
wire video_pll_lock;
wire ext_rst_n;
wire sdcard_rst_n;
wire mem_rst_n;
wire video_rst_n;
wire Sdr_init_done_sd;

assign ext_rst_n = rst_n & sys_pll_lock & video_pll_lock;

reset_sync u_sdcard_reset (
    .clk        (sd_card_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (sdcard_rst_n)
);

reset_sync u_mem_reset (
    .clk        (ext_mem_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (mem_rst_n)
);

reset_sync u_video_reset (
    .clk        (video_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (video_rst_n)
);

sync_2ff u_sdram_init_sync (
    .clk        (sd_card_clk),
    .rst_n      (sdcard_rst_n),
    .async_in   (Sdr_init_done),
    .sync_out   (Sdr_init_done_sd)
);
```

#### 2.3.2 PLL 复位与锁定

两个 PLL 的复位端口都改为由外部复位控制，同时引出 `locked`。

```verilog
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (~rst_n),
    .locked     (sys_pll_lock)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (~rst_n),
    .locked     (video_pll_lock)
);
```

对应修改 `src/IP/sys_pll.v` 和 `src/IP/video_pll.v`：

```verilog
output locked;

.extlock(locked)
```

#### 2.3.3 子模块复位按域连接

当前工程的子模块多为高有效 `rst`，所以低有效同步复位需要取反：

```verilog
// sd_card_clk 域
sd_card_bmp_m0.rst              (~sdcard_rst_n);
sd_card_write_req_ack_sync      (negedge sdcard_rst_n);

// ext_mem_clk 域
frame_write_toggle_mem          (negedge mem_rst_n);
frame_read_write_m0.rst         (~mem_rst_n);
sdram U3.Rst                    (~mem_rst_n);

// video_clk 域
video_timing_data_m0.rst        (~video_rst_n);
video_delay_m0.rst              (~video_rst_n);
audio_arc_calculate.I_rst       (~video_rst_n);
video_rgb_to_axis.I_rst         (~video_rst_n);
startup_pulse.I_rst             (~video_rst_n);
hdmi_1_4b_transmitter.I_rst     (~video_rst_n);
hdmi_phy_wrapper.I_rst          (~video_rst_n);

// 已经是低有效复位的模块直接接同步复位
hdmi_pcm_audio_bridge.rst_n     (video_rst_n);
```

`seg_scan` 仍运行在 50MHz 板级 `clk` 域，本讲按最小改动保留 `.rst_n(rst_n)`。它只负责数码管扫描，不参与图片存储或 HDMI 主链路。

### 2.4 修改 `src/SD/sd_card_bmp.v`

新增一个已经同步到本时钟域的 SDRAM 就绪输入：

```verilog
input sdr_init_done,
```

上电扫描条件由：

```verilog
if (!scan_kicked && bmp_ready) begin
```

改为：

```verilog
if (!scan_kicked && bmp_ready && sdr_init_done) begin
```

这样启动顺序变为：

```text
外部复位释放
  -> sys_pll/video_pll 锁定
  -> 三个时钟域同步释放复位
  -> ext_mem_clk 域 SDRAM 初始化
  -> Sdr_init_done 同步到 sd_card_clk 域
  -> TF 卡扫描
  -> 首图写入 SDRAM
  -> 双缓冲提交并显示
```

### 2.5 修改 `prj/VinylFPGA.al`

工程文件已把新增源码加入编译列表：

```xml
<File Path="../src/reset_sync.v">
    <FileInfo>
        <Attr Name="UsedInSyn" Val="true"/>
        <Attr Name="UsedInP&R" Val="true"/>
        <Attr Name="BelongTo" Val="design_1"/>
        <Attr Name="CompileOrder" Val="40"/>
    </FileInfo>
</File>
<File Path="../src/sync_2ff.v">
    <FileInfo>
        <Attr Name="UsedInSyn" Val="true"/>
        <Attr Name="UsedInP&R" Val="true"/>
        <Attr Name="BelongTo" Val="design_1"/>
        <Attr Name="CompileOrder" Val="41"/>
    </FileInfo>
</File>
```

### 2.6 修改 `constraints/timing.sdc`

本工程在原有约束末尾增加了第六讲约束：

```tcl
# 复位信号异步进入各时钟域，由 reset_sync 做同步释放。
set_false_path -from [get_ports {rst_n}]

# reset_sync / sync_2ff 的第一级均为异步采样寄存器。
set_false_path -to [get_regs -hier {*/s1}]

# HDMI TMDS ODDR 输出路径的数字延迟上限。
set_max_delay -from [get_clocks {hdmi_5x_clk}] \
    -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}] \
    8.000 -datapath_only

# SDRAM 移位采样时钟属于硬 IP 的 I/O 窗口，不做 fabric 跨时钟分析。
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]
```

同时补上了 `ext_mem_clk_sft` 的命名，保证 false_path 可以引用实际时钟：

```tcl
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
```

教程中的 `set_clock_uncertainty -hold 0.050` 本次没有保留。原因是 TD 6.2.168116 会把显式 `0.050ns` 与默认 `0.100ns` 相加，实际形成 `0.150ns`，新增了视频域保持和 removal 违例。该条属于教程选做项，本工程按“不破坏已验证稳定链路”的原则停用。

---

## 三、验证记录

### 3.1 本机仿真

第五讲稳定性回归：

```text
PASS: valid scan finds sector 0
PASS: valid scan reports one image
PASS: valid load has no error
PASS: valid load writes 8 pixels
PASS: bad DIB reports ERR_HEADER
PASS: bad planes reports ERR_HEADER
PASS: short file_len reports ERR_HEADER
PASS: pixel stream reports ERR_TRUNCATED
PASS: BMP fast-skip lands on sector 2
PASS: fast-skip finds the valid image
PASS: missing SD response reports ERR_TIMEOUT
PASS: scan timeout reports ERR_TIMEOUT
PASS: long scan is not falsely timed out
PASS: bmp_read stability tests completed
```

HDMI 音频回归：

```text
PASS: 48kHz PCM count=4800, amplitude/error checks clean, blip active
```

### 3.2 TD 全流程

SynthPilot 使用以下参数完成真实 TD 构建：

```text
工程：D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al
器件：eagle_s20.db / EG4S20BG256
顶层：top
SDC ：constraints/timing.sdc
ADC ：constraints/pin.adc
终点：bitgen
```

构建结果：

```text
BUILD SUCCEEDED through bitgen
elaborate            成功
read_adc             成功
read_sdc             成功
optimize_rtl         成功
optimize_gate        成功
place                成功
route                成功
update_timing        成功
bitgen               成功
```

最终位流：

```text
D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA_lecture6_flash_v2.bit
```

### 3.3 最终时序摘要

```text
SWNS: -0.056ns
HWNS:  0.003ns
Period Check WNS: 0.000ns

video_clk      : SWNS +5.659ns, HWNS +0.003ns
sd_card_clk    : SWNS +0.130ns, HWNS +0.037ns
ext_mem_clk    : SWNS -0.056ns, HWNS +0.012ns
hdmi_5x_clk    : SWNS +5.157ns, HWNS +0.239ns
clk            : SWNS +7.273ns, HWNS +0.031ns
ext_mem_clk_sft: 无 fabric 建立/保持违例
```

说明：

- 视频域、SD 卡域、HDMI 串行域和 50MHz 域均没有建立/保持违例。
- `ext_mem_clk` 剩余的 `-0.056ns` 位于 `frame_read_write` 内部异步 FIFO 的 `rdusedw -> into_burst` 同域组合路径，不是本次新增的跨时钟违例。
- 第五讲之前该存储器域曾出现 `-6.565ns` 级别的遗留违例，本次结果已收敛到 56ps；未改动 SDRAM 加密核和 FIFO 数据通路，避免引入新的上板风险。
- `td_check_timing` 的约束检查结果为：0 条无效约束、0 个组合环路、0 个无路径约束。

---

## 四、Flash 固化与上电自启

### 4.1 TD 操作步骤

1. 在 TD 中打开 `prj/VinylFPGA.al`，运行综合、布局布线并生成 `.bit`。
2. 连接安路下载器，给开发板上电。
3. 打开 `Tools -> Download`，选择下载器并执行 `Auto Detect`，确认识别到 `EG4S20`。
4. 在器件上右键选择 `Edit`，选择最终位流 `VinylFPGA_lecture6_flash_v2.bit`。
5. 在 `External Flash` 中选择开发板实际 Flash，当前板卡为 `W25Q64`。
6. 勾选 `Program/Configure` 和 `Verify`，点击 `Start`。
7. 烧写完成后断电，拔掉下载器，再重新上电。
8. 确认 HDMI 自动显示图片、音频正常、KEY1/KEY2 正常、数码管编号正常。

### 4.2 上电验收

按第六讲教程的启动顺序检查：

| 检查项 | 预期现象 |
|---|---|
| PLL 锁定前 | 系统保持复位，不抢跑 |
| PLL 锁定后 | 三个时钟域同步释放 |
| SDRAM 初始化阶段 | TF 卡不提前扫描 |
| SDRAM 初始化完成 | 开始扫描 TF 卡 |
| 首图写入完成 | HDMI 显示首张图片 |
| 数码管 | 显示当前图片编号 |
| KEY1 | 短按切换下一张 |
| KEY2 | 短按开关自动轮播，长按切换上一张 |
| 音频 | HDMI 音频和切图音效正常 |

### 4.3 长稳测试

上板后按以下标准测试：

1. 自动轮播连续运行 30 到 60 分钟，无黑屏、无花屏、无卡死。
2. 快速按 KEY1 100 次，每次切换正常，无漏切和错切。
3. KEY2 短按和长按各测试 20 次，自动轮播开关和上一张功能正常。
4. 连续断电重启 10 次，每次都能自动加载并显示图片。
5. 系统运行 1 小时后触摸 FPGA 和 SDRAM 芯片，温度应正常。

---

## 五、回退方法

如果第六讲位流上板异常，可先回退到第五讲已验证位流：

```text
prj/VinylFPGA_stability_v3.bit
```

如果怀疑源码回退，可将本讲改动恢复到移植前基线：

```text
git checkout ba7771d -- src/top_tf_hdmi_audio.v src/SD/sd_card_bmp.v src/IP/sys_pll.v src/IP/video_pll.v prj/VinylFPGA.al constraints/timing.sdc
```

新增文件 `src/reset_sync.v` 和 `src/sync_2ff.v` 可以保留，因为它们不参与回退后的顶层连接。不要用 `git reset --hard` 或整体覆盖工作区，以免影响用户已有改动。

---

## 六、本讲改动文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `src/reset_sync.v` | 新增 | 异步复位、同步释放 |
| `src/sync_2ff.v` | 新增 | 单比特两级同步 |
| `src/top_tf_hdmi_audio.v` | 修改 | PLL 锁定复位、域复位、SDRAM 就绪同步 |
| `src/SD/sd_card_bmp.v` | 修改 | 增加 SDRAM 就绪启动条件 |
| `src/IP/sys_pll.v` | 修改 | 引出 `locked` |
| `src/IP/video_pll.v` | 修改 | 引出 `locked` |
| `prj/VinylFPGA.al` | 修改 | 加入新增源码 |
| `constraints/timing.sdc` | 修改 | 第六讲 false_path、max_delay 和时钟命名 |
| `doc/第六讲_Flash固化与上电自启移植教程.md` | 新增 | 本文件 |
