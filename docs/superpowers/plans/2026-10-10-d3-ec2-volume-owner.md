# D3 EC2 与唯一音量源实施计划

> **For agentic workers:** 按本计划逐项实施并复核；本次直接在用户指定的 `main` 工作区执行。

**目标：**让 EC2、播放态 KEY/IR 共用唯一 VOL 状态，同时保留 KEY/IR 原有播放态门控和 EC1 Seek 行为。

**架构：**50 MHz 域的单写口 CSR 持有 VOL。EC2 累计步数在 50 MHz 域逐步重放；`play_ctrl` 在 SD 域确认 KEY/IR 意图是否被 PLAY 接受，再经有序小型 CDC FIFO 回到 CSR。CSR 的音量更新经 bundled-data 快照跨至视频音频增益链。

**技术栈：**Verilog-2001、Anlogic Tang Dynasty、SynthPilot MCP。

---

## 文件边界

- 新建 `src/io/ui_ms_tick.v`：50 MHz 共享 1 ms 使能脉冲。
- 新建 `src/io/ec2_param_controller.v`：消费路由后的 EC2 步数/按压，管理 VOL 的 SELECT/ADJUST、快速计数差重放和超时。
- 新建 `src/io/ui_param_csr.v`：唯一 VOL 状态、0～255 饱和和 16 级步进。
- 新建 `src/io/volume_intent_bridge.v`：SD 域已接受的 up/down 意图到 50 MHz 域的有序异步 FIFO。
- 复用 top 中既有 `cdc_bundle_latest`：将 CSR 音量从 50 MHz 控制域原子送往 video 音频域，避免重复封装 CDC。
- 修改 `src/audio/play_ctrl.v`：保留播放态门控与事件优先级，移除本地 VOL 状态，输出已接受的方向意图。
- 修改 `src/top_tf_hdmi_audio.v`：实例化新模块、仲裁 CSR 请求、把 CSR 快照接入音频增益。
- 修改 `prj/VinylFPGA.al`：登记新 RTL，避免 TD 将模块解析为 black box。
- 新建 `doc/实施记录_20261009/D3/`：接口合同、输入清单、SynthPilot 结果和人工验收清单。

## 执行步骤

1. 对照 D3 需求和现有调用点，冻结 CSR `valid/id/op/value`、桥接请求优先于 EC2 的同拍仲裁、CDC 两侧复位及 8 项 FIFO 深度；依据 KEY 消抖、NEC 最短完整帧与 150 ms repeat 节流给出低于 170 项/秒的保守输入上界、最多 3 项的入口突发与 FIFO 容量余量。
2. 实现共享 ms_tick、VOL CSR、EC2 控制器及快照 CDC。累计计数按模 16 位差重放；边界仍计 activity；同拍 activity 优先于超时隐藏。
3. 实现方向意图异步 FIFO，并将 `play_ctrl` 的本地音量更新替换为保留原播放态接受条件的 up/down 意图脉冲。
4. 顶层接入 CSR 单写口：每拍最多消费一个请求；同拍时先消费播放域桥接项，EC2 请求保持有效；EC2 饱和旋转仍刷新活动计时；EC2 与播放域桥接都写入同一个 VOL 状态；音频只接收 CSR 快照；EC1 Seek 与媒体静音/淡变链不改语义。
5. 登记工程文件、逐项审阅 RTL/CDC/复位和约束，再通过 SynthPilot 构建至 `opt_gate` 并检查资源/时序报告；不运行 bitgen。
6. 记录构建输入哈希、构建阶段、面积/时序结果和限制，给出 EC2、KEY/IR、边界静音、EC1 Seek、切歌暂停/恢复的人工验收步骤。

## 放行条件

- 工程清单中的新模块均被 TD 解析，D3 主工程在 `opt_gate` 无 black box 或综合失败。
- VOL 默认 200、步进 16、0～255 饱和，KEY/IR 在 BROWSE 不改音量且原有 PLAY 接受语义不变。
- EC2 各模式只调 VOL；EC1 Seek 不变；音频目标音量取自唯一 CSR 快照。
- 阶段报告明确区分“RTL 静态审阅”“TD 综合”“板上人工验收”；未生成 bitstream 或未人工验收时不得宣称整机通过。
