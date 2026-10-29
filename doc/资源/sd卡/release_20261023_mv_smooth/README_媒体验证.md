# 2026-10-23 MV 播放修复配套媒体包

本目录的 SD 镜像已从四条原始 MP4 重新生成 MV 并完整回读。镜像为普通文件，未写入物理 SD 卡。固件由同轮硬件构建另外提供；请以最终 `release_manifest.json` 为固件身份依据。

本轮固件已放入本目录：`VinylFPGA_MV_Smooth_20261023.bit`，SHA-256 为 `62b37ab748a67dad02d09d8e01c5fe33a2c0d971476e27f8ce9ec781e4d28d34`；`SHA256SUMS_FIRMWARE.txt` 同时记录 BID 与 bitgen 参数文件。原工程完整构建及最终时序通过，实板连续播放待验收。若卡上已是同哈希的原 fullbleed 镜像，直接使用新固件即可。

镜像：`VinylFPGA_SD_4SONGS_4MVS_MANUAL_LYRICS_MV_SMOOTH_20261023.img`。

- 大小：1,610,612,736 字节（1536 MiB）。
- SHA-256：`3bf36c259d093b9f85fd538892e11c74275b1e68111ed366b8c77e58cd654654`。
- 视频合同：320×240、RGB565LE、10 fps、每帧 153,600 字节 / 300 扇区，四首分别为 2123、1693、855、2439 帧。
- 保留已审阅的裁边与铺满 4:3 画面方式。第一首先去除原侧边黑条，第四首先去除原上下黑条。
- 每首保持独立 PCM、原人工校准歌词、封面和背景。全部 INDEX、FAT、目录、非 MV 文件和未使用空间与原发布逐段 SHA-256 一致。

## 媒体处理与卡顿结论

本次采用显式 `fps=fps=10:start_time=0:round=near:eof_action=round` 按源 PTS 采样，先抽取所需帧再缩放，降低离线素材制作工作量。没有把非零源视频起始 PTS 强制归零，因此没有人为改变音频与视频原有起始关系。解码、过滤、输出最多分别使用 2 个线程，按歌曲顺序处理。

重建的四条 MV **逐字节等于 2026-10-20 fullbleed 发布**，全镜像 SHA-256 也相同。这是完整复现和验证，不宣称素材重编码修复了 SD 取数停顿。此次实际运行时抗停顿改善来自同轮 RTL 修复，验证边界应查阅最终硬件报告。

全部原视频 PTS 严格递增，最大帧间隔不超过 40 ms，没有超过 100 ms 的时间戳洞。下表完全相同的输出画面来自源内容，保留正常时长：

| 曲目 | 发布流中的静止区间（秒，右端不含） | 来源 |
|---|---|---|
| 第二首 | 0.0–0.5、163.7–163.9、163.9–164.7、164.7–164.9 | 原视频已有静止/重复，原分辨率解码窗口也含连续重复帧；少量不同编码噪声经 RGB565 量化后合并 |
| 第四首 | 72.2–72.5、242.8–243.9 | 输出是全黑帧；末尾原视频也有连续重复帧 |

第一、三首没有相邻完全相同的输出帧。没有删去静止片段、缩短时间线、伪造动作或插入运动补偿帧。10 fps 本身每张画面保持约 100 ms；该合同没有升级为 25/30/60 fps。

## 证据与复现

`S2_mv_manifest.json` 是本次真实镜像清单，包含四条实际 MV、源哈希、采样命令、逐帧哈希路径、重复区间、物理 LBA、整镜像哈希及非 MV 区域哈希。`S1_media_manifest.json` 和 `S3_lyrics_manifest.json` 保留原来源记录，并增加本次最终镜像指向与保留说明。`SHA256SUMS_MEDIA.txt` 提供镜像和四条裸 MV 的哈希。

`evidence/source_audit/` 保存全部源帧 PTS、原分辨率局部解码帧哈希及执行命令。局部帧哈希的窗口时间按 seek 请求和片段相对时间计算，允许一张原生帧的取整误差；精确源 PTS 以 `source_N_pts.json` 为准。

在项目根目录复现（输出目录须不存在）：

```powershell
python -X utf8 tools/audit_mv_timeline.py --manifest "doc/资源/sd卡/release_20261020_manual_lyrics_4songs_4mvs_fullbleed/S2_mv_manifest.json" --output ".codex_tmp/mv_source_audit_new"
python -X utf8 tools/build_mv_smooth_release.py --manifest "doc/资源/sd卡/release_20261020_manual_lyrics_4songs_4mvs_fullbleed/S2_mv_manifest.json" --source-audit ".codex_tmp/mv_source_audit_new" --output "doc/资源/sd卡/release_mv_verified_new"
```

这些检查证明本地镜像与素材身份、布局和完整性，不能代替真实 SD 卡长尾延迟与整机播放验收。
