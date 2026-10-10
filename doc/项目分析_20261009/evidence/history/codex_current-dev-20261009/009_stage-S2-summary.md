# VinylFPGA Stage S2 Testbench 交付摘要

current_stage: S2
goal: 为 C2.3/C2.4 提供可运行的 Verilog stimulus、monitor 和通过判定。

confirmed_constraints:
- 仿真时钟为单一 SD 控制时钟；客户端的 `sec_req/sec_busy/sec_valid/sec_done` 遵循现有 `sd_sector_adapter` 电平协议。
- 目录扫描测试覆盖 FAT32 直接引导扇区、根目录短文件名、PIC1~4、AUDIO.PCM、UIRES.BIN。
- 客户端测试覆盖高优先级阻塞、两扇区 LBA 递增、generation 保持和 cancel 静默停止。

artifacts:
- sim/tb_fat32_volume_scanner.v
- sim/tb_uires_sector_client.v
- src/SD/uires_sector_client.v

decision: 已具备交给仿真执行工具的完整纯 RTL 输入；本地 Icarus 通过后再交 SynthPilot 综合。
blocking_reason: 无；顶层包含厂家 PLL/加密 IP，不使用 Icarus 作为整机顶层门禁，以 SynthPilot elaborate/opt_gate 为工程级证据。
next_action: 完成 SynthPilot opt_gate/resource report；通过后进入下一批 UIRES 静态槽加载器。
