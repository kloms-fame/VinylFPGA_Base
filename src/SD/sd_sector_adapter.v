`timescale 1ns/1ps
// =============================================================================
// SD 扇区读接口适配层
//
// 现有 sd_card_top 的 sd_sec_read 是电平请求：拉高后启动一次 CMD17，
// sd_sec_read_end 到来后完成。FAT32 模块使用带 busy / byte_index / error
// 的通用 sector 接口，本模块在两者之间做协议转换。
// =============================================================================
module sd_sector_adapter #(
    parameter [31:0] SECTOR_TIMEOUT_CYCLES = 32'd25_000_000 // 250ms @100MHz
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    output wire        sector_busy,
    output wire        sector_valid,
    output wire [7:0]  sector_byte,
    output wire [8:0]  sector_byte_index,
    output wire        sector_done,
    output reg  [7:0]  sector_error,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire        sd_sec_read_data_valid,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_end
);

    localparam [7:0] ERR_NONE   = 8'd0;
    localparam [7:0] ERR_RD_TMO = 8'h05;  // Err-05 读超时（集中错误码表）

    reg [8:0] byte_cnt;
    reg       busy_reg;
    reg [31:0] tmo_cnt;
    reg       tmo_done;

    assign sector_busy       = busy_reg;
    assign sector_valid      = sd_sec_read_data_valid;
    assign sector_byte       = sd_sec_read_data;
    assign sector_byte_index = byte_cnt;
    assign sector_done       = sd_sec_read_end | tmo_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_sec_read <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            byte_cnt <= 9'd0;
            busy_reg <= 1'b0;
            tmo_cnt <= 32'd0;
            tmo_done <= 1'b0;
            sector_error <= ERR_NONE;
        end else begin
            tmo_done <= 1'b0;
            if (sector_req && !busy_reg) begin
                sd_sec_read <= 1'b1;
                sd_sec_read_addr <= sector_lba;
                busy_reg <= 1'b1;
                byte_cnt <= 9'd0;
                tmo_cnt <= 32'd0;
                sector_error <= ERR_NONE;
            end else if (sd_sec_read_end) begin
                sd_sec_read <= 1'b0;
                busy_reg <= 1'b0;
                byte_cnt <= 9'd0;
                tmo_cnt <= 32'd0;
                sector_error <= ERR_NONE;
            end else if (sd_sec_read_data_valid) begin
                byte_cnt <= byte_cnt + 9'd1;
            end else if (busy_reg) begin
                // 扇区事务看门狗：无数据/无结束活动时累计，超过期限即超时。
                // 底层 SD 控制器可能已卡死，本层强制释放 busy 并返回 Err-05，
                // 交由 media_supervisor 复位底层控制器恢复。
                if (tmo_cnt >= (SECTOR_TIMEOUT_CYCLES - 1)) begin
                    sd_sec_read  <= 1'b0;
                    busy_reg     <= 1'b0;
                    byte_cnt     <= 9'd0;
                    tmo_cnt      <= 32'd0;
                    tmo_done     <= 1'b1;
                    sector_error <= ERR_RD_TMO;
                end else begin
                    tmo_cnt <= tmo_cnt + 32'd1;
                end
            end
        end
    end

endmodule
