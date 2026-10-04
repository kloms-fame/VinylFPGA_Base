# 第四讲 第3课：HDMI 音频输出基础 —— VinylFPGA 工程移植教程

> 适用工程：`VinylFPGA`（TF 图片轮播 + 按键切换 + 数码管 + SDRAM 双缓冲 + HDMI 1.4b 加密发射核）
> 目标：按“完赛系列 第四讲 第3课_HDMI音频输出基础”完成音频移植，**消除杂音**，且不影响视频链路、按键、轮播、数码管、SDRAM 等既有功能。
> 参考代码：`.../第四讲：HDMI音频输出基础/第3课_HDMI音频基础/`（目录内共 14 个 `.v`；本次实际采用 `pcm_media_tone.v` 与 `m06_pcm_contract_adapter.v` 两个文件，已与参考文件逐字节比对一致）
> 实际落地目录：`VinylFPGA/src/audio/`
> 本次改动已经过 **Icarus Verilog 仿真 + 安路 TD 6.2.1 全流程（import_device → elaborate → read_adc → read_sdc → opt_rtl → opt_gate → legalize_phy_inst → place → route → update_timing → bitgen）** 验证通过。

---

## 一、问题定位：为什么之前有杂音

### 1.1 现状（移植前的真实状态）

移植前工程里**没有任何完赛系列的音频模块被综合**——`prj/VinylFPGA.al` 的源文件清单里
只有官方例程的那几个音频文件，完赛系列的 `pcm_media_tone.v` 等文件既不在工程里、也没有实例。

真正在工作的音频链路是**官方例程的方波链路**：

```
PLL_HDMI_AUDIO(12.288MHz) -> hdmi_audio_tone_i2s_64fs(方波) -> I2S -> I2S_receiver -> 加密HDMI核
```

### 1.2 杂音的根因

| 根因 | 说明 |
|---|---|
| **① 方波谐波** | `hdmi_audio_tone_i2s_64fs` 用相位累加器直接输出方波。方波含 3、5、7… 次奇次谐波，听感就是“嘀嘀”的刺耳电子音，中高频能量很强——这正是用户听到的“杂音”。 |
| **② 独立音频 PLL 耦合** | 原设计 `rst_all = ~rst_n \| ~audio_pll_lock`，音频 PLL 一旦失锁会把**整机（含视频）一起复位**，链路脆弱。 |
| **③ 幅值/削波** | 官方 `AMP = 24'sd2000000` 的方波峰值高、谐波多，更容易听成“破音”。 |

结论：**换掉音源（方波 → 正弦 DDS）才是治本**，同时把音频搬到像素时钟域，去掉独立音频 PLL。

---

## 二、架构决策：为什么不能照搬教程的 `hdmi_audio_symbol_core`

这是本次移植最关键、也最容易踩坑的地方，必须讲清楚。

### 2.1 两条技术路线

| | 路线 A（本工程） | 路线 B（教程完赛工程） |
|---|---|---|
| TMDS 编码 | 安路官方 **加密** HDMI 1.4b 核内部完成 | 自己用 `hdmi_tmds_channel_encoder` 做 |
| 音频包封装 | 加密核内部完成（接收 24bit PCM + valid + ACR） | 自己写 `hdmi_audio_symbol_core` 封装 |
| 顶层接口 | `I_audio_valid / I_audio_left_data / I_audio_right_data / I_acr_*` | `channel0/1/2_symbol` |
| 教程适配 | 教程 3.3 / 4.2 节描述的正是路线 B | — |

### 2.2 第1课的“不可修改清单”（原文摘录）

> \| 9 \| `sdram` \| SD/sdram.v + include/sdr_*.enc.v \| SDRAM控制器（**核心加密**） \| ❌ **绝对不能改** \|
> \| 10 \| `hdmi_1_4b_transmitter_core_wrapper` \| hdmi1.4b_transmitter_core/（加密） \| HDMI 1.4b发射器核心（**加密**） \| ❌ **绝对不能改** \|
> \| 11 \| `hdmi_phy_wrapper` \| hdmi_phy_warpper.v \| HDMI PHY层，ODDR串行化 \| ❌ 别动 \|
> \| 12 \| `hdmi_audio_tone_i2s_64fs` \| hdmi_audio_tone_i2s_64fs.v \| 1kHz测试音生成 \| ✅ **可改音调音量** \|

