# X0R 告警审计

日期：2026-10-07

审计对象：固定基线快照 `prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7`

主要证据：

- `X0R_20261007_evidence/baseline_archive/native_build.log`
- `X0R_20261007_evidence/baseline_archive/final.area`
- `X0R_20261007_evidence/baseline_archive/final.qor`
- `X0R_20261007_evidence/baseline_archive/final.timing`
- `X0R_20261007_evidence/baseline_archive/release_bitgen.log`
- `X0R_20261007_evidence/compile_manifest.json`

## 1. 审计口径

本审计按 TD 6.2.168116 固定基线构建日志逐条检索。统计口径如下：

- 可计告警行：67 条 `WARNING`，其中 5 条为 `CRITICAL-WARNING`。
- 另有 3 条 `Similar messages will be suppressed`，表示同类告警被工具折叠；折叠掉的具体条数无法从该日志恢复，不计入 67 条。
- `native_build.log` 第 40 行的 `hdl_warning_level` 是构建参数文本，不是诊断告警。
- `compile_manifest.json` 记录 `error_fatal_lines = 0`、`duplicate_module_lines = 0`。

分组统计：

| 代码 | 可见告警数 | 定性 | 本轮处置 |
|---|---:|---|---|
| `HDL-5007` | 17 | 位宽/无尺寸常数 | 保留，后续治理 |
| `HDL-5314` | 3 | ROM 初始化和未使用消息位 | 保留，已判读 |
| `HDL-5317` | 3 | FIFO/加密 SDRAM 输入未连接 | 保留，残余观察 |
| `HDL-5323` | 1 | SD 写数据未连接 | 设计只读，保留 |
| `HDL-5369` | 1 | 组合块锁存推断 | 保留，最终 RTL 检查为 0 锁存 |
| `HDL-5001` | 2 | 匿名实例/网络未重命名 | 可追溯性问题，保留 |
| `SYN-5013` | 10 | 综合前未驱动网络 | 保留，综合按 0 处理 |
| `SYN-5011` | 14 | 综合后未驱动引脚 | 保留，低风险 |
| `SYN-5025` | 3 | 未驱动引脚/网络按 0 处理 | 工具一致性说明 |
| `SYN-6562` | 7 | `eram_init` 关闭导致初值忽略 | FIFO 复位接管，保留 |
| `SYN-6577` | 1 | SDRAM 时钟网合成指令 | 需板级长时间观察 |
| `PHY-7002` | 2 | SDRAM 初始位置被移动 | 工具合法化，保留 |
| `PHY-5079` | 1 | 本地时钟布线 | 需板级长时间观察 |
| `USR-6135` | 2 | 两个 PLL 反馈路径不可预测 | 既有 IP 配置，需板级验证 |
| 合计 | 67 | - | - |

## 2. 逐条审计

### 2.1 `HDL-5369`：`thumbnail_layout` 锁存推断

证据：

```text
HDL-5369 WARNING: latch inferred for net 'window_x[31]' in src/display/thumbnail_layout.v(33)
```

源码行为：

- `window_x`、`window_y` 是 `integer` 组合变量，只在 `in_de` 有效分支中赋值。
- 它们只在该分支内参与 `local_x/local_y` 计算；输出端口在块首已有默认赋值。
- TD RTL 报告显示 `#LATCH 0`，说明该推断没有在最终 RTL 结构中留下锁存器。

处置：本轮不修改。该模块是教程原样移植文件，修改属于行为清理，不属于 X0R 的零行为减负证据链。

残余风险：低。若后续 X1 调整缩略图布局，应顺手消除组合变量锁存推断，并重跑缩略图布局回归。

### 2.2 `HDL-5323`：SD 写数据位未连接

证据：

```text
HDL-5323 WARNING: input port 'sd_sec_write_data[7]' remains unconnected for this instance in src/SD/sd_card_bmp.v(705)
```

源码行为：

- `sd_card_bmp.v` 对 `sd_card_top` 的写接口使用固定只读连接：

```verilog
.sd_sec_write      (1'b0),
.sd_sec_write_addr (32'd0),
.sd_sec_write_data (),
```

- 因此 `sd_card_cmd` 中的 `block_write_data[7:0]` 在综合前未驱动，`SYN-5013` 将该路径按 0 处理。

处置：保留。当前工程是媒体读取/播放路径，不提供 SD 写入业务；强行接 0 只能消除文本告警，不能增加功能价值。

残余风险：低。后续若启用写卡、日志落盘或配置文件写入，必须先完整接通写数据、写请求和结束握手，不能沿用当前只读空连接。

### 2.3 `HDL-5317`：FIFO 与加密 SDRAM 输入未连接

证据：

```text
HDL-5317 WARNING: input port 'dib[31]' is not connected on this instance in src/IP/afifo_16_32_256.v(231)
HDL-5317 WARNING: input port 'dib[31]' is not connected on this instance in src/IP/afifo_32_16_256.v(231)
HDL-5317 WARNING: input port '**' is not connected on this instance in src/include/sdr_as_ram.enc.v(17)
```

