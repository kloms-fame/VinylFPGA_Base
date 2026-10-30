# 媒体资源与 Git 分发

本目录的索引、歌词、校准数据、背景图、处理说明和脚本随源码保留。PCM、MV、MP4、整卡 IMG、提取帧和 PSD 编辑源不纳入 Git；已有文件保留在原本机路径，不因此次整理而丢失。`tf_card_stage/` 是旧教学阶段的本地拷卡包，也不随源码分发。

最终项目沿用用户人工验收时的媒体卡配置。本轮未重新打包或写卡，未把历史示例媒体指定成新的已验收媒体。只有源码仓库时，需要另外准备自己的媒体输入；旧说明中指向 `.img`、`.bit`、`assets/` 或源视频的路径可能仅存在于原开发机。

| 工具 | 用途 |
| --- | --- |
| `tools/vinyl_packer.py` | 媒体索引、镜像打包与只读校验 |
| `tools/mv_pack.py` | MV 数据转换 |
| `tools/pack_backgrounds.py` | 背景图转换和打包 |
| `tools/gen_lrc_assets.py` | 歌词资源生成 |
| `tools/prepare_s1_media.py`、`prepare_s2_mv.py`、`prepare_s3_lyrics.py` | 分阶段媒体准备 |

在仓库根目录使用各工具的 `--help` 查看参数。镜像只读检查：

```powershell
python -X utf8 tools/vinyl_packer.py verify --image "你的镜像.img"
```

PCM 为 48 kHz、16-bit、单声道；PCM/MV 要求物理连续，相关条目位于根目录首扇区的前 16 个目录项内。不要把分阶段测试镜像与最终验收媒体混用。
