# D1 定时图片自动轮播

## 实施范围

- J2 DIP2 上拨（消抖后的 `dip_level[1]=1`）开启轮播；默认间隔 5 秒。
- 只有媒体已挂载、首图有效、主浏览模式、非播放状态且图片数大于 1 时轮播才计时。
- 用 SD 卡 100 MHz 时钟域内的毫秒使能计时，不生成新时钟。
- 自动请求接入现有 `cover_navigation` 的 desired/select/ack 事务，manual next/prev 优先；忙时只保留一个待处理请求。
- 缩略图确认和播放换曲不作为轮播手动动作；缩略图、播放、启动、拔卡均关闭轮播。

## 实现文件

- `src/io/slideshow_controller.v`：5 秒调度、pending 和手动操作优先级。
- `src/io/cover_navigation.v`：接入低优先级 `auto_next`。
- `src/io/expansion_integration.v`：输出消抖后的 DIP2 电平。
- `src/top_tf_hdmi_audio.v`：跨域同步和运行条件门控。
- `prj/VinylFPGA.al`：新增源文件，综合和布局布线均启用，CompileOrder 62。

## 当前状态

RTL 定向仿真通过，SynthPilot 已通过 `opt_gate`。尚未生成 bit，也未进行上板人工验收、布局布线或 route 时序签核；详细记录见 `metrics.json`、`build_manifest.json` 和 `manual.md`。
