# 阶段 4：SPI Flash 参数持久化

本轮基线：`main` / `093efe7`（校准红外按键，修复 KEY4 静音）。阶段 4 完成人工验收后再提交；当前源码为待上板验收候选。原有上下左右、确认、编码器和红外事件桥不作功能变更。

## 硬件依据与存储范围

实际采用用户提供的《HX4S20开发板手册-HDL版2410.pdf》第 17 页 U33 **W25Q64 用户 Flash**。第 22 页的 **W25Q16 配置 Flash** 是另一颗芯片，固件启动镜像不参与本功能。资料原路径：

`D:/Data_Backup/比赛Game/安陆FPGA/官方资源/HX4S20_Contest_202606/9_康芯开发板使用手册及实验平台/HX4S20开发板手册-HDL版2410.pdf`

| 信号 | FPGA 引脚 | 方向/正常电平 |
|---|---|---|
| `flash_cs_n` | P8 | 输出，空闲为 1 |
| `flash_sclk` | M9 | 输出，Mode 0 空闲为 0 |
| `flash_mosi` | P7 | 输出，接 Flash SDI/DI |
| `flash_miso` | N8 | 输入，接 Flash SDO/DO |
| `flash_wp_n` | P9 | 输出，固定 1 |
| `flash_hold_n` | R9 | 输出，固定 1 |

这些引脚与原约束没有重复位置。仅保留用户 Flash 最后两个 4 KiB 扇区：`0x7FE000`、`0x7FF000`。所有擦除/写入地址均由固定槽地址及提交标记偏移生成，不接受外部任意地址，也不发送整片擦除指令。其它用户 Flash 数据不修改。

