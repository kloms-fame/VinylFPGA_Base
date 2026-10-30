# VinylFPGA

基于安路 EG4S20BG256 的唱片主题本地音乐画屏：TF 卡媒体、HDMI 音视频、歌词、MV、实体控制、灯效与 Flash 参数保存。

2026-10-30：**用户确认人工验收通过，项目完成最终冻结。** 主工程为 TD 6.2.168116、顶层 top、单 seed 10；SWNS +0.105 ns，HWNS +0.024 ns，STNS/HTNS 和 setup/hold 违例端点均为 0。本轮已核对当前源码、工程、固件身份并从冻结数据库独立复算时序。

- [最终验收与冻结记录](doc/开发方案/最终人工验收确认与项目冻结_20261030.md)
- [最终交付清单](doc/开发方案/最终冻结清单_20261030.json)
- 已验收固件（本地归档）：`prj/VinylFPGA_Runs/final_accepted_20261030/prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`
- 完整交付 ZIP（本地归档）：`prj/VinylFPGA_Runs/VinylFPGA_FinalAccepted_20261030.zip`
- [工程入口](prj/VinylFPGA.al)
- [前轮综合实现与时序复核](doc/开发方案/最终工程收尾与时序复核_20261029.md)
- [文档导航与仓库结构](doc/README.md)
- [Git 整理与最终复核](doc/开发方案/Git整理与最终复核_20261030.md)

上轮功能回归 61 项、工具测试 33 项通过，原始证据已归档。厂商告警及 PLL/SDRAM/外部 I/O 约束检查项仍按报告保留；人工验收状态由用户确认。

Git 保存 RTL、约束、工程入口、测试、工具及文档。TD Runs、固件、仿真结果、个人配置和大体积媒体作为本地交付物单独保存；克隆仓库后需另外准备媒体输入。媒体处理与输入说明见 [媒体资源说明](doc/资源/sd卡/README.md)。旧草稿和重复文件已备份后清理，清单见上述 Git 整理记录。已有提交历史仍保留，当前文件树的整理不会清除历史对象。

复建前关闭同一工程的 TD 窗口并停止其他构建，在项目根目录执行：

```powershell
pwsh -File tools/build_closeout.ps1
python -X utf8 tools/verify_gui_runs.py
```

复建会更新当前 Runs。修改源码、约束或实现策略后需重新验证；最终冻结目录和 ZIP 应保留，用其 manifest.json 与 SHA256SUMS.txt 核对版本身份。固件和完整 Runs 被 Git 忽略，Git 仓库不等同于完整交付备份。

媒体镜像只读校验：

```powershell
python -X utf8 tools/vinyl_packer.py verify --image "你的镜像.img"
```

以完整命令退出码 0 判定通过。PCM 为 48 kHz、16-bit、单声道裸数据；PCM/MV 必须物理连续，相关文件位于根目录首扇区前 16 个目录项内。歌词与标题为编译期 ROM。媒体卡沿用人工验收配置，整卡镜像未包含在此次 ZIP 中。
