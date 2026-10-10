# VinylFPGA Stage S3 设计与集成交付摘要

current_stage: S3
goal: 将已通过独立仿真的 UIRES V1 静态槽装载器接入现有 SD 最低优先级 owner、双时钟歌词缓存和 video 域时间定位读取口。

confirmed_constraints:
- 工程入口仍为 `prj/VinylFPGA.al`，顶层仍为 `top`，器件仍为 EG4S20BG256。
- 音频、BMP/MV、FAT32 扫描和既有 `lrc_osd` 像素通路保持原接口和优先级；UIRES 只在封面预加载完成后后台请求。
- UIRES owner 只在扇区边界取得一个扇区，音频外部客户端和 BMP/INDEX 流请求优先；UIRES 扇区完成不冒充旧媒体 supervisor 的 storage_done。
- `lrc_cache` 在 SD 域写入、video 域同步读取；`lyric_timeline` 只消费缓存时间，不自行运行音频计时器。
- 当前阶段只做到 `opt_gate`，未执行 place/route/bit，也未完成动态歌词像素替换。

artifacts:
- `src/SD/song_index_db.v`
- `src/SD/fat32_media_loader.v`
- `src/SD/sd_card_bmp.v`
- `src/SD/uires_static_loader.v`
- `src/top_tf_hdmi_audio.v`
- `sim/tb_uires_static_loader.v`
- `docs/acceptance/VinylFPGA_C2_人工验收清单_20261008.md`

decision: 通过 RTL 定向仿真、既有媒体回归和 SynthPilot 第 12 代 `opt_gate`；资源为 LUT 16478/19600、MSlice 1778/4900、BRAM 42/64。由于 gate Setup WNS 约 -9.945 ns，当前不生成 bit，不宣称物理实现或板级通过。

blocking_reason: 动态歌词像素提交尚未接入；完整工程仍需先完成资源/时序优化，再执行 place/route 和 bitgen。

next_action: 先进行 C2.7 动态歌词显示提交的最小模块级实现与仿真，同时保持旧 `lrc_osd` 可回退；随后重新做 gate、place/route 门禁，只有 route 时序和资源通过后才生成 bit。
