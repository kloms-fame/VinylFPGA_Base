# O3 蜂鸣器计数器减负实施计划

**目标：** 在 `24b680f` 的蜂鸣器效果不变的条件下评估计数器和终值判断减负；只有相同配置测出净收益才保留。

**评估：** 分别测量参数化计数器收窄与等价终值比较候选。以 Git 中父提交 RTL 作为黄金模块，自动逐周期对比 `buzzer_n` 和 `busy`。

**范围：** `src/io/buzzer_feedback.v`、`tools/verify_buzzer_o3_equivalence.py`、本阶段记录。不得更改蜂鸣器听感/节拍，不生成 bitstream。

## 步骤

- [x] 新建冻结父版本输出等价检查，先在原 RTL 上确认“计数器未收窄”断言失败。
- [x] 测试收窄计数器候选；逐周期检查通过，但完整 route setup −153 ps，拒绝。
- [x] 测试等价终值比较候选；24 组配置及完整 3,000,000 周期事件逐周期输出一致。
- [x] 用同配置 seed5、area_prior 完整构建精确父版本和候选。
- [x] 对比资源/时序，确认比较候选 LUT +75、Slice +31、setup WNS 下降18 ps；父版为 +121/+24 ps、0违例，候选不采用。
- [x] 生产 RTL 回到父提交原样；S7 回归已全通过，bit 由用户自行生成。

**本地命令：**

```powershell
python tools/verify_buzzer_o3_equivalence.py
python tools/verify_s7_acceptance.py
```

**出口：** `skipped_after_measurement`。蜂鸣器声音和生产代码保持 `24b680f` 基线。两候选完整 route 与父版证据保留在独立构建目录；不生成 bitstream。
