`timescale 1ns/1ps
// =============================================================================
// FAT32 卷扫描器（第七讲教程 5.1）
//
// 读取 LBA0，识别直接 FAT32 引导扇区或 MBR，解析 BPB，然后扫描根目录
// 第一个簇，按 8.3 短文件名匹配 PIC1.BMP ~ PIC4.BMP。
//
// 根目录限制：只扫描根目录的第一个簇，这是完赛参考实现的范围，也是
// 第七讲明确接受的教学约束。PIC1~4.BMP 应放在根目录靠前的位置。
// =============================================================================
module fat32_volume_scanner (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg         audio_valid,
    output reg  [31:0] audio_cluster,
    output reg  [31:0] audio_size,
    // ---- S4：INDEX.BIN 曲目索引（根目录首扇区匹配，可选）----
    // 索引存在时上层优先用它；缺失/损坏时回退到 PIC1~4 + AUDIO.PCM 旧路径。
    output reg         index_valid,
    output reg  [31:0] index_cluster,
    output reg  [31:0] index_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

    localparam ERR_NONE             = 8'h00;
    localparam ERR_SECTOR           = 8'h10;
    localparam ERR_BOOT_SIGNATURE   = 8'h20;
    localparam ERR_UNSUPPORTED_BPB  = 8'h21;
    localparam ERR_RESOURCE_MISSING = 8'h22;

    localparam ST_IDLE        = 4'd0;
    localparam ST_READ0_REQ   = 4'd1;
    localparam ST_READ0_WAIT  = 4'd2;
    localparam ST_BOOT_PARSE  = 4'd3;
    localparam ST_BOOT_REQ    = 4'd4;
    localparam ST_BOOT_WAIT   = 4'd5;
    localparam ST_ROOT_REQ    = 4'd6;
    localparam ST_ROOT_WAIT   = 4'd7;
    localparam ST_DIR_SCAN    = 4'd8;
    localparam ST_FINISH      = 4'd9;
    localparam ST_BOOT_LAYOUT = 4'd10;
    localparam ST_BOOT_ROOT   = 4'd11;

    reg [3:0]  state;
    reg [7:0]  sector_buffer [0:511];
    reg [31:0] root_cluster;
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0]  fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] data_sector_count;
    reg [31:0] fat_span;
    reg [2:0]  sectors_per_cluster_shift;
    // Store only per-position filename predicates (25 bits) and PIC digit (2 bits).
    reg        dir_pos0_p;
    reg        dir_pos0_a;
    reg        dir_pos0_i;
    reg        dir_pos1_i;
    reg        dir_pos1_u;
    reg        dir_pos1_n;
    reg        dir_pos2_c;
    reg        dir_pos2_d;
    reg        dir_pos3_pic_digit;
    reg        dir_pos3_i;
    reg        dir_pos3_e;
    reg        dir_pos4_space;
    reg        dir_pos4_o;
    reg        dir_pos4_x;
    reg        dir_pos5_space;
    reg        dir_pos6_space;
    reg        dir_pos7_space;
    reg        dir_pos8_b;
    reg        dir_pos8_p;
    reg        dir_pos9_m;
    reg        dir_pos9_c;
    reg        dir_pos9_i;
    reg        dir_pos10_p;
    reg        dir_pos10_m;
    reg        dir_pos10_n;
    reg [1:0]  dir_pic_digit;
    reg        dir_entry_match;
    reg        dir_audio_match;
    reg        dir_index_match;
    reg [1:0]  dir_resource_index;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;

    assign scan_busy = (state != ST_IDLE);

    function [15:0] le16;
        input integer offset;
        begin
            le16 = {sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function [31:0] le32;
        input integer offset;
        begin
            le32 = {sector_buffer[offset+3], sector_buffer[offset+2],
                    sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = (value != 0) && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd1:   spc_shift = 3'd0;
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            scan_done <= 1'b0;
            fs_error <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            resource_valid <= 4'd0;
            resource0_cluster <= 32'd0;
            resource1_cluster <= 32'd0;
            resource2_cluster <= 32'd0;
            resource3_cluster <= 32'd0;
            resource0_size <= 32'd0;
            resource1_size <= 32'd0;
            resource2_size <= 32'd0;
            resource3_size <= 32'd0;
            audio_valid <= 1'b0;
            audio_cluster <= 32'd0;
            audio_size <= 32'd0;
            index_valid <= 1'b0;
            index_cluster <= 32'd0;
            index_size <= 32'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            root_cluster <= 32'd0;
            total_sectors <= 32'd0;
            fat_sectors <= 32'd0;
            fat_count <= 8'd0;
            reserved_sectors <= 16'd0;
            data_sector_count <= 32'd0;
            fat_span <= 32'd0;
            sectors_per_cluster_shift <= 3'd0;
            dir_pos0_p <= 1'b0;
            dir_pos0_a <= 1'b0;
            dir_pos0_i <= 1'b0;
            dir_pos1_i <= 1'b0;
            dir_pos1_u <= 1'b0;
            dir_pos1_n <= 1'b0;
            dir_pos2_c <= 1'b0;
            dir_pos2_d <= 1'b0;
            dir_pos3_pic_digit <= 1'b0;
            dir_pos3_i <= 1'b0;
            dir_pos3_e <= 1'b0;
            dir_pos4_space <= 1'b0;
            dir_pos4_o <= 1'b0;
            dir_pos4_x <= 1'b0;
            dir_pos5_space <= 1'b0;
            dir_pos6_space <= 1'b0;
            dir_pos7_space <= 1'b0;
            dir_pos8_b <= 1'b0;
            dir_pos8_p <= 1'b0;
            dir_pos9_m <= 1'b0;
            dir_pos9_c <= 1'b0;
            dir_pos9_i <= 1'b0;
            dir_pos10_p <= 1'b0;
            dir_pos10_m <= 1'b0;
            dir_pos10_n <= 1'b0;
            dir_pic_digit <= 2'd3;
            dir_entry_match <= 1'b0;
            dir_audio_match <= 1'b0;
            dir_index_match <= 1'b0;
            dir_resource_index <= 2'd3;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;

            // 引导扇区/根目录扇区先缓存；根目录同时按字节扫描目录项。
            if (sector_valid && state != ST_ROOT_WAIT)
                sector_buffer[sector_byte_index] <= sector_byte;

            if (sector_valid && state == ST_ROOT_WAIT) begin
                case (sector_byte_index[4:0])
                    5'd0: begin
                        dir_pos0_p <= (sector_byte == "P");
                        dir_pos0_a <= (sector_byte == "A");
                        dir_pos0_i <= (sector_byte == "I");
                        dir_entry_match <= 1'b0;
                        dir_audio_match <= 1'b0;
                        dir_index_match <= 1'b0;
                    end
                    5'd1: begin
                        dir_pos1_i <= (sector_byte == "I");
                        dir_pos1_u <= (sector_byte == "U");
                        dir_pos1_n <= (sector_byte == "N");
                    end
                    5'd2: begin
                        dir_pos2_c <= (sector_byte == "C");
                        dir_pos2_d <= (sector_byte == "D");
                    end
                    5'd3: begin
                        dir_pos3_pic_digit <= (sector_byte >= "1") && (sector_byte <= "4");
                        dir_pos3_i <= (sector_byte == "I");
                        dir_pos3_e <= (sector_byte == "E");
                        dir_pic_digit <= sector_byte - "1";
                    end
                    5'd4: begin
                        dir_pos4_space <= (sector_byte == " ");
                        dir_pos4_o <= (sector_byte == "O");
                        dir_pos4_x <= (sector_byte == "X");
                    end
                    5'd5: begin
                        dir_pos5_space <= (sector_byte == " ");
                    end
                    5'd6: begin
                        dir_pos6_space <= (sector_byte == " ");
                    end
                    5'd7: begin
                        dir_pos7_space <= (sector_byte == " ");
                    end
                    5'd8: begin
                        dir_pos8_b <= (sector_byte == "B");
                        dir_pos8_p <= (sector_byte == "P");
                    end
                    5'd9: begin
                        dir_pos9_m <= (sector_byte == "M");
                        dir_pos9_c <= (sector_byte == "C");
                        dir_pos9_i <= (sector_byte == "I");
                    end
                    5'd10: begin
                        dir_pos10_p <= (sector_byte == "P");
                        dir_pos10_m <= (sector_byte == "M");
                        dir_pos10_n <= (sector_byte == "N");
                    end
                    5'd11: begin
                        if ((sector_byte == 8'h20) &&
                            dir_pos0_p && dir_pos1_i &&
                            dir_pos2_c && dir_pos3_pic_digit && dir_pos4_space &&
                            dir_pos5_space && dir_pos6_space &&
                            dir_pos7_space && dir_pos8_b &&
                            dir_pos9_m && dir_pos10_p) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= dir_pic_digit;
                        end
                        if ((sector_byte == 8'h20) &&
                            dir_pos0_a && dir_pos1_u &&
                            dir_pos2_d && dir_pos3_i &&
                            dir_pos4_o && dir_pos5_space &&
                            dir_pos6_space && dir_pos7_space &&
                            dir_pos8_p && dir_pos9_c &&
                            dir_pos10_m) begin
                            dir_audio_match <= 1'b1;
                        end
                        // S4：INDEX.BIN —— 曲目索引（"INDEX" + 3 空格 + "BIN"）
                        if ((sector_byte == 8'h20) &&
                            dir_pos0_i && dir_pos1_n &&
                            dir_pos2_d && dir_pos3_e &&
                            dir_pos4_x && dir_pos5_space &&
                            dir_pos6_space && dir_pos7_space &&
                            dir_pos8_b && dir_pos9_i &&
                            dir_pos10_n) begin
                            dir_index_match <= 1'b1;
                        end
                    end
                    5'd20: dir_cluster_high[7:0] <= sector_byte;
                    5'd21: dir_cluster_high[15:8] <= sector_byte;
                    5'd26: dir_cluster_low[7:0] <= sector_byte;
                    5'd27: dir_cluster_low[15:8] <= sector_byte;
                    5'd28: dir_file_size[7:0] <= sector_byte;
                    5'd29: dir_file_size[15:8] <= sector_byte;
                    5'd30: dir_file_size[23:16] <= sector_byte;
                    5'd31: begin
                        dir_file_size[31:24] <= sector_byte;
                        if (dir_entry_match) begin
                            case (dir_resource_index)
                                2'd0: begin
                                    resource0_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource0_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[0] <= 1'b1;
                                end
                                2'd1: begin
                                    resource1_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource1_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[1] <= 1'b1;
                                end
                                2'd2: begin
                                    resource2_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource2_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[2] <= 1'b1;
                                end
                                default: begin
                                    resource3_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource3_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[3] <= 1'b1;
                                end
                            endcase
                        end
                        if (dir_audio_match) begin
                            audio_cluster <= {dir_cluster_high, dir_cluster_low};
                            audio_size <= {sector_byte, dir_file_size[23:0]};
                            audio_valid <= 1'b1;
                        end
                        if (dir_index_match) begin
                            index_cluster <= {dir_cluster_high, dir_cluster_low};
                            index_size <= {sector_byte, dir_file_size[23:0]};
                            index_valid <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            case (state)
                ST_IDLE: if (scan_start) begin
                    fs_error <= ERR_NONE;
                    partition_lba <= 32'd0;
                    resource_valid <= 4'd0;
                    state <= ST_READ0_REQ;
                end
                ST_READ0_REQ: if (!sector_busy) begin
                    sector_lba <= 32'd0;
                    sector_req <= 1'b1;
                    state <= ST_READ0_WAIT;
                end
                ST_READ0_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (sector_buffer[510] != 8'h55 ||
                             sector_buffer[511] != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if (sector_buffer[0] == 8'heb ||
                             sector_buffer[0] == 8'he9) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    end else if (sector_buffer[450] == 8'h0b ||
                                 sector_buffer[450] == 8'h0c) begin
                        partition_lba <= le32(454);
                        sector_lba <= le32(454);
                        state <= ST_BOOT_REQ;
                    end else begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end
                end
                ST_BOOT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (sector_buffer[510] != 8'h55 ||
                             sector_buffer[511] != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    if ((le16(11) != 16'd512) || !valid_spc(sector_buffer[13]) ||
                        (le16(14) == 0) ||
                        ((sector_buffer[16] != 1) && (sector_buffer[16] != 2)) ||
                        (le16(17) != 0) || (le16(22) != 0) ||
                        (le32(32) == 0) || (le32(36) == 0) ||
                        (le32(44) < 2)) begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end else begin
                        sectors_per_cluster <= sector_buffer[13];
                        reserved_sectors <= le16(14);
                        fat_count <= sector_buffer[16];
                        total_sectors <= le32(32);
                        fat_sectors <= le32(36);
                        root_cluster <= le32(44);
                        sectors_per_cluster_shift <= spc_shift(sector_buffer[13]);
                        fat_span <= (sector_buffer[16] == 2) ?
                                    (le32(36) << 1) : le32(36);
                        fat_start_lba <= partition_lba + le16(14);
                        state <= ST_BOOT_LAYOUT;
                    end
                end
                ST_BOOT_LAYOUT: begin
                    data_start_lba <= partition_lba + reserved_sectors + fat_span;
                    data_sector_count <= total_sectors - reserved_sectors - fat_span;
                    state <= ST_BOOT_ROOT;
                end
                ST_BOOT_ROOT: begin
                    max_cluster <= (data_sector_count >>
                                   sectors_per_cluster_shift) + 1'b1;
                    sector_lba <= data_start_lba +
                                  ((root_cluster - 2) <<
                                   sectors_per_cluster_shift);
                    state <= ST_ROOT_REQ;
                end
                ST_ROOT_REQ: if (!sector_busy) begin
                    resource_valid <= 4'd0;
                    audio_valid <= 1'b0;
                    audio_cluster <= 32'd0;
                    audio_size <= 32'd0;
                    index_valid <= 1'b0;
                    index_cluster <= 32'd0;
                    index_size <= 32'd0;
                    dir_entry_match <= 1'b0;
                    dir_audio_match <= 1'b0;
                    dir_index_match <= 1'b0;
                    sector_req <= 1'b1;
                    state <= ST_ROOT_WAIT;
                end
                ST_ROOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else
                        state <= ST_DIR_SCAN;
                end
                ST_DIR_SCAN: begin
                    // S4：有 INDEX.BIN 时不再强制要求 PIC1~4.BMP。
                    if ((resource_valid == 4'hf) || index_valid)
                        state <= ST_FINISH;
                    else
                        finish_with_error(ERR_RESOURCE_MISSING);
                end
                ST_FINISH: begin
                    scan_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
