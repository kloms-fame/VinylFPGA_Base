# 第十二讲彩点问题：从外向内单变量隔离实验（2026-10-05）

## 一、现象（本轮复现口径）

- 图片显示完成后，画面随时间出现彩色噪点，并且**越来越多**。
- 图片加载完成后**拔掉 SD 卡**，彩点仍然出现并继续增多。
- 已有结论：拔卡后写路径不再向显示 bank 写数据（`write_en = bmp_data_wr_en`
  只在加载逐像素阶段拉高），因此"拔卡后仍增长"指向**读路径 / SDRAM 数据完整性 /
  HDMI 最后一公里**，而不是写坏累积。
- 上一轮 `VinylFPGA_lecture12_dotfix_readpace.bit`（读突发节流）已上板证伪：
  彩点仍增长，拔卡仍增长。

## 二、依据（《第1课_从官方例程到完赛工程_架构认知与FPGA思维框架.md》）

- 313-324 行 现象分类表：**花屏/竖条/颜色不对 → 像素数据错误、FIFO、SDRAM、BMP 解析**。
- 326-342 行 责任层级法（从外向内）：
  1. 官方 HDMI 内部 TPG → 验证 HDMI 最后一公里
  2. 外部 AXIS 本地彩条 → 验证 AXIS 接口与 HDMI 核心
  3. 像素域本地图案 → 验证视频时序与像素消费端
  4. …… 5. SDRAM 返回节奏 6. 真实 SDRAM 数据 ……
- 344-355 行 单变量隔离四要素：**唯一变量 / 保持不变 / 预期A / 预期B**。
- 357-369 行 诊断工具自证：**"设置了 DIAG 参数"不等于"真的隔离了变量"**，
  必须从端口和状态机逐行证明原路径已被切断。
- 371-381 行 证据强度分级：**只有 HDMI 实拍画面是最终裁判**。

## 三、实验设计（一次只改一个变量）

### 实验 A —— 显示输出改到 HDMI_A

| 项 | 内容 |
|---|---|
| 唯一变量 | TMDS 四根线的物理引脚：HDMI_B(C3/G5/F1/E1) → HDMI_A(K1/F5/E3/B3) |
| 保持不变 | 全部 RTL、时钟、SDC、SDRAM、SD 卡、显示内容 |
| 预期A | 彩点消失或显著改变 → 根因含 HDMI_B 物理链路（连接器/走线/线缆/显示器口） |
| 预期B | 彩点不变 → 排除物理输出口，继续往里查 |

引脚依据：本机完赛工程总装仓 `constraints/adc/hdmi_a.adc`（K1/F5/E3/B3，
DDC 仍为 P2/R2），与官方 lab_ex5_i2s HDMI_A 复用底座一致。

### 实验 B —— 像素域本地彩条 + 硬切断 SDRAM 帧读请求

| 项 | 内容 |
|---|---|
| 唯一变量 | `DIAG_LOCAL_PATTERN=1`：`vout_data` 改用本地竖彩条（64px 一段，白/黄/青/绿/品红/红/蓝/黑/中灰/深灰） |
| 保持不变 | HDMI_A、HDMI 核、AXIS 桥、OSD、转场、波形叠加、音频、时钟、约束 |
| 预期A | 彩点消失 → 根因在 **SDRAM 帧读链路**（读突发/采样窗口/CDC/FIFO） |
| 预期B | 彩点仍在 → 根因在**像素域之后**（OSD/波形/AXIS 桥/HDMI 核/PHY/线缆/显示器） |

**自证（隔离是否真的生效）：**

- `assign video_read_req_eff = DIAG_LOCAL_PATTERN ? 1'b0 : video_read_req;`
  接在 `frame_read_write` 的 `.read_req` 输入（消费者侧），不是接在
  `video_timing_data` 的输出侧。
- `frame_read_write` 内的 `frame_fifo_read` 只有 S_IDLE 满足
  `read_req_d2 == 1'b1 && Sdr_init_done` 才会离开空闲态
  （`src/SD/frame_fifo_read.v` S_IDLE 分支）。
- 因此 `read_req` 恒 0 ⇒ 状态机永停 S_IDLE ⇒ `App_rd_en` 恒 0 ⇒
  **不会有任何 SDRAM 读突发**被发出。

### 实验 C —— HDMI 核内部 TPG

