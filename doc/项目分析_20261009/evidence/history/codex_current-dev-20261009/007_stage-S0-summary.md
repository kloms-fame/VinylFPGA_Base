# Stage S0 Summary

- stage_id: `S0-X2-closeout-20261008`
- objective: 审查 `cb12d8d` 之后实际开发轨迹，补齐当前资产/验收工具缺口，并验证当前 U2 工作树的构建放行状态。
- scope_in: C1~C4、U1~U4、R1 方案矩阵；RTL 定向回归；UIRES 镜像；Anlogic TD 综合/布局布线/bit 门禁；JTAG/串口可用性。
- scope_out: 在未通过资源与时序门禁前继续集成 C4/U3/U4；配置 Flash 固化；冒充人工画面/声音验收。
- inputs: `prj/VinylFPGA.al`、三份用户指定方案文档、基线 `cb12d8d`、当前工作树、TD 6.2.1、SynthPilot 1.4.0。
- outputs: 收尾报告、13 项回归入口、修正后的构建脚本、每曲 4 背景 UIRES 验收镜像、构建/串口证据。
- constraints: EG4S20BG256；SD 100 MHz、视频 25 MHz、外存 125 MHz；旧验收链路不得回退；Setup/Hold 负裕量禁止下载。
- assumptions: 用户声明基线之前已经验收；现有 PIC1~4.BMP 可作为轮播背景验收素材；JTAG SRAM 下载不等于板级功能通过。
- interfaces: FAT32 `INDEX.BIN` + `UIRES.BIN`；低优先级 UI/背景扇区；SDRAM 背景 A/B；HDMI 像素末级；OmniProbe 8765。
- risks: route 后 97.55% slices、BRAM 90.62%、拥塞导致 setup/hold 失败；C4 未接入；U1/U2 越序；当前无串口数据。
- acceptance: 13 项仿真通过；UIRES 连续/CRC/INDEX 绑定通过；TD place/route/timing/bit 按硬门禁判定；只有签核 bit 才允许 JTAG。
- rollback: 保留用户工作树；负收益 RTL 实验已回退；不覆盖历史已验收 bit/Flash；测试镜像单独使用 `card_UIRES.img`。
- evidence_paths: `sim/closeout_20261008_full/`、`sim/closeout_20261008_u2/`、`prj/closeout_20261008/`、`doc/资源/sd卡/INDEX_UIRES.json`、本收尾报告。
- open_questions: 当前器件继续优化还是升级容量；C4 前需要的最低物理余量；最终每曲正式背景素材；C4/U4 的下一轮板验窗口。
- next_stage: 2026-10-08 R0 当前收尾已交付；用户选择暂不继续长时间构建。先作资源架构取舍，再恢复 R0-B/R0-C；物理签核通过后进入 C4.1。

### R0 当前收尾（2026-10-08）

- 交付报告：`doc/开发资料/拓展功能开发/evidence/R0-signoff.md`。
- 扇区仲裁流水的重复请求/owner 风险已修复；新增 5 场景仿真通过。
- 原默认 RTL 13/13 与补充 RTL 3/3 PASS；指标单元测试 14/14 PASS；4 曲目 UIRES 镜像验证 PASS。
- 资源检查前置到 gate/place；修复 BOM 清单、资源超限漏判和混阶段报告；gate/place 不可签核为 route。
- 状态：`signed_off=false`；未生成签核 bit，未烧录。中间 gate LUT 17110 仍超限，且不绑定最后一笔兼容修复；历史 place slices 99.26%，不能代表当前源码的最终 route。
