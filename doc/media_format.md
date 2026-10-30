# 媒体格式与资源准备

最终演示沿用用户人工验收时的媒体卡配置。本次源码交付不包含完整 TF 卡镜像、商业音视频原素材或历史媒体发布包，也未为整张验收卡建立新的哈希绑定。原素材保留在工作区旁的 `VinylFPGA_file` 等资料目录，源码克隆需要另外准备相符媒体。

## 板端约定

| 数据 | 当前格式 |
| --- | --- |
| 文件系统 | FAT32；由 FPGA 扫描并读取索引与文件信息 |
| BMP | 640×480、24-bit RGB、非压缩 BMP；由读取器解析文件头及像素布局 |
| PCM | 48 kHz、16-bit 有符号小端、单声道裸样本；无 WAV 容器头 |
| MV | 无容器头的 RGB565LE 帧序列，320×240、10 fps；从上到下、逐行存储 |
| MV 单帧 | 153,600 字节，即 300 个 512-byte 扇区 |
| 歌词/标题 | 当前版本的字形、行表 ROM 已包含于 `src/display/`，不是运行时任意字体渲染 |
| 背景 | 按索引及背景工具所定义的布局打包，由背景缓存通路读取 |

PCM/MV 必须满足板端所需的物理连续布局；相关条目应处于根目录首扇区的前 16 个目录项内。封面读取支持 FAT 链不意味着音频/MV 也允许碎片。单纯将文件复制到卡上或在 PC 播放正常，不能证明满足板端布局要求。

## 工具

在项目根目录运行。媒体图像处理需要 Pillow，可使用 `python -m pip install -r requirements-media.txt` 安装；实际参数以各工具的 `--help` 为准。

```powershell
python tools/vinyl_packer.py --help
python tools/pack_backgrounds.py --help
python tools/mv_pack.py --help
```

[vinyl_packer.py](../tools/vinyl_packer.py)负责索引/镜像操作与验证。[pack_backgrounds.py](../tools/pack_backgrounds.py)负责背景准备。[mv_pack.py](../tools/mv_pack.py)只将已经整理好的有序图像帧编码成 MV，不负责 MP4 解码、帧率重采样、缩放或裁切。

例如，输入帧已为 320×240、10 fps，且文件名以补零数字保持时间顺序时：

```powershell
python tools/mv_pack.py --frames "你的帧目录" --output "TRACK1.MV"
```

输出按文件名字典序排列。将 MP4 改扩展名为 `.MV` 无法使用；时间轴与音频的对齐需在输入准备时保留，并在板上检查。

只读检查镜像：

```powershell
python tools/vinyl_packer.py verify --image "你的镜像.img"
```

以完整命令退出码 0 判定通过，前面的单项输出不代表整体成功。`pack` 是写操作，应针对明确的文件副本使用；本次提交整理不自动写入物理卡或生成替代验收媒体。

## 资源与提交的关系

源码包保留仿真所需的小型 HEX 夹具，测试不依赖原机器的大体积媒体库。实际展示仍需准备已验收的 TF 卡、显示/声音设备及同一版本固件。若修改歌词 ROM、媒体格式、帧率、索引、背景布局或曲目内容，应建立新版本并重新验证对应功能，不能沿用旧卡的验收结论。
