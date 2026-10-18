# Physical flow 修复与验证（2026-10-18）

> 本文记录 21:37 的首轮修复。22:14 已针对工程配置回写导致的复发重新完整构建，最新固件哈希和证据见 [VinylFPGA工程配置回写修复_20261018.md](VinylFPGA工程配置回写修复_20261018.md)。

## 范围与基线

- 在现有 `main` 分支修改，不回退历史提交，不自动提交或烧录。
- 用户确认的可用提交：`da9d07a0bd864a915c01a329df17e99ea4848118`。
- 开始时 HEAD：`2ee987d7da8a2507e6e81129cbbc98446ee0df8c`。
- 两个提交之间主要是 `cover_navigation.v` 的早期浏览操作暂存和顶层的播放确认暂存；这些功能保留。
- 工作区原有 LED 媒体故障提示、文档、回标文件和仿真目录等修改保留。
- 器件：EG4S20BG256；TD：6.2.168116；源文件、引脚和时钟约束保持原工程入口。

## 直接失败证据

原 `prj/VinylFPGA_Runs/phy_1/seed_6/run.log` 末尾：

```text
PHY-8023 ERROR: Location: (x25y56_n2beg4), nets: mux82_syn_2[18] u_media_video_reset/s2
RUN-8102 ERROR: Incremental route failed.
```

这是 `opt_route` 的物理布线资源争用，尚未进入 BitGen。原 run 的物理资源为 LUT 17714/19600（90.38%），Slice 9570/9800（97.65%），BRAM9K 64/64；低余量使小幅网表变化也可能导致固定 seed 失败。存在 `pr.db` 不能证明布线成功，必须同时核对错误、marker 和最终时序。

失败 run 完整副本：`.codex_tmp/physical_repair_20261018/failed_runs/`。
修改前源码和约束快照：`prj/resource_opt_verified_20261005/physical_repair_before_20261018/`。

## 对照与取舍

| 对照 | 结果 | 决策 |
|---|---|---|
| 原网表，seed 6，pack_effort=high | Slice 9232（94.20%）；普通布线仍有歌词局部网络冲突 | 保留装箱优化收益，不能单独放行 |
| SD/video 复位 max_fanout=128 | Slice 9636（98.33%），仍有布线冲突 | 撤销，未进入交付源码 |
| high 装箱、seed 6、routability | 布线完成，setup -0.523 ns，hold +0.030 ns | 不能放行；无须把实验参数留在工程 |
| high 装箱、seed 6、routability + greedy | 未改善上述最终时序 | 不采用 |
| high 装箱、seed 3、普通布线 | Slice 9220（94.08%）；setup -0.058 ns，TNS -0.058 ns，1 个违例端点；hold +0.024 ns | 定位并优化唯一剩余 Seek 路径 |
| Seek 优化后，原工程 R2 | 已生成 bit；Slice 9214（94.02%），Seek 路径通过，但 FAT32 流读取器还有 1 个 -0.190 ns 端点 | 不放行该轮 bit |
| R3：增加 place opt_timing=high | Slice 9210（93.98%）；出现另一处局部布线冲突 | 组合 routability，保持 RTL 和综合结果不变 |
| **R4：high 装箱 + high 布局时序优化 + routability + seed 3** | **setup +0.143 ns、hold +0.024 ns，TNS=0，违例端点=0；Slice 9210（93.98%）** | **最终原工程结果通过，生成 bit** |

最终参数选择依据同输入实测，不把某个历史 seed 视为适用于所有后续网表的保证。

## 代码及工具修复

1. `src/audio/seek_controller.v`：报告指向 `sum_reg -> clamped -> work_base`。将宽有符号范围比较展开为符号判断、32 位以上溢出判断和两个 16 位分段比较；为比较选择控制指定 TD 的 `max_fanout=8`，允许局部分发。保留原始钳位范围、结果、流水状态及处理拍数。
2. `prj/VinylFPGA.al`：`area_prior`、`pack_effort=high`、`place opt_timing=high`、`route effort=routability`，单一确定性 MultiSeed=3。未改板级引脚、PLL 频率或时序例外。
3. `tools/configure_optimized_project.tcl`：读取工程实际 seed，配置后校验落盘值；捕获变量的 `regexp` 独立执行，避免本机 TD 在嵌套表达式中读空捕获变量。删除不必要的私有 place seed 设置。
4. `tools/verify_gui_runs.py`：从 `.al` 读取实际 seed；保留 marker、日志错误、产物新鲜度、最终 setup/hold、输入哈希、GUI 选中结果哈希校验，移除固定 seed 5 的限制。
5. `tools/build_optimized_project.ps1`：保存配置日志，输出 GUI 选中结果的标准 bit 路径。
6. `sim/tb_playback_page_glyph_select.v`：补齐环形歌词缓存增加的 `row_base_slot` 测试桩端口，恢复实际显示专项测试。

## 验证证据

