`timescale 1ns/1ps

// 第十一讲 WAV 音频播放核心模块。
//
// 数据格式与完赛教程一致：
//   原始 16bit signed little-endian PCM / 48kHz / 单声道。
// FPGA 不解析 WAV 头，文件由 PC 工具预处理成 AUDIO.PCM。
//
// 结构：
//   写侧 sd_card_clk：按扇区请求 SD 数据，拼成 16bit 样本写入 BRAM
//   读侧 video_clk ：sample_tick 到来时消费一个样本
//
// 读写指针使用格雷码 + 2FF 同步。写侧在缓冲达到高水位后暂停请求
// 下一扇区，避免教程文字中说明的“TF 读入速度远高于音频消费速度”
// 导致循环缓冲被覆盖。读侧下溢时输出静音但保持 sample_valid，防止
// 下游 HDMI 音频链停顿产生爆音。
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,          // 4096 x 16bit = 8KB
    parameter integer SAMPLES_PER_SECTOR = 256  // 512B / 2B
) (
    // 写侧：sd_card_clk 域
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,
    input  wire [31:0] start_lba,
    input  wire [31:0] total_sectors,
    input  wire [31:0] valid_samples,  // X2：真实有效样本数（末扇区截断）
    input  wire [7:0]  skip_samples,    // X2：首扇区丢弃的样本数（Seek 扇区内偏移）
    output wire        sd_req,
    output reg  [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    // 读侧：video_clk 域
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,
    output wire signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,

    output reg  [31:0] sample_counter,
    output wire        stream_active,
    output wire        stream_end,
    output wire        reader_idle,
    output wire        sample_consumed,
    output wire        buffer_low,
    input  wire [31:0] sample_base,     // X2：Seek 后读侧计数器起始值（video_clk 域）
    output reg         underrun_pulse   // S7-01B：流式播放中读侧欠载单拍脉冲（video_clk 域）
);
    localparam [ADDR_WIDTH:0] BUFFER_HIGH_WATER = (1 << (ADDR_WIDTH - 1));
    localparam [ADDR_WIDTH:0] BUFFER_LOW_WATER  = (1 << (ADDR_WIDTH - 2));

    (* ram_style = "bram" *) reg [15:0] buffer [0:(1 << ADDR_WIDTH) - 1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    reg finished_wr;
    reg [1:0] finished_sync;
    reg       play_enable_sync1;
    reg       play_enable_sync2;
    reg       play_enable_sync3;
    reg       stream_active_rd;
    reg       stream_end_rd;
    reg stream_fault_wr;
    reg [1:0] fault_sync;

    reg [ADDR_WIDTH-1:0] wr_gray;
    reg [ADDR_WIDTH-1:0] wr_gray_sync1;
    reg [ADDR_WIDTH-1:0] wr_gray_sync2;
    reg [ADDR_WIDTH-1:0] rd_gray;
    reg [ADDR_WIDTH-1:0] rd_gray_sync1;
    reg [ADDR_WIDTH-1:0] rd_gray_sync2;

    function [ADDR_WIDTH-1:0] to_gray;
        input [ADDR_WIDTH-1:0] b;
        begin
            to_gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_WIDTH-1:0] from_gray;
        input [ADDR_WIDTH-1:0] g;
        reg [ADDR_WIDTH-1:0] b;
        integer i;
        begin
            b[ADDR_WIDTH-1] = g[ADDR_WIDTH-1];
            for (i = ADDR_WIDTH-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            from_gray = b;
        end
    endfunction

    wire [ADDR_WIDTH-1:0] wr_ptr_in_rd = from_gray(wr_gray_sync2);
    wire [ADDR_WIDTH-1:0] rd_ptr_in_wr = from_gray(rd_gray_sync2);

    wire [ADDR_WIDTH-1:0] distance_wr = wr_ptr - rd_ptr_in_wr;
    wire [ADDR_WIDTH-1:0] distance_rd = wr_ptr_in_rd - rd_ptr;
    wire [ADDR_WIDTH:0] level_wr = {1'b0, distance_wr};
    wire [ADDR_WIDTH:0] level_rd = {1'b0, distance_rd};

    localparam [2:0] WS_IDLE  = 3'd0;
    localparam [2:0] WS_REQ   = 3'd1;
    localparam [2:0] WS_FILL  = 3'd2;
    localparam [2:0] WS_DONE  = 3'd3;
    localparam [2:0] WS_END   = 3'd4;
    localparam [2:0] WS_WAIT  = 3'd5;

    reg [2:0]  wstate;
    reg [31:0] cur_lba;
    reg [31:0] sectors_read;
    reg [31:0] remaining;
    reg [7:0]  lo_byte;
    reg [7:0]  skip_cnt;
    reg        lo_pending;
    reg        limit_reached;

    // TD 的块 RAM 推断需要独立、无数组复位的同步读写端口。
    // 仍为 4096 x 16bit，读数据在消费沿更新，不增加 sample_valid 延迟。
    wire buffer_write = wr_rst_n && play_enable &&
                        (wstate == WS_FILL) && sd_valid && lo_pending &&
                        (skip_cnt == 8'd0) && (remaining != 32'd0);
    wire buffer_available = play_enable_sync2 && !fault_sync[1] &&
                            ((level_rd >= SAMPLES_PER_SECTOR) ||
                            (finished_sync[1] && (level_rd > 0)));
    wire buffer_read = rd_rst_n && sample_tick && sample_ready && buffer_available;
    reg [15:0] buffer_data;
    reg sample_has_data;

    always @(posedge wr_clk) begin
        if (buffer_write)
            buffer[wr_ptr] <= {sd_byte, lo_byte};
    end

    always @(posedge rd_clk) begin
        if (buffer_read)
            buffer_data <= buffer[rd_ptr];
    end

    // RAM 本体不复位；输出选择位保留原来的异步复位、静音和保持语义。
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            sample_has_data <= 1'b0;
        else if (!play_enable_sync2 || fault_sync[1])
            sample_has_data <= 1'b0;
        else if (sample_tick && sample_ready)
            sample_has_data <= buffer_available;
    end
    assign sample_out = sample_has_data ? buffer_data : 16'sd0;

    assign reader_idle = !play_enable_sync2 && rd_ptr==0 && !sample_has_data;
    assign sample_consumed = buffer_read;
    assign sd_req = play_enable && (wstate == WS_REQ);
    // stream_active/stream_end 必须由读时钟域给出：写侧完成最后一个扇区后，
    // 读侧还要把 BRAM 里的残余样本排空，之后才允许声源选择器切回琶音。
    assign stream_active = stream_active_rd;
    assign stream_end = stream_end_rd;
    assign buffer_low = (level_rd < BUFFER_LOW_WATER);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wstate        <= WS_IDLE;
            cur_lba       <= 32'd0;
            sectors_read  <= 32'd0;
            wr_ptr        <= {ADDR_WIDTH{1'b0}};
            remaining     <= 32'd0;
            lo_pending    <= 1'b0;
            lo_byte       <= 8'd0;
            skip_cnt      <= 8'd0;
            limit_reached <= 1'b0;
            rd_gray_sync1 <= {ADDR_WIDTH{1'b0}};
            rd_gray_sync2 <= {ADDR_WIDTH{1'b0}};
            wr_gray       <= {ADDR_WIDTH{1'b0}};
            stream_fault_wr <= 1'b0;
            finished_wr <= 1'b0;
            sd_lba <= 32'd0;
        end else begin
            wr_gray       <= to_gray(wr_ptr);
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;

            if (!play_enable) begin
                stream_fault_wr <= 1'b0;
                finished_wr <= 1'b0;
                wstate       <= WS_IDLE;
                cur_lba      <= 32'd0;
                sectors_read <= 32'd0;
                wr_ptr       <= {ADDR_WIDTH{1'b0}};
                remaining    <= 32'd0;
                lo_pending   <= 1'b0;
                skip_cnt     <= 8'd0;
                limit_reached <= 1'b0;
            end else begin
                case (wstate)
                WS_IDLE: begin
                    if (start_lba != 32'd0 && total_sectors != 32'd0) begin
                        cur_lba      <= start_lba;
                        sectors_read <= 32'd0;
                        wr_ptr       <= {ADDR_WIDTH{1'b0}};
                        remaining    <= valid_samples;
                        lo_pending   <= 1'b0;
                        skip_cnt     <= skip_samples;
                        limit_reached <= (valid_samples == 32'd0);
                        wstate       <= WS_REQ;
                    end
                end
                WS_REQ: begin
                    if (!sd_busy) begin
                        sd_lba <= cur_lba;
                        wstate <= WS_FILL;
                    end
                end
                WS_FILL: begin
                    if (sd_valid) begin
                        if (!lo_pending) begin
                            lo_byte    <= sd_byte;
                            lo_pending <= 1'b1;
                        end else begin
                            lo_pending     <= 1'b0;
                            if (skip_cnt != 8'd0)
                                skip_cnt <= skip_cnt - 1'b1;
                            else if (remaining != 32'd0) begin
                                wr_ptr <= wr_ptr + 1'b1;
                                remaining <= remaining - 32'd1;
                                if (remaining == 32'd1)
                                    limit_reached <= 1'b1;
                            end
                        end
                    end

                    if (sd_done) begin
                        if (sd_error != 8'd0) begin
                            stream_fault_wr <= 1'b1;
                            wstate <= WS_END;
                        end else begin
                            sectors_read <= sectors_read + 1'b1;
                            cur_lba      <= cur_lba + 1'b1;
                            // Commit counters before comparing. Combining the
                            // 32-bit increment, compare and state mux exceeded
                            // the routed 100 MHz setup budget.
                            wstate <= WS_DONE;
                        end
                    end
                end
                WS_DONE: begin
                    if (limit_reached || (sectors_read >= total_sectors)) begin
                        wstate <= WS_END;
                        finished_wr <= 1'b1;
                    end else if (level_wr >= BUFFER_HIGH_WATER)
                        wstate <= WS_WAIT;
                    else
                        wstate <= WS_REQ;
                end
                WS_END: begin
                    if (!play_enable)
                        wstate <= WS_IDLE;
                end
                WS_WAIT: begin
                    if (level_wr < BUFFER_HIGH_WATER)
                        wstate <= WS_REQ;
                end
                default: wstate <= WS_IDLE;
                endcase
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr         <= {ADDR_WIDTH{1'b0}};
            sample_valid   <= 1'b0;
            sample_counter <= 32'd0;
            underrun_pulse <= 1'b0;
            wr_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            wr_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            rd_gray        <= {ADDR_WIDTH{1'b0}};
            fault_sync <= 2'b00;
            finished_sync <= 2'd0;
            play_enable_sync1 <= 1'b0;
            play_enable_sync2 <= 1'b0;
            play_enable_sync3 <= 1'b0;
            stream_active_rd  <= 1'b0;
            stream_end_rd     <= 1'b0;
        end else begin
            underrun_pulse <= 1'b0;
            rd_gray       <= to_gray(rd_ptr);
            fault_sync <= {fault_sync[0],stream_fault_wr};
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            finished_sync <= {finished_sync[0],finished_wr};
            play_enable_sync1 <= play_enable;
            play_enable_sync2 <= play_enable_sync1;
            play_enable_sync3 <= play_enable_sync2;

            sample_valid <= 1'b0;

            if (!play_enable_sync2 || fault_sync[1]) begin
                stream_active_rd <= 1'b0;
                stream_end_rd    <= 1'b0;
            end else if (finished_sync[1]) begin
                if (level_rd == 0) begin
                    stream_active_rd <= 1'b0;
                    stream_end_rd    <= 1'b1;
                end else begin
                    stream_active_rd <= 1'b1;
                    stream_end_rd    <= 1'b0;
                end
            end else begin
                stream_active_rd <= 1'b1;
                stream_end_rd    <= 1'b0;
            end

            if (sample_tick && sample_ready) begin
                if (buffer_available) begin
                    rd_ptr        <= rd_ptr + 1'b1;
                    sample_valid  <= 1'b1;
                    sample_counter <= sample_counter + 1'b1;
                end else begin
                    sample_valid <= 1'b1;
                    // 欠载：写侧尚未完成最后一个扇区（WS_END），但读侧已无
                    // 可用样本。此时输出静音，同时打一拍欠载脉冲供 S7-01B 遥测。
                    // 门控 sample_counter!=0：播放起始阶段缓冲尚未充满时不应
                    // 计为欠载，避免每次起播都产生一次误报。
                    if (stream_active_rd && !finished_sync[1] &&
                        (sample_counter != 32'd0))
                        underrun_pulse <= 1'b1;
                end
            end

            if (!play_enable_sync2) begin
                rd_ptr         <= {ADDR_WIDTH{1'b0}};
                sample_counter <= 32'd0;
            end else if (play_enable_sync2 && !play_enable_sync3) begin
                // X2：整条流重启后的第一个使能沿把计数器载到 Seek 目标
                sample_counter <= sample_base;
            end
        end
    end
endmodule
