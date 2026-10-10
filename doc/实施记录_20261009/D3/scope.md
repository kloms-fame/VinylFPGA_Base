# D3：EC2 与唯一音量源

## 实施内容

- 在 50 MHz 控制域新增唯一音量 CSR：复位值 200，每次调整 16，向上饱和到 255，向下饱和到 0。
- EC2 仅消费现有 UI 路由确认后的事件。隐藏态旋转直接调整一步；按压在 SELECT / ADJUST 间切换；SELECT 旋转只刷新活动时间；1800 ms 无操作后隐藏。D3 不增加可视浮窗。
- EC2 累计计数使用 16 位模差重放，保留快速连续旋转、反转与计数回绕中的逐步方向，不按净差吞掉反向动作。
- PLAY 域 KEY04/05 和现有 IR 音量命令仅在原播放控制接受后形成 up/down 意图，经 8 项异步 FIFO 返回 CSR。CSR 同拍有 PLAY 桥接项时先消费它，EC2 请求保持有效等下一拍。
- 音频增益只读取 CSR 的原子快照；复用已有 cdc_bundle_latest。新增共享 1 ms 使能复用现有控制计数基准。
- EC2 在启动、画面消隐、媒体未就绪/恢复、输入动作尚未就绪、重启确认期间关闭；禁用期间吸收计数基线，避免恢复后补发旧旋转。
- 两侧异步 FIFO 复位只受扩展控制复位驱动；媒体单独恢复不会清除已经接收的 KEY/IR 音量意图，也不重置 CSR。

## SynthPilot 结果

使用 Tang Dynasty 6.2.168116，通过 SynthPilot MCP 对隔离快照执行了受约束综合：

- 器件：EG4S20BG256，数据库 eagle_s20.db，顶层 top。
- 输入：主工程 RTL、prj/VinylFPGA.al、constraints/pin.adc、constraints/timing.sdc。综合结束于 opt_gate，耗时 58.324 秒，结果 PASS。
- 项目清单包含 69 个文件引用；5 个新模块登记在 CompileOrder 63～67。
- 没有执行 place、route、timing 实现或 bitgen，也没有运行 RTL 仿真。当前不能视为完整时序签核或板上验收。
- 面积相对 D1 r5 记录：LUT 利用量 14,440 / 19,600（73.67%），较 14,150 增 290，低于 D3 的 +300 LUT 预警 10 个；Slice 2,413，较 2,384 增 29，低于 +150 预警；BRAM9K 42 / 64、DSP 13 / 29 均不变。寄存器面积报告为 9,488 / 19,600，较 D1 记录 9,385 增 103。
- 受约束 opt_gate 的 setup WNS 为 -0.281 ns、TNS 为 -0.942 ns、4 个 setup 端点违例；hold WNS 为 +0.471 ns、无 hold 违例。最差路径位于 ext_mem_clk 域，从 frame_fifo_write 的 write_cnt_reg[0] 经 burst 比较与 FIFO 读状态组合逻辑到 frame_fifo_read 的 state_reg[2]，不经过新增 EC2/音量 CSR。该阶段只定位，不把这一路径归因为 D3，也不宣称时序闭合。
- check_timing 检出 0 个组合环、0 个无效约束；另有 2 个 PLL 本地反馈补偿警告、33 个输入无 input delay、38 个输出无 output delay、32 个 abnormal input delay。仍需完整布局布线报告检查最终实现。

报告位于隔离目录 prj/resource_opt_verified_20261005/d3_volume_20261010_r1/prj/ 下。SynthPilot 未向工作区暴露 gate.db；报告记录和受约束 opt_gate 的成功结果作为本次综合证据。

## 状态

RTL 与工程清单已提交前复核，SynthPilot opt_gate 通过。bitstream 由用户自行生成；硬件音量、旋钮与边界行为待人工验收。详细步骤见 manual.md。
