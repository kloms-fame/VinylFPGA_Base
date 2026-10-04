# 第十二讲音频波形可视化构建记录

## 交付物

- 位流：`../VinylFPGA_lecture12_waveform_final.bit`
- SHA256：`AB0A146F29AD63658A7B83CCD783B94FA4683425B398E38789BF602ABA2EA690`
- 大小：`629624` 字节
- 构建工具：Tang Dynasty `v6.2.168116`
- 目标器件：`EG4S20BG256`

## 构建参数

- 物理实现策略：`TimingHigh`
- 布线：`route effort high`
- 布线：`route timing on`
- 布线：`route fix_hold on`
- 主工程文件中的物理实现策略已恢复为 `Default_PhysicalDesign_Strategy`
- 主工程已登记 `../src/display/promax_audio_waveform.v`，编译顺序为 `56`

## 最终时序

- Setup：WNS `-55 ps`，TNS `-55 ps`，违例端点 `1`
- Hold：WNS `-2 ps`，TNS `-8 ps`，违例端点 `4`
- Slice：`8824 / 9800`，`90.04%`
- 关键 Setup 路径位于原有 FAT32 链路：
  `fat32_volume_scanner/sectors_per_cluster` 到 `fat32_media_loader/audio_start_lba`

## 残余风险

本次构建仍未达到完全时序闭合，Setup 和 Hold 分别存在 `55 ps` 与 `2 ps` 的极小负余量。波形模块位于 25 MHz 视频域，关键负余量路径来自原有 100 MHz FAT32 路径，不是波形模块自身引入的新路径。

上板时重点验证：

1. 上电首图显示和 KEY1 切图。
2. 自动轮播和切图提示音。
3. WAV 播放和 HDMI 音频。
4. OSD 字幕、图片转场。
5. 播放 WAV 时的波形和峰值条叠加。
