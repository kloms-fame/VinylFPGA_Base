# VinylFPGA bit 固件人工验收详细清单

日期：2026-10-08  
工程：`VinylFPGA`  
目标器件：`EG4S20BG256`  
目标工程：`prj/VinylFPGA.al`

## 0. 验收记录

| 项目 | 记录 |
|---|---|
| bit 路径 | `prj/r0_final_bit/VinylFPGA.bit` |
| bit SHA-256 | `待填写` |
| gate/pr 数据库 | `待填写` |
| TD 版本 | `6.2.168116` |
| FPGA 板卡编号 | `待填写` |
| SD 卡镜像版本 | `待填写` |
| 验收人员 | `待填写` |
| 验收时间 | `待填写` |

结论只能填写：`通过`、`有条件通过`、`不通过`。旧 bit 不得替代本次 bit。

## 1. 文件和版本一致性

- [ ] 工作区路径为 `D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`。
- [ ] `prj/VinylFPGA.al` 存在，顶层为 `top`，器件为 `EG4S20BG256`。
- [ ] 本次 bit 使用的 gate/pr 数据库、约束和源代码来自同一构建目录。
- [ ] 构建目录没有复用旧 `.bit`、旧 `*_pr.db` 或旧 `.bitgen_param.f`。
- [ ] 记录当前提交号、工作区 dirty hash、TD 版本和构建时间。
- [ ] 记录 bit 文件大小和 SHA-256。

建议命令：

```powershell
Get-FileHash .\prj\r0_final_bit\VinylFPGA.bit -Algorithm SHA256
Get-ChildItem .\prj\r0_final_bit | Sort-Object LastWriteTime
```

## 2. TD 物理实现和 bitgen 交付物

- [ ] place 阶段正常结束，存在 `VinylFPGA_place.db`。
- [ ] route 阶段正常结束，存在 `VinylFPGA_pr.db`。
- [ ] 存在 `route_flow.status`，且无失败状态。
- [ ] 存在 `route.timing`、`route.exceptions`、`route.constraints`。
- [ ] 存在本轮新生成的 `VinylFPGA.bit`。
- [ ] 存在本轮新生成的 `.bitgen_param.f`。
- [ ] 日志包含 `FINAL_BITGEN_PASS`。
- [ ] 不存在 `.bitgen.error.f`、route error marker 或 TD fatal error。
- [ ] bitgen 的器件、封装、启动配置和安全选项与板卡实际配置一致。
- [ ] 若使用 debugger/probe，`setup_debugger` 已完成且产物来自同一轮构建。

硬性停线：缺少 `VinylFPGA_pr.db`、`route_flow.status`、`VinylFPGA.bit` 或 `.bitgen_param.f` 时，不得进入烧录验收。

## 3. 资源和时序

- [ ] LUT 不超过器件上限 19600；R0 目标不超过 16500。
- [ ] BRAM 不超过 64；R0 阶段目标不超过 60。
- [ ] Slice 不超过器件上限，且不因拥塞导致 route 失败。
- [ ] DSP、PLL、GCLK、IO 数量均未超限。
- [ ] Setup WNS ≥ 0 ns，或已由项目负责人书面批准有条件验收。
- [ ] Hold WNS ≥ 0 ns。
- [ ] 无未约束时钟、组合环、非法约束或关键时钟异常。
- [ ] 记录 gate 和 route 两套资源/时序数据，不只看 `gate.qor`。

当前历史阻塞参考：LUT `17267/19600`、gate setup WNS `-0.846 ns`、SynthPilot place 曾报告 MSlice `5251/4900`。若本轮仍出现这些值，结论必须为“不通过”。

## 4. 烧录前板卡检查

- [ ] FPGA 板卡电源、电流和 USB/JTAG 连接正常。
- [ ] JTAG 识别到目标器件，器件 ID 与 EG4S20BG256 一致。
- [ ] HDMI 接收端、显示器、音频功放/耳机、SD 卡已连接。
- [ ] SD 卡使用经过 PC 端工具验证的镜像，文件系统和资源文件完整。
- [ ] 烧录前保存板卡原有可用 bit 和当前实验日志。
- [ ] 明确烧录介质：易失 SRAM/JTAG 或 SPI Flash；不得混淆两者。

## 5. JTAG/SRAM 烧录

- [ ] 选择本轮 `prj/r0_final_bit/VinylFPGA.bit`，不是目录中旧日期 bit。
- [ ] 下载工具识别目标器件且无 cable/driver 错误。
- [ ] 下载过程无校验错误、配置超时或 DONE 失败。
- [ ] DONE/INIT_B 等配置状态正常。
- [ ] 重新上电后按项目要求确认 SRAM bit 的易失性行为。
- [ ] 记录烧录时间、工具版本、端口号和日志路径。

