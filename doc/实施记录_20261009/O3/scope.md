# O3 蜂鸣器逻辑减负结论

## 目标与结论

目标是以 `24b680faf367e4e6f8a51b99aab38a86798f895d` 为基准减少蜂鸣器资源并保持输出逐周期一致。评估后标记为 `skipped_after_measurement`：当前 RTL 保持父版本原样，不提交生产 RTL 改动。

## 设计

- 保留事件检测、优先级/抢占、启停边沿、DIP 双阶段音、IR 音调选择、旋钮方向/来源音调、各事件时长及复位/禁音语义。
- 测试过参数化窄计数器和等价终值比较两种候选，并以父版本输出逐周期对照。
- 参数化窄计数器候选 route 得到 setup WNS −153 ps、1 条违例；该候选被拒绝。
- 终值比较候选 route 通过，但在完全相同的父版本输入/工具/seed 下，总 LUT +75、Slice +31、setup WNS −18 ps，故不采用。
- `24b680f` 父版本同配置完整 route 为 setup +121 ps、hold +24 ps、TNS/违例 0。最终生产 `src/io/buzzer_feedback.v` 与该父版本字节一致，既有旋钮/DIP/按键/IR 声效未变。

## 验收

- 使用冻结版本作参考，覆盖所有事件、方向、IR动作、事件优先级/抢占、禁音/复位及 3,000,000 周期长音；候选公开输出每周期完全相等。
- 对候选和精确父版本分别运行相同配置的完整 gate/place/route/fix_hold/final；比较后拒绝所有未达资源收益的候选。
- 不生成 bitstream；bit 由用户后续自行生成。

## 文件边界

生产 RTL：`src/io/buzzer_feedback.v` 保持原样。保留 `tools/verify_buzzer_o3_equivalence.py` 和本阶段独立测量记录。不得更改用户已有构建报告或未跟踪资料。

## 构建差分

父版本快照：`prj/resource_opt_verified_20261005/opt_o3_parent_24b680_r1/`。

拒绝的候选快照：`opt_o3_preserve_buzzer_r1/`（负 setup）；`opt_o3_terminal_eq_r1/`（资源增加）。这些快照位于 Git 忽略的构建目录，不纳入提交。
