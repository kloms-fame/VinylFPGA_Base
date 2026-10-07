# VinylFPGA Slice/LUT 优化执行与验收报告

日期：2026-10-07。工程入口：`prj/VinylFPGA.al`，器件 EG4S20BG256，TD 6.2.168116。

## 范围与真实基线

按《VinylFPGA_最终优化执行方案_Slice与LUT优先_20261007.md》实施 O0–O7。本次执行前 HEAD 为 `533f605`，比方案中的 `66da60f` 更新；保留最新八位数码管、EC1 Seek、灯效与播放修复。资料中的历史资源、板验、烧录结论不作为本轮结果。

独立重建 `533f605` 的 O0 基线：9504 Slice（96.98%）、17839 LUT、10711 REG、40 BRAM9K、15 DSP；Setup WNS −1.609ns、TNS −31.135ns、82 个违规端点，Hold WNS +0.032ns。因此最新基线自身也存在时序问题，不能直接继承旧方案的 +0.048ns 结论。

## 实现内容

| 项目 | 本次实现与边界 |
|---|---|
| O1 UART/健康状态 | 生产移除 reporter、baud、TX，D12 UART 输出固定高。保留当前错误码和四位故障历史，合法零错误码可以恢复 LED 错误状态。 |
| O2 母板旧交互 | 撤销母板 KEY1/KEY2 的端口、引脚、消抖、短长按、双键菜单、图片轮播与提示音来源。保留 J2 KEY01–12、两个编码器、IR、六位 DIP、母板 KEY3 和 SW1–4。保留四 bank、播放结束自动下一曲、Seek。 |
| O3 调试字符 | 移除旧三行 OSD 及其私有状态，保留正常图像、歌词、Logo、MV/黑胶/波形、转场、首图失败背景；画质默认亮度255、对比度128，保留原输出寄存级。 |
| O4 共享消抖 | 50MHz 域唯一5000周期时基服务25路输入。每路独立两级同步和7位稳定计数，首tick启动，随后80个完整tick确认；同步后的反向毛刺每时钟取消计数，保证至少8ms。A/B正交解码不变。 |
| O5 同步歌词字库 | 1024×16同步ROM，原960个字形行保持一致、余64行补零；映射到2块BRAM9K。提前一像素读字形行并缓存，保持RGB/DE/VS时延。 |
| O6 工程清理 | `.al` 撤销退出生产及原AutoExcluded登记，加入两个消抖模块。退出模块/测试归档到 `sim/legacy`；原已排除的教学源文件可继续留存，不计面积收益。顶层仿真明确列出厂商IP边界桩，取消忽略任意未知模块的 `iverilog -i`。 |
| O7 集成与时序 | 增加两位 `metadata_song_sd` 寄存器，切断缩略图焦点/视图选择到音频索引簇号计算的组合路径。播放会话原有32拍空闲等待覆盖新增1拍；显示和选曲确认仍使用实时状态。未修改SDRAM仲裁、时钟频率或时序例外。 |

母板 KEY3 现在接真实管脚，仅保留启动跳过/蜂鸣反馈；不恢复最新提交已撤销的数码管翻页功能。J2 未接入时，母板 KEY1/2 不再提供导航兜底，这是本轮裁剪后的产品行为。

## 使用变化

- SW1 控制数码管总使能。正常显示继续为八位 `MM-SS NN`，曲号为01–04。
- SW3 进入诊断显示，八位从左到右为 `EhhFh NN`：`Ehh` 是当前十六进制错误码，`Fh` 是四位历史故障位掩码，末两位为曲号。
- 历史位：bit0音频欠载、bit1运行中低水位上升沿、bit2视频失败、bit3事件队列溢出；多项可同时存在，复位清除。当前错误恢复不会清除历史位。
- 默认预填充低水位不会直接记成运行中故障；保留运行状态和低水位上升沿条件。
- 播放中 EC1 旋转用于 Seek，按压暂停/恢复；KEY07 进入缩略图并停止，KEY11 返回主页。J2 KEY01/KEY02 与母板 KEY1/KEY2 是不同输入，前者保留。
- UART 已退出产品功能，串口静默是预期行为，不能用“无串口输出”判断播放失败或证明板验通过。