### 2.3 决策

本工程已经用了**加密 HDMI 核（路线 A）**，而教程 `media_hdmi_audio_bridge` 输出的 `channel0/1/2_symbol`
是给**路线 B**（自己生成 TMDS 裸符号）用的。如果硬把 symbol core 接到加密核的输出上，会和加密核
驱动的 TMDS 通道**直接打架**，视频、音频一起坏——这很可能就是之前“不能正常工作”的原因。

因此本次移植的做法是：**严格保留加密核、严格保留视频链路，只替换“音源”**，
把完赛工程真正有价值的部分移植过来：

1. 复用像素时钟（弃用 12.288MHz 音频 PLL）
2. 16 点正弦波 DDS（替代方波）
3. `media_id` 媒体音调联动（切图换调 + 1.5kHz 提示音）
4. `volume` 音量缩放
5. 保留 valid/ready 握手契约（`m06_pcm_contract_adapter`）

**不自己写音频包封装**（避免重复造轮子 + 高风险），音频采样包 / InfoFrame / ACR 依旧交给加密核。

### 2.4 移植后的音频数据流

```
video_clk(25MHz)
   |
   +-- media_id(来自 sd_card_clk 域, 两级同步)
   |
   v
hdmi_pcm_audio_bridge
   |  (48kHz 分数累加节拍)
   +--> pcm_media_tone        (16点正弦 DDS + 媒体琶音 + 提示音)
   |        |
   |        v
   +--> m06_pcm_contract_adapter (valid/ready 契约)
   |
   v  24bit PCM (16bit 左移8位符号对齐)
加密 HDMI 核音频接口 (I_audio_valid / left / right)
   ^
   |
audio_arc_calculate (ACR: N=6144, CTS≈25000)  ← 保留原逻辑
```

---

## 三、改动文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `src/audio/pcm_media_tone.v` | 新增（教程原样） | 媒体音调/正弦 DDS |
| `src/audio/m06_pcm_contract_adapter.v` | 新增（教程原样） | PCM 契约适配 |
| `src/audio/hdmi_pcm_audio_bridge.v` | **新增（本工程适配层）** | 把正弦 PCM 接到加密核接口 |
| `sim/tb_hdmi_pcm_audio_bridge.v` | 新增 | Icarus 自校验仿真 |
| `src/top_tf_hdmi_audio.v` | 修改 | 删方波链路/音频PLL，接新音源 |
| `constraints/timing.sdc` | 修改 | 删除 `audio_mclk` 相关约束 |
| `prj/VinylFPGA.al` | 修改 | 把 3 个音频文件加入源清单 |

**未改动（高危链路，保持原样）：**
`hdmi_1_4b_transmitter_core_wrapper.enc.v`、`hdmi_phy_warpper.v`、`lane_lvds_10_1.v`、
`SD/sdram.v` + `include/sdr_*.enc.v`、`frame_fifo_read/write.v`、`video_timing_data.v`、
`video_delay.v`、`sd_card_*`、`seg_*`、按键/轮播逻辑。

---

## 四、完整代码

### 4.1 新增：`src/audio/hdmi_pcm_audio_bridge.v`（本工程适配层，完整代码）

```verilog
`timescale 1ns/1ps

