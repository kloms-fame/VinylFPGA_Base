# 阶段四 SD 卡镜像生成与写卡说明

2026-10-13。本轮只生成、读取工作区内的镜像文件，没有打开或写入物理磁盘。原 `card_S6.img` 和阶段三镜像保留。

## 一、使用本轮新镜像

阶段四固件的完整背景验收使用：

`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\doc\资源\sd卡\stage4\card_STAGE4.img`

| 项目 | 结果 |
|---|---|
| 镜像大小 | 134217728 字节，即 128 MiB |
| 镜像 SHA256 | `e9f24f4c8a901a820fd2a0d6b4fdad572d9d842a6af5390ca3b0fb059b0f94f1` |
| 只读来源 | `doc\资源\sd卡\card_S6.img` |
| 来源 SHA256 | `a8be9d182a9b206a39f8baffe5277fe93fd1308221ffed14d7c0af70611b42ef` |
| INDEX 条目 CRC32 | `0x0218C950` |
| BGR1 背景帧数 | 6 |
| BG.BIN 起始 LBA | 147317 |
| 每帧 | 640×480，RGB565 小端，614400 字节，1200 扇区 |
| BG.BIN 总长度 | 3686400 字节，7200 个连续扇区 |

帧 0～3 为四首歌曲各自的封面模糊图；帧 4 为蓝紫柔和 ART1；帧 5 为暖金/青灰柔和 ART2。两张艺术图在 FPGA 内复用同一个 SDRAM 槽，切换时等待装载和帧边界提交。装载期间显示灰底，实际装载时间由板上验收测量。

独立导出文件 `ART1.BIN`、`ART2.BIN`、`BG.BIN`、`INDEX.BIN` 和 PNG 预览位于同一 stage4 目录。镜像已经包含背景数据和索引，独立导出主要供核查、预览和后续离线制作使用。

## 二、生成及离线核验结果

执行命令：

```powershell
Set-Location -LiteralPath 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA'
& 'D:\Anaconda\python.exe' 'tools/test_pack_backgrounds.py'
& 'D:\Anaconda\python.exe' 'tools/pack_backgrounds.py' --source 'doc/资源/sd卡/card_S6.img' --output-dir 'doc/资源/sd卡/stage4'
```

本轮 14 项离线测试通过。覆盖 RGB565 编解码、有序抖动、旧索引、新旧背景头、无效边界、原文件保留、连续物理回读、拒绝覆盖和 MBR 扩容。

打包器内建核验也通过：

- 来源镜像在打包前后 SHA256 一致。
- 原目录项、簇号、文件内容保留；扩容后数据区整体移动 1822 个扇区，INDEX 内绝对音频/MV LBA 随之修正。
- 所有原媒体文件搬迁回读的 SHA256 与来源一致；封面与音频 CRC 通过。
- INDEX 条目 CRC、索引回读、音频/MV 起始 LBA、大小和连续性检查通过。
- BG.BIN 为单一连续簇链，完整 6 帧物理 LBA 回读与生成数据逐字节一致。
- ART1/ART2 的独立 BIN 与 BG.BIN 对应帧、记录的 SHA256 和解码 PNG 预览一致，且两张艺术图内容不同。

详细证据见：

`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\doc\资源\sd卡\stage4\background_pack_report.json`

打包器拒绝覆盖已存在的 `card_STAGE4.img`。需要重新生成时，指定新的输出目录并核对新报告中的 SHA256。

## 三、用户自行写卡

### 3.1 直接使用已生成镜像

本轮文件已经打包完成；首次验收直接写现有 `stage4/card_STAGE4.img`，不需要先重新打包。建议保留此前能用的测试卡，使用另一张容量至少 128 MiB 的卡验收。

1. 在电脑上校验本轮镜像：

   ```powershell
   Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\doc\资源\sd卡\stage4\card_STAGE4.img'
   ```

   结果应与上表镜像 SHA256 一致。

2. 将测试 SD 卡连接读卡器，使用支持原始 `.img` 镜像的写卡工具，选择上述 `card_STAGE4.img` 和对应的测试 SD 卡。核对目标卡的型号、容量与盘符；写镜像会覆盖目标卡已有内容，需要的文件请先保存。
3. 执行完整镜像写入并启用工具的写后回读校验；等待写入、校验结束后安全弹出。
4. 开发板断电后插入 SD 卡，再上电，并自行烧录与阶段四匹配的 bit 固件。
5. 按下文核验背景和媒体功能。

当前用户维护的 `write_card.ps1`、`write_firmware_card.bat` 未被本轮修改。其选项 8/9 和 FirmwareAuto 仍指向旧 `stage3b/card_STAGE3B.img`，不能用这些现有选项完成 ART2 新镜像验收。请在写卡工具中明确选择 stage4 镜像；将 `.img` 作为普通文件复制到 SD 卡不等同于写入整盘镜像。

### 3.2 Windows 图形写卡步骤