判读：

- 前两条来自工程内 FIFO 包装层，属于宽字 FIFO 的高位数据路径未被业务使用或由包装层内部处理。
- 第三条来自加密 SDRAM 宏，日志已将具体网络名折叠为 `**`，无法从日志恢复加密源码内部语义。
- 综合未报错误，未驱动路径按工具规则处理；固定基线仍完成放置、布线和 bitgen。

处置：保留，不触碰加密 IP 和既有 FIFO 包装层。

残余风险：低到中。加密 SDRAM 那条不能仅凭日志宣称已完全解释；应以固定 bit 的 SDRAM 长时间读写、缩略图、MV 和音频并发作为功能判据。

### 2.4 `HDL-5314`：ROM 未驱动与消息缓冲位未驱动

证据：

```text
HDL-5314 WARNING: net 'word_mem_0' does not have a driver in src/boot/boot_logo_rom.v(30)
HDL-5314 WARNING: net 'word_mem_1' does not have a driver in src/boot/boot_logo_rom.v(550)
HDL-5314 WARNING: net 'msg[58][7]' does not have a driver in src/io/exp_echo_reporter.v(72)
```

判读：

- `word_mem_0/1` 是 `initial` 初始化的 ROM 数组。TD 已成功推断 10 个 BRAM，开机 Logo 资源在 `top/u_boot_layer` 层级可见。
- `msg` 是 UART 格式化消息缓冲，`MSG_MAX = 96`。当前最长格式化消息不覆盖 `msg[58]`，该单元属于未使用存储位。
- 这些不是组合环或时序违例，不改变固定基线时序结论。

处置：保留。删除或重写消息缓冲不会带来可测业务收益。

残余风险：低。若后续新增超过 58 字节的 UART 文本，应补齐消息缓冲初始化或缩短格式，避免未使用位影响可读性。

### 2.5 `HDL-5007`：位宽与无尺寸常数

证据分布：

- `src/include/sdr_init_ref.enc.v(47)`：无尺寸常数拼接按 32 位处理。
- `src/include/sdr_wrrd.enc.v(283)`：无尺寸常数拼接按 32 位处理。
- `src/SD/frame_read_write.v(148,198)`：FIFO 使用量端口 9 位与 10 位形式宽度混用。
- `src/top_tf_hdmi_audio.v(1475-1480,1493-1496)`：SDRAM 读写地址/长度端口 24 位连到 21 位形式端口。
- 加密 HDMI 核内部有 2 条形式/实际位宽差异告警，日志将名称折叠为 `**`。

判读：

- SDRAM 宏为 2M x 32，字地址空间需要 21 位。
- 顶层当前用 24 位地址和长度表达帧缓冲范围，低 21 位外的信息被工具截去。
- 既有设计没有新增形式断言证明所有 24 位地址始终落在 2M 字范围内；这是一条需要后续治理的真实契约风险，而不是纯噪声。
- 固定基线在既有媒体布局下通过综合、布局布线、时序检查和 bitgen，说明已有回归场景未触发越界。

处置：本轮不修改。该路径属于主链路 SDRAM 地址契约；在 X0R 收尾阶段改动会扩大验证面，也违背“零行为减负、最小改动”的约束。

残余风险：中。建议 X1 或后续资源治理阶段加入地址范围断言或显式饱和逻辑，并保留四 bank、缩略图、MV、WAV 并发回归。未完成该治理前，不得把 24 位到 21 位的截断写成“已证明安全”。

### 2.6 `HDL-5001`：匿名实例/网络未重命名

证据：

```text
HDL-5001 WARNING: Contains anonymous inst(s) and/or net(s) that have not been renamed
HDL-5001 WARNING: Contains anonymous inst(s) and/or net(s) that have not been renamed
```

判读：影响是网表可追溯性和 debug 命名，不是功能错误、时序违例或资源门禁问题。

处置：保留。当前不应为了文档美观重命名主链路网表。

残余风险：低。若后续需要上板 ILA 或门级定位，优先对相关层次显式命名。

### 2.7 `SYN-5013` / `SYN-5011` / `SYN-5025`：未驱动网络与引脚

证据分布：

- `SYN-5013` 共 10 条可见告警：2 条加密 SDRAM 初始化 BA，8 条 SD 写路径 `block_write_data[7:0]`。
- `SYN-5011` 共 14 条可见告警：4 条 BRAM byte-enable `bea[0]/beb[0]`，10 条加密 SDRAM 读数据寄存器的 `clk` 引脚。
- `SYN-5025` 共 3 条，说明综合器对未驱动引脚/网络统一使用 0。

判读：

- SD 写路径与 `HDL-5323` 是同一只读设计选择。
- 32 位 BRAM 未使用 byte-enable 时，将 `bea[0]/beb[0]` 按 0 处理属于正常资源映射。
- 加密 SDRAM 内部引脚不可从日志展开，属于残余不确定项。