- `sim/tb_seek_clamp.v`：修改前通过 120000 组检查；优化后的最终测试通过 120012 组边界/随机检查，包括负数、零、等于上限、上限两侧、超过 32 位的正数。
- Seek 回归：`tb_x2_seek`、`tb_x2_seek_wav` 通过，覆盖首尾钳位、空媒体、忙时累积、100 次往返、clear 优先、时基加载及扇区内样本跳过。
- `tools/test_verify_gui_runs.py`：6/6，通过 seed 5/6、失败 marker、负时序、过期 bit、选中副本不匹配检查。
- `tools/run_audio_cache_regression.py`：最终 32/32 通过，且结果文件中的输入哈希全部与当前源码一致。
- 额外 CDC、媒体生命周期、四封面调度等专项通过。
- 旧 `verify_s7_acceptance.py` 的部分测试仍依赖已删除的缩略图接口；旧顶层测试还缺少缓存 primitive 的仿真配置。未通过这些历史测试，不宣称旧总套件全绿。

证据目录：`.codex_tmp/physical_repair_20261018/`；32 项回归：`audio_regression_final/results.json`；Seek 回归：`seek_after/`。

## SynthPilot 与原工程验证

已通过用户指定的 `curl.exe -sL https://www.synthpilot.dev/llms.txt` 获取说明，并实际调用 SynthPilot 的 TD 发现、工程打开、器件加载、elaborate、RTL/Gate 综合等接口。

本机 SynthPilot 的多运行 `td_open_run` 发生 TD 进程退出；其单次综合入口默认映射也与原 `.al` 的 `area_prior` 不同，单次默认综合的 LUT 占用达到 97.58%。因此最终交付必须使用原 `.al` 的官方运行管理器，避免以不同默认策略的结果替代 GUI 工程验证。

综合日志来自原工程 R2；最终物理实现、选中结果和 BitGen 来自原工程 R4。R2/R4 的全部 RTL/约束文件集和 SHA256 完全一致，只调整物理策略时复用有效综合数据库。

最终构建快照、物理运行日志及放行记录：`prj/resource_opt_verified_20261005/physical_repair_gui_20261018_r4/`。其中 `release_signoff.json` 记录输入快照校验、main 分支、HEAD、bit 哈希和最终时序；`post_signoff.log` 记录从本轮选中 `pr.db` 重新读取后的时序/结构检查及参数导出。

## 最终交付状态

**允许由 anlogic-place-route 放行到 anlogic-create-bitstream；BitGen 已完成，具备进入后续下载调试的前提。**

| 项目 | 最终结果 |
|---|---|
| 分支 / HEAD | main / `2ee987d7da8a2507e6e81129cbbc98446ee0df8c`，修复保留为工作区修改，未自动提交 |
| GUI 选中固件 | `prj/VinylFPGA_Runs/phy_1/VinylFPGA.bit` |
| 对应 seed 固件 | `prj/VinylFPGA_Runs/phy_1/seed_3/VinylFPGA.bit`，与选中副本 SHA256 相同 |
| bit 大小 | 676184 字节 |
| bit SHA256 | `4c4512c1c211ffe51b87955186203f06d511836436a3df8eb3953069e11325d5` |
| setup WNS / TNS | +0.143 ns / 0 ns |
| hold WNS / TNS | +0.024 ns / 0 ns |
| setup / hold 违例端点 | 0 / 0 |
| 物理 Slice | 9570 → 9210，97.65% → 93.98%，减少 360 个 Slice |
| 物理 LUT | 17714 → 17659，90.38% → 90.10% |
| 综合 LUT | 17188 → 17072 |
| RAM | BRAM9K 64/64；BRAM32K 1/16，未增加 RAM 使用量 |
| 结构检查 | no clock=0；invalid constraint=0；combinational loops=0 |
| 运行 marker | seed_3 的 opt_place / opt_route / bitgen 和 phy_1 的 MultiSeed 均有本轮 end marker；无 error marker |

最终报告及交付辅助文件均位于 `prj/VinylFPGA_Runs/phy_1/`：

- `VinylFPGA_place.timing`、`VinylFPGA_pr.timing`、`VinylFPGA_exception.timing`
- `VinylFPGA_pr.db`、`route.qor`、`route_flow.status`
- `signoff_timing.ts`、`signoff_constraints.rpt`、`signoff_area.rpt`
- `.bitgen_param.f`：本轮从有效路由库重新导出；未启用新的 probe/debugger，不以旧 `.bid` 作为本轮交付依据。

烧录使用上面的 GUI 选中固件。当前 TD GUI 若仍打开旧工程，请先重新打开 `prj/VinylFPGA.al` 以加载新策略，再执行 Run All。

可复现命令（项目根目录执行）：

```powershell
pwsh -NoProfile -File tools/build_optimized_project.ps1
python tools/verify_gui_runs.py
python -m unittest discover -s tools -p test_verify_gui_runs.py
python tools/run_audio_cache_regression.py --out .codex_tmp/audio_regression_new
```

上板验证不在本轮自动执行范围。I/O 约束仍缺少板外接口的完整 input/output delay 数据，不能以内部 STA 通过代替板级验收。
