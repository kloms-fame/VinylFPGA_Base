# S7-03 TD 实测资源与时序

层次 LUT=lut+ripple，FF=seq；父模块包含子模块，不可重复相加。全局 FF 以 #reg 为准。

| 轮次 | LUT | FF | BRAM9K | BRAM32K | DSP | Slices | Setup WNS ps | Hold WNS ps | Setup/Hold TNS ps | S/H 违例端点 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| S7_03b_key07_key11_20261006_s7 | 15733 | 9699 | 40 | 0 | 15 | 8412 | 114 | 3 | 0/0 | 0/0 |
| X0R_R1_thumb_20261007 | 15677 | 9687 | 40 | 0 | 15 | 8433 | 123 | 4 | 0/0 | 0/0 |
| X0R_R2_bootfields_20261007 | 15724 | 9687 | 40 | 0 | 15 | 8463 | 147 | 3 | 0/0 | 0/0 |

**当前保留版本：S7_03b_key07_key11_20261006_s7。** 后续失败实验不代表交付版本。
M3 与 M6 seed7 未完成 final 报告，其 gate/失败诊断见执行记录，未混入本表。

## S7_03b_key07_key11_20261006_s7

### 各时钟 Fmax（TD 原生报告值）

| 时钟 | Fmax MHz | 最小周期 ns |
|---|---:|---:|
| sd_card_clk | 101.153 | 9.886 |
| video_clk | 34.257 | 29.191 |
| clk | 59.751 | 16.736 |
| ext_mem_clk | 135.999 | 7.353 |
| hdmi_5x_clk | 256.345 | 3.901 |

### LUT 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4560 | 3364 | 0 | 0 |
| top/u_expansion_integration | 3424 | 1674 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1645 | 1454 | 16 | 0 |
| top/u_video_rgb_to_axis_640x480 | 676 | 88 | 0 | 0 |
| top/u_lrc_osd | 630 | 88 | 0 | 0 |
| top/u_s6_video_layer | 568 | 307 | 0 | 4 |
| top/frame_read_write_m0 | 556 | 365 | 4 | 0 |
| top/u_wav_stream_player | 463 | 262 | 8 | 0 |
| top/u_thumbnail_view_reader | 365 | 261 | 2 | 1 |
| top/U3 | 307 | 395 | 0 | 0 |
| top/u_param_menu_controller | 307 | 176 | 0 | 0 |
| top/u_ui_event_bridge | 210 | 73 | 0 | 0 |

### FF 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4560 | 3364 | 0 | 0 |
| top/u_expansion_integration | 3424 | 1674 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1645 | 1454 | 16 | 0 |
| top/U3 | 307 | 395 | 0 | 0 |
| top/frame_read_write_m0 | 556 | 365 | 4 | 0 |
| top/u_s6_video_layer | 568 | 307 | 0 | 4 |
| top/u_wav_stream_player | 463 | 262 | 8 | 0 |
| top/u_thumbnail_view_reader | 365 | 261 | 2 | 1 |
| top/u_param_menu_controller | 307 | 176 | 0 | 0 |
| top/u_sync_fade_gain | 149 | 105 | 0 | 0 |
| top/u_lrc_osd | 630 | 88 | 0 | 0 |
| top/u_video_rgb_to_axis_640x480 | 676 | 88 | 0 | 0 |

### BRAM 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1645 | 1454 | 16 | 0 |
| top/u_boot_layer | 174 | 71 | 10 | 3 |
| top/u_wav_stream_player | 463 | 262 | 8 | 0 |
| top/frame_read_write_m0 | 556 | 365 | 4 | 0 |
| top/u_thumbnail_view_reader | 365 | 261 | 2 | 1 |

### DSP 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_s6_video_layer | 568 | 307 | 0 | 4 |
| top/u_boot_layer | 174 | 71 | 10 | 3 |
| top/u_brightness_contrast_adjust | 24 | 24 | 0 | 3 |
| top/u_video_transition_apply | 15 | 2 | 0 | 3 |
| top/u_pcm_volume_fade | 14 | 4 | 0 | 1 |
| top/u_thumbnail_view_reader | 365 | 261 | 2 | 1 |

### 子模块热点（与父树重叠，仅用于定位）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_file_streamer | 570 | 294 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db | 1000 | 874 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_volume_scanner | 1201 | 1049 | 0 | 0 |
| top/u_expansion_integration/u_exp_echo_reporter | 953 | 361 | 0 | 0 |
| top/u_lrc_osd/u_font_rom | 412 | 0 | 0 | 0 |

## X0R_R1_thumb_20261007

### 各时钟 Fmax（TD 原生报告值）

| 时钟 | Fmax MHz | 最小周期 ns |
|---|---:|---:|
| sd_card_clk | 101.245 | 9.877 |
| video_clk | 34.67 | 28.843 |
| clk | 54.242 | 18.436 |
| ext_mem_clk | 132.45 | 7.55 |
| hdmi_5x_clk | 324.992 | 3.077 |

### LUT 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4505 | 3354 | 0 | 0 |
| top/u_expansion_integration | 3513 | 1649 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1717 | 1508 | 16 | 0 |
| top/u_lrc_osd | 627 | 92 | 0 | 0 |
| top/u_s6_video_layer | 610 | 306 | 0 | 4 |
| top/frame_read_write_m0 | 545 | 385 | 4 | 0 |
| top/u_video_rgb_to_axis_640x480 | 503 | 88 | 0 | 0 |
| top/u_wav_stream_player | 474 | 266 | 8 | 0 |
| top/u_thumbnail_view_reader | 335 | 243 | 2 | 1 |
| top/U3 | 331 | 384 | 0 | 0 |
| top/u_param_menu_controller | 316 | 171 | 0 | 0 |
| top/u_ui_event_bridge | 264 | 63 | 0 | 0 |

