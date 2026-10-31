# 复建与环境

## 工程与依赖

- 主入口 `prj/VinylFPGA.al`，顶层 `top`，器件 EG4S20BG256，TD 6.2.168116，原生 MultiSeed 选中 seed 18。
- `src/` 与 `constraints/` 为已验收输入，不需要同级历史备份目录。61 个工程源条目的相对路径由提交核验工具检查。
- TD 自带的安路器件库、原语和合法可用的厂商加密 HDMI/SDRAM 文件是必要依赖；它们的接口/源码包装随工程保留，TD 安装程序不分发。
- Python 3.10+；Icarus Verilog 提供 `iverilog` 和 `vvp`；工具测试还使用 tkinter 中的 Tcl 解释器。无需网络账户运行提交核验与源码打包。
- 可选 ModelSim 10.6e（脚本默认安装路径）；可选图片/MV 工具需 `python -m pip install -r requirements-media.txt`。

## 源码和回归

在工程根目录执行 README 中的核验/回归命令。`verify_submission.py` 检查 144 个源码/约束输入和主工程相对路径；哈希对文本 CRLF/LF 做统一，以支持 Windows 和 Linux 签出。该检查不代替时序分析。

`run_current_regression.py` 默认运行全部精选功能，`--quick` 运行工具及收尾测试。输出保存到新的 `.codex_tmp/regression_时间/`，可用 `--output 新目录` 指定。已有输出目录会被拒绝，避免覆盖旧证据。每个套件单独保留日志，整体以进程退出码 0 判定通过。控制接口模型用于替代仿真中的硬 IP 边界，不代表完整 DDR/HDMI 协议物理验证。

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

推荐固件来自 `prj/VinylFPGA_Runs/best_result/VinylFPGA.bit`。bit 头部开启时间信息，重新生成可能仅改变日期行；以实际交付 SHA-256、配置数据及关联数据库确认身份，不能只用文件名。

`package_submission.py --output 新路径.zip` 将当前源码树打包并逐文件核验，附 `SHA256SUMS.json` 和外部 `.sha256`。解压后从 `VinylFPGA/prj/VinylFPGA.al` 打开。源码 ZIP 不代替固件、实板固化状态或媒体卡；这些应按比赛提交入口分别准备。

本仓库没有自动烧录命令。用户已确认项目人工验收通过；赛题要求的固化、断电上电自启动和完整设计同镜像演示，应在比赛设备上按验收说明核对。
