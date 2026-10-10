# D1 定时图片自动轮播

## 实施范围

- J2 DIP2 上拨（消抖后的 `dip_level[1]=1`）开启轮播；默认间隔 3 秒。
- 只有媒体已挂载、首图有效、主浏览模式、非播放状态且图片数大于 1 时轮播才计时。
- 用 SD 卡 100 MHz 时钟域内的毫秒使能计时，不生成新时钟。
- 自动请求接入现有 `cover_navigation` 的 desired/select/ack 事务，manual next/prev 优先；忙时只保留一个待处理请求。
- 只在自动事务的 `select_req && select_ack` 成功确认时输出事件；手动 next/prev/choose 不产生自动切图提示音。
- 确认事件通过 SD 域 toggle 和已有 `sync_2ff` 跨至 50 MHz；蜂鸣器复用现有计数器发出 4 kHz、12 ms 短音，自动音可抢占其他正在播放的低优先级音。
- 缩略图确认和播放换曲不作为轮播手动动作；缩略图、播放、启动、拔卡均关闭轮播。

## 实现文件

- `src/io/slideshow_controller.v`：3 秒调度、pending 和手动操作优先级。
- `src/io/cover_navigation.v`：接入 `auto_next`，标记自动事务并在 bank ack 后发出确认。
- `src/io/buzzer_feedback.v`：复用既有音调和时长计数器，新增最高优先级 4 kHz / 12 ms 自动短音。
- `src/io/expansion_integration.v`：接收跨域后的单拍事件并接入板载蜂鸣器。
- `src/top_tf_hdmi_audio.v`：DIP2 运行条件门控，以及 SD 域事件 toggle 到 50 MHz 的同步。
- `prj/VinylFPGA.al`：继续使用现有完整源文件清单；未更改工程文件。

## 当前状态

本次版本 SynthPilot 已通过 `opt_gate`；未运行 RTL 仿真、未生成 bit，也未进行上板人工验收或布局布线时序签核。D1 r4 的轮播仿真记录仅作为本次改动前的基线。面积较 r4 少 49 个 LUT、增加 8 个寄存器；当前版本综合后预布线 SWNS 为 +0.207 ns、STNS 为 0 ns，不能替代 route 或上板时序签核。详细数据见 `metrics.json`、`build_manifest.json` 和 `manual.md`。
