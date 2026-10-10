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
- next_stage: 资源/拥塞收敛与时序签核；通过后再进入 C4.1。
