# VinylFPGA 资源优化实施记录（2026-10-05）

## 范围与证据

保持当前全部功能、所有模块端口、容量、数值精度、时钟及逐拍事件语义。参考资料是待核实的分析材料，不把其中的重构/删功能建议当作授权。主工程已有暂存与未跟踪改动，保持原样；本次构建输入在 `prj/resource_opt_verified_20261005/` 分轮快照并保存 SHA256。

当前 HEAD 为 c4bfcd3。历史主工程 phy_1 报告：8711 LUT、5955 REG、5185 Slice、30 BRAM9K、0 BRAM32K、11 DSP，Setup +82ps、Hold +3ps。旧稿 8402 LUT 属于 eacc5c9，不能混用。新一轮基线正在重建，历史报告不冒充本轮结果。

## 架构与瓶颈

- 50MHz 输入由两 PLL 产生 SD/FAT32 100MHz、SDRAM 125MHz（含移相输出）、视频/PCM 25MHz、HDMI 串行 125MHz。
- SD 路径：sd_card_bmp 调度 → fat32_media_loader → scanner/file_streamer → sector_adapter → 官方 SPI/SD。保留 32 位 LBA、文件长度与任意 BMP 数据偏移。
- SDRAM 保存四个图像 bank；frame_read_write 与 thumbnail_view_reader 通过读仲裁和异步 FIFO 共享 SDRAM。跨时钟 FIFO、bank 映射和安静窗口是功能必需项。
- WAV 4096×16 缓冲已映射 8 BRAM9K；HDMI 加密核使用 16 BRAM9K；帧读写 4、缩略图 2，总计 30。不得削减 FIFO 容量冒充无损优化。
- 历史最大逻辑子树为 sd_card_bmp 3416 LUT（含 scanner 1016、streamer 793），HDMI 核 1689、frame_read_write 533、菜单 457、缩略图 416。
- 历史 setup 瓶颈位于 100MHz 域，裕量 82ps；hold 最小 3ps。既有 SDC 缺少部分板级 IO delay，STA 通过仅表示现有约束下通过，不代表完整板级签核；本轮保持相同约束作公平比较。

## 按预计收益排序的候选清单

|优先级|候选|预计收益（非实测）|风险与处理|
|---|---|---|---|
|1|菜单 6 个计数器按参数门限收窄|40–120 LUT；源码宽度减少39bit|低；保留门限、饱和、复位、松开触发节拍，先测逐拍等价|
|2|按键/轮播计数器同类收窄|40–100 LUT；源码宽度减少51bit|低；长按须容纳100,000,000而非10,000,000；逐项综合实现|
|3|BMP固定54字节头计数器32→6bit|约10–40 LUT；26bit源码宽度|低；不收窄动态输入相关pixel_count/pixel_byte_cnt，不改尺寸端口|
|4|其他有证明上界的计数器|0–20 LUT，可能已自动裁剪|低；不为零收益进行接口清理|
|待确认|scanner移位/算术、同源gain同步、按键共享、仲裁压平|分别约60–160、20–50、60–130、30–80 LUT|模块重构；按用户约束需先说明具体方案再确认|
|待确认|音频公共精确增益乘积|主要期望减少DSP（实测可能已共享）|需保持完整16bit增益乘积及32bit有符号结果；不允许先截到8bit；数据通路重构待确认|
|待确认|WAV迁BRAM32K|资源种类置换，不等于总存储减少|原语支持、读写延迟、回卷语义待验证；不减缓冲容量|
|不实施|LBA/BMP偏移收窄、毫秒时基、删端口、FIFO缩深、降频|可能节省资源|分别限制输入范围、改变事件节拍或接口/吞吐，不满足当前无损约束|

scanner 的512字节声明不等于4096个FF：读取常量偏移会被综合裁剪。资料中“可省700–800 FF”与模块总FF结构矛盾，不能据此承诺收益。长按饱和计数器使用可容纳门限本身的位宽，特别测试门限为2的幂的情况。

## 执行与放行

每轮：原版/新版逐拍比对 → 全部既有回归 → 相同器件/约束的综合、布局布线 → 对比 LUT/REG/Slice/BRAM/DSP 和 setup/hold → 仅通过后进入下一项。新增构建目录不覆盖旧bit与主工程结果。

