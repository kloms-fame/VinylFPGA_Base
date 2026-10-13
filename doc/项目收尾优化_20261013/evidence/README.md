# 收尾优化证据索引

本目录为小型报告/日志副本；原生数据库和bit位于 `prj/resource_opt_verified_20261005/closure_opt_20261013_r5/`，源/约束清单 `inputs.sha256.json` 与当前代码一致。主说明见 `doc/项目收尾资源优化与时序收敛完整报告.md`。

- `release_manifest.json`：最终固件绝对路径、SHA256、大小、基线提交、seed/map_mode及板级待验收状态。
- `round_metrics.json`：原3B与r1～r5同口径最终指标；r2走线失败，没有final指标。
- `closure_opt_20261013_r5_final_verbose.area`：MSlice/LSlice/PLB及物理LUT/REG，最终面积结论以此为准。
- `closure_opt_20261013_r5_final.qor`、`..._final.constraints`：Setup+140ps/Hold+22ps、TNS0、结构检查及原有IO/PLL提示。
- `closure_opt_20261013_r5_pipeline.log`、`..._bitstream.sha256`：后台bitgen成功及摘要。
- `closure_verification_20261013_final_*`：第三轮完整29项RTL、PC11项及镜像回读日志。
- `closure_verification_20261013_r4_final_*`：INDEX提前比较改动的5项针对性检查。
- `closure_verification_20261013_r5_final_*`：最后7项相关检查，含完整新旧loader/INDEX逐周期差分与10007偏移比较向量。
- `mcp_closure_20261013_*`：第1/2/4轮MCP auto综合分析记录，与native area_prior指标分开。
- r1～r4原生结果和r2失败摘录：保留尝试过程，不能拿未通过结果烧录。

本轮优化取得PLB减少和时序收敛，最终LUT/MSlice有所增加，详见主报告取舍表。软件/构建通过不代表新的板级验收通过；Git新优化提交待用户验收。
