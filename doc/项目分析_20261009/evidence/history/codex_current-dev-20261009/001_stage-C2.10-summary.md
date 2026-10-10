# VinylFPGA C2.10 黑胶几何渲染资源优化摘要

current_stage: C2.10
goal: 在不改变黑胶层接口、播放态切换和视频像素节拍的前提下，去除黑胶几何距离计算中的两个可变乘法器，降低 DSP/LUT/MSlice 压力并改善门级 Setup QoR。

change:
- `src/display/vinyl_renderer.v` 将 `dx*dx + dy*dy` 的欧氏距离平方判定改为 `max(|dx|,|dy|) + min(|dx|,|dy|)/4` 的定点八边形近似。
- 保留 `hit`、`rgb_in/rgb_out` 透传、盘体、标签、外沿、高光、phase 旋转和 enable/de 关闭语义；纹理改用近似径向距离的分段位生成。
- 第 16 代曾尝试 3/8 系数，资源下降但 WNS 退化到 -10.431 ns，未提交；第 17 代收敛为单移位加法版本后再统一记录。

verification:
- `tb_vinyl_renderer`：输出 `TEST_PASS vinyl_renderer_s6`。
- `tb_s6_video_layer`：输出 `TEST_PASS s6_video_layer 320x240 FIFO window KEY08 frame boundary rollback`。
- `tb_s5_play`：输出 `TEST_PASS s5_play_timebase_lrc`。
- `tb_c1_param_core`：输出 `TB_C1_PARAM_CORE_PASS`。
- `tb_lrc_dynamic_select`：输出 `TB_LRC_DYNAMIC_SELECT_PASS hits=17`。
- `tb_lrc_osd_equiv`：15 个完整 800x525 帧、12602100 次相位比较通过。
- SynthPilot 第 17 代 `td_build end_step=opt_gate`：通过；未执行 place/route/bitgen。

qor_comparison:

| 指标 | C2.9 / 第15代基线 | C2.10 / 第17代 | 变化 |
|---|---:|---:|---:|
| LUT（器件总量） | 16881/19600 | 16809/19600 | -72 |
| MSlice | 1792/4900 | 1772/4900 | -20 |
| 综合切片 | 2757 | 2729 | -28 |
| DSP | 17/29 | 15/29 | -2 |
| BRAM | 50/64 | 50/64 | 不变 |
| Setup WNS | -9.951 ns | -8.991 ns | 改善 0.960 ns |
| Setup TNS | -326736 ps | -302347 ps | 改善 24389 ps |
| Setup 违例端点 | 82 | 73 | -9 |
| Hold WNS | 0.471 ns | 0.471 ns | 不变 |
| Hold 违例端点 | 0 | 0 | 不变 |

decision:
- C2.10 作为生产 RTL 资源/门级时序优化通过软件回归和 `opt_gate` 门禁，可提交并等待人工显示验收。
- 当前 Setup WNS 仍为负，不能宣称已完成布局布线时序收敛；本阶段不生成 bit，不覆盖用户已验证固件。
- 只有在后续物理实现取得正 Setup WNS、零 Setup/Hold 违例并完成人工烧录验收后，才允许把该优化放行到最终 bit。

manual_acceptance:
- 在用户侧综合/布局布线前，确认黑胶模式仍能显示盘体、中心标签、纹理和移动高光；盘外区域保持输入像素，不出现整屏覆盖。
- KEY08 在 MV/黑胶间切换只在帧边界生效；暂停时黑胶停止推进，恢复后继续转动。
- 含 MV、无 MV、无效元数据和缺失资源的曲目分别确认：MV 正常显示、黑胶回退显示、无黑屏死锁。
- 确认 C2.9 既有歌词动态/静态回退、C1 参数、S5 播放暂停和 S6 MV 窗口行为未回归。

next_action: 由用户使用当前提交运行完整 place/route；若仍有负 Setup，基于新的 route 关键路径继续做单变量物理可归因优化，未满足时序门禁前不生成 bit。
