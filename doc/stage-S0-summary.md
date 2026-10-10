# 开发前分析阶段摘要（2026-10-09）

- **current_stage**：S0，当前稳定工程、赛题与资源分析完成；未开始新功能RTL开发。
- **goal**：在 `afd8bfb`（生产代码等价 `cb12d8d`）上规划赛题一基础与全部五项扩展，逐功能开发、逐功能人工验收。
- **confirmed_constraints**：HX4S20/EG4S20BG256，19,600 LUT/REG、9,800 Slice、64×BRAM9K、16×BRAM32K、29DSP；2M×32bit SDRAM；50MHz输入、SD100MHz、存储125MHz、video25MHz、HDMI125MHz；沿用现有SDRAM/HDMI加密IP。
- **interfaces**：现有TF SPI扇区、FAT32受限目录/簇链、512B INDEX v1/v2、48kHz16bit单声道连续PCM、320×240 RGB565 10fps连续MV、J2事件、真实消费样本时基、帧边界图层提交。新多曲文字资源尚未冻结生产合同。
- **artifacts**：[详细分析](项目分析_20261009/项目现状_赛题对照_资源优化与分阶段开发方案.md)、[逐文件索引](项目分析_20261009/全量文件阅读与证据索引.md)、[人工验收清单](项目分析_20261009/逐功能人工验收清单.md)、[原始证据](项目分析_20261009/evidence/README.md)。
- **resource_result**：本轮原生area_prior/seed5/fix_hold最终LUT13,734，Slice7,541（76.95%），PLB2,360（96.33%），BRAM42、DSP15；setup121ps、hold24ps、TNS/违例0。MCP AUTO结果另记，不能混用；现有默认50项回归通过。
- **decision**：当前名义资源允许有节制的增量开发；先冻结构建/告警记录并确认定时图片轮播、测试音、不同输入分辨率缩放等实际缺口，再依序接EC2/画质/面板/多曲文字/播放页/五行/滚动。保留BRI/CON、缩放、波形与稳定性证据，不整套恢复历史UIRES扩展。
- **blocking_reason**：分析交付无阻塞。用户参考图路径不存在，精确视觉对图尚缺依据；PLL反馈告警和CDC/I/O约束审计未关闭；本轮不执行bitgen或硬件验收。
- **primitive_guidance**：优先复用现有SDRAM/HDMI包装、PLL、同步FIFO/BRAM字库；动态画质需比较档位移位加法或明确端口成本的转移表，不新增全帧UI图片加载器；未例化参考代码删除不带来资源收益。
- **project_input_guidance**：固定TD6.2.168116、器件数据库eagle_s20.db、top=top、显式map_mode=area_prior、seed5、ADC/SDC/源/.al/素材哈希。MCP single-run实参须报告核验，不能只看.al策略名。
- **next_stage_routing**：开始具体单功能设计前，先冻结关键事件、样本/帧时序、timeout和CDC合同，保存Python信号参考/预期波形，再进入RTL设计与testbench；每项自动验证/完整route后形成候选，人工通过才进入下一项。

本轮只新增分析资料，未修改原有RTL、约束、工程和资产。

## 详细实施规划更新（2026-10-09）

用户进一步明确“先优化、删减简化，再开发功能”。新的执行顺序以[执行总览与阶段门禁](实施方案_20261009/00_执行总览与阶段门禁.md)为准，覆盖上文decision及原分析报告第9节的建议顺序；原分析报告事实与证据保持不变。

- **planning_artifacts**：[优化删减与简化方案](实施方案_20261009/01_优化删减与简化实施方案.md)、[赛题功能与产品界面开发方案](实施方案_20261009/02_赛题功能与产品界面开发方案.md)。
- **optimization_first**：O0冻结→O1时钟/CDC→O2移除WS充能进度→O3简化蜂鸣→O4测量黑胶/读地址减负→O5测量Boot/源清理→O6精简版整机人工验收。无收益候选记录不采用；O6未通过不新增功能。
- **development_after_acceptance**：D0规格→轮播/测试音→EC2唯一参数源→亮度→对比度→浮窗→ROT/WSL→多曲文字→播放页→五行静态→滚动→真实尺寸缩放→波形边界→最终固化；各项分别验收。
- **status**：详细计划已形成，任务均未实施；资源与回归数字沿用上轮审计证据，不代表本轮新构建或板上验收。
