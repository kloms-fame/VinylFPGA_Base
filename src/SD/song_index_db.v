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
    output wire [63:0] song_cover0,
    output wire [63:0] song_cover1,
    output wire [63:0] song_cover2,
    output wire [63:0] song_cover3,
    output wire [63:0] song_audio0,
    output wire [63:0] song_audio1,
    output wire [63:0] song_audio2,
    output wire [63:0] song_audio3,
    output wire [63:0] song_mv0, song_mv1, song_mv2, song_mv3,
    output wire [31:0] background_base_lba,
    output wire background_art2_supported
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
    reg [31:0] hdr_crc_exp;
    reg [31:0] crc_calc;
    reg [8:0]  byte_idx;

    // Optional BGR1 header extension. An absent/invalid extension disables only
    // backgrounds: entry CRC and all legacy cover/audio/MV validation stay intact.
    reg bg_magic_ok;
    reg bg_layout_ok;
    reg [31:0] bg_base_lba;
    reg bg_art2 = 1'b0;
    initial bg_magic_ok = 1'b0;
    initial bg_layout_ok = 1'b0;
    initial bg_base_lba = 32'd0;
    assign background_base_lba = valid && bg_magic_ok && bg_layout_ok &&
        bg_base_lba != 32'd0 && bg_base_lba <= (bg_art2 ? 32'hFFFFE3DF : 32'hFFFFE88F) ? bg_base_lba : 32'd0;
    assign background_art2_supported = background_base_lba != 0 && bg_art2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bg_art2 <= 1'b0;
        else if (start && phase == P_IDLE) bg_art2 <= 1'b0;
        else if (phase == P_STREAM && in_valid && byte_idx == 9'd44)
            bg_art2 <= in_byte == 8'd6;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bg_magic_ok <= 1'b0;
        else if (start && phase == P_IDLE) bg_magic_ok <= 1'b1;
        else if (phase == P_STREAM && in_valid) begin
            case (byte_idx)
                9'd32: bg_magic_ok <= bg_magic_ok && in_byte == 8'h42;
                9'd33: bg_magic_ok <= bg_magic_ok && in_byte == 8'h47;
                9'd34: bg_magic_ok <= bg_magic_ok && in_byte == 8'h52;
                9'd35: bg_magic_ok <= bg_magic_ok && in_byte == 8'h31;
                default: ;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bg_layout_ok <= 1'b0;
        else if (start && phase == P_IDLE) bg_layout_ok <= 1'b1;
        else if (phase == P_STREAM && in_valid) begin
            case (byte_idx)
                9'd40, 9'd43, 9'd45, 9'd46, 9'd47:
                    bg_layout_ok <= bg_layout_ok && in_byte == 8'h00;
                9'd41: bg_layout_ok <= bg_layout_ok && in_byte == 8'h60;
                9'd42: bg_layout_ok <= bg_layout_ok && in_byte == 8'h09;
                9'd44: bg_layout_ok <= bg_layout_ok && (in_byte == 8'd5 || in_byte == 8'd6);
                default: ;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bg_base_lba <= 32'd0;
        else if (start && phase == P_IDLE) bg_base_lba <= 32'd0;
        else if (phase == P_STREAM && in_valid) begin
            case (byte_idx)
                9'd36: bg_base_lba[7:0] <= in_byte;
                9'd37: bg_base_lba[15:8] <= in_byte;
                9'd38: bg_base_lba[23:16] <= in_byte;
                9'd39: bg_base_lba[31:24] <= in_byte;
                default: ;
            endcase
        end
    end

    // ---- 条目 ----
    // 封面：每首都要（S4 的 4 张封面来自索引）—— 保留 4 组。
    reg [31:0] e_cov_cl [0:MAX_SONGS-1];
    reg [31:0] e_cov_by [0:MAX_SONGS-1];
    // 音频：S5 起需要按选中曲目切换，因此 4 首的音频簇号/字节数都要保留。
    reg [3:0]  e_has_cover;
    reg [3:0]  e_has_audio;
    reg [31:0] e_aud_cl [0:MAX_SONGS-1];
    reg [31:0] e_aud_by [0:MAX_SONGS-1];

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

    // S6 v2: reserved entry bytes become {codec,fps,count16,lba32}.
    reg [63:0] e_mv [0:3];
    reg [3:0] e_has_mv;
    integer m;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e_has_mv <= 0;
            for(m=0;m<4;m=m+1) e_mv[m]<=0;
        end else if(start && phase==P_IDLE) begin
            e_has_mv <= 0;
            for(m=0;m<4;m=m+1) e_mv[m]<=0;
        end else if(phase==P_STREAM && in_valid && in_entries) begin
            // Decode the entry before selecting the shift register. A dynamic
            // array write otherwise needs a wide read mux on the old value.
            if(entry_off==0) begin
                case(entry_sel)
                    2'd0: e_has_mv[0] <= in_byte[3];
                    2'd1: e_has_mv[1] <= in_byte[3];
                    2'd2: e_has_mv[2] <= in_byte[3];
                    2'd3: e_has_mv[3] <= in_byte[3];
                endcase
            end
            if(entry_off>=56) begin
                case(entry_sel)
                    2'd0: e_mv[0] <= {in_byte,e_mv[0][63:8]};
                    2'd1: e_mv[1] <= {in_byte,e_mv[1][63:8]};
                    2'd2: e_mv[2] <= {in_byte,e_mv[2][63:8]};
                    2'd3: e_mv[3] <= {in_byte,e_mv[3][63:8]};
                endcase
            end
        end
    end
    assign song_mv0=(valid && hdr_version==2 && e_has_mv[0]) ? e_mv[0] : 64'd0;
    assign song_mv1=(valid && hdr_version==2 && e_has_mv[1]) ? e_mv[1] : 64'd0;
    assign song_mv2=(valid && hdr_version==2 && e_has_mv[2]) ? e_mv[2] : 64'd0;
    assign song_mv3=(valid && hdr_version==2 && e_has_mv[3]) ? e_mv[3] : 64'd0;
    // Payload is consumed only after valid, at the unchanged P_FIN edge.
    // The loader clears index_mode before starting a reload. Invalid payloads
    // are zero; no second 512-bit output bank is needed. busy/song_flags keep
    // their module API and are already pruned when unconnected in the product.
    assign song_cover0 = valid ? {e_cov_by[0], e_cov_cl[0]} : 64'd0;
    assign song_cover1 = valid ? {e_cov_by[1], e_cov_cl[1]} : 64'd0;
    assign song_cover2 = valid ? {e_cov_by[2], e_cov_cl[2]} : 64'd0;
    assign song_cover3 = valid ? {e_cov_by[3], e_cov_cl[3]} : 64'd0;
    assign song_audio0 = valid ? {e_aud_by[0], e_aud_cl[0]} : 64'd0;
    assign song_audio1 = valid ? {e_aud_by[1], e_aud_cl[1]} : 64'd0;
    assign song_audio2 = valid ? {e_aud_by[2], e_aud_cl[2]} : 64'd0;
    assign song_audio3 = valid ? {e_aud_by[3], e_aud_cl[3]} : 64'd0;

    // Look one entry ahead; keep the original one-entry-per-clock P_CHK.
    // The final stream beat prepares entry zero, then each check prepares
    // its successor. Splitting the range at 16 bits avoids mux -> wide
    // comparator -> accumulated validity in one 100 MHz path.
    reg [2:0] check_read_index = 3'd0;
    reg [5:0] entry_checks = 6'd0;
    wire [31:0] check_cluster = e_cov_cl[check_read_index];
    wire [31:0] check_bytes = e_cov_by[check_read_index];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) check_read_index <= 3'd0;
        else if (start && phase == P_IDLE) check_read_index <= 3'd0;
        else if (phase == P_STREAM && in_done) check_read_index <= 3'd1;
        else if (phase == P_CHK) check_read_index <= check_read_index + 3'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) entry_checks <= 6'd0;
        else if ((phase == P_STREAM && in_done) || phase == P_CHK)
            entry_checks <= {check_cluster[15:0] > max_cluster[15:0],
                             check_cluster[31:16] == max_cluster[31:16],
                             check_cluster[31:16] > max_cluster[31:16],
                             check_cluster < 32'd2,
                             check_bytes == 32'd0,
                             !e_has_cover[check_read_index]};
    end
    wire cover_entry_bad = entry_checks[0] || entry_checks[1] ||
                           entry_checks[2] || entry_checks[3] ||
                           (entry_checks[4] && entry_checks[5]);

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

            chk_idx        <= 3'd0;
            chk_ok         <= 1'b0;
            fin_err        <= SIDX_ERR_NONE;
            magic_ok       <= 1'b0;
            hdr_version    <= 16'd0;
            hdr_entry_size <= 16'd0;
            hdr_count      <= 16'd0;
            hdr_crc_exp    <= 32'd0;
            crc_calc       <= 32'hFFFFFFFF;
            byte_idx       <= 9'd0;
            e_has_cover    <= 4'd0;
            e_has_audio    <= 4'd0;
            for (k = 0; k < MAX_SONGS; k = k + 1) begin
                e_cov_cl[k] <= 32'd0;
                e_cov_by[k] <= 32'd0;
                e_aud_cl[k] <= 32'd0;
                e_aud_by[k] <= 32'd0;
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
                    hdr_crc_exp    <= 32'd0;
                    crc_calc       <= 32'hFFFFFFFF;
                    byte_idx       <= 9'd0;
                    e_has_cover    <= 4'd0;
                    e_has_audio    <= 4'd0;
                    for (k = 0; k < MAX_SONGS; k = k + 1) begin
                        e_cov_cl[k] <= 32'd0;
                        e_cov_by[k] <= 32'd0;
                        e_aud_cl[k] <= 32'd0;
                        e_aud_by[k] <= 32'd0;
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
                            6'd16: hdr_crc_exp[7:0]    <= in_byte;
                            6'd17: hdr_crc_exp[15:8]   <= in_byte;
                            6'd18: hdr_crc_exp[23:16]  <= in_byte;
                            6'd19: hdr_crc_exp[31:24]  <= in_byte;
                            default: ;
                        endcase
                    end else if (in_entries) begin
                        if (crc_in_span)
                            crc_calc <= crc32_byte(crc_calc, in_byte);

                        // Store each field byte in its final little-endian lane.
                        // These words are read only after P_STREAM completes, so
                        // shifting the whole 32-bit field on every byte is wasteful.
                        // Store the field bytes in their final little-endian lanes.
                        // The entries are consumed only after P_STREAM completes.
                        case (entry_off)
                            6'd0: begin
                                e_has_cover[entry_sel] <= in_byte[SIDX_FLAG_COVER];
                                e_has_audio[entry_sel] <= in_byte[SIDX_FLAG_AUDIO];
                            end
                            // The cover cluster occupies bytes 4..7; 1..3 are reserved.
                            6'd4:  e_cov_cl[entry_sel][7:0]   <= in_byte;
                            6'd5:  e_cov_cl[entry_sel][15:8]  <= in_byte;
                            6'd6:  e_cov_cl[entry_sel][23:16] <= in_byte;
                            6'd7:  e_cov_cl[entry_sel][31:24] <= in_byte;
                            6'd8:  e_cov_by[entry_sel][7:0]   <= in_byte;
                            6'd9:  e_cov_by[entry_sel][15:8]  <= in_byte;
                            6'd10: e_cov_by[entry_sel][23:16] <= in_byte;
                            6'd11: e_cov_by[entry_sel][31:24] <= in_byte;
                            6'd16: e_aud_cl[entry_sel][7:0]   <= in_byte;
                            6'd17: e_aud_cl[entry_sel][15:8]  <= in_byte;
                            6'd18: e_aud_cl[entry_sel][23:16] <= in_byte;
                            6'd19: e_aud_cl[entry_sel][31:24] <= in_byte;
                            6'd20: e_aud_by[entry_sel][7:0]   <= in_byte;
                            6'd21: e_aud_by[entry_sel][15:8]  <= in_byte;
                            6'd22: e_aud_by[entry_sel][23:16] <= in_byte;
                            6'd23: e_aud_by[entry_sel][31:24] <= in_byte;
                            default: ;
                        endcase
                    end
                end

                if (in_done) begin
                    if (in_error != 8'h00)
                        fin_err <= SIDX_ERR_STREAM;
                    else if (!magic_ok)
                        fin_err <= SIDX_ERR_MAGIC;
                    else if (hdr_version != SIDX_VERSION && hdr_version != 16'd2)
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
                    song_flags  <= {{(e_has_mv[3] && hdr_version==2), 1'b0, e_has_audio[3], e_has_cover[3]},
                                    {(e_has_mv[2] && hdr_version==2), 1'b0, e_has_audio[2], e_has_cover[2]},
                                    {(e_has_mv[1] && hdr_version==2), 1'b0, e_has_audio[1], e_has_cover[1]},
                                    {(e_has_mv[0] && hdr_version==2), 1'b0, e_has_audio[0], e_has_cover[0]}};

                end
            end
            default: phase <= P_IDLE;
            endcase
        end
    end
endmodule
`endif