| 项 | 内容 |
|---|---|
| 唯一变量 | `VIDEO_TPG` 由 `"Disable"` 改为 `"Enable"` |
| 保持不变 | 其余全部（含 HDMI_A） |
| 预期A | 彩点消失 → 根因在**像素源到 HDMI 核输入之间**（AXIS 桥/像素域） |
| 预期B | 彩点仍在 → 根因在 **HDMI 核/PHY/TMDS 输出/线缆/显示器** |

## 四、产物（`VinylFPGA/prj/`，均为易失 JTAG/SRAM 下载）

| 实验 | 位流 | SHA256 | Setup WNS/TNS/端点 | Hold WNS/端点 | 映像通路余量 |
|---|---|---|---|---|---|
| A HDMI_A | `VinylFPGA_expA_hdmia.bit` | `171F044D1DDD9EE24F760E9E64A2E23C41E8724D2B26243EF1DCE966C858F3A7` | -427ps / -11603ps / 82 | -12ps / 15 | ext_mem_clk +0.131ns，video_clk +3.464ns |
| B 本地彩条 | `VinylFPGA_expB_localpattern.bit` | `6205B44E04AA97F3105106352915A7E7E45539830AF7C354AAD123738B3F6AB2` | -323ps / -2011ps / 21 | -8ps / 8 | ext_mem_clk +0.300ns，video_clk +1.448ns |
| C TPG | `VinylFPGA_expC_tpg.bit` | `3738237B7E6FB2FB9BACBE950CE646EC2EACF460C30677CC09858E734CACC2F9` | -362ps / -6272ps / 46 | -44ps / 17 | ext_mem_clk +0.599ns，video_clk +1.233ns |

三个位流的残余 setup/hold 违例**全部落在 `sd_card_clk`（100MHz）的
SD/WAV 音频链**（`fat32_media_loader/audio_start_lba → wav_stream_player` 等），
不在图像显示通路上；`ext_mem_clk`（SDRAM）与 `video_clk`（像素）均为正余量。

构建方式：TD `v6.2.168116` 官方 `doc/scripts/DefaultFlow.tcl` 全流程
（syn_1: read_design→opt_gate；phy_1: opt_place→opt_route→bitgen），
布局种子固定 `place seed 2`（`prj/VinylFPGA_Runs/phy_1/settings.cfg`）。
日志：`_l12_regress/exp{A,B,C}_{syn,phy}.log`。

## 五、上板步骤（务必按顺序，一步一结论）

1. 显示器线插到 **HDMI_A** 口（不要再插 B 口）。
2. 烧写 **A** → 正常放图 → 观察 ≥10 分钟 → 记录"有无彩点 / 是否增多"。
3. 烧写 **B** → 应看到**满屏竖彩条** → 观察 ≥10 分钟 → 记录。
4. 烧写 **C** → 应看到**HDMI 核自带测试图** → 观察 ≥10 分钟 → 记录。
5. 三步都记下：`烧写文件 / 画面内容 / 有无彩点 / 是否随时间增多 / 观察时长`。

## 六、判定表（结果 → 结论 → 下一步）

| A | B | C | 结论 | 下一步 |
|---|---|---|---|---|
| 彩点 | 无彩点 | — | 根因在 **SDRAM 帧读链路** | 调 SDRAM 读：降 `ext_mem_clk` 到 80MHz 或重定 `ext_mem_clk_sft` 相位；加 UART/ILA 遥测确认 `App_rd_en` 与读回数据 |
| 彩点 | 彩点 | 无彩点 | 根因在 **像素域→HDMI 核输入**（OSD/波形/AXIS） | 逐个旁路 OSD、波形、`video_transition_apply` 做下一级隔离 |
| 彩点 | 彩点 | 彩点 | 根因在 **HDMI 核/PHY/TMDS/线缆/显示器** | 换线、换显示器口、换 sink 对照；检查 `hdmi_5x_clk` 与 ODDR 输出约束 |
| 无彩点 | — | — | 根因是 **HDMI_B 物理链路** | 直接使用 HDMI_A 交付 |

## 七、说明

- 本轮**未做 git commit**；工作区保留全部改动与实验产物供复核。
- 实验 B 的诊断开关 `DIAG_LOCAL_PATTERN` 主线默认 0，正式行为与实验前完全一致。
- `prj/` 下其它历史 `.bit`（`*_timingfix.bit`、`*_pixelfix.bit`、
  `*_decayfix.bit`、`*_dotfix_readpace.bit` 等）为先前多轮实验产物，
  **不对应本轮源码**，不要与本次三个实验位流混用。