处置：保留。综合器已将未驱动值固定为 0，且固定基线完成全流程；本轮没有证据支持为消除文本告警而修改加密宏或 FIFO。

残余风险：低到中。SDRAM 部分必须通过板级长时间运行确认。

### 2.8 `SYN-6562`：`eram_init` 关闭导致初值忽略

证据涉及：

- `frame_read_write` 读/写 FIFO
- HDMI 核内 EDID/音频/视频 FIFO
- `u_thumbnail_view_reader` FIFO
- `u_wav_stream_player` 缓冲 RAM

判读：这些 RAM 的数据内容由运行时写指针、读指针和复位状态接管；综合器忽略的是 RAM 电源上电初值，不是业务寄存器初值。

处置：保留。若强行打开 `eram_init`，会增加启动资源或改变既有 PPA，不符合最小改动。

残余风险：低。上电后首个采样窗口仍应由板级 HDMI、WAV、缩略图和 MV 冒烟覆盖。

### 2.9 `SYN-6577`：SDRAM 时钟网合成指令

证据：

```text
SYN-6577 WARNING: The clock signal "U3/u2_ram/SDRAM_CLK" is added with the synthetic instruction (keep/mark_debug/dont_touch/max_fanout), which may create additional logic on this net
```

判读：工具在 SDRAM 时钟网加入合成指令，可能引入额外逻辑。固定基线仍以 `ext_mem_clk` 专用时钟域和既有 false path 完成时序检查。

处置：保留。不要通过删除 keep/dont_touch 规避告警，否则可能改变硬核时钟实现。

残余风险：中。必须用板级 SDRAM 长时间读写观察。

### 2.10 `PHY-7002`：SDRAM 初始位置未保持

证据：

```text
PHY-7002 CRITICAL-WARNING: Instance U3/sdram location (12, 12) is not honored...
PHY-7002 CRITICAL-WARNING: Instance U3/sdram location (164, 288) is not honored...
```

判读：

- 两条记录的是初始位置在 ECO placement 开始时非法，工具自动移动硬核到合法位置。
- 初始位置不是最终用户位置契约；工具移动后仍完成放置、布线和 bitgen。

处置：保留。`pin.adc` 不改；SDRAM 位置问题不能用无证据的手工 LOCATION 强行覆盖。

残余风险：中。SDRAM 数据完整性以板级并发运行和长时间播放为准。

### 2.11 `PHY-5079`：本地路由时钟网

证据：

```text
PHY-5079 CRITICAL-WARNING: Marked 1 clock net(s) utilize the local routing resources...
```

判读：

- 结合既有约束，该观察点对应 SDRAM 硬核时钟/移位时钟路径。
- 本地布线不等于必然功能错误，但普通 STA 对物理偏斜的表达能力有限。

处置：保留。X0R 不通过修改时钟约束来掩盖物理实现现象。

残余风险：中。SDRAM 长时间读写和音频/视频并发必须作为人工验收项。

### 2.12 `USR-6135`：两个 PLL 反馈路径

证据：

```text
USR-6135 CRITICAL-WARNING: The feedback path of PLL sys_pll_m0/pll_inst is on local network...
USR-6135 CRITICAL-WARNING: The feedback path of PLL video_pll_m0/pll_inst is on local network...
```

判读：

- 两个 PLL 均使用 `FEEDBK_PATH=CLKC0_EXT`，工具认为补偿延迟不可完全预测。
- 这是既有 IP 配置现象，不是 X0R 新增 RTL 引入。
- 固定基线片内时序为 Setup WNS `+114 ps`、Hold WNS `+3 ps`、TNS `0/0`、违例端点 `0/0`。

处置：保留。片内 STA 通过不代表时钟质量和 HDMI PHY 板级表现自动合格。

残余风险：中。HDMI 首图、显示设备兼容性、SDRAM 并发和音频连续性必须在固定 bit 上人工验证。

## 3. 告警结论

1. 固定基线没有错误/致命综合错误，67 条可计告警均可从源码意图或工具处理规则归类。
2. 不构成 X0R 主链路功能阻断的告警包括：只读 SD 写空连接、ROM 初始化、匿名命名、未使用消息位、FIFO 初值忽略。
3. 需要保留为残余风险的项目包括：24 位到 21 位 SDRAM 地址截断、加密 SDRAM 未驱动引脚、SDRAM 硬核位置迁移、本地时钟布线和两个 PLL 反馈路径。
4. 本轮不修改业务 RTL、`pin.adc` 或 `timing.sdc`，原因是没有新板级参数，也没有完成 X1 的回归闭环；在 X0R 收尾阶段改主链路会破坏“最小改动”边界。
5. 告警审计不能替代板级验收。未完成人工板测前，只能写成“综合/bitgen/下载证据成立”，不能写成“HDMI、音频、SD、SDRAM 板级功能全部通过”。
