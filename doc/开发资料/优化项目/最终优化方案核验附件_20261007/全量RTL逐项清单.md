# 全量 RTL/头文件逐项清单

文件来自当前 src，例化引用为去注释后的静态扫描；generate 展开和实际资源以完整综合实例树为准。静态扫描不解析加密IP内部，AutoExcluded 不等于仿真不用。

| 文件与定义行 | 功能 | 生产状态 | 本轮决策 |
|---|---|---|---|
| `src/I2S_receiver.v`<br>I2S_receiver:3 | 旧 I2S 接收 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/IP/PLL_HDMI_AUDIO.v`<br>PLL_HDMI_AUDIO:24 | 已排除的旧音频PLL | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/IP/afifo_16_32_256.v`<br>wfifo_32_32_512:13, fifo_cross_domain_addr_process_al_wfifo_32_32_512:250, ram_infer_wfifo_32_32_512:333 | 32×512写异步FIFO；写FIFO指针跨域；写FIFO双口RAM存储 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/IP/afifo_32_16_256.v`<br>rfifo_32_32_512:13, fifo_cross_domain_addr_process_al_rfifo_32_32_512:250, ram_infer_rfifo_32_32_512:333 | 32×512读异步FIFO；读FIFO指针跨域；读FIFO双口RAM存储 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/IP/sdram.v`<br>sdram_phy:14 | 旧SDRAM物理包装，当前AutoExcluded | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/IP/sys_pll.v`<br>sys_pll:24 | 100/125/125相移时钟 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/IP/video_pll.v`<br>video_pll:23 | 25/125MHz时钟 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/ax_debounce.v`<br>ax_debounce:1 | 旧消抖模块 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/SD/bmp_read.v`<br>bmp_read:1 | 旧裸扇区BMP扫描 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/SD/color_bar.v`<br>color_bar:3 | 显示扫描时序，RGB彩条口不使用 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/fat32_file_streamer.v`<br>fat32_file_streamer:8 | FAT簇链字节流 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/fat32_media_loader.v`<br>fat32_media_loader:17 | 卷/索引/BMP/媒体装载仲裁 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/fat32_volume_scanner.v`<br>fat32_volume_scanner:11 | MBR/BPB/根目录资源发现 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/frame_fifo_read.v`<br>frame_fifo_read:2 | 帧读突发节奏/刷新间隔 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/frame_fifo_write.v`<br>frame_fifo_write:2 | 帧写突发/翻转地址 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/frame_read_write.v`<br>frame_read_write:2 | 双异步FIFO与SDRAM请求 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/key_press_hold.v`<br>key_press_hold:17 | 母板短按/长按识别 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/SD/media_probe.v`<br>media_probe:5 | 空闲低优先级卡在场探测 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/media_supervisor.v`<br>media_supervisor:11 | 挂载/超时/重试/复位代次 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sd_card_bmp.v`<br>sd_card_bmp:8, key_press_debounce:737 | 封面预加载/显示提交/旧轮播；sd_card_bmp 文件内母板消抖 | 顶层可达 | 定向重构，保留业务 |
| `src/SD/sd_card_cmd.v`<br>sd_card_cmd:2 | SD命令/响应 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sd_card_sec_read_write.v`<br>sd_card_sec_read_write:2 | SD初始化/扇区事务 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sd_card_top.v`<br>sd_card_top:2 | SD SPI封装 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sd_sector_adapter.v`<br>sd_sector_adapter:9 | 扇区请求适配/超时 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sdram.v`<br>sdram:12 | SDRAM硬核包装（SD版有效，IP版排除） | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/sdram_rd_arbiter.v`<br>sdram_rd_arbiter:30 | 正常/缩略图单读口交接 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/seg_decoder.v`<br>seg_decoder:2 | 数码管字形译码 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/seg_scan.v`<br>seg_scan:2 | 六位数码管扫描 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/song_index_db.v`<br>song_index_db:29 | INDEX校验/条目/CRC | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/spi_master.v`<br>spi_master:2 | SPI字节传输 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/video_define.v`<br> | 参数/宏定义 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/SD/video_delay.v`<br>video_delay:1 | 视频数据与同步对齐 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/SD/video_timing_data.v`<br>video_timing_data:1 | 帧请求/扫描接口 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/audio_source_mux.v`<br>audio_source_mux:5 | 音源选择及 ready 路由 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/hdmi_pcm_audio_bridge.v`<br>hdmi_pcm_audio_bridge:14 | 旧 PCM 测试桥 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/audio/hdmi_pcm_source_bridge.v`<br>hdmi_pcm_source_bridge:5 | PCM 到 HDMI 契约桥 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/m06_pcm_contract_adapter.v`<br>m06_pcm_contract_adapter:6 | PCM valid/ready 契约转换 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/pcm_media_tone.v`<br>pcm_media_tone:9 | 非 WAV 场景琶音源 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/pcm_tap.v`<br>pcm_tap:18 | PCM 只读幅值抽头 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/pcm_volume_fade.v`<br>pcm_volume_fade:5 | 音量和淡变乘法 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/play_ctrl.v`<br>play_ctrl:13 | 播放/暂停/选曲/EOF 策略 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/seek_controller.v`<br>seek_controller:17 | Seek 钳位与目标运算流水 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/stream_session.v`<br>stream_session:5 | 切曲/Seek 代次与在途事务排空 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/sync_fade_gain.v`<br>sync_fade_gain:5 | 视频包络到 PCM 增益 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/timebase_48k.v`<br>timebase_48k:18 | 样本驱动媒体时基 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio/wav_stream_player.v`<br>wav_stream_player:17 | WAV 缓冲/读取/EOF/Seek | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/audio_arc_calculate.v`<br>audio_arc_calculate:4 | HDMI ACR N/CTS 生成 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/boot/boot_layer.v`<br>boot_layer:29 | 启动 Logo/保护窗/跳过 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/boot/boot_logo_rom.v`<br>boot_logo_rom:17 | 压缩调色板 Logo BRAM | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/bilinear_8q8.v`<br>bilinear_8q8:16 | 可选双线性插值 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/display/brightness_contrast_adjust.v`<br>brightness_contrast_adjust:15 | 画质流水/对比度 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/frame_blend.v`<br>frame_blend:3 | 旧双帧 alpha 混合 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/display/lrc_font_rom.v`<br>lrc_font_rom:4 | 60 个 16×16 字形组合 ROM | 顶层可达 | 定向重构，保留业务 |
| `src/display/lrc_lines_rom.v`<br>lrc_lines_rom:4 | 单曲时间戳与字形索引 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/lrc_osd.v`<br>lrc_osd:17 | 单行歌词扫描与像素叠加 | 顶层可达 | 定向重构，保留业务 |
| `src/display/osd_overlay_24.v`<br>osd_overlay_24:8 | 旧调试字符 OSD 包装 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/display/promax_audio_waveform.v`<br>promax_audio_waveform:7 | 时域幅度柱（非 FFT） | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/seg_business_mux.v`<br>seg_business_mux:24 | 错误/临时参数/业务数码管页面 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/status_osd_overlay.v`<br>status_osd_overlay:3 | 1E00 / E0F0 / BxxCyy 三行显示 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/display/thumbnail_layout.v`<br>thumbnail_layout:12 | 四宫格坐标/bank映射 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/thumbnail_view_reader.v`<br>thumbnail_view_reader:31 | 缩略图 SDRAM 读与 FIFO | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/video_fade_transition.v`<br>video_fade_transition:5 | F0/F1/F2 转场状态控制 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/video_transition_apply.v`<br>video_transition_apply:7 | 转场/亮度像素运算 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/display/vinyl_renderer.v`<br>vinyl_renderer:18 | 黑胶几何像素层 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v`<br> | 加密逻辑，保留IP边界 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/hdmi_audio_tone_i2s_64fs.v`<br>hdmi_audio_tone_i2s_64fs:2 | 旧 I2S 测试音 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |
| `src/hdmi_phy_warpper.v`<br>hdmi_phy_wrapper:3 | HDMI PHY 包装 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/include/boot_logo_geom.vh`<br> | 参数/宏定义 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/exp_event_defs.vh`<br> | 参数/宏定义 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/global_def.v`<br> | 参数/宏定义 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/lrc_geom.vh`<br> | 参数/宏定义 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/sdr_as_ram.enc.v`<br>sdr_as_ram:12 | 加密SDRAM用户接口与控制核 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/include/sdr_init_ref.enc.v`<br>sdr_init_ref:13 | 加密SDRAM初始化与刷新 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/sdr_wrrd.enc.v`<br> | 加密逻辑，保留IP边界 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/include/song_index_defs.vh`<br> | 参数/宏定义 | 头文件/加密IP/内联候选，不能据无层次行判死代码 | 保留；暂无可证明安全的资源删除项 |
| `src/io/browse_fsm.v`<br>browse_fsm:34 | J2/母板事件到全屏/缩略图/播放 | 顶层可达 | 定向重构，保留业务 |
| `src/io/buzzer_feedback.v`<br>buzzer_feedback:5 | 母板/J2 操作反馈音 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/cover_navigation.v`<br>cover_navigation:5 | 忙时累计封面目标 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/debounce_filter.v`<br>debounce_filter:3 | 独立同步+20位消抖计数 | 顶层可达 | 定向重构，保留业务 |
| `src/io/encoder_monitor.v`<br>encoder_monitor:3 | 编码器旋转及按压事件 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/exp_baud_tick.v`<br>exp_baud_tick:9 | UART 波特率时基 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/io/exp_echo_reporter.v`<br>exp_echo_reporter:24 | UART 格式化/队列/报文 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/io/exp_uart_tx.v`<br>exp_uart_tx:9 | UART 8N1 发送 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/io/expansion_integration.v`<br>expansion_integration:23 | 输入/命令/诊断/LED/WS/蜂鸣集成 | 顶层可达 | 定向重构，保留业务 |
| `src/io/expansion_io_hub.v`<br>expansion_io_hub:21 | J2 键/DIP/EC/IR 驱动 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/health_monitor.v`<br>health_monitor:21 | 诊断计数与当前错误锁存 | 顶层可达 | 定向重构，保留业务 |
| `src/io/ir_nec_decoder.v`<br>ir_nec_decoder:3 | NEC 帧/重复帧解码 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/key_dip_monitor.v`<br>key_dip_monitor:3 | 按键/DIP 消抖与启动抑制 | 顶层可达 | 定向重构，保留业务 |
| `src/io/led_business_driver.v`<br>led_business_driver:17 | IR/操作/心跳/故障 LED | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/param_menu_controller.v`<br>param_menu_controller:19 | 母板组合长按亮度/对比度菜单 | 顶层可达 | 按用户要求移除生产实例；关联测试迁移 |
| `src/io/quadrature_decoder.v`<br>quadrature_decoder:3 | A/B 稳定和正交方向计数 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/sync_bit.v`<br>sync_bit:3 | 输入两级同步 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/thumbnail_controller.v`<br>thumbnail_controller:15 | 缩略图焦点/选择/模式 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/ui_command_router.v`<br>ui_command_router:31 | IR/DIP/消隐唤醒/重启/命令 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/ui_event_bridge.v`<br>ui_event_bridge:24 | 业务事件到各域 toggle | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/ui_event_bus.v`<br>ui_event_bus:27 | 逐源 pending 事件仲裁 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/ws2812_driver.v`<br>ws2812_driver:18 | WS2812 GRB 串行发送 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/io/ws2812_effects.v`<br>ws2812_effects:16 | WS 音频包络/进度效果 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/lane_lvds_10_1.v`<br>lane_lvds_10_1:4 | TMDS LVDS 串化 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/reset_sync.v`<br>reset_sync:12 | 异步复位同步释放 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/startup_pulse.v`<br>startup_pulse:2 | 启动 EDID 触发 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/sync_2ff.v`<br>sync_2ff:11 | 单比特跨域同步 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/top_tf_hdmi_audio.v`<br>top:62 | 系统集成与 CDC/复位/图层/存储仲裁 | 顶层可达 | 定向重构，保留业务 |
| `src/video/mv_frame_scheduler.v`<br>mv_frame_scheduler:6 | 按媒体时间预取/提交MV帧 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/video/mv_sector_mux.v`<br>mv_sector_mux:4 | PCM优先的MV/WAV扇区互斥 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/video/mv_stream_player.v`<br>mv_stream_player:6 | MV RGB565字节流与SDRAM写完成 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/video/s6_video_layer.v`<br>s6_video_layer:4 | MV/黑胶选择与帧边界提交 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/video_rgb_to_axis_640x480.v`<br>video_rgb_to_axis_640x480:2 | RGB/DE 到 AXIS，综合可能归入上游组合逻辑 | 顶层可达 | 保留；暂无可证明安全的资源删除项 |
| `src/video_source_test.v`<br>video_source_test:3 | 旧测试图 | AutoExcluded（清理前核回归依赖） | 生产清单可移除；物理删除须完成依赖审计；面积收益0 |

## 源码例化边（包含内联前和参数化候选）

| 父模块 | 子实例 | 类型 | 源文件:行 |
|---|---|---|---|
| hdmi_phy_wrapper | u0_lane_lvds_8_1 | lane_lvds_10_1 | src/hdmi_phy_warpper.v:71 |
| hdmi_phy_wrapper | u1_lane_lvds_8_1 | lane_lvds_10_1 | src/hdmi_phy_warpper.v:83 |
| hdmi_phy_wrapper | u2_lane_lvds_8_1 | lane_lvds_10_1 | src/hdmi_phy_warpper.v:95 |
| hdmi_phy_wrapper | u3_lane_lvds_8_1 | lane_lvds_10_1 | src/hdmi_phy_warpper.v:107 |
| top | u_media_video_reset | reset_sync | src/top_tf_hdmi_audio.v:655 |
| top | u_sdcard_reset | reset_sync | src/top_tf_hdmi_audio.v:671 |
| top | u_mem_reset | reset_sync | src/top_tf_hdmi_audio.v:677 |
| top | u_video_reset | reset_sync | src/top_tf_hdmi_audio.v:683 |
| top | u_sdram_init_sync | sync_2ff | src/top_tf_hdmi_audio.v:690 |
| top | u_param_menu_controller | param_menu_controller | src/top_tf_hdmi_audio.v:701 |
| top | sys_pll_m0 | sys_pll | src/top_tf_hdmi_audio.v:890 |
| top | video_pll_m0 | video_pll | src/top_tf_hdmi_audio.v:899 |
| top | sd_card_bmp_m0 | sd_card_bmp | src/top_tf_hdmi_audio.v:925 |
| top | _m0 | sd_card_bmp | src/top_tf_hdmi_audio.v:930 |
| top | u_media_probe | media_probe | src/top_tf_hdmi_audio.v:986 |
| top | u_media_supervisor | media_supervisor | src/top_tf_hdmi_audio.v:994 |
| top | u_key_next_transition | key_press_hold | src/top_tf_hdmi_audio.v:1020 |
| top | u_key_thumb_left_confirm | key_press_hold | src/top_tf_hdmi_audio.v:1035 |
| top | u_play_ctrl | play_ctrl | src/top_tf_hdmi_audio.v:1053 |
| top | u_seek_controller | seek_controller | src/top_tf_hdmi_audio.v:1085 |
| top | u_stream_session | stream_session | src/top_tf_hdmi_audio.v:1192 |
| top | u_browse_fsm | browse_fsm | src/top_tf_hdmi_audio.v:1213 |
| top | u_thumbnail_controller | thumbnail_controller | src/top_tf_hdmi_audio.v:1243 |
| top | u_cover_navigation | cover_navigation | src/top_tf_hdmi_audio.v:1287 |
| top | u_video_fade_transition | video_fade_transition | src/top_tf_hdmi_audio.v:1300 |
| top | seg_decoder_m0 | seg_decoder | src/top_tf_hdmi_audio.v:1324 |
| top | u_seg_business_mux | seg_business_mux | src/top_tf_hdmi_audio.v:1382 |
| top | seg_scan_m0 | seg_scan | src/top_tf_hdmi_audio.v:1406 |
| top | _m0 | seg_scan | src/top_tf_hdmi_audio.v:1408 |
| top | video_timing_data_m0 | video_timing_data | src/top_tf_hdmi_audio.v:1508 |
| top | video_delay_m0 | video_delay | src/top_tf_hdmi_audio.v:1518 |
| top | u_video_transition_apply | video_transition_apply | src/top_tf_hdmi_audio.v:1590 |
| top | u_brightness_contrast_adjust | brightness_contrast_adjust | src/top_tf_hdmi_audio.v:1606 |
| top | u_osd_overlay_24 | osd_overlay_24 | src/top_tf_hdmi_audio.v:1632 |
| top | u_promax_audio_waveform | promax_audio_waveform | src/top_tf_hdmi_audio.v:1657 |
| top | _valid | pcm_tap | src/top_tf_hdmi_audio.v:1671 |
| top | _left | pcm_tap | src/top_tf_hdmi_audio.v:1672 |
| top | frame_read_write_m0 | frame_read_write | src/top_tf_hdmi_audio.v:1677 |
| top | _m0 | frame_read_write | src/top_tf_hdmi_audio.v:1683 |
| top | U3 | sdram | src/top_tf_hdmi_audio.v:1732 |
| top | u_sdram_rd_arbiter | sdram_rd_arbiter | src/top_tf_hdmi_audio.v:1764 |
| top | u_thumbnail_view_reader | thumbnail_view_reader | src/top_tf_hdmi_audio.v:1810 |
| top | u_wav_stream_player | wav_stream_player | src/top_tf_hdmi_audio.v:2109 |
| top | u_sync_fade_gain | sync_fade_gain | src/top_tf_hdmi_audio.v:2149 |
| top | u_pcm_volume_fade | pcm_volume_fade | src/top_tf_hdmi_audio.v:2161 |
| top | u_pcm_media_tone | pcm_media_tone | src/top_tf_hdmi_audio.v:2175 |
| top | u_audio_source_mux | audio_source_mux | src/top_tf_hdmi_audio.v:2191 |
| top | u_hdmi_pcm_source_bridge | hdmi_pcm_source_bridge | src/top_tf_hdmi_audio.v:2210 |
| top | u_pcm_tap | pcm_tap | src/top_tf_hdmi_audio.v:2228 |
| top | u_audio_arc_calculate | audio_arc_calculate | src/top_tf_hdmi_audio.v:2272 |
| top | u_boot_layer | boot_layer | src/top_tf_hdmi_audio.v:2288 |
| top | u_mv_preloaded_sync | sync_2ff | src/top_tf_hdmi_audio.v:2311 |
| top | u_mv_writer_sync | sync_2ff | src/top_tf_hdmi_audio.v:2313 |
| top | u_mv_sector_mux | mv_sector_mux | src/top_tf_hdmi_audio.v:2319 |
| top | u_mv_stream_player | mv_stream_player | src/top_tf_hdmi_audio.v:2328 |
| top | u_s6_video_layer | s6_video_layer | src/top_tf_hdmi_audio.v:2348 |
| top | u_lrc_osd | lrc_osd | src/top_tf_hdmi_audio.v:2364 |
| top | u_video_rgb_to_axis_640x480 | video_rgb_to_axis_640x480 | src/top_tf_hdmi_audio.v:2394 |
| top | u_startup_pulse | startup_pulse | src/top_tf_hdmi_audio.v:2407 |
| top | u_hdmi2phy_wrapper | hdmi_phy_wrapper | src/top_tf_hdmi_audio.v:2465 |
| top | u_exp_reset | reset_sync | src/top_tf_hdmi_audio.v:2492 |
| top | u_expansion_integration | expansion_integration | src/top_tf_hdmi_audio.v:2498 |
| top | u_ui_event_bridge | ui_event_bridge | src/top_tf_hdmi_audio.v:2561 |
| top | u_timebase_48k | timebase_48k | src/top_tf_hdmi_audio.v:2641 |
| hdmi_pcm_audio_bridge | u_pcm_media_tone | pcm_media_tone | src/audio/hdmi_pcm_audio_bridge.v:37 |
| hdmi_pcm_audio_bridge | u_m06_pcm_contract_adapter | m06_pcm_contract_adapter | src/audio/hdmi_pcm_audio_bridge.v:53 |
| hdmi_pcm_source_bridge | u_m06_pcm_contract_adapter | m06_pcm_contract_adapter | src/audio/hdmi_pcm_source_bridge.v:21 |
| boot_layer | u_boot_logo_rom | boot_logo_rom | src/boot/boot_layer.v:166 |
| lrc_osd | u_lines_rom | lrc_lines_rom | src/display/lrc_osd.v:50 |
| lrc_osd | u_font_rom | lrc_font_rom | src/display/lrc_osd.v:61 |
| osd_overlay_24 | u_osd | status_osd_overlay | src/display/osd_overlay_24.v:54 |
| thumbnail_view_reader | u_layout_display | thumbnail_layout | src/display/thumbnail_view_reader.v:109 |
| thumbnail_view_reader | u_thmb_fifo | rfifo_32_32_512 | src/display/thumbnail_view_reader.v:423 |
| debounce_filter | u_sync_bit | sync_bit | src/io/debounce_filter.v:17 |
| encoder_monitor | u_enc1 | quadrature_decoder | src/io/encoder_monitor.v:28 |
| encoder_monitor | u_enc2 | quadrature_decoder | src/io/encoder_monitor.v:40 |
| encoder_monitor | u_enc1_sw | debounce_filter | src/io/encoder_monitor.v:52 |
| encoder_monitor | u_enc2_sw | debounce_filter | src/io/encoder_monitor.v:64 |
| expansion_integration | u_expansion_io_hub | expansion_io_hub | src/io/expansion_integration.v:153 |
| expansion_integration | u_ui_event_bus | ui_event_bus | src/io/expansion_integration.v:196 |
| expansion_integration | u_ui_command_router | ui_command_router | src/io/expansion_integration.v:267 |
| expansion_integration | u_health_monitor | health_monitor | src/io/expansion_integration.v:294 |
| expansion_integration | u_exp_echo_reporter | exp_echo_reporter | src/io/expansion_integration.v:319 |
| expansion_integration | u_board_key_sw_monitor | key_dip_monitor | src/io/expansion_integration.v:364 |
| expansion_integration | u_buzzer_feedback | buzzer_feedback | src/io/expansion_integration.v:442 |
| expansion_integration | u_led_business_driver | led_business_driver | src/io/expansion_integration.v:463 |
| expansion_integration | u_ws2812_effects | ws2812_effects | src/io/expansion_integration.v:478 |
| expansion_io_hub | u_key_dip_monitor | key_dip_monitor | src/io/expansion_io_hub.v:72 |
| expansion_io_hub | u_encoder_monitor | encoder_monitor | src/io/expansion_io_hub.v:90 |
| expansion_io_hub | u_ir_nec_decoder | ir_nec_decoder | src/io/expansion_io_hub.v:117 |
| exp_echo_reporter | u_baud_tick | exp_baud_tick | src/io/exp_echo_reporter.v:109 |
| exp_echo_reporter | u_uart_tx | exp_uart_tx | src/io/exp_echo_reporter.v:118 |
| ir_nec_decoder | u_sync_ir | sync_bit | src/io/ir_nec_decoder.v:57 |
| key_dip_monitor | u_debounce | debounce_filter | src/io/key_dip_monitor.v:43 |
| key_dip_monitor | u_debounce | debounce_filter | src/io/key_dip_monitor.v:60 |
| quadrature_decoder | u_sync_a | sync_bit | src/io/quadrature_decoder.v:26 |
| quadrature_decoder | u_sync_b | sync_bit | src/io/quadrature_decoder.v:33 |
| ws2812_effects | u_ws2812_driver | ws2812_driver | src/io/ws2812_effects.v:126 |
| wfifo_32_32_512 | rd_to_wr_cross_inst | fifo_cross_domain_addr_process_al_wfifo_32_32_512 | src/IP/afifo_16_32_256.v:213 |
| wfifo_32_32_512 | wr_to_rd_cross_inst | fifo_cross_domain_addr_process_al_wfifo_32_32_512 | src/IP/afifo_16_32_256.v:220 |
| wfifo_32_32_512 | ram_inst | ram_infer_wfifo_32_32_512 | src/IP/afifo_16_32_256.v:226 |
| rfifo_32_32_512 | rd_to_wr_cross_inst | fifo_cross_domain_addr_process_al_rfifo_32_32_512 | src/IP/afifo_32_16_256.v:213 |
| rfifo_32_32_512 | wr_to_rd_cross_inst | fifo_cross_domain_addr_process_al_rfifo_32_32_512 | src/IP/afifo_32_16_256.v:220 |
| rfifo_32_32_512 | ram_inst | ram_infer_rfifo_32_32_512 | src/IP/afifo_32_16_256.v:226 |
| fat32_media_loader | u_volume_scanner | fat32_volume_scanner | src/SD/fat32_media_loader.v:437 |
| fat32_media_loader | u_file_streamer | fat32_file_streamer | src/SD/fat32_media_loader.v:477 |
| fat32_media_loader | u_song_index_db | song_index_db | src/SD/fat32_media_loader.v:508 |
| fat32_media_loader | u_sd_sector_adapter | sd_sector_adapter | src/SD/fat32_media_loader.v:885 |
| frame_read_write | write_buf | wfifo_32_32_512 | src/SD/frame_read_write.v:98 |
| frame_read_write | frame_fifo_write_m0 | frame_fifo_write | src/SD/frame_read_write.v:113 |
| frame_read_write | _m0 | frame_fifo_write | src/SD/frame_read_write.v:125 |
| frame_read_write | read_buf | rfifo_32_32_512 | src/SD/frame_read_write.v:152 |
| frame_read_write | frame_fifo_read_m0 | frame_fifo_read | src/SD/frame_read_write.v:167 |
| frame_read_write | _m0 | frame_fifo_read | src/SD/frame_read_write.v:175 |
| sdram | u2_ram | sdr_as_ram | src/SD/sdram.v:56 |
| sd_card_bmp | u_key_next | key_press_debounce | src/SD/sd_card_bmp.v:640 |
| sd_card_bmp | u_key_auto | key_press_debounce | src/SD/sd_card_bmp.v:651 |
| sd_card_bmp | fat32_media_loader_m0 | fat32_media_loader | src/SD/sd_card_bmp.v:665 |
| sd_card_bmp | sd_card_top_m0 | sd_card_top | src/SD/sd_card_bmp.v:711 |
| sd_card_top | sd_card_sec_read_write_m0 | sd_card_sec_read_write | src/SD/sd_card_top.v:48 |
| sd_card_top | _m0 | sd_card_sec_read_write | src/SD/sd_card_top.v:53 |
| sd_card_top | sd_card_cmd_m0 | sd_card_cmd | src/SD/sd_card_top.v:84 |
| sd_card_top | spi_master_m0 | spi_master | src/SD/sd_card_top.v:111 |
| video_timing_data | color_bar_m0 | color_bar | src/SD/video_timing_data.v:74 |
| s6_video_layer | scheduler | mv_frame_scheduler | src/video/s6_video_layer.v:67 |
| s6_video_layer | renderer | vinyl_renderer | src/video/s6_video_layer.v:104 |
