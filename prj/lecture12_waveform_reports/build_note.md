# 第十二讲音频波形可视化构建记录（彩点修复：dotfix_readpace）

## 问题背景

现象：图片显示完成后随时间出现彩色噪点，且拔掉 SD 卡后彩点仍继续增多。
定位方向：SDRAM 读突发与自动刷新/忙窗口冲突（读采样被刷新命令挤掉），
叠加 display_valid / audio_play_enable 跨时钟域信号未做两级同步。

## 交付物

- 位流：`../VinylFPGA_lecture12_dotfix_readpace.bit`
- SHA256：`E6403DEDC1DB59A1CEBBEE1677594A087379F501EEB175F46BA5AD0DF216C825`
- 配套 BID：`../VinylFPGA_lecture12_dotfix_readpace.bid`
- 大小：`629624` 字节
- 构建工具：Tang Dynasty `v6.2.168116`
- 目标器件：`EG4S20BG256`
- 构建方式：TD 官方 `doc/scripts/DefaultFlow.tcl` 全流程
  （syn_1: read_design→opt_gate；phy_1: opt_place→opt_route→bitgen）
- 布局种子：`place seed 2`（`prj/VinylFPGA_Runs/phy_1/settings.cfg`）

## 本轮源码改动（均在工作区，未提交）

1. `src/SD/frame_fifo_read.v`
   - 新增 `BURST_GAP_CYCLES = 12`、`FIFO_LOW_WATERMARK = 128`
   - 读突发判据加入 `rd_gap_ok && (ctrl_quiet || fifo_low)`：
     `ctrl_quiet = ~Sdr_init_ref_vld & ~Sdr_busy`，避让刷新与控制器忙窗口；
     FIFO 低于低水位时兜底放行（worst case 退化回官方行为，不死锁）。
2. `src/SD/fat32_media_loader.v`
   - `audio_start_lba` 的“减2→移位→加 data_start”组合链拆成两级寄存器，
     对外语义晚一拍不变（扫描结果为准静态）。
3. `src/top_tf_hdmi_audio.v`
   - `display_valid`、`audio_play_enable` 进 video_clk 域前增加两级同步；
   - `seg_scan` 整体搬入 sd_card_clk 域（CLK_FREQ=100MHz），消除 50MHz/100MHz
     真实跨域 hold 路径（原 -0.738ns / 12 端点）。

## 时序结果（对比上一版保底产物）

来源：`prj/VinylFPGA_Runs/phy_1/route.qor`、`VinylFPGA_pr.timing`（final 模式）。

| 指标 | cdcfix_seed2 (22:03) | dotfix_readpace (22:23) |
| --- | --- | --- |
| Setup WNS | -524 ps | -356 ps |
| Setup TNS | -12492 ps | -3470 ps |
| Setup 违例端点 | 77 | 29 |
| Hold WNS | -738 ps | -20 ps |
| Hold TNS | -2872 ps | -56 ps |
| Hold 违例端点 | 12 | 15 |
| Slice | 8995/9800 = 91.79% | 9030/9800 = 92.14% |

各时钟（final）：

- `video_clk` SWNS +2.047ns / HWNS -0.020ns（HDMI 音频岛 inter-clock 路径）
- `ext_mem_clk` SWNS +0.690ns / HWNS -0.004ns（读缓存 wr_addr→RAM 地址，4ps）
- `sd_card_clk` SWNS -0.356ns：残余 29 个 setup 端点全部位于音频/WAV 相关路径
  （`fat32_media_loader/audio_start_lba` → `wav_stream_player/wr_ptr`、
  `sd_card_sec_read_write` → `wav_stream_player` RAM），不在图像显示通路上

结论：图像显示通路（ext_mem_clk 读缓存 + video_clk 视频）已无实质违例；
残余违例集中在 100MHz WAV 音频加载/指针链。

## 仿真验证（Icarus Verilog）

- 新增 `sim/tb_frame_fifo_read_pace.v`：5 项全部 PASS
  - 刷新窗口 60 周期内 0 次读脉冲；刷新撤销后 3 周期恢复
  - 控制器忙窗口 60 周期内 0 次读脉冲
  - 低水位兜底：busy+refresh 同时成立时仍能发突发（3 周期）
  - 全帧 1024 字无死锁，突发间隔 min = 14 周期（≥ 12）
- `sim/tb_frame_fifo_read_gap.v`：min gap = 14 周期 PASS
- `sim/tb_fat32_media_loader.v`（重编译自当前源码）：PASS
- 上一轮既有回归 14 个 TB 全 PASS（`_l12_regress/*.log`）

## 上板验收清单（待硬件验证）

1. 上电首图显示 ≥ 60 分钟，观察彩点是否停止增长。
2. 图片加载完成后拔掉 SD 卡，再观察 ≥ 30 分钟（重点复现路径）。
3. 冷启动、KEY1 切图、自动轮播、转场淡入淡出各 ≥ 10 次。
4. WAV 播放 + HDMI 音频 + 波形叠加同时开启 ≥ 10 分钟。
5. 如仍复现：断点回退单变量比对，并用 ILA 抓
   `App_rd_en` / `Sdr_busy` / `Sdr_init_ref_vld` / `Sdr_rd_en` 与
   `display_valid_sync2`，确认读突发时序与跨域同步是否按预期。

## 说明

- `prj/` 下 18:xx~22:19 的历史位流（含 `*_timingfix.bit`、`*_pixelfix.bit`、
  `*_decayfix.bit` 等）为先前多轮实验产物，不对应本轮源码快照；
  本轮唯一交付基线为 `VinylFPGA_lecture12_dotfix_readpace.bit`。
- 本轮改动未做 git commit；工作区保留全部修改供复核。
