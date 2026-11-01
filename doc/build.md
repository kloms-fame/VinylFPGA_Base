# 复建与环境

## 工程与依赖

- 主入口 `prj/VinylFPGA.al`，顶层 `top`，器件 EG4S20BG256，TD 6.2.168116，当前选中 seed 15。
- `src/` 与 `constraints/` 为当前提交输入，不需要同级历史备份目录。145 个设计输入及 63 个工程条目的相对路径由提交核验工具检查。
- TD 自带的安路器件库、原语和合法可用的厂商加密 HDMI/SDRAM 文件是必要依赖；它们的接口/源码包装随工程保留，TD 安装程序不分发。
- Python 3.10+；Icarus Verilog 提供 `iverilog` 和 `vvp`；工具测试还使用 tkinter 中的 Tcl 解释器。无需网络账户运行提交核验与源码打包。
- 可选 ModelSim 10.6e（脚本默认安装路径）；可选图片/MV 工具需 `python -m pip install -r requirements-media.txt`。

## 源码和回归

在工程根目录执行 README 中的核验/回归命令。`verify_submission.py` 检查 145 个源码/约束输入和主工程相对路径；哈希对文本 CRLF/LF 做统一，以支持 Windows 和 Linux 签出。该检查不代替时序分析。

`run_current_regression.py` 默认运行全部精选功能，`--quick` 运行工具、收尾 RTL 和麦克风数字通路测试。输出保存到新的 `.codex_tmp/regression_时间/`，可用 `--output 新目录` 指定。已有输出目录会被拒绝，避免覆盖旧证据。每个套件单独保留日志，整体以进程退出码 0 判定通过。控制接口模型只替代仿真中的硬 IP 边界，ADC 模型也不代表模拟输入、噪声或真实音质已经通过。

可选 ModelSim：

```powershell
python -X utf8 tools/verify_finish_modelsim.py --output .codex_tmp/modelsim_current --vsim D:/modeltech64_10.6e/win64/vsim.exe --td-root D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116
```

保留 run.do、wave.do、WLF 与 VCD；目录必须新建。

## TD 综合、实现与 bitgen

打开 `prj/VinylFPGA.al` 后核对器件、顶层和种子。使用 Run All，或关闭同工程窗口后批处理：

```powershell
pwsh -File tools/build_closeout.ps1 -TD D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td.exe
python -X utf8 tools/verify_gui_runs.py
```

脚本默认执行完整综合、布局、布线及 bitgen，检查四项时序、端点违例数和 best_result 一致性。它会重置当前 syn_1/phy_1；需要保留的固件应先独立归档。同工程窗口或另一构建进程未关闭时会拒绝启动，以免保存旧配置或覆盖 Runs。

TD 默认参数、器件库版本和实现策略会影响结果，换版本或修改输入后必须重新核验，不能沿用旧 WNS。工程根路径字段保留原机器信息；迁移后请让 TD 使用当前打开的 `.al` 所在目录，核对所有源文件解析后重新生成 Runs。

独立导入布线数据库复算可运行 `td_commands_prompt.exe tools/audit_final_timing.tcl`，详细 check_timing 与 bitgen 参数写到所选 seed 目录。源码包没有 Runs，需先构建后再使用此入口和 `verify_gui_runs.py`。

## 固件和比赛提交

当前冻结版本 `mic-followvol-v1.0` 的规范固件以外部归档的 `稳定固件_麦克风跟随VOL_seed15_12888BE7.bit` 为准，SHA-256 为 `12888BE734514BCE75FBF16651CACA2C2E680833A75909AD35F90CC582C4B2F8`，大小 684,332 字节。源码目录中的 `prj/VinylFPGA_Runs/best_result/VinylFPGA.bit` 是本地构建候选，重新生成可能只改变 bit 头部的日期字节；交付前必须用实际文件哈希、配置数据和关联报告确认身份，不能把候选文件名直接当成规范固件。

`package_submission.py --output 新路径.zip` 将当前源码树打包并逐文件核验，附 `SHA256SUMS.json` 和外部 `.sha256`。解压后从 `VinylFPGA/prj/VinylFPGA.al` 打开。源码 ZIP 不代替固件、实板固化状态或媒体卡；这些应按比赛提交入口分别准备。

本仓库没有自动烧录命令。用户已确认 seed 10 主线人工验收通过；麦克风版本还需按[硬件接入说明](microphone_bringup.md)完成模拟通路实测。赛题要求的固化、断电上电自启动和完整设计同镜像演示，应在比赛设备上按验收说明核对。
