# VinylFPGA

基于安路 **HX4S20C / EG4S20BG256** 的唱片主题 HDMI 多媒体播放器。FPGA 完成 TF/FAT32 媒体读取、SDRAM 帧缓存、HDMI 视频与 PCM 音频输出，并整合 MV、歌词、波形、片内 ADC 麦克风混音、实体控制、灯效及 Flash 参数保存。

本仓库为比赛提交源码工程。用户在 **2026-10-30 确认 seed 10 主线人工验收通过**；之后加入的麦克风跟随音量版本冻结为 `mic-followvol-v1.0`。当前工程为 **seed 15**，布线报告为 **SWNS +0.060 ns、HWNS +0.021 ns**，setup/hold 违例端点均为 0。麦克风的数字通路与构建已记录，模拟供电和上板效果仍按 [硬件接入说明](doc/microphone_bringup.md)实测后展示。

| 目录 | 内容 |
| --- | --- |
| `src/` | RTL、ROM、生成 IP 包装和厂商加密核心 |
| `constraints/` | 引脚约束和时序约束 |
| `prj/VinylFPGA.al` | TD 6.2.168116 主工程入口，顶层 `top`，当前选中 seed 15 |
| [tools/](tools/README.md) | 当前构建、核验、回归、媒体与提交打包工具 |
| [sim/](sim/README.md) | 当前功能测试台、控制接口模型和必要 HEX 夹具 |
| [doc/](doc/README.md) | 项目架构、赛题对应、复建、媒体、演示与验收说明 |

## 快速核验

Python 3.10 或更新版本。完整 RTL 回归还需把 Icarus Verilog 的 `iverilog`、`vvp` 加入 PATH；工具测试需 Python 的 tkinter/Tcl 组件。

```powershell
python -X utf8 tools/verify_submission.py
python -X utf8 tools/run_current_regression.py --quick
python -X utf8 tools/run_current_regression.py
```

第一条检查 145 个设计输入、63 个工程条目和文档链接；第二条运行 27 项工具测试、10 项收尾 RTL 测试及 5 项麦克风数字通路测试；第三条运行全部精选回归。它们不烧录硬件。可选 ModelSim 独立检查见 [构建说明](doc/build.md)。

## TD 复建与提交

在 TD 中打开 `prj/VinylFPGA.al` 使用 Run All。也可关闭该工程的 GUI 窗口后执行：

```powershell
pwsh -File tools/build_closeout.ps1
python -X utf8 tools/verify_gui_runs.py
python -X utf8 tools/package_submission.py --output output/VinylFPGA_Contest_Source.zip
```

TD 工具路径可通过 `-TD` 指定，详见 [复建步骤](doc/build.md)。提交脚本只打包源码、约束、主工程、精选工具、仿真和文档，并生成逐文件 SHA256SUMS 与 ZIP 校验文件。复建生成的固件位于 `prj/VinylFPGA_Runs/best_result/`，应作为独立附件核对身份；源码包不包含 TD、Git 历史、Runs、媒体镜像和第三方软件。

官方赛题资料保存在 [doc/reference/](doc/reference/README.md)。旧开发资料已由用户转存到同级 `VinylFPGA_file`，该目录不是当前源码工程的运行依赖。Git 保留此前提交历史，当前源码包只包含现行文件树；如需上传远程仓库，应先确认 origin 地址及访问权限。

本轮另提供固件附件及不含旧提交历史的独立 Git bundle，交付范围与恢复方式见 [比赛提交说明](doc/submission.md)。

当前图像能力为固定布局/比例显示；双线性插值例程未接入顶层，不宣称任意分辨率自适应。音频可视化为 PCM 波形，非 FFT。厂商 IP 告警、PLL/SDRAM/外部 I/O 模型检查项及人工验收依据已在验证记录中列明。