SPI 时钟为 `50 MHz / (2 × 8) = 3.125 MHz`，MSB 先行，Mode 0。CS 建立、保持及事务间高电平各至少 160 ns。使用标准命令：`AB` 退出掉电、`9F` JEDEC ID、`03` 读、`06` 写使能、`05` 状态、`20` 4 KiB 擦除、`02` 页编程。器件依据见 [Winbond W25Q64 系列技术资料](https://www.winbond.com/hq/product/code-storage-flash/qspi-nor/w25q-jv/?__locale=en&partNo=W25Q64JVBYIQ)。

启动先等待 20 ms，退出掉电并等 1 ms，再轮询 WIP。这也处理 FPGA 单独复位时 Flash 内部擦写尚未结束的情况。只接受 `EF4017` / `EF6017`，验证写使能与保护位，不自动修改 Flash 状态寄存器或解除保护。WIP 等待有 2 秒上限；ID 错误、超时、写使能失败、写保护或回读失败均停止持久化操作并点亮故障灯，播放和运行参数仍正常使用，复位后重新探测。

## 保存内容与行为

保存 CSR 的五项参数：VOL、BRI、CON、ROT、WSL。默认值为 `200 / 3 / 2 / 2 / 4`。不保存播放位置、KEY4 静音状态、上下左右交互状态、当前曲目或 EC2 浮窗状态。

- **KEY3**：短按保存当前五项参数。保持按下只产生一次请求；事务忙时再次按下，合并为一个待处理请求。与已保存值相同的重复保存不擦写 Flash。
- **SW3 上拨**：自动保存使能。实际参数发生变化后，停变 5 秒才保存；继续改变参数会重新计时。SW3 下拨不触发自动保存，手动保存仍可用。已经开始的 Flash 事务会正常完成。
- **KEY2**：立即恢复运行默认值，并排队保存带“默认值”标志的新记录；验证提交成功后才擦除旧槽。即使旧槽清理中断电，下次启动也会优先读取新默认记录。清除成功需等待忙灯熄灭且已保存灯点亮；在新记录提交之前断电，允许保留上一次有效配置。
- **上电/KEY1 复位**：校验两个槽并恢复最新有效配置；两槽均空白或无有效记录时保持默认值。启动加载期间已经发生的用户写入或 KEY2 默认值请求优先，迟到的 Flash 加载不会覆盖用户操作。
- **保存中继续调参**：正在写入的快照固定不变。新值保留在 CSR，保存完成后仍显示未保存状态，后续手动/自动保存会处理新值。

参数在 50 MHz UI 域一次性恢复到原 CSR；视频及轮播域沿用原 `cdc_bundle_latest`，没有新增多位总线的逐位同步。

## 原子记录与掉电处理

两个槽交替擦写，每槽一条 16 字节记录，均在单页内：

| 字节 | 内容 |
|---|---|
| 0–1 | Magic：`56 50` |
| 2 | 格式版本 `01`，未知版本不加载 |
| 3 | `00` 普通记录 / `01` 默认值记录 |
| 4 | 保留，必须为 `00` |
| 5 | 8 位循环序号；两槽按串行数差值选择最新值，支持 `FF → 00` |
| 6 | VOL，0–255 |
| 7–10 | BRI 0–4、CON 0–4、ROT 0–5、WSL 0–4 |
| 11 | 保留，必须为 `00` |
| 12–13 | CRC16/CCITT-FALSE，高字节先行；覆盖字节 0–11 |
| 14–15 | 提交标记 `A5 5A` |

保存顺序：擦除另一槽 → WIP 结束 → 编程字节 0–13 → WIP 结束 → 逐字节回读比较 → 独立编程提交标记 → WIP 结束 → 回读完整记录 → 才报告成功。任何失败均不发送成功提示。

中断擦除/主体写入/主体验证时，上一条有效记录仍存在。提交标记没有全部写好、CRC 不符、范围不符或版本不符的记录均不加载。默认值记录提交后再清理旧槽，避免先清空两槽造成旧参数与默认恢复行为不确定。

选择双槽而非单扇区覆写，是为了保留最后一条有效记录；本轮没有引入多页日志和磨损均衡索引，以控制 Slice 用量。两个槽轮换、只在真实变化且停变后自动保存、重复手动保存不擦写，可减少常规 OSD 调参的擦写次数。本功能面向低频参数保存，不作为连续数据记录器。

## 主板验收指示

本基线主板四颗 LED 原本固定熄灭；本阶段接入 NVM 状态提示，均为高电平点亮：

| LED | 含义 |
|---|---|
| LED1 | 本次启动已接受一条有效 Flash 配置并恢复到 CSR，保持到复位 |
| LED2 | 当前五项参数与已确认保存的参数一致；改参后熄灭，保存完成后点亮 |
| LED3 | Flash 初始化/读写正在进行 |
| LED4 | Flash 故障，保持到复位；无芯片、错误 ID、保护、超时、回读失败均可触发 |

空白 Flash 首次启动 LED1/LED2 不亮、LED3 初始化后熄灭，属于正常状态。KEY3 保存一次后 LED2 点亮。没有用按键反馈音冒充“Flash 保存成功”。扩展板 LED、蜂鸣器及原显示流程保持原逻辑。

## 文件与验证

- `src/io/nvm_spi_transaction.v`：固定分频的字节/事务控制，约束 CS 时序。
- `src/io/w25q64_param_store.v`：设备探测、双槽校验、串行 CRC、写使能、擦写轮询、两阶段提交与回读。
- `src/io/ui_param_persistence.v`：KEY2/KEY3/SW3 调度、5 秒停变、用户操作优先、快照与状态。
- `src/io/ui_param_csr.v`：新增同域原子恢复接口与独立范围校验；原写入优先级高于恢复。
- `src/io/expansion_integration.v`：消抖器扩展一位接入 KEY3，原 KEY2/KEY4 索引保持。
- `src/top_tf_hdmi_audio.v`：模块 include、接口互联及指示灯连接。
- `constraints/pin.adc`：新增 U33 六个引脚。
- `sim/tb_stage4_nvm.v`：独立 SPI NOR 行为模型与故障注入测试。

新模块从顶层 include 编译，带包含保护；`VinylFPGA.al` 的源入口、器件、`area_prior`、seed 5 和 BitGen 设置保持原值。新增 RTL 无 RAM 数组，不使用 BRAM。

仿真命令（PowerShell，在仓库目录执行）：

```powershell
$nvmOut = Join-Path $env:TEMP 'VinylFPGA_stage4_nvm.vvp'
iverilog -g2005-sv -I src/include -s tb_stage4_nvm -o $nvmOut sim/tb_stage4_nvm.v src/io/ui_param_csr.v src/io/ui_param_persistence.v src/io/w25q64_param_store.v src/io/nvm_spi_transaction.v
vvp $nvmOut
```

要求最后输出 `PASS STAGE4_NVM`。覆盖手动保存、自动停变计时、重复保存不擦写、五项参数恢复、事务中改参、未提交记录掉电、CRC 损坏回退、序号回绕、KEY2 清除及忙时排队、范围错误、未知版本、未完成提交标记、启动用户操作优先、回读失败不提交、错误 ID、WEL 拒绝、写保护、无 Flash 超时。模型对写入范围、页边界和 WIP 忙期间命令有独立检查，FPGA 复位不清除模型的 Flash 数据或内部忙状态。仿真加速毫秒 tick，自动保存阈值设为 5 个 tick；工程实例仍使用真实 1 ms tick、5000 tick 停变阈值。

仿真验证协议与逻辑，不代替实际芯片的 IO 电气时序或上板擦写。新增 Flash IO 未伪造外部 input/output delay；物理时序结论以实际约束和报告边界为准。

## 人工验收步骤

1. 用本阶段源码重新生成固件并烧录；首次空白参数区时，确认播放、MV、背景、原按键和红外正常。初始化结束后 LED3 熄灭，LED4 不亮。
2. SW3 下拨，改变全部五项参数，记下数值，按 KEY3。预期 LED3 写入期间点亮，成功后熄灭，LED2 点亮。KEY1 复位，再检查五项数值全部恢复，LED1 点亮。
3. 已保存且参数不变时再按 KEY3，预期不重复擦写，不出现持续忙状态。长按 KEY3 不应连续保存。
4. SW3 下拨改参后等超过 5 秒再复位，预期仍恢复之前保存值。SW3 上拨再改参，停变 5 秒并等待忙灯熄灭后复位，预期恢复新值；连续调参期间不应自动写入。
5. 保存期间继续调参，预期新数值保留、LED2 显示未保存；再次保存或满足自动保存条件后，复位应恢复最后的新数值。
6. SW3 下拨，按 KEY2，预期五项立即变为 `200/3/2/2/4`；等待忙灯熄灭、LED2 点亮后断电重启，预期不再恢复旧配置。写入期间按 KEY2 也应最终得到此结果。
7. 先保存一组已知参数；修改后开始保存，在 LED3 亮时复位/断电，多次测试。下次启动应得到上一组有效参数或已经完整提交的新参数，不应出现越界参数或播放异常。KEY2 测试也以“默认记录已提交”为持久化完成边界。
8. 静音/恢复、上下左右/确定、进度加减、编码器、唱针电机与双灯带回归验收。Flash 保存不得导致暂停、断音或改变原控件功能。

真实电源测试需使用已固化的本阶段启动镜像；仅 JTAG SRAM 下载在断电后会重新加载原有启动镜像，不能用来判断本阶段断电恢复结果。

## TD 构建记录

通过 SynthPilot 查询连接状态并完成 Anlogic doctor；当前 MCP 的结构化接口未提供与仓库既定 `area_prior + seed 5` 一致的参数设置入口，因此使用已有 `resource_opt_round.py` / `build_verified_round.py` 进行独立快照构建，不覆盖主工程 Runs。

- `stage4_nvm_20261017_r1`：综合通过；布局打包为 4911 个 MSlice（上限 4900），明确失败，不交付该版本。
- 随后复用参数快照、CRC 和 SPI 接收寄存器，并将 JEDEC 比较改为逐字节验证；使用 8 位循环序号减少计数/比较资源。全部 NVM 仿真重新通过。
- `stage4_nvm_20261017_r2`：综合 LUT 从 18007 降至 17832、寄存器从 11951 降至 11832，但物理打包为 MSlice/LSlice 各 4938，仍失败。这说明综合 LUT/寄存器下降不保证物理 Slice 下降，不能仅凭综合面积放行。
- `stage4_nvm_20261017_r3`：将 WIP 轮询后的动态状态地址改为固定状态分支，TD 日志确认成功识别 NVM 状态机；综合 LUT 17744、寄存器 11850、BRAM9K 64、BRAM32K 1、DSP 10。首次物理打包为 MSlice 4884 / LSlice 4885，总计 9769/9800，进入布线。

另外通过 SynthPilot 的 `td_import_device → td_read_hdl → td_optimize_rtl → td_optimize_gate → td_report_area` 独立检查 NVM 子模块，确认不推断 RAM/DSP，并比较了 TD 官方模板支持的状态编码方式。独立子模块面积用于定位资源，不作为整机打包或时序通过证据。

已有主工程最近一次报告（2026-10-17 22:05:40）为 Slice 9579/9800、setup WNS −630 ps、52 个违例、hold WNS +21 ps。本阶段不把这份既有报告当作新增 Flash 后的时序通过证据。

### r3 最终构建结果与放行边界

| 指标 | r3 最终报告 |
|---|---:|
| Slice | 9766/9800（99.65%，余量 34） |
| LUT | 18190/19600 |
| 寄存器 | 11896/19600 |
| BRAM9K / BRAM32K / DSP | 64 / 1 / 10，与原报告数量一致 |
| Setup WNS / TNS / 违例端点 | −2522 ps / −104586 ps / 193 |
| Hold WNS / TNS / 违例端点 | +30 ps / 0 / 0 |
| NVM 所在 50 MHz clk 域 SWNS | +481 ps |
| 原 SD 100 MHz / SDRAM 125 MHz 域 SWNS | −2522 ps / −1706 ps |
| no clock / invalid constraint / combinational loops | 0 / 0 / 0 |
| BitGen | 成功，676184 字节 |

相对既有物理报告，Slice 增加 187；两个既有高速域的 setup 时序仍未关闭，且本次结果较旧报告变差。功能 RTL 和 bit 生成链路已完成，**未达到《最终开发收尾方案》的零违例正式放行条件**。此文件只交付待验收候选，不宣称最终稳定版；硬件验收通过也不等价于静态时序关闭。

独立构建目录：`prj/resource_opt_verified_20261005/stage4_nvm_20261017_r3/`。候选固件：

`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/stage4_nvm_20261017_r3/VinylFPGA_stage4_nvm_candidate.bit`

SHA-256：`8e7561b115ec95c69c67451c53768c337a4e42cc91c83e2da2fab1747393136b`

对应 `inputs.sha256.json` 的 139 个源码/约束文件均与当前工作区一致，`.al` 快照匹配；`input_validation.json` 记录器件、seed 5、`area_prior` 和引脚无冲突检查。最终证据为 `final.area`、`final.qor`、`final.timing`、`final.constraints`、`native_build.log`、`candidate_bitgen2.log`、`candidate_manifest.json`、`nvm_simulation.log`。清单明确记录 `candidate_only=true`、`hardware_verified=false`、`route_timing_pass=false`。未执行硬件烧录，未提交本阶段 Git。
