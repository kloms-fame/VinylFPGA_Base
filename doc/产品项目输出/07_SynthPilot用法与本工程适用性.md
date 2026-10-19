# 07｜SynthPilot 用法与本工程适用性

## 1. 本次读取来源与当前状态

按照项目请求，本次使用以下命令完整获取 SynthPilot 官方面向大模型的说明：

~~~powershell
curl.exe -sL https://www.synthpilot.dev/llms.txt
~~~

下载内容共 120 行，全文保存在本地临时核对文件 .codex_tmp/synthpilot-llms.txt（不属于交付文档）。官方说明列出产品模型、安装配置、平台差异、AI agent 使用要求、数据边界和故障排查方法。联网内容可能随 SynthPilot 版本变化；本文记录本次读到的版本信息与时间，不替代网站上的实时文档。

本次只读调用 SynthPilot MCP：

- get_license_status：版本 1.4.0，Plan Pro，Anlogic 可用工具 90 个（另有 12 个 Max 专属工具）。
- td_connection_info：Tang Dynasty 6.2.168116 已发现；managed session 为 stopped，build idle、state empty，没有打开的项目或 run。

本次没有通过 SynthPilot 启动 TD、打开工程、导入器件、综合、布局布线或写出设计结果。该状态与仓库 2026-10-19 验收记录所述“此前完成完整构建”不是同一时间证据：MCP 当前没有正在运行的 TD 会话。

## 2. SynthPilot 产品模型摘要

官方 llms.txt 描述一个安装可支持 AMD Vivado、安路 Tang Dynasty 和 Intel Quartus，但每个 MCP server 进程只加载一个指定平台；当前许可证再过滤该平台可见工具。公开目录数量为：Vivado 510、Anlogic 102、Quartus 24；Free/Pro/Max 权限不同，Trial 在有效期内按 Pro 工具权限工作。Raw vendor Tcl escape hatch 不对所有计划开放。

官方建议：

1. 只调用当前连接 MCP 实际返回的工具，不推断其他平台/套餐工具可用。
2. 公开 catalog 用于理解能力概览，运行时 MCP schema 才是精确参数权威。
3. 使用结构化工具，不拼接厂商 Tcl。
4. 长流程采用生命周期工具并轮询终态后再读报告或关闭项目。
5. setup/doctor 仅做安装、注册和诊断，不代表打开项目、改变设计或启动构建。

Anlogic 平台使用受管理的 Tang Dynasty runtime，并支持文档所列 Windows 环境。本工程路径为 Windows 本机文件系统，因此该平台匹配；但当前连接状态为 stopped，缺少可以直接查询的活动 run/report。

## 3. 工程适用的安全调用策略

本次项目目标是代码与架构分析、文档撰写，不需要触发综合或生成 bit。合适的只读 MCP 用法是 license 状态、连接状态，以及在工程已被用户启动/导入后查询 ports、clocks、registers、timing 或报告。任何构建设计、添加源文件、改约束、写出 bit、关闭项目等操作都会超出本次只读文档范围。

若未来需要通过 SynthPilot 复核本项目：

1. 先使用当前连接实际提供的工具 schema 确认能力，不能把 public catalog 当作当前 MCP 工具承诺。
2. 检查当前 TD 工程与运行目录、.al 文件、器件/封装、seed、时钟约束及工作区差异。
3. 项目运行状态停止时，先明确是否要启动/打开项目；不要把 connection_info 或 doctor 的结果写成构建已经完成。
4. 对有状态或破坏性 flow 按其生命周期和防重策略执行，记录每一步结果，不自动重试不确定的非幂等操作。
5. 完成后将 MCP run 的源码/约束哈希、TD 版本、build 阶段、报告和固件哈希与仓库记录比较。

## 4. 关于数据边界

SynthPilot 官方说明称 EDA runtime 和工具执行发生在本地，SynthPilot 服务不会通过其服务上传 FPGA 源码或工程文件。提示词、上下文和文件仍可能由用户所配置的 AI 客户端或模型服务按各自隐私策略处理。该说明只描述 SynthPilot 服务的工具执行边界，不应被解释成对 AI 客户端所有数据处理方式的保证。

## 5. 本次对项目分析的贡献

SynthPilot MCP 为本次分析确认了平台、许可证和 EDA runtime 当前状态；没有活动设计数据库，因此无法从 MCP 读取实际构建时序路径、资源对象或当前 TD elaboration 输出。最终物理数据引用的是仓库已有的 2026-10-19 收尾报告，其属于归档证据。将来要出新的时序/资源结论，应在用户选择的工程 run 上重新打开并获取相同输入哈希对应的数据。

## 6. 官方链接

- [SynthPilot 官方文档](https://www.synthpilot.dev/docs.html)
- [SynthPilot 公共工具目录](https://www.synthpilot.dev/tools.html)
- [SynthPilot Anlogic 平台说明](https://www.synthpilot.dev/platform-anlogic.html)
- [SynthPilot llms.txt](https://www.synthpilot.dev/llms.txt)

## 7. 最终文档复核记录

2026-10-19最终整理再次执行 curl.exe -sL https://www.synthpilot.dev/llms.txt 并完整阅读返回内容，随后重新查询 get_license_status 和 td_connection_info。结果仍为 SynthPilot 1.4.0、Pro、安路工具90项可用；TD安装被发现，managed runtime stopped，build idle/state empty，没有活动工程。

该结果仅更新工具背景。本轮没有启动TD、打开设计或查询活动网表，也没有通过MCP执行综合、物理实现、bitgen或下载。当前代码依赖索引是本地文本分析；归档139项输入与7项产物的哈希核对也由本地只读操作完成，不能称为SynthPilot重新构建通过。
