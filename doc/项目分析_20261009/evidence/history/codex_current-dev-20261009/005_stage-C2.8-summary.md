# VinylFPGA C2.8 动态歌词提交时序优化摘要

current_stage: C2.8
goal: 在不增加第二套字库和不改变像素节拍的前提下，降低动态歌词像素期的组合选择深度。

change:
- `lrc_osd` 动态模式不再在每个像素通过第二套 16 路字形多选器从 `dynamic_glyphs` 取字。
- `lyric_timeline` 完成后，经一级视频域事件延迟产生 `dynamic_load`，把当前行 16 个字形槽一次性写入原有 `glyph0..glyph15` 寄存器。
- 动态模式暂停静态行表扫描机，像素期继续使用原有 `char_sel` 和字形选择器；动态关闭时完整保留原静态扫描回退。

verification:
- `TB_LRC_DYNAMIC_SELECT_PASS`，动态字形命中 17 个有效像素。
- 原有 `tb_lrc_osd_equiv` 15 帧、12602100 次相位比较通过。
- SynthPilot 第 14 代 `opt_gate` 通过，无 elaboration、RTL 或 gate 失败。

qor_before_after:
- C2.7：LUT 16877/19600，MSlice 1792/4900，BRAM 50/64，Setup WNS -10.431 ns，TNS -317227 ps，73 个违例端点。
- C2.8：LUT 16881/19600，MSlice 1792/4900，BRAM 50/64，Setup WNS -9.951 ns，TNS -326736 ps，82 个违例端点。
- 结论：最差 Setup WNS 改善约 0.480 ns，但总 Setup TNS 和违例数量变差；这是有明确权衡的局部时序优化，不是全面收敛。

known_test_boundary:
- `tb_s5_play` 的音量 4 项断言仍要求已迁移前的 `play_ctrl` 内部调音量行为；当前工程音量由 `param_csr` 统一消费。该旧测试需单独维护，本阶段只将其作为已知回归基线问题记录。

decision: C2.8 RTL 和定向验证可提交，但不进入 place/route/bitgen；当前 Setup TNS、违例端点和资源余量仍需继续优化。

next_action: 修正旧音量回归的验证口径，并针对门级 Setup TNS/高扇出和物理实现拥塞继续做单变量优化；只有 route 时序、资源和 DRC 均通过后才生成 bit。