基线回归发现 TB 的 FIFO 模型把连续赋值端口 valid 声明为 reg，导致 Verilog-2005 编译失败；改为 wire，仅修测试模型声明，保持驱动和RTL不变。修正后基线全部回归通过，包括307200次缩略图检查、262144个簇偏移用例及WAV逐拍等价。

## 本轮实测（SynthPilot MCP，同一默认布局设置）

|轮次|相对输入|LUT|FF|Slice|BRAM9K/32K|DSP|Setup/Hold ps|决策|
|---|---|---:|---:|---:|---|---:|---|---|
|baseline|c4bfcd3 当前工作区源码|8711|5955|5185|30/0|11|+82 / +3|基线精确复现|
|p01_menu|基线，仅菜单计数器|8709|5953|5209|30/0|11|−415 / +11|回归和逐拍等价通过，但时序失败，已回退|
|p02_keys_checked|基线，仅按键/轮播计数器|8694|5953|5203|30/0|11|−140 / +11|回归和逐拍等价通过，但时序失败，已回退|
|p03_header|基线，仅BMP头计数器|8728|5925|5279|30/0|11|+1 / +11|时序通过但资源装箱退化，不选用|
|p03_s5|相同BMP头修改，seed5|8719|5929|5184|30/0|11|−25 / +3|时序失败，不选用|
|p03_s3|相同BMP头修改，seed3|8705|5924|5183|30/0|11|+109 / +3|保留为当前通过版本|
|p04_area|p03_s3源码，gate map_mode=area_prior，seed3|7825|5922|4515|30/0|11|+141 / +4|保留；相对上一通过版本−880 LUT、−668 Slice|
|p05_pcm|p04_area + 已授权精确增益共享，seed3|7834|5924|4579|30/0|10|−265 / +3|功能验证通过，时序失败，不下载|
|p05_s5|同一音频修改，复用gate.db，seed5|7827|5920|4527|30/0|10|+53 / +3|最终保留并生成固件|

p03_s3 相比基线减少6 LUT、31 FF、2 Slice，BRAM/DSP不变；属于RTL修改与布局种子的联合结果，不能将6 LUT全算成计数器修改的净收益。header_byte_cnt从复位0起，仅在LD_HEADER收到有效字节时递增，在53离开该状态，因此所有可达值均在0..53。六位容量足够，不改变任何文件偏移、尺寸输入或输出周期。

本轮默认设置由SynthPilot MCP构建和读报告；种子复测由TD原生命令完成，保存了rtl/gate/place/routed数据库以复用gate.db，避免每个种子重复综合。p03_header_seed5和p03_header_seed5_literal为原生脚本入口失败记录，无有效综合结果；修正为正斜杠绝对路径和字面Tcl参数后，p03_s5/p03_s3正常运行。保留错误记录，不计入优化实测。

两项综合后寄存器数均与基线相同（gate.qor #registers=5926），证明源码39/51bit的减少不能兑现为同等FF收益。p01 gate #luts 5448→5451，p02 5448→5429；gate #luts与布线后含ripple口径不同，不能混算。布线产生的2FF差异不归因于源码宽度。

逐拍专项验证覆盖真实默认门限附近、1/2/4/8/17周期门限、饱和值、按键抖动与复位。p02_keys为编译前的中间快照（参数声明先后顺序已修正），最终有效输入为p02_keys_checked。

历史及复现基线的关键路径：load_cluster_reg[23] → u_file_streamer/sector_lba_reg[27]，逻辑8级（4 ADDER + 3 LUT5 + 1 LUT4），数据延迟9.638ns（cell 4.683ns + net 4.955ns）。计数器改动无法直接消除该地址链瓶颈。

基线已有工具告警：两个PLL反馈使用local network；SDRAM IP位置约束未满足后由placer移动；缺5个input delay、23个output delay。不能宣称DRC/约束全清。这些既有问题本次不通过加假路径或放宽时钟隐藏。

## 已授权的音频表达式重构

用户明确同意仅重构pcm_volume_fade的精确乘法。将 `(sample * volume) * fade` 改为 `sample * (volume * fade)`，中间增益保留完整无符号16位（最大65025），零扩展为有符号32位后与符号扩展的sample相乘。原截位、饱和判断、握手与组合延迟级数不变。没有将增益截断成8位，也没有使用近似除法。

