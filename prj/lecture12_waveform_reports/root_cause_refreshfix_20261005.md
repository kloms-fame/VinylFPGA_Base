# 第十二讲彩点根因与修复记录（2026-10-05）

## 一、最终现象

- 图片加载完成后随时间出现彩点，并持续增多；拔掉 SD 卡后仍会增长。
- 当前正在显示的图片不出彩点；未显示的另外三张图片会出彩点。
- 自动轮播四张图片时不出彩点；暂停轮播后，未显示图片重新出现彩点。
- 加载完成后拔卡，再开启自动轮播，也不会出现彩点。

## 二、根因

SDRAM 自动刷新间隔宏在 Verilog 预处理后发生整数除法截断：

```verilog
`define SDR_CLK_PERIOD        1000000000/125000000
`define SELF_REFRESH_INTERVAL 64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)
```

宏只做文本展开，展开后等价于：

```verilog
64000000 / 1000000000 / 125000000 / 2048
```

第一步 `64000000 / 1000000000` 的整数结果为 `0`，因此
`SELF_REFRESH_INTERVAL = 0`。

在 `src/include/sdr_init_ref.enc.v` 中：

- `init_cnt == 0` 时每拍立即清零，计数器锁死在 0。
- 刷新请求比较值为 `0 - 10`，在 14 位无符号计数器中下溢为 16374。
- `init_cnt` 永远到不了 16374，所以 `ref_req` 永远为 0。
- `src/SD/sdram.v` 中 `App_ref_req` 固定接 `1'b0`，因此
  `Sdr_ref_req` 从上电起恒为 0，SDRAM 完全没有自动刷新。

## 三、为什么现象呈现“当前图不花，其他图花”

视频每帧持续扫描当前显示 bank 的所有行。SDRAM 的行激活会重新驱动并恢复该行电荷，
相当于对当前显示 bank 做了一次高频“伪刷新”，因此当前图通常不出彩点。

未显示的三块 bank 长期空闲。没有自动刷新后，存储电容持续漏电，所以它们先发生位翻转；
切到那张图片时，错误像素就以彩点形式显现。

自动轮播时四块 bank 轮流被逐帧扫描，每块 bank 都能周期性恢复电荷，所以画面看起来正常。
暂停后未显示的 bank 再次长期空闲，彩点继续出现。这组现象与“零自动刷新”完全吻合。

## 四、单变量修复

只修改 `src/include/global_def.v` 的运算优先级：

```verilog
`define SDR_CLK_PERIOD        (1000000000/125000000)
`define SELF_REFRESH_INTERVAL (64000000/(`SDR_CLK_PERIOD)/2**(`ROW_WIDTH))
```

计算结果：

```text
SDR_CLK_PERIOD        = 8
SELF_REFRESH_INTERVAL = 3906
```

125MHz 下 3906 拍约为 31.248us；器件为 4 bank x 2048 行，
64ms / 2048 行约等于 31.25us，符合该 SDRAM 的刷新要求。

没有修改加密 SDRAM 控制器、PLL 频率、HDMI 核、SD 卡协议或像素路径。

## 五、自证与构建证据

宏修复仿真：

- `SDR_CLK_PERIOD        = 8 ns`
- `SELF_REFRESH_INTERVAL = 3906 cycles`
- 40us 内刷新请求脉冲数 = 1
- 结论：刷新计数器能够回卷并产生刷新请求

构建环境：

- TD：`6.2.168116`
- 器件：`EG4S20BG256`
- 显示口：`HDMI_A`，引脚 K1/F5/E3/B3
- 布局种子：`place seed 2`

final timing：

- `video_clk`：SWNS +2.046ns，STNS 0
- `ext_mem_clk`：SWNS +0.173ns，STNS 0
- 全局负余量集中在 `sd_card_clk` 的 SD/WAV 音频链，不在 SDRAM 帧缓存和视频显示链

## 六、位流交付物

### 1. SDRAM 已知图案自检（诊断 D）

- 文件：`prj/VinylFPGA_diagD_sdram_selftest.bit`
- SHA256：`1929BE54CD4E9EDAAF56F98838FB963611A18DC3CD1394D85D570618A089E410`
- 作用：完全不依赖 SD 卡，由 FPGA 向 bank0 写固定渐变并读回比对
- 用途：检查 SDRAM 读写链路本身是否稳定

### 2. 自动刷新修复版（最终候选）

- 文件：`prj/VinylFPGA_refreshfix_hdmia.bit`
- SHA256：`2BA5EC735951D1A63B5C3106C1DD6E76AD4560702E5DC4A04754BE149D34C74E`
- 配套 BID：`prj/VinylFPGA_refreshfix_hdmia.bid`
- 配套 BID SHA256：`1804653DD7C4C7FDCC444ADCCB0C3D2F27454E0F2F04C87088E194A4D7AB6D99`
- 用途：主交付位流，先上板验证静止长时间不产生新增彩点

## 七、上板验收步骤

1. 显示器接 `HDMI_A`，烧写 `VinylFPGA_refreshfix_hdmia.bit`。
2. 等待四张图片加载完成，保持第 1 张静止 10 到 15 分钟。
3. 手动切到第 2、3、4 张，每张静止至少 5 分钟，检查是否仍新增彩点。
4. 拔掉 SD 卡，再让任意一张静止 10 到 15 分钟，检查彩点是否停止增长。
5. 开启自动轮播至少 30 分钟，再暂停，确认暂停后未显示图片也不再出现彩点。
6. 断电冷启动，重复第 2 到第 5 步一次。

## 八、若仍有问题时的下一层诊断

若刷新修复版仍出现增长彩点，下一层只抓以下信号，不再同时改多个模块：

- `Sdr_ref_req`
- `Sdr_init_ref_vld`
- `Sdr_busy`
- `App_rd_en`
- `App_rd_addr`
- `Sdr_rd_en`
- `Sdr_rd_dout`
- `frame_read_write_m0/read_buf.wrusedw`

判定口径：

- `Sdr_ref_req` 长期无脉冲：刷新宏或加密控制器输入仍有问题。
- `Sdr_ref_req` 有脉冲但 `Sdr_init_ref_vld` 不响应：刷新握手或控制器状态有问题。
- 两者都正常但读回数据在静止 bank 上翻转：进入 SDRAM 采样窗口、相位或器件时序排查。
- 读回数据正确但画面仍有彩点：责任转移到视频域、HDMI 核或 HDMI_A 物理链路。

## 九、上板烧写记录（2026-10-05）

- 链路探测：`read_device_id` 返回 `EG4S20BG256`，JTAG 在线。
- 烧写命令：`download -mode jtag -bit prj/VinylFPGA_refreshfix_hdmia.bit`
- 结果：`PRG-2014 : Chip validation success: EG4S20BG256`，耗时 6.18s，成功。
- 说明：JTAG/SRAM 易失下载，断电即失效，不影响 Flash 内旧固化版本。

## 十、上板验收结论（2026-10-05，通过）

用户实测：

- JTAG 下载刷新修复版后，加载四张图完成，静止第 1 张后切到第 2 张，
  **画面干净，无已积累彩点**。此前的"未显示 bank 漏电积累彩点"现象消失。
- 用户随后自行将修复版**固化烧录到 Flash**，断电上电复测，
  **第 2、3、4 张同样干净，无彩点**。

结论：SDRAM 零自动刷新根因确认成立，`SELF_REFRESH_INTERVAL` 运算优先级修复有效，
问题关闭。修复为单变量改动（`src/include/global_def.v` 一处宏加括号），
未触及其它任何逻辑。
