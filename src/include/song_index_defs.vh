// =============================================================================
// song_index_defs.vh —— S4 曲目索引 INDEX.BIN 布局（RTL 侧单一事实来源）
//
// 与 PC 侧工具 tools/vinyl_packer.py 必须逐字节一致；改这里必须同步改那里。
// 全文件小端（little-endian），长度固定 512 字节（正好 1 个扇区）。
//
// ---- 头部 64 字节 ----
//   偏移  长度  字段
//   0     8     magic = "VINYLIDX"
//   8     2     version = 1
//   10    2     entry_size = 64
//   12    2     song_count（1..MAX_SONGS，超限必须报错，不得静默越界）
//   14    2     max_songs（写入端声明，读取端仅作参考校验）
//   16    4     entries_crc32（CRC-32/ISO-HDLC，覆盖 [64, 64+song_count*64) ）
//   20    4     flags（bit0=索引由 vinyl_packer 生成）
//   24    40    reserved（必须为 0）
//
// ---- 曲目条目 64 字节 × song_count，起始偏移 64 ----
//   偏移  长度  字段
//   0     4     flags：bit0=有封面 bmp，bit1=有音频 pcm，bit2=歌词，bit3=MV
//   4     4     cover_first_cluster
//   8     4     cover_bytes（BMP 文件字节数）
//   12    4     cover_crc32（记录值；PC 侧 SHA256 见 INDEX.json）
//   16    4     audio_first_cluster
//   20    4     audio_bytes（裸 PCM 字节数）
//   24    4     audio_crc32（记录值）
//   28    4     audio_start_sector_hint（PC 侧解析出的物理起始 LBA，便于追溯）
//   32    24    title（ASCII，NUL 补齐；RTL 不消费）
//   56    8     reserved
//
// 说明：RTL 只按 first_cluster 走 FAT 链取数（复用 fat32_file_streamer），
//       因此封面天然支持碎片；audio_start_sector_hint 仅供 PC 侧追溯与 S5 使用。
// =============================================================================

localparam [7:0]  SIDX_MAGIC_0 = "V";
localparam [7:0]  SIDX_MAGIC_1 = "I";
localparam [7:0]  SIDX_MAGIC_2 = "N";
localparam [7:0]  SIDX_MAGIC_3 = "Y";
localparam [7:0]  SIDX_MAGIC_4 = "L";
localparam [7:0]  SIDX_MAGIC_5 = "I";
localparam [7:0]  SIDX_MAGIC_6 = "D";
localparam [7:0]  SIDX_MAGIC_7 = "X";

localparam [15:0] SIDX_VERSION     = 16'd1;
localparam [15:0] SIDX_ENTRY_SIZE  = 16'd64;
localparam [15:0] SIDX_MAX_SONGS   = 16'd4;
localparam [15:0] SIDX_HEADER_SIZE = 16'd64;

localparam [2:0]  SIDX_FLAG_COVER = 3'd0;
localparam [2:0]  SIDX_FLAG_AUDIO = 3'd1;
localparam [2:0]  SIDX_FLAG_LRC   = 3'd2;
localparam [2:0]  SIDX_FLAG_MV    = 3'd3;

// 索引错误码（与既有 FAT32 fs_error/bmp_error 值域不冲突）
localparam [7:0] SIDX_ERR_NONE          = 8'h00;
localparam [7:0] SIDX_ERR_MAGIC         = 8'h30;
localparam [7:0] SIDX_ERR_VERSION       = 8'h31;
localparam [7:0] SIDX_ERR_ENTRY_SIZE    = 8'h32;
localparam [7:0] SIDX_ERR_COUNT         = 8'h33;
localparam [7:0] SIDX_ERR_CRC           = 8'h34;
localparam [7:0] SIDX_ERR_CLUSTER_RANGE = 8'h35;
localparam [7:0] SIDX_ERR_STREAM        = 8'h36;
localparam [7:0] SIDX_ERR_NO_COVER      = 8'h37;
