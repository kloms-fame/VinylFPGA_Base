# VinylFPGA

基于安路 EG4S20BG256 的唱片主题本地音乐画屏：TF 卡媒体、HDMI 音视频、歌词、MV、实体控制、灯效与 Flash 参数保存。

2026-10-29—30 收尾核验：**主工程 seed 10 完整构建及数据库复算通过**，SWNS +0.105 ns、HWNS +0.024 ns，setup/hold 违例端点均为 0；功能回归 61 项、工具测试 33 项通过。生产 RTL 和约束未改变。[最终固件](prj/VinylFPGA_Runs/release_main_seed10_20261030/VinylFPGA.bit)、[收尾与检查边界](doc/开发方案/最终工程收尾与时序复核_20261029.md)、[证据清单](doc/开发方案/最终收尾证据_20261029.json)。

新固件尚未实板验收，PLL/SDRAM/外部 I/O 的检查项详见报告。此前图形界面并发运行导致的中间记录属于历史过程；最终主工程已在关闭窗口后重新完成构建。以下为历史发布记录。

2026-10-23 完成 **MV 紧凑存储与六帧缓存修复**。相同 SDRAM 区域保有六帧，新增 132 LUT / 128 REG，BRAM、DSP 不变；原 `VinylFPGA.al`、seed 7 完整构建与独立最终时序通过。预热后 220 ms 单扇区等待、400 ms 慢窗口测试均保持最长 100.8 ms 换帧间隔。原生 10 fps；setup WNS +0.001 ns，余量很小，实板连续播放待验收。[本轮固件](prj/VinylFPGA_Runs/mv_smooth_20261023/release/VinylFPGA.bit)、[修复与验证报告](doc/产品项目输出/32_MV六帧缓存修复与固件交付_20261023.md)、[配套媒体](doc/资源/sd卡/release_20261023_mv_smooth/README_媒体验证.md)。媒体与原 fullbleed 镜像逐字节相同，原卡可直接配合新固件。

2026-10-22 新增 **SW9 / KEY6：五行歌词 / 单句专注切换**，已通过仿真及原工程完整构建，新增行为待实板验收。[本轮固件](prj/VinylFPGA_Runs/lyric_focus_20261022/release/VinylFPGA.bit)与[开发验证记录](doc/产品项目输出/29_KEY6歌词专注模式开发与验证_20261022.md)单独归档；原工程布局 seed 已固定为本轮通过时序的 **7**，其他策略、引脚与约束沿用原配置。

此前的 2026-10-22 冻结版本已完成代码复核和交付工具修复；用户已明确确认该版本全部功能人工验收通过。完整验证范围、资源、时序、已有告警和冗余处理决定见 [最终收尾验收](doc/产品项目输出/27_最终冻结与收尾验收_20261022.md)，该次身份与回归复核见 [人工验收确认与开发冻结复核](doc/产品项目输出/28_人工验收确认与开发冻结复核_20261022.md)。

- 工程入口：[prj/VinylFPGA.al](prj/VinylFPGA.al)，TD 6.2.168116，顶层 `top`，当前选用 seed 10。
- 此前冻结固件：[VinylFPGA.bit](prj/VinylFPGA_Runs/save_success_phrase_20261022/release/VinylFPGA.bit)，SHA-256 为 `1801a8d36429fe767c0d7e510db0edfed86faaccdba966c8843e043aba39dad5`。
- 此前冻结版本的源码、工程、固件和媒体身份：[版本清单](doc/产品项目输出/final_release_20261022.json)。原三音发布包保留原样；新增 KEY6 版本见上方本轮固件与验证记录。
- 交付 ZIP：[包校验值](doc/产品项目输出/final_delivery_20261022.sha256)，用于核对单独归档的 `VinylFPGA_Final_20261022.zip`。
- 项目分析与交接：[文档导航](doc/产品项目输出/00_文档集导航.md)。

在 TD 中打开原 `.al`，使用 Run All 生成固件。修改源码、约束或工程策略后，应重新完成仿真、综合、布局布线和最终时序检查；原冻结验收不自动覆盖修改版本。

交付镜像先运行只读检查：

```powershell
python -X utf8 tools/vinyl_packer.py verify --image "你的镜像.img"
```

以进程返回码 `0` 判定通过；前面的逐项 `VERIFY_OK` 不能代替整体结果。正式校验会拒绝碎片 PCM；`pack --allow-fragmented-audio` 仅供离线实验。封面仍支持 FAT 碎片链，PCM/MV 必须物理连续；相关文件须位于根目录首扇区的前 16 个目录项内。音频为 48 kHz、16-bit、单声道裸 PCM，歌词与标题为编译期 ROM。

固件、媒体镜像和完整 Runs 产物由 `.gitignore` 排除，Git 仓库不包含完整交付备份。收尾交付包位于 `prj/VinylFPGA_Runs/final_closeout_20261022/`；保留该包和清单指定的媒体镜像，避免与历史失败候选混用。
