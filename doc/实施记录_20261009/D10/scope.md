# D10：进度、时间与静态播放页

## D10a 后台进度与时间

- 唯一输入使用 `timebase_48k` 的已消费 PCM 样本数，以及当前歌曲的 `play_total_samples`。
- 每个视频帧起点采样一次；elapsed 超过 total 时先饱和到 total。进度精确计算为 `floor(240 × elapsed / total)`，总样本数为 0 时显示空条。
- `×240` 使用移位减法 (`×256 - ×16 - ×8`)，除法使用一个 40 拍 restoring divider；无 `/` 或 `%` 运算进入像素路径。
- elapsed/total 的 `mm:ss` 通过后台样本率除法、秒/分除法和 11 拍 double-dabble 转换成 13 个 ASCII 字节。未知/零时长为 `---:--/---:--`。
- 一帧计算有限在约 200 个视频时钟周期内结束；进度、时间字符串在空白期一起提交。Seek、暂停、切曲沿用既有样本时基。

## D10b 静态播放页

- 页面仅在播放态启用，新增一拍 RGB/DE/VS/x 同步级，并接在 EC2 浮窗之前；最终消隐和 Boot 优先级保持在最末端。
- 现有媒体窗口 `[16,336)×[64,304)` 与波形/峰值区域 `[64,596)×[376,472)` 原像素直通，不搬动 MV/FIFO 坐标。其他播放背景使用常量深色。
- 左侧信息区：歌名 `(24,312)`、歌手 `(24,336)`、`elapsed/total` 时间 `(24,352)`、240 像素进度条 `(24,372)`。
- 右侧歌词面板 `[352,632)×[120,360)`，单行歌词位于 `(356,224)`。标题为空时显示 `TRACK NN`，歌手为空时显示 `ARTIST --`；空歌词显示 `NO LYRICS`，尚未到首句时留空。
- 标题、歌手、ASCII 时间、歌词共享 D9 的 16×16 `song_font_rom` 单同步读口。D9 单行独立渲染器在此阶段关闭，避免重复字库端口。
- EC2 仍在播放页上方；Boot 与消隐仍为末级优先层。

## SynthPilot

SynthPilot / Tang Dynasty 6.2.168116 对隔离快照完成 `opt_gate`，用时约 82.9 秒；器件 EG4S20BG256、数据库 `eagle_s20.db`、顶层 `top`，ADC/SDC 已加载，默认 AUTO 映射。

- 面积报告：LUT 利用量 16,123/19,600（82.26%），报告内 `#Total_luts=10,637`；寄存器 10,032/19,600；MSlice 1,784、LSlice 959（QoR 合计 2,743）；BRAM9K 42/64；DSP 10/29。
- Hierarchy area：`u_playback_page` 为 370 LUT / 138 ripple / 71 seq / 1 BRAM；其中共享 `u_shared_song_font` 为 106 LUT / 1 BRAM。`u_playback_progress` 为 462 LUT / 72 ripple / 333 seq / 0 BRAM。字库仍只有单个同步读实例；全工程 BRAM9K 维持 42。
- 与同会话 D9 AUTO gate 面积观察值相比，LUT site 为 +1,257（14,866→16,123），寄存器 +428（9,604→10,032），BRAM/DSP 不变。此差值仅代表两个源码快照的综合观察，不代表布局布线增量或物理容量结论。
- Gate QoR：setup WNS −297 ps、TNS −1,277 ps、6 个违例端点；hold WNS +471 ps、TNS 0、无违例。STA 覆盖 99.96%。该 gate 结果没有达到 setup 通过门槛。
- SynthPilot basic timing analysis 的最差路径位于既有 `frame_read_write_m0/frame_fifo_write_m0/write_cnt[0]` 到帧 FIFO 读写握手逻辑；后续负裕量路径涉及 `sd_card_bmp_m0/fat32_media_loader_m0/u_song_index_db/valid` 的高扇出。关键路径报告未列出 `u_playback_page` 或 `u_playback_progress` 为端点/主要组合路径；现有读写 FIFO 与 SD 控制路径仍需单独收敛，不能将 gate 负裕量归因于新页面算法。
- 结果报告保存在 `evidence/synthpilot_auto/`。没有执行 place、route、final timing、bitgen、RTL 仿真或板级验收。当前仅证明此快照能综合展开；不声称物理时序通过。