// 第3课音频源到安路 HDMI 1.4b 加密核的适配层。
//
// 完赛工程原本使用：
//   pcm_media_tone -> m06_pcm_contract_adapter -> hdmi_audio_symbol_core
// 其中 hdmi_audio_symbol_core 负责自行封装 HDMI 音频包并输出 TMDS 符号。
//
// 本工程使用官方加密 HDMI 1.4b 发射核，音频采样包、InfoFrame 和 ACR 已在
// 核内部完成。该核只接收 48kHz 的 24bit 并行 PCM：
//   I_audio_valid / I_audio_left_data / I_audio_right_data
// 因此这里保留教程的 PCM 音源和契约适配，只把 16bit PCM 左移 8bit 后送入
// 加密核，避免重复实现 HDMI 音频包封装。
module hdmi_pcm_audio_bridge #(
    parameter integer CLOCK_HZ  = 25000000,
    parameter integer SAMPLE_HZ = 48000
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [1:0]         media_id,
    input  wire [7:0]         volume,
    output wire               audio_valid,
    output wire signed [23:0] audio_left,
    output wire signed [23:0] audio_right,
    output wire               sample_overflow,
    output wire               contract_error,
    output wire               blip_active
);
    wire               source_valid;
    wire               source_ready;
    wire signed [15:0] source_left;
    wire signed [15:0] source_right;
    wire               pcm_valid;
    wire signed [15:0] pcm_left;
    wire signed [15:0] pcm_right;

    pcm_media_tone #(
        .CLOCK_HZ  (CLOCK_HZ),
        .SAMPLE_HZ (SAMPLE_HZ)
    ) u_pcm_media_tone (
        .clk          (clk),
        .rst_n        (rst_n),
        .media_id     (media_id),
        .volume       (volume),
        .sample_valid (source_valid),
        .sample_ready (source_ready),
        .sample_left  (source_left),
        .sample_right (source_right),
        .overflow     (sample_overflow),
        .blip_active  (blip_active)
    );

    m06_pcm_contract_adapter u_m06_pcm_contract_adapter (
        .clk            (clk),
        .rst_n          (rst_n),
        .source_valid   (source_valid),
        .source_ready   (source_ready),
        .source_left    (source_left),
        .source_right   (source_right),
        .pcm_valid      (pcm_valid),
        .pcm_ready      (1'b1),
        .pcm_left       (pcm_left),
        .pcm_right      (pcm_right),
        .contract_error (contract_error)
    );

    // 16bit PCM 在 HDMI/IEC 60958 的 24bit sample word 中左对齐。
    assign audio_valid = pcm_valid;
    assign audio_left  = {pcm_left,  8'b0};
    assign audio_right = {pcm_right, 8'b0};
endmodule
```

> 采样节拍完全由 `pcm_media_tone` 内部的分数累加器
> （`rate_accumulator`，25MHz / 48kHz = 520.833，在 520/521 之间交替）产生，
> 长期平均严格等于 48kHz。因此 `pcm_ready` 直接给 `1'b1`，
> 不再另做一个消费端 tick，避免生产端与消费端两个累加器相位漂移。

### 4.2 新增：`src/audio/pcm_media_tone.v`（教程原样，逐字节一致）

SHA256 与教程参考相同（`E709E933…B0E0`）。见工程内文件，内容与
`.../第3课_HDMI音频基础/pcm_media_tone.v` 完全一致（16 点正弦 LUT、4 组琶音、
1.5kHz 提示音、volume 缩放、8 深 FIFO）。

### 4.3 新增：`src/audio/m06_pcm_contract_adapter.v`（教程原样，逐字节一致）

SHA256 与教程参考相同（`33E0A6EA…30C4`）。见工程内文件，内容与
`.../第3课_HDMI音频基础/m06_pcm_contract_adapter.v` 完全一致。

### 4.4 修改：`src/top_tf_hdmi_audio.v`

**（1）删除音频 PLL 与 I2S 相关声明**

```verilog
// 删除（原）：
// wire        audio_pll_lock;
// wire        audio_mclk;
// wire        audio_i2s_bclk;
// wire        audio_i2s_lrck;
// wire        audio_i2s_dout;

// 新增（第3课：改用像素时钟的正弦波 PCM 音源）：
wire [1:0]  media_id;          // 当前显示图片编号，驱动媒体音调
wire [7:0]  audio_volume;      // 音量，0..255
wire        audio_sample_overflow;
wire        audio_contract_error;
wire        audio_blip_active;
```

**（2）复位改为只受外部 rst_n 控制**

```verilog
// 第3课起音频复用像素时钟，不再依赖独立音频 PLL，避免
// “音频 PLL 异常导致整机包括视频一起复位”的脆弱耦合。
wire rst_all;
assign rst_all = ~rst_n;      // 原来： ~rst_n | ~audio_pll_lock
```

**（3）删除音频 PLL 实例**

```verilog
// 删除整段：
// PLL_HDMI_AUDIO u_audio_pll(
//     .refclk(clk), .reset(1'b0), .extlock(audio_pll_lock),
//     .clk0_out(), .clk1_out(), .clk2_out(audio_mclk)
// );
```

**（4）用新音源替换 方波 + I2S_receiver**

```verilog
// ===================== 音频：第3课正弦媒体音调 =====================
// state_code 在第二讲中已改为“当前图片编号 1~4”，这里减 1 得到 media_id 0~3。
// 两拍同步把 100MHz sd_card_clk 域的图片编号安全地带到 25MHz video_clk 域。
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        media_state_code_sync1 <= 4'd0;
        media_state_code_sync2 <= 4'd0;
        display_valid_sync1    <= 1'b0;
        display_valid_sync2    <= 1'b0;
    end else begin
        media_state_code_sync1 <= state_code;
        media_state_code_sync2 <= media_state_code_sync1;
        display_valid_sync1    <= display_valid;
        display_valid_sync2    <= display_valid_sync1;
    end
end

// display_valid 置位后 state_code 稳定为 1~4；首图提交前固定使用 media_id=0。
assign media_id = (display_valid_sync2 &&
                   media_state_code_sync2 >= 4'd1 &&
                   media_state_code_sync2 <= 4'd4)
                ? (media_state_code_sync2[1:0] - 2'd1)
                : 2'd0;

// 16点正弦 LUT 峰值约 12000，200/255 缩放后仍保留足够余量，避免削波爆音。
assign audio_volume = 8'd200;

hdmi_pcm_audio_bridge #(
    .CLOCK_HZ  (25_000_000),
    .SAMPLE_HZ (48_000)
) u_hdmi_pcm_audio_bridge (
    .clk             (video_clk),
    .rst_n           (~rst_all),
    .media_id        (media_id),
    .volume          (audio_volume),
    .audio_valid     (audio_valid),
    .audio_left      (audio_left_data),
    .audio_right     (audio_right_data),
    .sample_overflow (audio_sample_overflow),
    .contract_error  (audio_contract_error),
    .blip_active     (audio_blip_active)
);

// 删除（原）：
// hdmi_audio_tone_i2s_64fs u_hdmi_audio_tone_i2s_64fs (...);
// I2S_receiver u_I2S_receiver (...);
```

> 为什么用 `state_code`（1~4）而不是 `disp_buf_idx`（0~3）？
> `disp_buf_idx` 是“正在写/读哪个缓冲区”的乒乓索引，和磁盘上的图片序号不是一回事；
> `state_code` 是第二讲已经做好的“当前图片编号 1~4”，用它减 1 得到 `media_id`，
> 音调才会和数码管显示的编号一一对应。`display_valid` 用来保证首图提交之前
> `state_code` 还是 0 的过渡期不会误触发切图提示音。

**（5）`audio_arc_calculate` 保持不动**（加密核需要 ACR）

```verilog
audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);
```

**（6）加密核接线不变**

```verilog
.I_audio_valid      (audio_valid),
.I_audio_left_data  (audio_left_data),
.I_audio_right_data (audio_right_data),
.I_acr_valid        (acr_valid),
.I_acr_cts          (acr_cts),
.I_acr_n            (acr_n),
```

### 4.5 修改：`constraints/timing.sdc`

删除两处：

1. `rename_clock -name {audio_mclk} -source … [get_pins {u_audio_pll/pll_inst.clkc[2]}]`
2. `set_clock_groups -asynchronous -group [get_clocks {audio_mclk}] -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]`

其余全部保留：`clk` 20ns、`derive_clocks`、`sys_pll_m0` 两路重命名（`sd_card_clk` / `ext_mem_clk`）、
`video_pll_m0` 两路重命名（`video_clk` / `hdmi_5x_clk`）、`video_clk` 与 `hdmi_5x_clk` 的 `-exclusive` 分组。

> 注意：第 2 条那个 `-asynchronous` 分组里，`video_clk / hdmi_5x_clk / sd_card_clk / ext_mem_clk`
> 本来就在**同一个 group** 里，所以删掉整条约束**不会**新引入这四个域之间的跨域路径分析，
> 只是去掉了已经不存在的 `audio_mclk`。这是本次改动对时序影响最小的做法。

### 4.6 修改：`prj/VinylFPGA.al`

在 `</Verilog>` 之前追加（CompileOrder 顺延为 37/38/39）：

```xml
<File Path="../src/audio/pcm_media_tone.v">
    <FileInfo>
        <Attr Name="UsedInSyn" Val="true"/>
        <Attr Name="UsedInP&R" Val="true"/>
        <Attr Name="BelongTo" Val="design_1"/>
        <Attr Name="CompileOrder" Val="37"/>
    </FileInfo>
</File>
<File Path="../src/audio/m06_pcm_contract_adapter.v">
    <FileInfo>
        <Attr Name="UsedInSyn" Val="true"/>
        <Attr Name="UsedInP&R" Val="true"/>
        <Attr Name="BelongTo" Val="design_1"/>
        <Attr Name="CompileOrder" Val="38"/>
    </FileInfo>
</File>
<File Path="../src/audio/hdmi_pcm_audio_bridge.v">
    <FileInfo>
        <Attr Name="UsedInSyn" Val="true"/>
        <Attr Name="UsedInP&R" Val="true"/>
        <Attr Name="BelongTo" Val="design_1"/>
        <Attr Name="CompileOrder" Val="39"/>
    </FileInfo>
</File>
```

> 注意：`UsedInP&R` 里的裸 `&` 是本工程 `.al` 的**原有风格**，TD 可以正常解析，不要“顺手修正”成 `&amp;`，否则和既有条目不一致。
>
> `PLL_HDMI_AUDIO.v`、`hdmi_audio_tone_i2s_64fs.v`、`I2S_receiver.v` 这三个文件**保留在源清单里不动**。
> 它们已经没有实例，TD 不会综合出对应电路（已实测：综合后不存在 `u_audio_pll` /
> `u_hdmi_audio_tone_i2s_64fs` / `u_I2S_receiver` 任何单元）。保留是为了随时能回退。

### 4.7 新增：`sim/tb_hdmi_pcm_audio_bridge.v`（自校验仿真，完整代码）

```verilog
`timescale 1ns/1ps

module tb_hdmi_pcm_audio_bridge;
    reg         clk;
    reg         rst_n;
    reg [1:0]   media_id;
    reg [7:0]   volume;
    wire        audio_valid;
    wire signed [23:0] audio_left;
    wire signed [23:0] audio_right;
    wire        sample_overflow;
    wire        contract_error;
    wire        blip_active;

    integer valid_count;
    integer amplitude_error;
    integer channel_error;
    integer contract_error_seen;
    reg     count_enable;

    hdmi_pcm_audio_bridge #(
        .CLOCK_HZ  (25_000_000),
        .SAMPLE_HZ (48_000)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .media_id        (media_id),
        .volume          (volume),
        .audio_valid     (audio_valid),
        .audio_left      (audio_left),
        .audio_right     (audio_right),
        .sample_overflow (sample_overflow),
        .contract_error  (contract_error),
        .blip_active     (blip_active)
    );

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        media_id      = 2'd0;
        volume        = 8'd200;
        valid_count   = 0;
        amplitude_error = 0;
        channel_error = 0;
        contract_error_seen = 0;
        count_enable  = 1'b0;
    end

    always #20 clk = ~clk;   // 25MHz

    always @(posedge clk) begin
        if (rst_n && count_enable && audio_valid)
            valid_count = valid_count + 1;

        if (rst_n && audio_valid) begin
            // 16bit PCM 左移 8bit 后，±10000 对应 24bit 的 ±2,560,000。
            if (audio_left > 24'sd3000000 || audio_left < -24'sd3000000) begin
                if (amplitude_error < 5)
                    $display("amplitude sample: left=%0d right=%0d time=%0t", audio_left, audio_right, $time);
                amplitude_error = amplitude_error + 1;
            end
            if (audio_left !== audio_right) begin
                if (channel_error < 5)
                    $display("channel sample: left=%0d right=%0d time=%0t", audio_left, audio_right, $time);
                channel_error = channel_error + 1;
            end
        end

        if (rst_n && contract_error)
            contract_error_seen = contract_error_seen + 1;
    end

    initial begin
        #200;
        rst_n = 1'b1;

        // 跳过首图提交前的准备时间，统计 100ms 内的有效音频样本数。
        #200000;
        count_enable = 1'b1;
        #100000000;
        count_enable = 1'b0;

        if (valid_count < 4790 || valid_count > 4810) begin
            $display("FAIL: 48kHz sample count mismatch, valid_count=%0d (expect 4800)", valid_count);
            $finish;
        end
        if (amplitude_error != 0) begin
            $display("FAIL: PCM amplitude error count=%0d", amplitude_error);
            $finish;
        end
        if (channel_error != 0) begin
            $display("FAIL: PCM channel error count=%0d", channel_error);
            $finish;
        end
        if (contract_error_seen != 0) begin
            $display("FAIL: PCM contract error count=%0d", contract_error_seen);
            $finish;
        end
        if (sample_overflow != 1'b0) begin
            $display("FAIL: tone source overflow asserted");
            $finish;
        end

        // 切图后应触发 1.5kHz 提示音。
        media_id = 2'd1;
        repeat (10) @(posedge clk);
        if (!blip_active) begin
            $display("FAIL: media_id change did not trigger blip");
            $finish;
        end

        $display("PASS: 48kHz PCM count=%0d, amplitude/error checks clean, blip active", valid_count);
        $finish;
    end
endmodule
```

---

## 五、逐步移植教程（可复现）

1. 复制教程文件
   把 `第3课_HDMI音频基础/` 下的 `pcm_media_tone.v`、`m06_pcm_contract_adapter.v`
   复制到 `VinylFPGA/src/audio/`（**原样复制，不要改动文件内容**）。
2. 新增适配层
   新建 `src/audio/hdmi_pcm_audio_bridge.v`（内容见 4.1）。
3. 改顶层
   按 4.4 的 (1)~(5) 修改 `src/top_tf_hdmi_audio.v`；加密核实例（4.4 (6)）不动。
4. 改约束
   按 4.5 修改 `constraints/timing.sdc`。
5. 改工程清单
   按 4.6 在 `prj/VinylFPGA.al` 追加 3 个文件（也可在 TD 里右键 Add Source）。
6. 编译
   TD 中：Read Design → Optimize RTL → Optimize Gate → Place → Route → Bitgen。
   本工程用 SynthPilot 自动跑通（见第六节）。
7. 仿真（可先做，省时间）
   用 Icarus 编译 `src/audio/*.v` + `sim/tb_hdmi_pcm_audio_bridge.v`（见 6.1），
   秒级就能确认采样率、幅度、切图提示音，不用等 1 分钟的布局布线。

> 手工核对要点：综合后确认 `u_hdmi_pcm_audio_bridge` 存在（实测有 114 个层级单元），且 `u_hdmi_audio_tone_i2s_64fs` /
> `u_I2S_receiver` / `u_audio_pll` **不再存在**（说明方波链路已彻底移除）。

---

## 六、验证记录（本次实测）

### 6.1 仿真（Icarus Verilog, `-g2012`）

命令（秒级即可跑完，建议每次改音频都先跑这个）：

```powershell
cd D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA
iverilog -g2012 -Wall -o "$env:TEMP\vinyl_audio_tb.vvp" `
  src/audio/pcm_media_tone.v `
  src/audio/m06_pcm_contract_adapter.v `
  src/audio/hdmi_pcm_audio_bridge.v `
  sim/tb_hdmi_pcm_audio_bridge.v
vvp "$env:TEMP\vinyl_audio_tb.vvp"
```

实测输出：

```text
PASS: 48kHz PCM count=4800, amplitude/error checks clean, blip active
```

| 测试项 | 判据 | 结果 |
|---|---|---|
| 采样率 | 100ms 窗口内有效样本数 4800（偏差 ≤10） | 4800 ✅ |
| 幅度 | 24bit 样本绝对值 < 3,000,000（16bit ±10000 左移 8bit） | 0 错 ✅ |
| 左右声道 | `audio_left === audio_right` | 0 错 ✅ |
| 契约 | `contract_error` 恒为 0 | 0 错 ✅ |
| 溢出 | `sample_overflow` 恒为 0 | 0 错 ✅ |
| 切图联动 | `media_id` 变化后 `blip_active` 变 1 | 通过 ✅ |

### 6.2 安路 TD 6.2.1 全流程（SynthPilot MCP 自动，实测耗时 59.3s）

| 步骤 | 结果 |
|---|---|
| import_device / open_project | OK（`eagle_s20.db`，EG4S20BG256，top = `top`） |
| elaborate / read_adc / read_sdc | OK |
| optimize_rtl (5.5s) / optimize_gate (7.0s) / legalize_phy_inst | OK |
| read_sdc_post_gate | OK |
| place (13.0s，2 warning) / route (31.3s，1 warning) | OK |
| update_timing (final) / bitgen | OK |

产物：`prj/VinylFPGA_lecture4_l3_pcm48k.bit`

**资源占用（route 后实测）：**

| 资源 | 用量 | 占比 |
|---|---|---|
| LUT | 4142 / 19600 | 21.13% |
| REG | 3548 / 19600 | 18.10% |
| BRAM9K | 20 / 64 | 31.25% |
| DSP | 1 / 29 | 3.45% |
| **PLL** | **2 / 4** | **50.00%**（改动前 3 个：音频 PLL 已移除 ✅） |
| IO | 28 / 188 | 14.89% |

**时序（post-route，slow+fast 双角）：**

- `video_clk -> video_clk` 域内：**0 违例**，SWNS **+28.855ns**，HWNS **+0.003ns**，共 2913 个端点 / 9554 条路径。
- `hdmi_5x_clk`：SWNS +5.281ns，0 违例。
- 全局：`SWNS -6.565ns / STNS -296.981ns`，`HWNS +0.003ns / HTNS 0`。
  负裕量**全部**落在既有 SDRAM/SD 链路：
  `ext_mem_clk -> sys_pll_m0/pll_inst.clkc[2]`（-6.565ns）、
  `sys_pll_m0/pll_inst.clkc[2] -> ext_mem_clk`（-2.920ns）、
  `ext_mem_clk -> sd_card_clk`（-1.613ns）、`ext_mem_clk -> ext_mem_clk`（-0.374ns）。
- **关键证据**：在 `prj/top_route.timingsummary` 全文里检索
  `pcm_media_tone` / `hdmi_pcm_audio_bridge` / `audio_arc_calculate`
  的结果是 **0 条**——新增音频逻辑完全不在任何关键路径上。

**对比第三讲基线**（`prj/VinylFPGA_Runs/phy_1/final_timing.rpt`，
该报告生成于 2026-10-03 20:32，时钟表里还带 `audio_mclk` 和 `u_audio_pll`，
即第三讲的原样构建）：

| 指标 | 第三讲基线 | 本次第四讲 | 结论 |
|---|---|---|---|
| 全局 SWNS | -6.699ns | -6.565ns | 略改善 |
| 全局 STNS | -295.293ns | -296.981ns | 同量级（SDRAM） |
| 违例路径组 | SDRAM/SD 跨域 | 完全相同 | **既有问题，非本次引入** |

**`check_timing` 结果**：HIGH 级 0 问题；仅有 TD 自身对两个 PLL 反馈网络的
`USR-6135 CRITICAL-WARNING`（`sys_pll_m0` / `video_pll_m0` 反馈走 local 网络），
改动前就存在；MEDIUM 级为 5 个输入端口无 input delay、23 个输出端口无 output delay、
32 条 abnormal `set_input_delay`——这些是原始 SDC 从来没有写过 I/O delay 导致的，
同样与本次改动无关。

> 副作用提醒：跑完整流程会刷新工程里几个**已被 git 跟踪**的报告文件
> （`prj/final_timing.rpt`、`prj/gate.qor`、`prj/place.qor`、`prj/route.qor`）。
> 它们是构建产物，提交与否按你的习惯决定即可。

---

## 七、上板测试与排查

上板后预期：

1. HDMI 显示器出声，**是悦耳的正弦琶音**，不再是刺耳方波；
2. 按 KEY1 / 自动轮播切图时，先响一声 1.5kHz 提示音，然后换成该图对应的琶音；
3. 视频显示、按键、轮播、数码管一切照旧。

**仍然没声音时按顺序排查：**

1. 显示器是否带扬声器 / 是否有音频输出接口（很多显示器无扬声器）；
2. HDMI 线是否是真·HDMI 线（劣质线只接视频引脚）；
3. 音量是否太小 → 把顶层 `assign audio_volume = 8'd200;` 调大（最大 255，注意别削波）；
4. 上板前确认烧的是**新** bit：`prj/VinylFPGA_lecture4_l3_pcm48k.bit`；
5. 仍有杂音 → 检查是不是误烧回旧 bit（`VinylFPGA.bit` 等旧文件仍是方波版本）。

**关于 48kHz 精度：** 25MHz / 48000 = 520.833 个时钟一个采样，分数累加器让节拍在
520/521 之间交替，长期平均严格等于 48kHz，单周期有 ±40ns 抖动，由 ACR 包补偿，
这是完赛工程的标准做法，听感无影响。

---

## 八、结论

- 杂音根因是**官方方波音源**，不是线路问题；换成 16 点正弦 DDS 后音质正常。
- 教程的 `hdmi_audio_symbol_core`（路线 B）与加密核（路线 A）架构冲突，
  **不应照搬**；本工程按第1课的“可改/不可改”清单，只替换音源，其余全部保留。
- 仿真、综合、布局布线、时序、bitgen 全部通过；音频/视频域零违例；
  既有 SDRAM 违例与本次改动无关。

---

## 九、回退方法（万一上板效果不满意）

本次改动只碰了 3 个地方，回退很干净：

1. `src/top_tf_hdmi_audio.v`：把 `hdmi_pcm_audio_bridge` 那段换回原来的
   `PLL_HDMI_AUDIO u_audio_pll` + `hdmi_audio_tone_i2s_64fs` + `I2S_receiver`，
   并把 `assign rst_all` 改回 `~rst_n | ~audio_pll_lock`。
2. `constraints/timing.sdc`：把删掉的那两行（`rename_clock … audio_mclk` 和
   `set_clock_groups -asynchronous …`）加回去。
3. `prj/VinylFPGA.al`：把追加的 3 条 `<File>` 条目删掉（或直接不管，反正没实例）。

最省事的做法是直接用 git：

```powershell
cd D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA
git diff --stat                 # 先看清楚有哪些改动
git checkout -- src/top_tf_hdmi_audio.v constraints/timing.sdc prj/VinylFPGA.al
```

> `src/audio/`、`sim/` 是新增文件，`git checkout` 不会动它们，留着不影响构建。

**音频相关参数在哪里调**（都不用动加密核）：

| 想改什么 | 改哪里 |
|---|---|
| 音量 | 顶层 `assign audio_volume = 8'd200;`（0~255） |
| 提示音时长 | `pcm_media_tone` 的 `BLIP_SAMPLES`（默认 4800 = 100ms） |
| 每个音符时长 | `pcm_media_tone` 的 `NOTE_SAMPLES`（默认 12000 = 250ms） |
| 各图片的音高 | `pcm_media_tone` 里 `melody_inc` 函数的 case 表 |
| 采样率 | 顶层和 bridge 的 `SAMPLE_HZ`，以及加密核 `AUDIO_SAMPLE_RATE ("48K")` 要一起改 |
