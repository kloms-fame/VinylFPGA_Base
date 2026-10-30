# 比赛提交与 Git 上传

## 本次交付物

本轮生成的本机输出位于 `output/`，不加入源码 Git：

| 文件 | 用途 |
| --- | --- |
| `VinylFPGA_Contest_Source.zip` | 源码、约束、主工程、精选工具、仿真和文档；含逐文件校验清单 |
| `VinylFPGA_Contest_Source.zip.sha256` | 源码 ZIP 的 SHA-256 |
| `VinylFPGA_Contest_Firmware.zip` | 当前 bit、BID、时序和资源报告及固件清单 |
| `VinylFPGA_Contest_Firmware.zip.sha256` | 固件附件 ZIP 的 SHA-256 |
| `VinylFPGA_Contest_CleanGit.bundle` | 只含当前提交树和单次初始提交的独立 Git 备份 |

源码包不含商业音视频、完整媒体卡、TD/ModelSim 安装文件或完整 Runs。赛事平台要求的媒体、说明、视频与固化设备按实际入口分别提交；不把已存在源码 ZIP 当成赛事平台已收到材料。

## 提交前复核

1. 解压源码包，执行 `python -X utf8 tools/verify_submission.py`，再按 [构建说明](build.md)运行回归或 TD 复建。
2. 对附件运行 `Get-FileHash -Algorithm SHA256`，与其 `.sha256` 文件比对；固件包内还提供逐文件清单。
3. 在实际 HX4S20C 上使用同一完整设计、配套验收媒体和固化状态演示；不要为不同功能更换不同镜像。
4. 项目介绍按 [赛题对应](contest_compliance.md)陈述，附 [验证记录](verification.md)说明测量与仿真范围。

## Git 状态和历史

当前工程目录是原 Git 仓库。用户移走的历史资料已按删除纳入整理，当前只保留比赛提交需要的文件；同级 `VinylFPGA_file` 继续作为用户备份。原仓库此前历史仍含大体积媒体，因此“当前工作区干净”不等于全部 Git 历史体积小。此次不重写原 main、删除其他 worktree 或强推。

独立 bundle 在新目录建立单次提交，排除了原提交历史、本地缓存和媒体，适合需要从干净历史开始上传时使用。可在另外的新目录恢复：

```powershell
git clone "完整路径/output/VinylFPGA_Contest_CleanGit.bundle" VinylFPGA_Submission
cd VinylFPGA_Submission
python -X utf8 tools/verify_submission.py
git remote remove origin
git remote add origin "你确认有权限的远程仓库地址"
```

核对地址与权限后，使用普通推送提交到目标仓库。若目标 main 已有不同历史，应使用新分支或新空仓库；不直接强推覆盖已有内容。本轮只生成本地提交与交付包，不自动更改远程地址或代替参赛者在比赛网站提交。