### FF 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4505 | 3354 | 0 | 0 |
| top/u_expansion_integration | 3513 | 1649 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1717 | 1508 | 16 | 0 |
| top/frame_read_write_m0 | 545 | 385 | 4 | 0 |
| top/U3 | 331 | 384 | 0 | 0 |
| top/u_s6_video_layer | 610 | 306 | 0 | 4 |
| top/u_wav_stream_player | 474 | 266 | 8 | 0 |
| top/u_thumbnail_view_reader | 335 | 243 | 2 | 1 |
| top/u_param_menu_controller | 316 | 171 | 0 | 0 |
| top/u_lrc_osd | 627 | 92 | 0 | 0 |
| top/u_sync_fade_gain | 121 | 89 | 0 | 0 |
| top/u_video_rgb_to_axis_640x480 | 503 | 88 | 0 | 0 |

### BRAM 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1717 | 1508 | 16 | 0 |
| top/u_boot_layer | 189 | 65 | 10 | 3 |
| top/u_wav_stream_player | 474 | 266 | 8 | 0 |
| top/frame_read_write_m0 | 545 | 385 | 4 | 0 |
| top/u_thumbnail_view_reader | 335 | 243 | 2 | 1 |

### DSP 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_s6_video_layer | 610 | 306 | 0 | 4 |
| top/u_boot_layer | 189 | 65 | 10 | 3 |
| top/u_brightness_contrast_adjust | 22 | 20 | 0 | 3 |
| top/u_video_transition_apply | 12 | 0 | 0 | 3 |
| top/u_pcm_volume_fade | 3 | 1 | 0 | 1 |
| top/u_thumbnail_view_reader | 335 | 243 | 2 | 1 |

### 子模块热点（与父树重叠，仅用于定位）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_file_streamer | 539 | 282 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db | 1025 | 894 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_volume_scanner | 1211 | 1037 | 0 | 0 |
| top/u_expansion_integration/u_exp_echo_reporter | 951 | 352 | 0 | 0 |
| top/u_lrc_osd/u_font_rom | 420 | 0 | 0 | 0 |

## X0R_R2_bootfields_20261007

### 各时钟 Fmax（TD 原生报告值）

| 时钟 | Fmax MHz | 最小周期 ns |
|---|---:|---:|
| sd_card_clk | 101.492 | 9.853 |
| video_clk | 36.587 | 27.332 |
| clk | 57.727 | 17.323 |
| ext_mem_clk | 133.923 | 7.467 |
| hdmi_5x_clk | 303.859 | 3.291 |

### LUT 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4532 | 3357 | 0 | 0 |
| top/u_expansion_integration | 3412 | 1668 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1696 | 1467 | 16 | 0 |
| top/u_video_rgb_to_axis_640x480 | 679 | 78 | 0 | 0 |
| top/u_lrc_osd | 644 | 86 | 0 | 0 |
| top/u_s6_video_layer | 604 | 320 | 0 | 4 |
| top/frame_read_write_m0 | 571 | 381 | 4 | 0 |
| top/u_wav_stream_player | 431 | 271 | 8 | 0 |
| top/u_thumbnail_view_reader | 340 | 255 | 2 | 1 |
| top/u_param_menu_controller | 297 | 176 | 0 | 0 |
| top/U3 | 288 | 387 | 0 | 0 |
| top/u_ui_event_bridge | 278 | 68 | 0 | 0 |

### FF 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0 | 4532 | 3357 | 0 | 0 |
| top/u_expansion_integration | 3412 | 1668 | 0 | 0 |
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1696 | 1467 | 16 | 0 |
| top/U3 | 288 | 387 | 0 | 0 |
| top/frame_read_write_m0 | 571 | 381 | 4 | 0 |
| top/u_s6_video_layer | 604 | 320 | 0 | 4 |
| top/u_wav_stream_player | 431 | 271 | 8 | 0 |
| top/u_thumbnail_view_reader | 340 | 255 | 2 | 1 |
| top/u_param_menu_controller | 297 | 176 | 0 | 0 |
| top/u_sync_fade_gain | 130 | 102 | 0 | 0 |
| top/u_lrc_osd | 644 | 86 | 0 | 0 |
| top/u_mv_stream_player | 122 | 81 | 0 | 0 |

### BRAM 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_hdmi_1_4b_transmitter_core_wrapper | 1696 | 1467 | 16 | 0 |
| top/u_boot_layer | 147 | 64 | 10 | 3 |
| top/u_wav_stream_player | 431 | 271 | 8 | 0 |
| top/frame_read_write_m0 | 571 | 381 | 4 | 0 |
| top/u_thumbnail_view_reader | 340 | 255 | 2 | 1 |

### DSP 排名（顶层互不重叠子树）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/u_s6_video_layer | 604 | 320 | 0 | 4 |
| top/u_boot_layer | 147 | 64 | 10 | 3 |
| top/u_brightness_contrast_adjust | 25 | 23 | 0 | 3 |
| top/u_video_transition_apply | 12 | 1 | 0 | 3 |
| top/u_pcm_volume_fade | 10 | 4 | 0 | 1 |
| top/u_thumbnail_view_reader | 340 | 255 | 2 | 1 |

### 子模块热点（与父树重叠，仅用于定位）

| 实例 | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_file_streamer | 565 | 286 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db | 1032 | 906 | 0 | 0 |
| top/sd_card_bmp_m0/fat32_media_loader_m0/u_volume_scanner | 1184 | 1033 | 0 | 0 |
| top/u_expansion_integration/u_exp_echo_reporter | 949 | 362 | 0 | 0 |
| top/u_lrc_osd/u_font_rom | 420 | 0 | 0 | 0 |
