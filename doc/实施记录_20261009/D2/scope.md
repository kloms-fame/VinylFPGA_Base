# D2 48 kHz 测试音演示

## 实施范围

- 生成 48 kHz、16-bit signed little-endian、mono、1 kHz 正弦裸 PCM，时长 5 秒，峰值约 -12 dBFS。
- 测试音经现有 SD/PCM/HDMI 播放链播放；本阶段没有新增 RTL 音源或修改 HDMI 音频链。
- 创建独立演示卡镜像，只把界面曲目 1（索引 entry 0）的 `AUDIO.PCM` 替换为测试音；其他三首保留封面但不附带音频。原始 `doc/资源/sd卡/card.img` 未修改。
- 生成器拒绝覆盖已有输出；镜像工具只在克隆副本上改写 FAT 链和根目录文件大小，然后重新打包并验证索引/CRC。

## 当前状态

PCM 合同测试 4 项通过；演示镜像包含 4 个曲目并通过 `vinyl_packer verify`，索引 CRC32 为 `0xC70A2107`。实际 FPGA 播放、暂停/恢复、音量和人工听音尚待上板，记录见 `manual.md`。
