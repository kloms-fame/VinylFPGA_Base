# O0 基线冻结与复现记录

## 范围与状态

- 阶段：O0，冻结基线、可重复构建和验收记录。
- 状态：自动回归通过，完整原生 route 通过 timing 门槛；route overflow 未由保存的 TD final 报告提供，故物理门禁为 `UNVERIFIED`；板上人工验收未做。
- 工作树：`.worktrees/codex-opt-o0-o2`；执行分支：`codex/opt-o0-o2`。
- 父提交：`c70aa529cb5a9393c888ca0a3ec826cbe0760204`。
- 不包含 O1/O2 RTL 优化，不生成或下载本轮 bit，不写 Flash/TF 卡。

## 回归用例注册

`tools/verify_s7_acceptance.py` 注册 49 个生产用例；完整运行另生成 `tb_s7_wav_wrap` FIFO-wrap 压力用例，因此总计 50 项。四个顶层用例 `tb_s7_top`、`tb_opt_osd_bypass`、`tb_opt_metadata`、`tb_visual_feedback_top` 显式编译 `src/top_tf_hdmi_audio.v` 和 `sim/integration/vendor_control_stubs.v`。原生成的 wrap 用例保留。

`--output` 默认仍是 `sim/s7_acceptance_fix`，新路径递归创建；accepted 标记存在时拒绝覆盖。O0 全量回归日志目录为 `sim/plan_runs/O0_full`（本地忽略目录）。

## 构建

- 正式轮次：`opt_o0_baseline_r4`。r1/r2/r3 是工具门禁补齐期间的独立审计构建；指标完全一致，O0 归档以 canonical manifest hash 校验通过的 r4 为准。
- 工具：Tang Dynasty 6.2.168116。
- 配置：`area_prior`，place seed 5，完整 gate/place/route、显式 `fix_hold`、final timing。
- 构建命令：`python tools/resource_opt_round.py opt_o0_baseline_r4`，随后 `python tools/collect_round_metrics.py opt_o0_baseline_r4 --freeze-manifest --bit <现存基线bit路径>`，以及 `python tools/build_verified_round.py opt_o0_baseline_r4 --seed 5 --map-mode area_prior`。
- EDA 报告及数据库：`prj/resource_opt_verified_20261005/opt_o0_baseline_r4/`（本地忽略目录）。完整输入快照为本目录 `build_manifest.json`；manifest SHA-256 为 `e2ba311b5bb9d35dca46be276d605caca871c35e9906320459281cd87e26de86`，含 595 项工作树输入哈希及 110 项实际轮次快照哈希（含重定位 `.al`、源代码、约束和 `inputs.sha256.json`）。冻结后工作树文件 hash 校验为 0 mismatches。指标读取时重算 canonical JSON SHA-256，并验证 schema 必需字段；损坏或缺项会拒绝采集。
- 本轮 `final_verbose.area` 由统一构建脚本在 route/fix_hold 后直接导出；时序来自本轮 `final.qor`。报告和数据库均属于 r4。

## final 指标

| 资源/时序 | 结果 |
|---|---:|
| LUT / REG | 13,734 / 9,400 |
| Slice / MS / LS / PLB | 7,541 / 3,758 / 3,783 / 2,360 |
| BRAM9K / BRAM32K / DSP | 42 / 0 / 15 |
| Setup WNS / TNS / violations | +121 ps / 0 ps / 0 |
| Hold WNS / TNS / violations | +24 ps / 0 ps / 0 |
| Route overflow | `null`，TD 保存的 final 报告没有该字段 |

因此本轮完成了完整 route 和时序门槛，但**不宣称 overflow=0，也不将本轮标记为完整物理验收通过**。机器可读指标见 `metrics.json`；摘要见 `metrics.md`。

## 基线固件和卡镜像

- 现存本地 bit：`prj/VinylFPGA_Runs/phy_1/VinylFPGA.bit`，SHA-256 `DC81F4C11DA565DECD8BD13D86CF27DD295A9A3084E0A668B0D04BDD3D8F75A2`。同目录 `best_result/VinylFPGA.bit` 哈希相同。
- 当前候选卡镜像 `doc/资源/sd卡/card_S6.img`，SHA-256 `A8BE9D182A9B206A39F8BAFFE5277FE93FD1308221FFED14D7C0AF70611B42EF`。
- 索引镜像 `doc/资源/sd卡/card_A.img`，SHA-256 `A7103F4072A90B59D69555354A6C7A0E686C8ECE84D71CC5D4289608ABCAADFC`。
- 这些只是本地文件哈希；当前板上 bit 与卡片未绑定，也没有当前实物基线画面记录。

## 执行结果

- 完整回归：49 个注册生产用例 + 1 个 FIFO-wrap 压力用例，全部 PASS。
- `python tools/test_collect_round_metrics.py`：6 项 PASS。
- `python tools/test_vinyl_packer.py`：24/24 PASS。
- `python tools/test_s6_assets.py`：PASS。
- `python tools/verify_lrc_assets_repro.py`：PASS。
- 指标解析样本：实际读取主工作区原生 `native_area_seed5/final_verbose.area` + `final.qor`，以及 MCP AUTO `mcp_auto/audit_20261009_route.area` + `audit_20261009_route.qor`。验证 ps/ns 换算与 AUTO/area_prior 策略不一致拒绝比较；两份历史样本均未提供 overflow 字段，故记录未知。10 项自动化测试验证缺字段拒绝、manifest 被改后 hash 不符拒绝、工具版本与构建快照约束不一致拒绝比较，且约束哈希来自本轮快照而非当前工作树。

## 路径说明

原始分析和证据位于主工作区未跟踪目录 `doc/项目分析_20261009/`，本隔离工作树内没有这些未跟踪文件。读取了主工作区证据目录的原生/MCP 报告用于格式验证，没有移动、复制进证据归档，也没有把主工作区未跟踪资料加入 Git。本记录与 manifest 仅保存结果和路径/哈希。