数学边界：最大正乘积32767×65025=2130674175，最小负乘积−32768×65025=−2130739200，均在signed32范围内，所以重结合不产生额外溢出或舍入。专项逐位测试比对左右完整32位积、最终16位输出和握手：全部65536组增益×8组样本边界，全部65536个样本×16组增益边界，以及100000随机组，总计1672864组全部通过。属于大规模仿真加代数证明，不冒称对43亿所有输入组合做过穷举或形式验证。

进行中用户/外部工作区将之前修改提交为530fccc；本任务未创建该提交，后续保留它，仍使用本轮最初c4bfcd3源码快照作比较基线。

## 最终交付与验证状态

最终采用p05_s5：相对基线LUT −884（−10.15%）、FF −35（−0.59%）、Slice −658（−12.69%）、DSP −1（11→10），BRAM9K=30、BRAM32K=0不变。Setup从+82ps变为+53ps，Hold维持+3ps，TNS=0、setup/hold违规端点均为0。时序有通过但裕量仍薄，不能称为时序大幅改善。

相对无音频重构的p04_area，最终p05_s5是用+2 LUT、+12 Slice换−1 DSP、−2 FF；这是明确的资源权衡，并非所有资源逐项都下降。采用理由是满足用户批准的精确共享方案、节省DSP且现有约束时序仍通过。保留p04_area全部快照与报告作为较大setup裕量的备选。

保留的实际修改只有：

1. `src/SD/fat32_media_loader.v`：BMP头计数器32→6位。
2. `src/audio/pcm_volume_fade.v`：完整16位公共增益乘积；原端口/输出位/延迟不变。
3. 构建采用 `set_param gate map_mode area_prior`、`set_param place seed 5`。该配置已固化为 `tools/build_verified_round.py` 的默认参数。**原GUI .al仍是默认策略，直接点击旧GUI构建不会自动获得本次配置；应使用下面的验证脚本。**
4. TB连续赋值端口声明reg→wire，及回归、归档、快照、发布脚本。

验证：全套既有回归通过；BMP原版/新版逐拍比较通过；PCM 1672864组精确比较通过；所有当前src/constraints文件与p05_s5构建输入SHA256完全一致。p05_s5与p05_pcm源码相同，仅布局种子变化，复用同一次通过的功能回归结果。

按照anlogic-place-route交付条件，route数据库与final时序一致，**允许放行到anlogic-create-bitstream**。新bit生成、setup_debugger、.bitgen_param.f均完成，**允许放行到下载/后续调试**。

固件：`prj/resource_opt_verified_20261005/p05_s5/VinylFPGA_optimized.bit`，629624字节。

SHA256：`8d6a4d3dd22e7b50c31ef1d97ee70e202794c9d2f5a9435af31a2e2288380f7c`。

已执行JTAG SRAM下载，日志包含芯片验证成功EG4S20BG256、program/download正常结束及VERIFIED_SRAM_DOWNLOAD_COMPLETE；未写Flash。hwserver初始探测输出一次device not found，但后续已找到目标并完成下载；不能据此替代人工功能验收。

**人工验收已通过（2026-10-05，用户反馈）**：用户明确回复“已验证，以上功能正常”，确认图片加载及四格bank映射、单击/长按/组合键菜单、自动轮播、亮度/对比度、WAV声音与淡入淡出正常；验收清单包含彩点、撕裂、爆音观察。此结论来自用户板级实测反馈，与自动仿真及下载成功分别记录。

### 复现命令

在VinylFPGA工程根目录运行，round名称必须是尚不存在的新名称：

```powershell
python tools/verify_resource_opt.py
python tools/verify_counter_opt.py header
python tools/verify_counter_opt.py pcm
python tools/resource_opt_round.py release_rebuild
python tools/build_verified_round.py release_rebuild --seed 5 --map-mode area_prior
python tools/release_verified_round.py release_rebuild --program-sram
```

快照中保留逐轮源码、输入哈希及数据库；小型实测证据另存 `prj/resource_history/20261005_verified/`，其中 `comparison.json` 汇总所有轮次。失败试验不作为可下载固件。

后续未授权结构改造不实施：scanner地址算术重排、跨模块SPC共享、同步链重构、按键共享和BRAM原语迁移。已证实收益很小的计数器裁剪停止扩展。当前结论是本轮在已授权范围内取得上述实测收益，不宣称找到所有可能实现的理论最小资源。