## 验证与证据

已先获取 SynthPilot 官方 `llms.txt`，通过真实 SynthPilot MCP 对 `O12345_r2_20261007` 综合至 `opt_gate`，并导出资源、时钟及约束检查。MCP默认auto映射结果：15215 LUT、9438 REG、42 BRAM、15 DSP；歌词字库实例45 LUT、2 BRAM。该结果仅证明综合/映射，不是最终布局布线数字。

MCP接口没有当前构建所需的map_mode/seed/fix_hold设置工具，物理实现使用项目原生TD脚本，明确 `area_prior`、seed5及独立 `fix_hold`。本轮 `td_report_param` 没有产生可核查参数文本，不据此声称已经验证策略；策略以保存的原生Tcl与日志为准。

完整 `python tools/verify_s7_acceptance.py`：47/47 PASS。其中：

- 消抖：25路缩参全相位、5000×80真实参数、6,470,065周期、毛刺/复位/阈值1。
- 字库：5129次读、1024地址、随机和边界、补零；生成器重复生成与生产文件字节一致。
- 歌词：15个完整800×525帧、9行歌词、Seek/倒退/暂停/使能，12,602,100次双相逐像素比较。
- 音频/媒体：多扇区顺序、三次FIFO完整回绕、欠载、Seek、EOF策略、CRC失败恢复、重挂载、四bank、MV/音频共享。
- 新增元数据：四首曲目WAV/MV数据、快速焦点后立即确认、会话等待、停止、复位。

`verify_s0_s5_fixes.py` 的9项、`verify_s6.py` 的8项及素材测试、`test_vinyl_packer.py` 的24项通过。事件总线10711周期、路由13477周期逐拍对比 `533f605` 通过；算术/CRC回归与歌词生成可重现检查通过。

旧编码器测试曾按旧切歌语义检查 `enc_cw/ccw`，未改基线也失败；已按 `533f605` 的EC1导航/Seek语义改为观察相应翻转事件。旧路由等价脚本默认对比10月6日的S703快照，与已有业务改动不等价；现默认固定对比本轮开始前的Git提交 `533f605`，也支持显式指定历史快照。没有为通过测试修改保留的路由业务逻辑。

顶层控制仿真将厂商PLL/HDMI/SDRAM IP作为明确边界，不代表门级仿真或物理HDMI音视频实测。

## 最终构建结果

放行候选：`O12345_r4_20261007`，`area_prior`、seed5。综合、布局布线、独立hold修复与bit生成均完成，最终构建日志无ERROR/FATAL。当前源码/约束全部逐文件SHA256与快照一致，当前 `.al` 仅作路径展开后与快照一致。

| 指标 | 当前基线533f605 | 最终候选 | 变化 |
|---|---:|---:|---:|
| Slice | 9504 / 9800（96.98%） | **7846 / 9800（80.06%）** | **−1658（−17.45%）** |
| LUT | 17839 / 19600 | **14550 / 19600（74.23%）** | **−3289（−18.44%）** |
| REG | 10711 | 9514 | −1197 |
| BRAM9K | 40 / 64 | 42 / 64 | +2，用于歌词字库 |
| DSP | 15 / 29 | 15 / 29 | 0 |
| Setup WNS | −1.609ns | **+0.158ns** | 通过 |
| Hold WNS | +0.032ns | **+0.030ns** | 通过 |
| Setup/Hold TNS | −31.135ns / 0 | **0 / 0** | 通过 |
| Setup/Hold违规端点 | 82 / 0 | **0 / 0** | 通过 |

剩余1954 Slice、5050 LUT、22块BRAM9K。满足方案88%最低线和84%优先目标，距离7834 Slice的保守全路线预算目标仍差12 Slice；后续功能仍应增量计量，不把当前余量等同于已验证的X3A–X8完整预算。

