# VinylFPGA 本阶段验收收尾（2026-10-08）

## 已通过

- SynthPilot 连接正常，TD Tcl 8.6.15，器件 `EG4S20BG256`。
- 定向核心仿真 12/12 PASS：C1 参数/EC2、C2 索引/MV/UIRES/歌词、C3 壁纸控制、U1 元数据、X2 Seek、S7 顶层烟囱。
- `elaborate → optimize_rtl → optimize_gate` 通过。
- `tb_lyric_loader_timeline.v` 的 Icarus Verilog-2005 端口连接问题已修正：`rd_addr` 改为 `wire`。
- `song_index_db` 保留 MV 元数据解析，受影响回归通过。

## 当前未放行项

- 当前工作区 `prj/VinylFPGA.al` 在 place 阶段被 TD 拒绝：`PHY-9009`，MSlice `5223 > 4900`，因此本轮没有 route/timing/bitgen，也没有生成“当前 U2 网表”的可烧录 bit。
- gate QoR：LUT 12464（器件 LUT 19600，约 95.87%）；BRAM 58/64；DSP 17/29；寄存器 11853/19600。
- gate 时序尚未具备放行条件：Setup WNS `-2200 ps`、TNS `-26874 ps`、25 个违例端点；Hold WNS `+471 ps`、Hold TNS `0`。

## 可用历史基线

`prj/VinylFPGA_C2_corelink_20261008.bit` 为此前 C2 corelink 版本，SHA-256：
`82BA20F4F522A6B8D92D4782019E2DABF453A8522D5105ED5BEE063483CF898C`。
该文件不代表当前 U2 工作区，不能作为本轮 U2 功能已固化的证明。

## 人工验收边界

1. 可人工验收已通过的仿真功能与源码差异。
2. 暂不对当前 U2 工作区执行烧录验收；需下一轮资源压缩/布放收敛后重新生成 bit。
3. 不将历史 C2 bit 的下载成功等同于当前 U2 网表通过。
