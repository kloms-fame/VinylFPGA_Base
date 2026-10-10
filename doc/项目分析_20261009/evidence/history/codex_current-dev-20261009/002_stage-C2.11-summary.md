# VinylFPGA C2.11 WS2812 低资源灯效摘要

current_stage: C2.11
goal: 按资源优化执行方案 Task 11，将 WS2812 灯效从实时乘法和复杂动画状态收敛为 Off、16 档量化 VU、简单 Progress 与离散亮度查表，保留现有发送器和外部接口。

confirmed_constraints:
- 目标器件为 EG4S20BG256；工程入口仍为 `prj/VinylFPGA.al`。
- 不改变 `ws2812_effects` 的端口、DIP6 黑帧关断语义、KEY10 模式循环和 `ws2812_driver` 800 kHz 发送器。
- 本批次只修改 WS2812 灯效逻辑锥和对应验收口径，不修改 SD、音频、MV、歌词和 HDMI 主链。

change:
- 删除彗星、充能、吸收、衰减等运行时状态。
- VU 使用 `level[7:4]` 量化为 16 档，Progress 保留 0～8 点亮范围并增加固定头部颜色。
- 颜色按固定类别查表；亮度使用 `param_csr` 已定义的离散档位常量查表，不再使用 3 路可变通道乘法。
- 独立仿真时亮度端口未连接时，查表默认回退到 255 档，避免旧夹具出现 X 扩散。
- `sim/tb_ws2812_x1.v` 更新为 C2.11 的简单 VU/Progress 验收口径。

verification:
- `tb_ws2812_x1`：输出 `TEST_PASS ws2812_x1`。
- `tb_expansion_s1`：输出 `PASS UART idle, 12 J2 keys, recovery, fault history, hotplug`。
- `tb_s5_play`：输出 `TEST_PASS s5_play_timebase_lrc`。
- `tb_s6_video_layer`：输出 `TEST_PASS s6_video_layer 320x240 FIFO window KEY08 frame boundary rollback`。
- `tb_c1_param_core`：输出 `TB_C1_PARAM_CORE_PASS`。
- SynthPilot 第 20 代 `td_build end_step=opt_gate`：通过。

qor_comparison:

| 指标 | C2.10 / 第17代 | C2.11 / 第20代 | 变化 |
|---|---:|---:|---:|
| LUT（器件总量） | 16809/19600 | 16799/19600 | -10 |
| MSlice | 1772/4900 | 1763/4900 | -9 |
| 综合切片 | 2729 | 2711 | -18 |
| 寄存器 | 10902 | 10880 | -22 |
| DSP | 15/29 | 13/29 | -2 |
| BRAM | 50/64 | 50/64 | 不变 |
| WS2812 目标路径余量 | 约 0.570 ns | 5.735 ns | 改善约 5.165 ns |
| 全局 Setup WNS | -8.991 ns | -10.431 ns | 退化 1.440 ns |
| 全局 Setup TNS | -302347 ps | -317227 ps | 退化 14880 ps |
| 全局 Setup 违例端点 | 73 | 73 | 不变 |

decision:
- C2.11 的 WS2812 局部资源和目标路径结果达到优化方向：DSP、MSlice、寄存器下降，WS2812 关键路径余量显著增加。
- 全局 Setup WNS/TNS 退化，因此本阶段只能作为“资源优化候选提交”，不能宣称全局时序改善或 bit 可交付。
- 现有 `tb_x1x2_lights`、`tb_ws2812_context_equiv` 属于旧彗星/充能或旧 O4 等价口径，C2.11 不以它们作为新功能放行依据；必须使用本摘要列出的新口径和板级清单。
- 当前仍不执行 place/route/bitgen，先由用户决定是否接受简单灯效行为，再基于 route 结果判断是否保留该批次。

manual_acceptance:
- WS2812 默认 Off：上电不误亮，`ws_data` 保持低电平。
- KEY10 循环：Off→VU→Progress→Off，各模式只在下一次整帧发送时生效。
- VU：低、中、满量程分别观察 16 档量化的点亮数量、绿/黄/红分段及亮度调节。
- Progress：进度 0、1、4、8 分别观察点亮范围，末端固定头部颜色不越界。
- DIP6 关闭：必须完整发送一帧全黑后停止；重新开启后恢复当前模式。
- 用户烧录前必须确认灯效简化符合外观预期；若不接受简化效果，回退本提交而不影响 C2.10 黑胶优化。

artifacts:
- `src/io/ws2812_effects.v`
- `sim/tb_ws2812_x1.v`
- `doc/stage-C2.11-summary.md`

next_action: 等待 C2.11 的人工灯效确认；若接受，下一步用当前版本执行 place/route 评估全局时序和路由拥塞，若不接受则回退 WS2812 变更并保留 C2.10。
