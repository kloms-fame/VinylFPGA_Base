# VinylFPGA.al 配置回写复发修复（2026-10-18 22:14）

## 结论

已在 main 上使用原始 `prj/VinylFPGA.al`，经 TD 6.2.168116 原生运行管理器从综合重新执行到 bitgen，生成本轮有效固件。重新打开、关闭工程后，配置和结果校验仍通过。

- 固件：`prj/VinylFPGA_Runs/phy_1/VinylFPGA.bit`
- 对应 seed：`prj/VinylFPGA_Runs/phy_1/seed_3/VinylFPGA.bit`
- 大小：676184 字节；两份文件 SHA256 相同。
- SHA256：`ee93db0ad0be0d543fc64661d29e56b8faa2a35ce393a090a74a28887001336a`
- Setup WNS +0.143 ns、Hold WNS +0.024 ns，TNS 均为 0，违例端点均为 0。
- Slice 9210/9800，LUT 17659/19600，BRAM9K 64/64，BRAM32K 1/16。
- no clock、invalid constraint、combinational loops 均为 0。
- 允许放行到后续下载调试；本轮没有执行烧录或板上功能验收。

## 本次失败证据

失败的 seed 6 于 21:52:34 启动，物理流程结束时报告：

```text
PHY-8023 ERROR: Location: (x4y25_local2)
  u_playback_page/direct_glyph_b[5]_syn_4
  u_playback_page/u_lrc_five_osd/sub1_syn_3[3]
PHY-8023 ERROR: Location: (x5y31_w2beg4)
  u_playback_page/direct_glyph_b[0]_syn_24
  u_playback_page/u_playback_background/add0_syn_97
PHY-8023 ERROR: Location: (x13y24_w2beg4)
  sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db/mux253_syn_2[5]
  sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db/mux256_syn_2[29]
RUN-8102 ERROR: Incremental route failed.
```

这是 opt_route 失败，尚未到 bitgen。不能把先前 seed 3 留下的 bit 或 signoff 报告作为该次 seed 6 的成功结果。

本轮开始时 `.al` 只有 `gate map_mode=area_prior`；`pack_effort=high`、`place opt_timing=high`、`route effort=routability` 均缺失，MultiSeed 回到 6。全部 139 个源码/约束文件 SHA256 与先前成功的 R4 一致。

配置恢复后，22:11:18 的磁盘 `.al` 又短暂回到旧配置，同时原来打开该工程的 TD GUI 进程退出。这个现象与旧窗口关闭时回写内存配置相符；没有证据断言是用户手动改动。保存了回写文件副本，随后恢复磁盘配置。运行中的本轮构建已加载正确策略，实际生成的 syn/phy `.prj` 也证实使用正确参数。

失败运行和回写副本：`.codex_tmp/al_repair_20261018_repeat/`。

## 修复内容

1. 原 `VinylFPGA.al` 持久化以下参数：

   | 阶段 | 参数 |
   |---|---|
   | syn_1 | map_mode=area_prior；pack_effort=high |
   | phy_1 | place opt_timing=high；route effort=routability |
   | MultiSeed | 单一确定性 seed 3；生成 bit；最终选中 seed 3 |

2. `configure_optimized_project.tcl` 关闭工程后检查关键策略确实落盘，防止仅配置了内存状态。
3. `verify_gui_runs.py` 检查 `.al` 中对应 run 的四项策略，同时继续检查 seed、完成标记、错误标记、新鲜度、最终时序、输入哈希和选中结果副本。
4. `build_optimized_project.ps1` 在启动构建前增加策略落盘校验。
5. 结果校验测试增加 seed 3、策略缺失和策略被改变的案例。新案例先在旧实现上失败，再在修复后通过。

本轮没有修改任何 RTL、引脚约束或时序约束，也没有实施 MV/歌词功能优化。

## 新鲜验证证据

- 完整重跑：`read_design -> opt_rtl -> opt_gate -> opt_place -> opt_route -> fix_hold -> bitgen`，构建脚本退出码 0。
- `tools/test_verify_gui_runs.py`：9 项测试通过。
- Tcl 落盘保护：有效配置通过，缺少装箱策略和 seed 不一致两种输入均拒绝。
- PowerShell 构建脚本语法检查通过，新增构建前策略校验独立执行通过。
- 从本轮 routed DB 重新导出时序、结构检查、面积、route_flow.status 和 `.bitgen_param.f`。
- 新 TD 进程重新打开并关闭 `.al`，随后再次执行结果校验通过。
- 当前源码、约束与构建前的 139 个文件哈希完全一致。

本轮完整证据目录：

`prj/resource_opt_verified_20261005/al_project_repair_20261018_repeat/`

包含：

- `configuration.log`、`pipeline.log`、`post_signoff.log`、`reopen_project.log`
- `release_signoff.json`、`bitstream.sha256`
- 构建前源码/约束及哈希、最终 `VinylFPGA.release.al`
- 完整归档的 `VinylFPGA_Runs`，含本轮综合/物理日志、数据库、完成标记和固件
- 本轮重新导出的 signoff、route 状态与 bitgen 参数

bitgen 的 `time_info=on`，本轮 bit 哈希与上一轮不同；不要继续使用旧 SHA256 验证这次文件。

## 继续使用原工程

重新打开 `prj/VinylFPGA.al` 后使用 Run All。不要从仍持有旧配置的窗口保存回该工程；需要重新编译时先确认 MultiSeed 为 3，以及上面列出的三项 high/routability 策略仍在。

也可在项目根目录执行：

```powershell
pwsh -NoProfile -File tools/build_optimized_project.ps1
python -B tools/verify_gui_runs.py
```

新一轮构建会替换标准 Runs 输出；本次交付的完整归档仍保留在上述证据目录。本结论只覆盖当前源码和配置，之后改变 RTL 仍需重新完成物理时序和 bitgen 验证。
