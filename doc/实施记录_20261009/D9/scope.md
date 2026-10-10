# D9：四曲文字 ROM 与单行歌词

## 本次范围

- 保持 INDEX v1/v2 与 512 B 条目格式不变；使用 `song_id` 0..3 绑定编译期文字资料。
- `tools/gen_lrc_assets.py` 保留原 `--lrc` 单曲生成路径，新增 `--songs-manifest` 四曲路径。
- LRC 解析支持每曲最多 128 行、每行最多 16 个 Unicode 字形、u32 毫秒时间；时间升序整理，重复时间由最后一行覆盖。
- 行记录按实际行数紧凑存储，使用每曲起始偏移和行数；歌词、标题、歌手共享去重字形表。
- `{song_id,generation}` 通过独立 `cdc_bundle_latest(WIDTH=3)` 原子跨入视频域。歌词扫描、当前行与歌曲代次在视频帧边界更新；时间来自唯一 `timebase_48k`。
- 单行 OSD 保持既有位置与金色字形样式。空歌词显示 `NO LYRICS`；有歌词但尚未到首句时间时留空。

## 素材状态

当前仓库没有可确认的四曲歌词、歌手和歌曲标题。新增的 `doc/资源/lyrics/songs_manifest.json` 因此显式留空，不使用 `demo.lrc` 中的说明文字，也不把缩略图标签当作歌曲名。上板默认四曲均显示 `NO LYRICS`。获得真实素材后可按下方人工步骤填充 manifest 并重新生成。

## 资源计算口径

当前无歌词素材，字形表包含 25 个去重字符（包含未来播放页的 ASCII 回退文本）；16×16 字库 ROM 深度按 512 行计算，共 8,192 bit。紧凑歌词行 ROM 为 1×165 bit 空表记录。标题/歌手最多各 16 glyph，四曲组合上限为 1,024 bit。它们是 RTL 存储位数，不等同厂商映射后的 BRAM 数；最终以 SynthPilot `opt_gate` 面积报告为准。

## SynthPilot

使用 Tang Dynasty 6.2.168116 / SynthPilot MCP，对 `VinylFPGA_D9_SynthPilot_20261010` 隔离快照执行 `opt_gate`，运行约 59.7 秒，成功完成器件导入、项目展开、RTL 优化、门级优化与器件合法化。器件 EG4S20BG256，数据库 `eagle_s20.db`，顶层 `top`，ADC/SDC 均已加载。该工具流采用 SynthPilot 默认映射策略；结果不与 O6 原生 TD `area_prior + seed 5` 路线直接差分。

- 面积报告：LUT 利用量 14,866/19,600（75.85%）；报告内 `#Total_luts=9,742`；寄存器 9,604/19,600；MSlice 1,665、LSlice 897（QoR 合计 2,562）；BRAM9K 42/64；DSP 10/29。
- gate QoR：setup WNS +123 ps、TNS 0、违例端点 0；hold WNS +471 ps、TNS 0、违例端点 0。计时摘要报告显示已读入约束、STA 覆盖 99.96%；报告均属综合数据库，不代表放置/布线后时序。
- 受约束 gate 面积、QoR、timing summary 与参数报告保存在 `evidence/synthpilot_auto/`。
- 未执行 place、route、timing 实现、bitgen、RTL 仿真或板级验收。自动综合通过只说明本快照可综合，不证明像素显示、曲目绑定或实际音画同步正确。
