`timescale 1ns/1ps
`ifndef EXP_SONG_INDEX_DB_V
`define EXP_SONG_INDEX_DB_V
// =============================================================================
// song_index_db —— S4：曲目索引 INDEX.BIN 的流式解析与校验
//
// 输入不是扇区接口，而是已由 fat32_file_streamer 走完 FAT 簇链的**字节流**
// （in_valid/in_byte/in_done）。因此索引本身天然支持碎片链，并完全复用既有
// 已验证的链校验（ERR_FAT_LOOP / ERR_CLUSTER_RANGE / ERR_EARLY_EOF），
// 不新增扇区仲裁通路。
//
// 布局见 src/include/song_index_defs.vh（必须与 tools/vinyl_packer.py 一致）。
//
// 时序设计（本模块位于 sd_card_clk 100 MHz 域，必须避免宽组合树）：
//   * 自带 byte_idx 计数，不消费流读取器的 file_byte_offset
//     （那是 32 位减法器，在本设计里原本无人使用、可被裁剪；一旦引用就会
//      把 32 位减法器拉进 100 MHz 关键区域）。
//   * 条目范围校验拆到 P_CHK 阶段"每拍只比较一首歌"，不在 in_done 当拍
//     把 4 路 32 位比较器拼成宽组合树去驱动大量寄存器使能。
//   * 一级状态机：P_IDLE -> P_STREAM -> P_CHK -> P_FIN -> P_IDLE。
//
// 校验顺序：magic -> version -> entry_size -> song_count 上限 -> entries_crc32
//           -> 每首必含封面且 cluster 落在 [2, max_cluster]
// 任一失败 valid=0 并给出 err，由上层回退到 PIC1~4 旧路径。
//
// 说明：RTL 只校验索引自身的 CRC32；封面/音频的文件级 SHA256/CRC32 由 PC 侧
// 工具写进 INDEX.json 并与卡上数据比对，属"PC 侧可追溯"，不在关键路径上重算。
// =============================================================================
module song_index_db #(
    parameter integer MAX_SONGS = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,        // 1 拍：开始新一轮解析（清空状态）
    input  wire        in_valid,     // 文件流字节有效（1 字节/拍）
    input  wire [7:0]  in_byte,
    input  wire        in_done,      // 文件流结束（1 拍）
    input  wire [7:0]  in_error,     // 文件流错误码（0=正常）
    input  wire [31:0] max_cluster,

    output reg         busy,
    output reg         done,         // 1 拍：解析结束
    output reg         valid,        // 1=索引可用
    output reg  [7:0]  err,
    output reg  [2:0]  song_count,
    output reg  [15:0] song_flags,   // 每首歌 4bit {mv,lrc,pcm,cover}
    // 每首歌 {bytes[63:32], first_cluster[31:0]}
    output reg  [63:0] song_cover0,
    output reg  [63:0] song_cover1,
    output reg  [63:0] song_cover2,
    output reg  [63:0] song_cover3,
    output reg  [63:0] song_audio0,
    output reg  [63:0] song_audio1,
    output reg  [63:0] song_audio2,
    output reg  [63:0] song_audio3
);
    `include "song_index_defs.vh"

    localparam integer ENTRY_BYTES = 64;
    localparam [31:0]  PAY_END     = 32'd64 + (MAX_SONGS * ENTRY_BYTES);

    localparam [1:0] P_IDLE   = 2'd0;
    localparam [1:0] P_STREAM = 2'd1;
    localparam [1:0] P_CHK    = 2'd2;
    localparam [1:0] P_FIN    = 2'd3;

    reg [1:0]  phase;
    reg [2:0]  chk_idx;
    reg        chk_ok;
    reg [7:0]  fin_err;

    // ---- 头部 ----
    reg        magic_ok;
    reg [15:0] hdr_version;
    reg [15:0] hdr_entry_size;
    reg [15:0] hdr_count;
    reg [15:0] hdr_max;
    reg [31:0] hdr_crc_exp;
    reg [31:0] crc_calc;
    reg [8:0]  byte_idx;

    // ---- 条目 ----
    // 封面：每首都要（S4 的 4 张封面来自索引）—— 保留 4 组。
    reg [31:0] e_cov_cl [0:MAX_SONGS-1];
    reg [31:0] e_cov_by [0:MAX_SONGS-1];
    // 标志与音频：S4 沿用既有"单轨播放"语义，只保留第 1 首的音频定位，
    // 其余曲目只记"是否有封面/音频"位。这样比保留 4×32bit 音频字段省约
    // 200 个触发器，避免把 sd_card_clk 的既有加法链挤出时序预算；
    // 多曲音频选择属 S5（届时把音频字段重新展开为 4 组即可）。
    reg [3:0]  e_has_cover;
    reg        e_has_audio0;
    reg [31:0] e_aud_cl0;
    reg [31:0] e_aud_by0;

    integer k;

    wire [31:0] off        = {23'd0, byte_idx};
    wire        in_header  = (off < 32'd64);
    wire [31:0] pay_off    = off - 32'd64;
    wire [1:0]  entry_sel  = pay_off[7:6];
    wire [5:0]  entry_off  = pay_off[5:0];
    wire        in_entries = (off >= 32'd64) && (off < PAY_END);

    wire [31:0] crc_end     = 32'd64 + ({16'd0, hdr_count} << 6);
    wire        crc_span_ok = (hdr_count >= 16'd1) && (hdr_count <= SIDX_MAX_SONGS);
    wire        crc_in_span = crc_span_ok && (off >= 32'd64) && (off < crc_end);
    wire [31:0] crc_final   = crc_calc ^ 32'hFFFFFFFF;

    // P_CHK 阶段每拍只比较一首歌
    wire cover_entry_bad =
        !e_has_cover[chk_idx] ||
        (e_cov_cl[chk_idx] < 32'd2) ||
        (e_cov_cl[chk_idx] > max_cluster) ||
        (e_cov_by[chk_idx] == 32'd0);

    // CRC-32/ISO-HDLC 的按字节内层循环（反射多项式 0xEDB88320）
    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0]  data;
        integer b;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data};
            for (b = 0; b < 8; b = b + 1)
                c = (c >> 1) ^ (32'hEDB88320 & {32{c[0]}});
            crc32_byte = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase          <= P_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            valid          <= 1'b0;
            err            <= SIDX_ERR_NONE;
            song_count     <= 3'd0;
            song_flags     <= 16'd0;
            song_cover0    <= 64'd0;
            song_cover1    <= 64'd0;
            song_cover2    <= 64'd0;
            song_cover3    <= 64'd0;
            song_audio0    <= 64'd0;
            song_audio1    <= 64'd0;
            song_audio2    <= 64'd0;
            song_audio3    <= 64'd0;
            chk_idx        <= 3'd0;
            chk_ok         <= 1'b0;
            fin_err        <= SIDX_ERR_NONE;
            magic_ok       <= 1'b0;
            hdr_version    <= 16'd0;
            hdr_entry_size <= 16'd0;
            hdr_count      <= 16'd0;
            hdr_max        <= 16'd0;
            hdr_crc_exp    <= 32'd0;
            crc_calc       <= 32'hFFFFFFFF;
            byte_idx       <= 9'd0;
            e_has_cover    <= 4'd0;
            e_has_audio0   <= 1'b0;
            e_aud_cl0      <= 32'd0;
            e_aud_by0      <= 32'd0;
            for (k = 0; k < MAX_SONGS; k = k + 1) begin
                e_cov_cl[k] <= 32'd0;
                e_cov_by[k] <= 32'd0;
            end
        end else begin
            done <= 1'b0;

            case (phase)
            // -------------------------------------------------------------
            P_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy           <= 1'b1;
                    valid          <= 1'b0;
                    err            <= SIDX_ERR_NONE;
                    song_count     <= 3'd0;
                    song_flags     <= 16'd0;
                    chk_idx        <= 3'd0;
                    chk_ok         <= 1'b1;
                    fin_err        <= SIDX_ERR_NONE;
                    magic_ok       <= 1'b1;
                    hdr_version    <= 16'd0;
                    hdr_entry_size <= 16'd0;
                    hdr_count      <= 16'd0;
                    hdr_max        <= 16'd0;
                    hdr_crc_exp    <= 32'd0;
                    crc_calc       <= 32'hFFFFFFFF;
                    byte_idx       <= 9'd0;
                    e_has_cover    <= 4'd0;
                    e_has_audio0   <= 1'b0;
                    e_aud_cl0      <= 32'd0;
                    e_aud_by0      <= 32'd0;
                    for (k = 0; k < MAX_SONGS; k = k + 1) begin
                        e_cov_cl[k] <= 32'd0;
                        e_cov_by[k] <= 32'd0;
                    end
                    phase <= P_STREAM;
                end
            end
            // -------------------------------------------------------------
            P_STREAM: begin
                busy <= 1'b1;

                if (in_valid) begin
                    byte_idx <= byte_idx + 9'd1;
                    if (in_header) begin
                        case (off[5:0])
                            6'd0:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_0);
                            6'd1:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_1);
                            6'd2:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_2);
                            6'd3:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_3);
                            6'd4:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_4);
                            6'd5:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_5);
                            6'd6:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_6);
                            6'd7:  magic_ok <= magic_ok & (in_byte == SIDX_MAGIC_7);
                            6'd8:  hdr_version[7:0]    <= in_byte;
                            6'd9:  hdr_version[15:8]   <= in_byte;
                            6'd10: hdr_entry_size[7:0] <= in_byte;
                            6'd11: hdr_entry_size[15:8]<= in_byte;
                            6'd12: hdr_count[7:0]      <= in_byte;
                            6'd13: hdr_count[15:8]     <= in_byte;
                            6'd14: hdr_max[7:0]        <= in_byte;
                            6'd15: hdr_max[15:8]       <= in_byte;
                            6'd16: hdr_crc_exp[7:0]    <= in_byte;
                            6'd17: hdr_crc_exp[15:8]   <= in_byte;
                            6'd18: hdr_crc_exp[23:16]  <= in_byte;
                            6'd19: hdr_crc_exp[31:24]  <= in_byte;
                            default: ;
                        endcase
                    end else if (in_entries) begin
                        if (crc_in_span)
                            crc_calc <= crc32_byte(crc_calc, in_byte);

                        if (entry_off == 6'd0) begin
                            e_has_cover[entry_sel] <= in_byte[SIDX_FLAG_COVER];
                            if (entry_sel == 2'd0)
                                e_has_audio0 <= in_byte[SIDX_FLAG_AUDIO];
                        end else if (entry_off <= 6'd7) begin
                            e_cov_cl[entry_sel] <= {in_byte, e_cov_cl[entry_sel][31:8]};
                        end else if (entry_off <= 6'd11) begin
                            e_cov_by[entry_sel] <= {in_byte, e_cov_by[entry_sel][31:8]};
                        end else if (entry_sel == 2'd0 &&
                                     entry_off >= 6'd16 && entry_off <= 6'd19) begin
                            e_aud_cl0 <= {in_byte, e_aud_cl0[31:8]};
                        end else if (entry_sel == 2'd0 &&
                                     entry_off >= 6'd20 && entry_off <= 6'd23) begin
                            e_aud_by0 <= {in_byte, e_aud_by0[31:8]};
                        end
                    end
                end

                if (in_done) begin
                    if (in_error != 8'h00)
                        fin_err <= SIDX_ERR_STREAM;
                    else if (!magic_ok)
                        fin_err <= SIDX_ERR_MAGIC;
                    else if (hdr_version != SIDX_VERSION)
                        fin_err <= SIDX_ERR_VERSION;
                    else if (hdr_entry_size != SIDX_ENTRY_SIZE)
                        fin_err <= SIDX_ERR_ENTRY_SIZE;
                    else if ((hdr_count < 16'd1) || (hdr_count > SIDX_MAX_SONGS))
                        fin_err <= SIDX_ERR_COUNT;
                    else if (crc_final != hdr_crc_exp)
                        fin_err <= SIDX_ERR_CRC;
                    else
                        fin_err <= SIDX_ERR_NONE;
                    chk_idx <= 3'd0;
                    chk_ok  <= 1'b1;
                    phase   <= P_CHK;
                end
            end
            // -------------------------------------------------------------
            P_CHK: begin
                busy <= 1'b1;
                if (chk_idx >= hdr_count[2:0]) begin
                    phase <= P_FIN;
                end else begin
                    if (cover_entry_bad)
                        chk_ok <= 1'b0;
                    chk_idx <= chk_idx + 3'd1;
                end
            end
            // -------------------------------------------------------------
            P_FIN: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                phase <= P_IDLE;
                if (fin_err != SIDX_ERR_NONE) begin
                    valid <= 1'b0;
                    err   <= fin_err;
                end else if (!chk_ok) begin
                    valid <= 1'b0;
                    err   <= SIDX_ERR_CLUSTER_RANGE;
                end else begin
                    valid       <= 1'b1;
                    err         <= SIDX_ERR_NONE;
                    song_count  <= hdr_count[2:0];
                    // 第 1 首带 {cover,audio} 两位，其余仅 cover 位（S4 单轨）
                    song_flags  <= {{3'b0, e_has_cover[3]},
                                    {3'b0, e_has_cover[2]},
                                    {3'b0, e_has_cover[1]},
                                    {2'b0, e_has_audio0, e_has_cover[0]}};
                    song_cover0 <= {e_cov_by[0], e_cov_cl[0]};
                    song_cover1 <= {e_cov_by[1], e_cov_cl[1]};
                    song_cover2 <= {e_cov_by[2], e_cov_cl[2]};
                    song_cover3 <= {e_cov_by[3], e_cov_cl[3]};
                    song_audio0 <= {e_aud_by0, e_aud_cl0};
                    song_audio1 <= 64'd0;
                    song_audio2 <= 64'd0;
                    song_audio3 <= 64'd0;
                end
            end
            default: phase <= P_IDLE;
            endcase
        end
    end
endmodule
`endif
