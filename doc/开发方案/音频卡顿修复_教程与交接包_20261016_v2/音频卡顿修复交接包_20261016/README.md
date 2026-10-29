# 音频卡顿修复交接包（R5 已验证功能）

本包与同级的 [执行教程](../音频卡顿修复与时序收敛执行教程_20261016.md) 配套使用。

基线 commit：`1f9013a26ce40f3d00b88d8cc3c63373ccb30df7`。核心补丁恢复已上板报告长播正常的 R5 功能源码，未包含未来的时序 CE 修复。R5 内部 setup 仍为 WNS −1.461ns、TNS −165.057ns、282 endpoints，不能把应用补丁等同于时序通过。

1. 在该 commit 的新隔离工作树应用 `01_baseline_to_R5_rtl.patch`。
2. 再应用 `02_verification.patch`，恢复 11 项验证源/脚本/说明。
3. 使用教程第 9 节命令，检查 manifest 中 19 个文件的 `target_sha256_lf`。
4. 先查 R5 post-fix `final.timing` 中的 `.ce` 路径，再按教程逐阶段优化与构建。

`R5_source/` 是 8 个 RTL 的原始字节副本；不应另外加入工程编译列表。`R5_project_template.al` 保留了 R5 绝对路径，复制后必须重定向到新快照并逐一验证 `.//File` 路径。`manifest.json` 包含补丁、源文件、DB、报告与 bit 的哈希；`RTL差异与哈希表.md` 提供便于审阅的完整源清单。

已验证：原 R5 输入 manifest 的 135 个文件全匹配；`src/constraints` 相对基线只有这 8 个 RTL 差异；两份 patch 经临时基线目录 `git -c core.autocrlf=false apply --check`、实际应用和逐文件 LF hash 核验通过。这是恢复补丁的验证，没有重新运行 FPGA 编译或 RTL 仿真。

补丁不包含生成的 back_annotation、项目锁文件、固件、数据库或 SD 卡媒体镜像，也不带入其他用户工作区修改。历史报告和 bit 仍保留在原 R5 目录，位置见 manifest 与执行教程。
