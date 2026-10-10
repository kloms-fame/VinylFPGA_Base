# D8 WSL 灯条亮度档位

## 行为与资源取舍

- WSL 加入唯一参数 CSR 与 EC2 参数菜单，默认 100%，提供 0%、25%、50%、75%、100% 五档。
- `ws2812_effects` 在 50 MHz 域锁存帧亮度；颜色分量使用移位和加法缩放，100% 直通原安全调色板，0% 发送黑色数据。
- 不增加乘法器或 DSP；DIP6 总使能仍拥有最高优先级。关闭 DIP6 后仍发送完整黑帧，再停止刷新；重新打开后恢复当前 KEY10 模式和 WSL 档位。
- 帧亮度只在开始接受新 WS2812 帧时采纳，传输中的 24-bit 像素数据保持稳定。WS2812 协议时序、像素数和 20 ms 刷新机制不变。
- D7 ROT 已开放六档 OFF/2/3/5/10/20 秒，并保留用户此前指定的 3 秒默认值。D8 后 EC2 参数菜单顺序为 VOL、BRI、CON、ROT、WSL。

## SynthPilot 综合结果

- Tang Dynasty 6.2.168116，器件 EG4S20BG256，数据库 `eagle_s20.db`，top `top`。
- `elaborate`、`opt_rtl`、`opt_gate`、`legalize_phy_inst` 均通过；构建快照为 `prj/resource_opt_verified_20261005/d8_wsl_20261010_r1/`。
- 相对 D7：总 LUT +72，寄存器 +24，slice、BRAM、DSP 不变。没有新增 DSP。
- gate timing summary：setup WNS -0.297 ns，STNS -0.354 ns；2 个 setup 违例端点；hold WNS +0.490 ns，无 hold 违例。最差 setup 路径仍处于既有 `ext_mem_clk` 外存 FIFO 控制逻辑。SD 卡域还有 -0.057 ns 的 setup 路径。没有路径经过 WSL 缩放逻辑成为全局最差路径。
- 约束检查：99.96% STA 覆盖；无无时钟叶引脚、无效约束或组合环；存在 2 个 dangling 节点、33 个输入未约束延迟、38 个输出未约束延迟、32 个 abnormal input delay，以及两个 PLL 本地反馈补偿警告。这些是当前工程约束/实现边界，不能据此宣称时序签核通过。
- 本阶段只综合到 `opt_gate` 并检查约束；未布局布线、未生成 bit、未仿真、未进行板级验收。