可使用 [Raspberry Pi Imager 官方下载入口](https://www.raspberrypi.com/software/)。其 [官方使用文档](https://www.raspberrypi.com/documentation/computers/getting-started.html) 支持自定义 `.img`；这里利用它的镜像写盘功能，选择本项目镜像。

1. 插入读卡器，打开 Windows 磁盘管理或资源管理器，记住目标卡的盘符和容量；关闭正在访问卡的程序。
2. 打开 Imager。在选择系统/镜像的页面选择 **Use Custom / 自定义镜像**，定位 `D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA\doc\资源\sd卡\stage4\card_STAGE4.img`。
3. 在 **Choose Storage / 选择存储设备** 中选测试 SD 卡，核对容量及设备名称。
4. 如果出现系统定制选项，不应用主机名、Wi-Fi、SSH 等设置；这是 FPGA 的媒体数据盘。
5. 执行 **Write / 写入**，确认目标卡覆盖提示，允许工具所需的管理员权限。保持写后校验启用，等待写入和校验都结束。
6. 安全弹出读卡器。Windows 若询问格式化，不执行格式化；完整镜像已经包含项目需要的 FAT32 结构。
7. 开发板断电后插卡，连接 HDMI、音频和下载线，再上电、烧录本轮 bit。

不同 Imager 版本的按钮排布可能略有不同；关键是“自定义 stage4 镜像 → 正确测试卡 → 完整写入 → 回读校验”。128 MiB 是镜像内文件系统容量，大容量实体卡的剩余空间不参与此次验收，不需要扩分区。

### 3.3 以后重新打包

在 PowerShell 执行以下命令，新目录名可以替换为本次版本号；输出目录中的镜像不能已经存在：

```powershell
Set-Location -LiteralPath 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA'
& 'D:\Anaconda\python.exe' 'tools/pack_backgrounds.py' `
  --source 'doc/资源/sd卡/card_S6.img' `
  --output-dir 'doc/资源/sd卡/stage4_repack_01' `
  --size-mib 128
if ($LASTEXITCODE -ne 0) { throw '镜像打包失败，请查看命令输出' }
Get-FileHash -Algorithm SHA256 -LiteralPath 'doc/资源/sd卡/stage4_repack_01/card_STAGE4.img'
Get-Content -LiteralPath 'doc/资源/sd卡/stage4_repack_01/background_pack_report.json'
```

打包器通过现有 Python/Pillow 环境运行。检查报告中的 `frame_count=6`、`input_unchanged=true`、`physical_background_readback=true`，镜像 SHA256 与报告一致，之后写入这个新目录内的镜像。

新目录会同时生成歌曲背景预览、`shared_art.png`、`shared_art_2.png`、`ART1.BIN`、`ART2.BIN`、`BG.BIN`、`INDEX.BIN` 和报告。可先打开 PNG 确认效果；两张艺术图由电脑端算法生成，FPGA 不实时做模糊或生成光晕。

本工具从已有效的 S6 基础卡生成背景增强镜像。以后更换歌曲/封面/MV，应先按照原媒体打包流程制作有效基础卡，再把 `--source` 指向新基础镜像，重新生成整个 stage4 镜像；不要把已经含 BG.BIN 的 stage3b/stage4 镜像直接作为来源，也不要在成品卡上手工替换 BG.BIN 或 INDEX.BIN，这会破坏绝对 LBA、连续性或 CRC 的对应关系。重新打包后的摘要以新报告为准。

## 四、新旧卡兼容与人工验收

阶段四背景解析兼容旧 5 帧 BGR1 卡和新 6 帧卡。旧 5 帧卡保留歌曲背景及 ART1；选择 ART2 时因卡内没有第 6 帧而回退灰底。验收 ART2 需要新 stage4 卡。

建议使用新镜像逐项检查：

1. KEY11 循环：柔和灰 → 当前歌曲封面模糊背景 → ART1 蓝紫 → ART2 暖金/青灰 → 柔和灰。两张艺术图应有明显风格差异。
2. 反复从 ART1 切到 ART2，并快速连续按 KEY11。允许加载期间暂时灰底；完成后应显示最终选定的艺术图，不应混合两张图或出现旧图残留。
3. 在歌曲模糊背景模式切换四首歌，确认背景随歌曲变化，播放保持连续，没有固定横线。
4. 切回选歌页，再进入播放页，确认模式在本次上电期间保持；复位后回到灰底。
5. 第一首的 MV 与其他歌曲静态封面、标题、歌手、歌词、进度及时长正常；结合主实施报告继续检查完整封面缩放及 MV 首帧黑场。
6. 如需要兼容性验收，换回原 5 帧卡重测 ART1 与歌曲背景，并确认 ART2 灰底回退。原镜像可直接供恢复使用。

离线核验不能替代开发板、SD 卡实际读写和视觉验收。上述板级结果由用户确认，验收通过后再提交阶段四改动。
