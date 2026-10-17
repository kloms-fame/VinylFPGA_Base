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
    // Only these MBR/BPB offsets are consumed below. Keeping a full 512-byte
    // sector register bank made an unrelated audio-sector valid signal fan
    // out to thousands of write enables and spent over 4k flip-flops.
    reg [7:0] sec0;
    reg [7:0] sec11, sec12, sec13, sec14, sec15, sec16, sec17, sec18;
    reg [7:0] sec22, sec23;
    reg [7:0] sec32, sec33, sec34, sec35, sec36, sec37, sec38, sec39;
    reg [7:0] sec44, sec45, sec46, sec47;
    reg [7:0] sec446, sec450;
    reg [7:0] sec454, sec455, sec456, sec457;
    reg [7:0] sec458, sec459, sec460, sec461;
    reg [7:0] sec510, sec511;
    reg [31:0] root_cluster;
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0]  fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] data_sector_count;
    reg [31:0] fat_span;
    reg [2:0]  sectors_per_cluster_shift;
    reg        dir_entry_match;
    reg        dir_audio_match;
    reg        dir_index_match;
    reg [1:0]  dir_resource_index;
    reg [7:0]  dir_name0;
    reg [7:0]  dir_name1;
    reg [7:0]  dir_name2;
    reg [7:0]  dir_name3;
    reg [7:0]  dir_name4;
    reg [7:0]  dir_name5;
    reg [7:0]  dir_name6;
    reg [7:0]  dir_name7;
    reg [7:0]  dir_name8;
    reg [7:0]  dir_name9;
    reg [7:0]  dir_name10;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;

    assign scan_busy = (state != ST_IDLE);

    function [15:0] le16;
        input integer offset;
        begin
            case (offset)
                11: le16 = {sec12, sec11};
                14: le16 = {sec15, sec14};
                17: le16 = {sec18, sec17};
                22: le16 = {sec23, sec22};
                default: le16 = 16'd0;
            endcase
        end
    endfunction

    function [31:0] le32;
        input integer offset;
        begin
            case (offset)
                32:  le32 = {sec35, sec34, sec33, sec32};
                36:  le32 = {sec39, sec38, sec37, sec36};
                44:  le32 = {sec47, sec46, sec45, sec44};
                454: le32 = {sec457, sec456, sec455, sec454};
                458: le32 = {sec461, sec460, sec459, sec458};
                default: le32 = 32'd0;
            endcase
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
            dir_entry_match <= 1'b0;
            dir_audio_match <= 1'b0;
            dir_index_match <= 1'b0;
            dir_resource_index <= 2'd3;
            dir_name0 <= 8'd0;
            dir_name1 <= 8'd0;
            dir_name2 <= 8'd0;
            dir_name3 <= 8'd0;
            dir_name4 <= 8'd0;
            dir_name5 <= 8'd0;
            dir_name6 <= 8'd0;
            dir_name7 <= 8'd0;
            dir_name8 <= 8'd0;
            dir_name9 <= 8'd0;
            dir_name10 <= 8'd0;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;

            // Capture only the fixed MBR/BPB fields used by this scanner,
            // and only while one of its sector reads is active. In particular,
            // audio/video sector traffic can no longer toggle this write bank.
            if (sector_valid &&
                ((state == ST_READ0_WAIT) || (state == ST_BOOT_WAIT))) begin
                case (sector_byte_index)
                    9'd0:   sec0   <= sector_byte;
                    9'd11:  sec11  <= sector_byte;
                    9'd12:  sec12  <= sector_byte;
                    9'd13:  sec13  <= sector_byte;
                    9'd14:  sec14  <= sector_byte;
                    9'd15:  sec15  <= sector_byte;
                    9'd16:  sec16  <= sector_byte;
                    9'd17:  sec17  <= sector_byte;
                    9'd18:  sec18  <= sector_byte;
                    9'd22:  sec22  <= sector_byte;
                    9'd23:  sec23  <= sector_byte;
                    9'd32:  sec32  <= sector_byte;
                    9'd33:  sec33  <= sector_byte;
                    9'd34:  sec34  <= sector_byte;
                    9'd35:  sec35  <= sector_byte;
                    9'd36:  sec36  <= sector_byte;
                    9'd37:  sec37  <= sector_byte;
                    9'd38:  sec38  <= sector_byte;
                    9'd39:  sec39  <= sector_byte;
                    9'd44:  sec44  <= sector_byte;
                    9'd45:  sec45  <= sector_byte;
                    9'd46:  sec46  <= sector_byte;
                    9'd47:  sec47  <= sector_byte;
                    9'd446: sec446 <= sector_byte;
                    9'd450: sec450 <= sector_byte;
                    9'd454: sec454 <= sector_byte;
                    9'd455: sec455 <= sector_byte;
                    9'd456: sec456 <= sector_byte;
                    9'd457: sec457 <= sector_byte;
                    9'd458: sec458 <= sector_byte;
                    9'd459: sec459 <= sector_byte;
                    9'd460: sec460 <= sector_byte;
                    9'd461: sec461 <= sector_byte;
                    9'd510: sec510 <= sector_byte;
                    9'd511: sec511 <= sector_byte;
                    default: ;
                endcase
            end

            if (sector_valid && state == ST_ROOT_WAIT) begin
                case (sector_byte_index[4:0])
                    5'd0:  dir_name0 <= sector_byte;
                    5'd1:  dir_name1 <= sector_byte;
                    5'd2:  dir_name2 <= sector_byte;
                    5'd3:  dir_name3 <= sector_byte;
                    5'd4:  dir_name4 <= sector_byte;
                    5'd5:  dir_name5 <= sector_byte;
                    5'd6:  dir_name6 <= sector_byte;
                    5'd7:  dir_name7 <= sector_byte;
                    5'd8:  dir_name8 <= sector_byte;
                    5'd9:  dir_name9 <= sector_byte;
                    5'd10: dir_name10 <= sector_byte;
                    5'd11: begin
                        if ((sector_byte == 8'h20) &&
                            (dir_name0 == "P") && (dir_name1 == "I") &&
                            (dir_name2 == "C") && (dir_name3 >= "1") &&
                            (dir_name3 <= "4") && (dir_name4 == " ") &&
                            (dir_name5 == " ") && (dir_name6 == " ") &&
                            (dir_name7 == " ") && (dir_name8 == "B") &&
                            (dir_name9 == "M") && (dir_name10 == "P")) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= dir_name3 - "1";
                        end else begin
                            dir_entry_match <= 1'b0;
                        end
                        if ((sector_byte == 8'h20) &&
                            (dir_name0 == "A") && (dir_name1 == "U") &&
                            (dir_name2 == "D") && (dir_name3 == "I") &&
                            (dir_name4 == "O") && (dir_name5 == " ") &&
                            (dir_name6 == " ") && (dir_name7 == " ") &&
                            (dir_name8 == "P") && (dir_name9 == "C") &&
                            (dir_name10 == "M")) begin
                            dir_audio_match <= 1'b1;
                        end else begin
                            dir_audio_match <= 1'b0;
                        end
                        if ((sector_byte == 8'h20) &&
                            (dir_name0 == "I") && (dir_name1 == "N") &&
                            (dir_name2 == "D") && (dir_name3 == "E") &&
                            (dir_name4 == "X") && (dir_name5 == " ") &&
                            (dir_name6 == " ") && (dir_name7 == " ") &&
                            (dir_name8 == "B") && (dir_name9 == "I") &&
                            (dir_name10 == "N")) begin
                            dir_index_match <= 1'b1;
                        end else begin
                            dir_index_match <= 1'b0;
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
                    // Result payloads are meaningful only while their valid
                    // flags are set. Clear the flags here; retaining the old
                    // payload avoids a wide synchronous clear mux on every
                    // metadata bit and is safe for consumers using the valid
                    // contract.
                    resource_valid <= 4'd0;
                    audio_valid <= 1'b0;
                    index_valid <= 1'b0;
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
                    else if (sec510 != 8'h55 || sec511 != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if (((sec446 == 8'h00) ||
                              (sec446 == 8'h80)) &&
                             ((sec450 == 8'h0b) ||
                              (sec450 == 8'h0c)) &&
                             (le32(454) != 0) && (le32(458) != 0)) begin
                        partition_lba <= le32(454);
                        sector_lba <= le32(454);
                        state <= ST_BOOT_REQ;
                    end else if (sec0 == 8'heb || sec0 == 8'he9) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
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
                    else if (sec510 != 8'h55 || sec511 != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    if ((le16(11) != 16'd512) || !valid_spc(sec13) ||
                        (le16(14) == 0) ||
                        ((sec16 != 1) && (sec16 != 2)) ||
                        (le16(17) != 0) || (le16(22) != 0) ||
                        (le32(32) == 0) || (le32(36) == 0) ||
                        (le32(44) < 2)) begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end else begin
                        sectors_per_cluster <= sec13;
                        reserved_sectors <= le16(14);
                        fat_count <= sec16;
                        total_sectors <= le32(32);
                        fat_sectors <= le32(36);
                        root_cluster <= le32(44);
                        sectors_per_cluster_shift <= spc_shift(sec13);
                        fat_span <= (sec16 == 2) ?
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
                    index_valid <= 1'b0;
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
