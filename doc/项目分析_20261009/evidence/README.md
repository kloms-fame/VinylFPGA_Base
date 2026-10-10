# 本轮分析证据

此目录是2026-10-09当前稳定源码的分析证据；不是新功能/固件发布包。

- `inputs.sha256.json`：原样复制的全部src/constraints字节哈希。
- `source_inventory.json`：249个主要源/脚本/约束逐文件记录。
- `doc_inventory.json`：新增分析前484个doc文件的完整指纹。
- `scan_all_text.json`：含doc参考代码的418项全文结构扫描。
- `documents/`：全部PDF/PPT文本提取、官方关键页图、素材联系表。
- `media_inventory.json`：307幅图解码尺寸/模式/哈希。
- `card_readback.json`：7张镜像的FAT目录/INDEX读取结果。
- `git_history.txt`、`git_reflog.txt`：全部分支历史与回退来源。
- `history/`：三份历史ref的相关分析/指标；index.json保存原始路径。
- `regression/`：本轮当前默认50项结果与日志，使用隔离副本。
- `test_vinyl_packer.py.log`：24/24，负例报错为预期。
- `test_s6_assets.py.log`：原始MV格式/连续性/损坏负例验证。
- `verify_lrc_assets_repro.log`：两次独立生成与冻结字形比对。
- `mcp_auto/`：SynthPilot TD gate/place/route/final；实际map_mode=AUTO。
- `native_area_seed5/`：显式area_prior、seed5、route后fix_hold完整复跑；包含入口、报告、日志、状态。

MCP报告原始根：`C:/Users/Renni/AppData/Local/Temp/synthpilot-td/reports/57d4befbc574f346`。

原生数据库原始目录：`C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2`。`database_locations.json`记录gate/place/routed等DB的实际位置、长度、哈希。大型DB保留在隔离工作目录，没有复制到doc。将来跨机器复跑应先恢复同哈希src/constraints，并重写隔离.al和Tcl入口的路径；该路径不是永久可移植发布合同。

成功轮次为`audit_area_seed5_v2`，`native_build.log`具有VERIFIED_ROUND_COMPLETE，final setup121ps/hold24ps，违例0。首次隔离入口因Project Name与.al文件名不一致失败，仅修隔离入口后复跑，未修改RTL。

本轮未执行bitgen、硬件下载、Flash和写卡；没有声称新的物理/逻辑结果经过板上人工验收。

主报告： [项目分析](../项目现状_赛题对照_资源优化与分阶段开发方案.md)。
