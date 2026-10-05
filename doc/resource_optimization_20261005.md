# 第十二讲资源优化：方案与证据

日期：2026-10-05。源码基线：`78dbb17`。器件 EG4S20BG256，TD 6.2.168116。

## 行为契约与课程核对

现有顶层含 FAT32 图片/PCM 加载、四 bank SDRAM、手动切换/轮播、OSD、转场、WAV/琶音声源、音量淡出及第十二讲可视化。波形直接采集 WAV 的 sample_valid/sample_out，在 OSD 后、HDMI 前叠加；32 点双缓冲、12 倍抽取保留。当前可视化已经扩展成柱形显示，应保留当前效果，而不是退回教程截图。音频来源为 SD 上的 AUDIO.PCM，并非新增麦克风采集。

约束：4096×16 bit 缓冲、256 样本启动阈值、2048/1024 高低水位、48kHz 样本节拍、握手、静音、尾部排空、复位行为全部保持；PLL、SDRAM 刷新修复、像素及音量运算不变。现有多寄存器 always/function 风格沿用课程，优先于技能的默认风格建议。

## 重新核对报告

基线物理报告：LUT 16852/19600，REG 5780，Slice 9077/9800，BRAM9K 20/64，BRAM32K 0/16，DSP 7/29；route setup +128ps，hold -20ps（11 端点）。WAV LUT 9834/REG 675/BRAM 0，确认为首要瓶颈。

原分析报告部分模块误读 LE 列为 LUT：fat32_media_loader 实为 2264 LUT（含子模块），HDMI 1569 LUT，波形 153 LUT。gate 的逻辑 LUT 与 physical 的总 LUT 统计口径不同，不能仅以两者差值证明布局复制量。各项资源收益以本轮实测为准。

## 执行方案

|阶段|改动|预期收益|风险及验证|
|---|---|---|---|
|P0a|只给现有 RAM 添加 TD 块 RAM 属性|若映射成功，约释放 9000 LUT，增加约 8 块 BRAM9K|RTL 行为不变；先查实际映射，再决定是否保留|
|P0b（必要时）|分离纯双时钟 RAM 读写，保留原控制逻辑及读出节拍|同上|读口复位/保持/静音与 BRAM 同步输出必须逐拍比对；必要时用厂家 primitive|
|P1（评估后）|检查 scanner 实际保留字节及综合裁剪结果|0～500 LUT，不能预先保证|只有证据表明收益明显才更改；避免将已裁剪常量字段重构为更多逻辑|
|P2|对优化后实际时序路径做定点处理|目标 setup/hold 非负|不降频、不放宽约束、不增加假路径掩盖问题|

不执行缓冲减半、音量近似、HDMI FIFO 减深或时钟降频：这些改变容量、数值精度或时序，违反严格行为保持目标。功能未覆盖的旧 CDC 问题须单独说明，不与资源优化混改。

## 验证与回退

先运行基线 WAV/波形测试，再运行优化版；增加旧版/新版逐拍比较，覆盖背压、下溢、SD 间隙、停止/重启及长流。现有 12 扇区测试仅 3072 样本，实际上未越过 4096 地址边界，须补足回卷覆盖。

每个通过阶段显式提交所改文件，保留用户已有 TD 日志修改。基线报告及源文件存于 `prj/resource_opt_20261005/baseline`。最终位流用独立名称，记录 SHA256；上板先 JTAG SRAM 下载。编译/下载成功与实际画面、听音验收分开记录。

## 初始阶段摘要

- current_stage: S0 analysis / baseline
- goal: 降低资源并逐拍保持既有功能
- confirmed_constraints: 上述器件、接口、时钟、容量和课程行为
- artifacts: 本文、baseline/physical.area、baseline/route.qor、baseline/wav_stream_player.v
- decision: 开始基线回归及最小 RAM 映射试验
- blocking_reason: 无；未安装的 Python 信号预研究技能不作为本次既有 RTL 等价优化的必要依赖，使用原 RTL 实际波形作参考
- next_action: 基线仿真、RAM 映射、等价回归、TD 实现、板级下载

## P0 阶段结果

独立无复位 RAM 端口 + ram_style=bram 映射成功。综合 LUT=7179、BRAM9K=28；物理 LUT=7325、REG=5329、Slice=4497、DSP=7。旧版/新版长流逐拍对比 329348 个沿、背压/间隙 440356 个沿，以及停止重启、复位、SD 错误和波形测试均通过。

P0 路由尚不能放行烧录：setup -653ps（22 端点），hold +11ps（0 端点）。全部 setup 端点来自 scanner.sectors_per_cluster 到 file_streamer.sector_lba 的首簇地址计算，WAV 不再是瓶颈。后续仅对该组合选择网络做等价改写，保持请求拍数。P0 提交是已通过仿真/资源验证的开发检查点，不标记为板级可用版本。

## 最终交付（P0 + 时序收敛）

|资源/指标|优化前 78dbb17|最终 seed 3|变化|
|---|---:|---:|---:|
|LUT|16852 / 19600（85.98%）|7428 / 19600（37.90%）|减少 9424（55.92%）|
|Slice|9077 / 9800（92.62%）|4555 / 9800（46.48%）|减少 4522（49.82%）|
|寄存器|5780|5335|减少 445|
|BRAM9K|20 / 64|28 / 64|增加 8，余 36|
|BRAM32K|0 / 16|0 / 16|全部保留|
|DSP|7 / 29|7 / 29|余 22|
|Setup WNS / 违例端点|+128ps / 0|+117ps / 0|通过|
|Hold WNS / 违例端点|-20ps / 11|+4ps / 0|通过|
|WAV 模块 LUT / BRAM|9834 / 0|278 / 8|完整 8KB 块 RAM|

