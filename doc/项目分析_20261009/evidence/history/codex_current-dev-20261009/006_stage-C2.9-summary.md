# VinylFPGA C2.9 回归口径修正摘要

current_stage: C2.9
goal: 修正 C1 参数入口迁移后遗留的 S5 音量回归断言，恢复连续可执行的人工验收前自动门禁。

change:
- `sim/tb_s5_play.v` 不再读取已停止维护的 `play_ctrl.volume` 作为音量功能结果。
- 新增测试专用 `param_csr` 实例，通过 `ext_vol_valid/ext_vol_dir` 覆盖默认值、步进、下限 0 和上限 255。
- 播放控制部分继续只验证播放态、暂停、选曲和切曲；参数核心完整行为由 `tb_c1_param_core` 复核。

verification:
- `python tools/verify_s7_acceptance.py tb_s5_play`：输出 `TEST_PASS s5_play_timebase_lrc`。
- `tb_c1_param_core`：输出 `TB_C1_PARAM_CORE_PASS`。
- `tb_lrc_dynamic_select`：输出 `TB_LRC_DYNAMIC_SELECT_PASS`。
- `tb_lrc_osd_equiv`：15 帧、12602100 次相位比较通过。
- SynthPilot 第 15 代 `opt_gate`：通过；生产 RTL 资源和时序与第 14 代一致。

production_boundary:
- 本阶段没有修改生产 RTL、没有修改 `prj/VinylFPGA.al` 的源文件组织，也没有改变音频、MV、SD、歌词显示或参数硬件路径。
- 仍使用 EG4S20BG256，当前门级资源为 LUT 16881/19600、MSlice 1792/4900、BRAM 50/64；Setup WNS -9.951 ns、TNS -326736 ps、82 个 Setup 违例。

decision: C2.9 验收基础已恢复，可继续进行生产 RTL 的时序/资源优化；当前仍不得执行 place/route/bitgen。

next_action: 以第 15 代门级结果为基线，针对 Setup TNS、违例端点和高扇出路径做一次单变量生产 RTL 优化，再统一运行回归和 SynthPilot 门禁。