综合阶段（原生area_prior）的14051 LUT、9439 REG，与最终物理实现数字分开记录。六个时钟保持原频率；100MHz域最差Setup +0.158ns，50MHz域 +0.368ns，125MHz SDRAM域 +0.479ns。最终STA slow/fast检查、99.95%覆盖率仅适用于当前约束。

约束检查：no clock=0、invalid constraint=0、combinational loops=0、no path constraints=0。保留历史dummy node检查项3、PLL/clock-buffer检查项2、no input delay=33、no output delay=38及PLL本地反馈警告；本轮没有把这些既有边界包装成“所有外部接口全约束”或“零警告”。按用户高效增量许可，本轮使用已通过的seed5，不重复执行seed7。

`O12345_r2_20261007` 实现得到7870 Slice、14570 LUT，但Setup WNS −0.882ns且日志出现两次PHY-8023布线冲突，未放行、未生成/下载bit。该数字只用于中间分析。

`O12345_r3_20261007` 在综合期间主动终止：Icarus要求新增always块放在复位信号声明之后。已调整声明顺序并冻结新快照，未拿旧快照冒充最终源码。

## 位流与实际下载

2026-10-07 18:36完成bit生成，18:39使用当前安路USB下载器完成JTAG SRAM下载并复读芯片型号。生成流程包含 `bitgen`、`setup_debugger`、`export_bitgen_param`；最终下载日志包含 `PRG-2014 Chip validation success: EG4S20BG256`、`program`和`download`完成、下载后仍识别EG4S20BG256，以及 `VERIFIED_SRAM_DOWNLOAD_CONFIRMED`。最终Allink下载进程退出0，日志无ERROR/FATAL。

- 便捷取用：`prj/VinylFPGA_SliceLUT_20261007.bit`。
- 原始固件：`prj/resource_opt_verified_20261005/O12345_r4_20261007/VinylFPGA_optimized.bit`。
- 大小：643592字节。
- SHA256：`9a97be400f3f7785346bfc3907c3b71d2238853c43c672a45e3001732dcc1cc0`。
- 下载类型：JTAG SRAM，掉电后不保留；没有覆盖Flash。

初次自动探测尝试不存在的FTDI `0403:6042`，打印 `mpsse.cpp:90 device not found`，但随后通过另一下载器识别及下载成功。Windows实际在场设备为 `Anlogic usb cable v0.1`（`0547:1002`）。改用TD公开选项 `connect_cable -open -allink` 后复核下载，探测错误消失。`release_verified_round.py` 增加 `--allink` 参数，发布日志检查同时覆盖大小写Error；原始含探测信息的日志保留，最终以 `release_download_allink.txt` 为准。

已确认工具级综合/实现/bit生成/实际下载闭环；未声称完成外部显示器和扬声器观察、长时间音视频播放、物理热插拔等板级人工验收。UART已裁剪，未用串口静默冒充功能板验。

## 复现与回退

工作分支 `opt/slice-lut-20261007`，原始提交 `533f605`。完整重建使用新的轮次名，避免覆盖历史证据：

```powershell
$env:PATH = 'D:/iverilog/bin;' + $env:PATH
python tools/verify_s7_acceptance.py
python tools/resource_opt_round.py MY_NEW_ROUND
python tools/build_verified_round.py MY_NEW_ROUND --seed 5 --map-mode area_prior
python tools/release_verified_round.py MY_NEW_ROUND --program-sram --allink
```

发布脚本要求时序通过、构建无ERROR/FATAL、无无时钟/无效约束/组合环，检查当前 `.al`、源文件集合及每个文件SHA256。SRAM下载会自动连接JTAG并核对EG4S20BG256型号；不烧写Flash。历史基线用于代码回退，但其本轮时序未通过，不能直接作为已验证可下载固件。

原始构建数据库保留在 `prj/resource_opt_verified_20261005/`（Git忽略）；小型证据归档在本报告所在目录的 `SliceLUT优化验收附件_20261007/`，由 `tools/archive_slice_lut_20261007.py` 生成。最终板上长时音视频、物理按键和热插拔观察需单独记录，不由RTL回归或JTAG成功替代。
