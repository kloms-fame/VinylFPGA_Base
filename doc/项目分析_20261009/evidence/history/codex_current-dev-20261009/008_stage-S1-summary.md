# VinylFPGA Stage S1 RTL 设计交付摘要

current_stage: S1
goal: 完成 C2.3 UIRES 根目录发现与 C2.4 低优先级单扇区客户端设计。

confirmed_constraints:
- 主 INDEX.BIN、音频和 MV 访问优先级不改变。
- UIRES 缺失或失败只影响可选文字层，不升级为全局媒体错误。
- UIRES 客户端单扇区在途；高优先级事务期间不发新请求；切曲使用 generation 作提交保护。
- 工程模块采用低有效复位，客户端寄存器均显式复位；顶层只增加 include/工程绑定，不接入旧歌词显示路径。

artifacts:
- src/SD/fat32_volume_scanner.v：新增 UIRES.BIN 8.3 目录元信息输出。
- src/SD/fat32_media_loader.v：透传 UIRES 文件有效、首簇和文件长度。
- src/SD/uires_sector_client.v：可取消、单在途、受高优先级门控的 UI 扇区客户端。
- sim/tb_fat32_volume_scanner.v：UIRES 目录发现检查。
- sim/tb_uires_sector_client.v：优先级、两扇区递增、generation、cancel 检查。

decision: RTL 设计交付可进入 S2 仿真验证；暂不接入 UIRES 头/静态槽 CRC loader 和顶层歌词显示。
blocking_reason: 无综合阻塞；尚缺 C2.5 扇区仲裁正式 owner 接口和 UIRES 静态槽装载协议。
next_action: 运行 S2 仿真与 SynthPilot opt_gate；人工确认后实现 UIRES 头/描述符/静态槽 CRC 装载。