## 6. 上电启动

- [ ] 上电后无异常过流、反复复位或明显发热。
- [ ] HDMI 输出在规定时间内出现有效画面。
- [ ] 启动画面/Logo/色条符合当前版本预期。
- [ ] 数码管或状态指示没有持续显示错误码。
- [ ] SD 初始化完成，未出现持续 `media_error` 或存储错误。
- [ ] 首张封面能正常显示，图像无花屏、错行、颜色颠倒。
- [ ] 音频时钟锁定，未出现持续噪声或无声。

## 7. SD 和资源链路

- [ ] 无 SD 卡时，系统显示确定性错误，不死锁。
- [ ] 插入正确 SD 卡后，扫描能完成。
- [ ] 四首歌曲/四组资源的曲目索引与实际文件一致。
- [ ] 封面四 bank 预加载完成，切换时不会读到上一首资源。
- [ ] 音频资源存在、缺失和损坏三种情况均有明确行为。
- [ ] UIRES 缺失时，系统不会将可选 UI 资源错误当成全局媒体失败。
- [ ] UIRES CRC 错误时，不发布无效歌词/背景数据。
- [ ] 切曲过程中旧曲资源不会覆盖新曲资源。

## 8. HDMI 视频和显示层

- [ ] HDMI 无明显闪屏、撕裂、横竖线或周期性黑屏。
- [ ] 封面、背景、MV、歌词、歌名/歌手图层叠加顺序正确。
- [ ] MV 播放时歌词和背景按预期让位。
- [ ] 浏览模式、播放模式、缩略图模式、诊断/色条模式切换正常。
- [ ] 亮度、对比度、淡入淡出和转场无异常跳变。
- [ ] 当前行歌词位置、上下文行、滚动动画和空行处理正确。
- [ ] 字形编号 0 和 127 显示正常；非法 128 不造成地址回绕或画面污染。
- [ ] 标题/歌手长度边界 0、1、15 字符分别验证。

## 9. 音频和播放控制

- [ ] 播放、暂停、继续、停止、重播均可用。
- [ ] Seek/快进/快退后音频位置和画面资源保持同一曲目代次。
- [ ] 切曲后音频不会继续播放上一首的数据。
- [ ] 音量、静音、淡入淡出和音频增益控制正常。
- [ ] 长时间播放至少 10 分钟无卡顿、爆音、失步或 FIFO 溢出。
- [ ] MV 播放期间音频连续，SD 后台资源请求不抢占音频优先级。

## 10. 按键、编码器、红外和 WS2812

- [ ] 板载按键逐个测试，去抖后无重复触发。
- [ ] 旋转编码器顺时针/逆时针各测试 20 次，计数方向正确。
- [ ] 编码器快速旋转不死机、不丢状态到不可恢复。
- [ ] DIP/扩展按键和红外遥控命令映射正确。
- [ ] 长按、短按、连按行为符合当前版本定义。
- [ ] 蜂鸣器反馈不持续鸣叫。
- [ ] WS2812 颜色、亮度、进度和错误状态显示正确。

## 11. 串口动态监听

在需要确认启动、SD、媒体错误或动态状态时执行：

```powershell
python skills/micu-omniprobe-ai/scripts/client.py watch --port 8765 --source serial
```

- [ ] 串口能够连接并持续接收数据。
- [ ] 启动阶段无重复复位、异常错误码或不可解释的乱码。
- [ ] SD 初始化、扫描、切曲、播放和错误路径均保留日志。
- [ ] 对异常卡、缺失资源、CRC 错误分别保存最小复现日志。
- [ ] 若进行串口发送，记录发送时间、命令、响应和恢复结果。

## 12. 自动化回归记录

- [ ] `python tools/test_lrc_cache_capacity.py` 通过。
- [ ] `python tools/verify_core_acceptance.py --out sim/r0_final_full` 通过。
- [ ] 回归结果为 14/14 PASS，失败列表为空。
- [ ] 记录仿真输出目录和 `results.json`。
- [ ] 对 bit 对应源码重新执行一次回归，不使用历史结果代替。

## 13. 最终放行条件

只有以下条件全部满足，才能填写“通过”并交付 bit：

1. 本轮 `VinylFPGA.bit`、`.bitgen_param.f`、`VinylFPGA_pr.db` 均存在且时间戳属于本轮。
2. bitgen marker 闭环，无 bitgen/route 错误文件。
3. route 资源、时序、约束和 DRC 检查通过。
4. JTAG 烧录成功且 FPGA DONE 正常。
5. 上电、SD、HDMI、音频、歌词/UI、控制输入和串口验收全部完成。
6. bit SHA-256、板卡编号、SD 镜像版本和日志归档完整。

任一项未完成，最终结论填写“有条件通过”或“不通过”，并写明阻塞项和复验条件。