最终只修改两个 RTL 文件：

1. `src/audio/wav_stream_player.v`：无复位的独立 RAM 读写端口，TD 原生 `ram_style="bram"`；输出选择位保留原来的异步复位、下溢静音及拍间保持。指针、容量、阈值、状态机及采样节拍不变。
2. `src/SD/fat32_file_streamer.v`：首簇地址用 `case` 直接选择固定移位结果，消除“编码后再桶形移位”的组合串联。默认分支保持原来非法 BPB 值的行为，不增加流水级或请求延迟。

未调整其他 RTL、顶层、PLL、SDC、ADC、HDMI/SDRAM IP、采样率、音量精度或波形颜色/坐标。暂不执行 P1：当前资源余量已充分，进一步重构文件系统缓存缺少与风险相称的收益。

### 验证证据

`tools/verify_resource_opt.py` 可重复运行，本轮 19 个测试全部 PASS：

- WAV 单扇区、40 扇区连续流（10240 个样本，2 次地址回卷）。
- 40 扇区旧/新逐拍等价：329348 个时钟沿；含 SD 数据间隙、下游背压：440356 个沿。
- 停止/重新使能、复位、SD 错误、尾部排空、静音：46240 个沿。
- FAT32 碎片链旧/新逐拍等价，全部 256 种 BPB 簇大小字节值 × 1024 个簇地址 = 262144 个地址表达式对比。
- 既有 BMP 异常/超时、FAT32 scanner/loader/streamer、四 bank 调度/按键/轮播、帧缓存刷新避让和写入、OSD、转场、HDMI PCM、柱形波形/峰值条回归。

本轮 SynthPilot 已用于综合、布局布线及报告查询。其接口没有布局种子设置和板级下载工具，因此最终 seed 3 构建及 JTAG 下载使用本机 TD 官方 Tcl 命令；未安装或更换工具。seed 3 复用同轮 seed 2 的已验证 gate.db，避免重复综合。完整构建脚本默认种子已固定为 3。

时序结果是**现有工程约束下**的内部 STA 通过。原工程仍缺少部分板级输入/输出 delay，保留的 clock/IP 和约束诊断见 `release/constraints_check.rpt`；没有新增假路径或放宽时钟周期来掩盖违例。不能把仿真和 STA 当作所有板级环境下的保证。

### 位流与下载

- 交付目录：`prj/resource_opt_20261005/release/`。
- 位流：`VinylFPGA_resource_opt.bit`，629624 字节。
- SHA256：`A07C08F5B54CAD8583BD53DFD1A091BC3095EE70F19FC7202B3E03537F08A2B1`。
- 配套映射：`top_inst.bid`；参数：`.bitgen_param.f`；路由数据库保留在本地 `seed3/VinylFPGA_pr.db`。
- 2026-10-05 11:44（北京时间）JTAG SRAM 下载完成。目标验证 `PRG-2014: Chip validation success: EG4S20BG256`，program 和 download 均正常结束，日志见 `release/download.log`。
- FTDI 初始化日志含一次 `device not found`，后续实际目标识别、编程与完成标志均成功；完整日志保留，不将这行隐藏。
- 尚待用户观察确认：HDMI_A 图片切换/轮播/转场、音频听感、波形柱和峰值条。当前没有采集卡或音频回采反馈，不能声称已自动完成肉眼/听音验收。
- 此次是易失 SRAM 下载，原有 Flash 固化版本保留；断电后恢复原 Flash 固件。用户板级验收正常前不覆盖原可用 Flash。

### 复现与回退

在 `VinylFPGA` 目录执行：

```powershell
python tools/verify_resource_opt.py
./tools/build_resource_opt.ps1
# 仅在 RTL/约束完全未变时，允许复用同一轮 gate.db：
./tools/build_resource_opt.ps1 -Seed 3 -GateDb prj/resource_opt_20261005/seed2/VinylFPGA_gate.db
```

原功能基线是 `78dbb17`；`e45b1d5` 保存优化方案和基线证据，`9e9aee8` 保存 RAM 改造与仿真/资源检查点。最后一个提交保存时序收敛版本、回归脚本、报告及可直接下载的位流。

需要回退时优先对优化代码提交执行 `git revert`，保留提交历史及个人修改；或用 `git switch -c recovery/lecture12 78dbb17` 创建基线恢复分支（先处理未提交改动）。不使用 `reset --hard` 丢弃工作。仅恢复板上运行状态时可断电重启，或下载原 `prj/VinylFPGA_refreshfix_hdmia.bit`，其 SHA256 为 `2BA5EC735951D1A63B5C3106C1DD6E76AD4560702E5DC4A04754BE149D34C74E`。

## 最终阶段摘要

- current_stage: RTL / simulation / place-route / bitgen / JTAG completed; board observation pending
- goal: 显著降低资源并保持第十二讲现有功能
- confirmed_constraints: 两个 RTL 等价改写，容量/时钟/位宽/采样/显示保持
- artifacts: release/ 位流、面积、时序、约束检查、下载日志、输入哈希；tools/ 可重复执行脚本
- decision: 软件验证与现有约束下的时序通过，已下载，等待实际画面与听音确认
- blocking_reason: 无构建/下载阻塞；助手无法直接观察显示器和音频输出
- next_action: 用户进行板级验收；如有异常，以基线位流单变量对比定位

