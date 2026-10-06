`ifndef VINYL_MEDIA_SUPERVISOR_V
`define VINYL_MEDIA_SUPERVISOR_V
// =============================================================================
// media_supervisor —— S7-02 媒体故障恢复监督器（sd_card_clk 域）
//
// 职责：把媒体存储失败变成有界事务，不让系统永久停在 busy。纯监督旁路 +
//       仅驱动 SD 媒体子系统复位，不触碰 wav/mv/视频/时钟主链数据流时序。
//
// 两个独立看门狗：
//   1) 挂载看门狗：media_ready(=media_status_sd[23], scan_done) 未在
//      MOUNT_TIMEOUT_MS 内出现 -> Err-01 挂载失败；连续 MOUNT_RETRY_MAX 次后
//      进入 REMOUNT_COOLDOWN_MS 冷却再重挂（无专用卡检测脚时以协议超时判卡，
//      重插卡后在下一次重挂窗口内自动恢复）。
//   2) 扇区事务看门狗：sector_done 伴随 sector_error!=0（由 sd_sector_adapter
//      的 SECTOR_TIMEOUT_MS 超时产生）-> Err-05 读超时；底层 SD 控制器此刻
//      已被卡死，立即复位恢复。
//
// 每次 SD 复位递增 media_epoch（恢复代次）；cnt_sd_reset/cnt_sector_err 为
// 饱和遥测计数（本阶段引出，供后续 S7-05 外设反馈扩展）。
//
// 集中错误码（本模块负责 01/05，其余 02/03/04/06/07/08/09 由既有 FAT/OSD
// 错误路径承载，见交付说明错误码表）：
//   Err-01 挂载失败 / Err-05 读超时
// =============================================================================
module media_supervisor #(
    parameter integer CLK_FREQ_HZ         = 100_000_000,
    parameter integer MOUNT_TIMEOUT_MS    = 5000,    // 挂载总期限
    parameter integer SECTOR_TIMEOUT_MS   = 250,     // 扇区事务期限（冗余观测）
    parameter integer MOUNT_RETRY_MAX     = 3,       // 单轮挂载重试上限
    parameter integer REMOUNT_COOLDOWN_MS = 30000,   // 连续失败后重挂冷却
    parameter integer RESET_PULSE_CYCLES  = 100      // SD 复位脉冲宽度
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 观测输入（全部 sd_card_clk 域）----
    input  wire        media_ready,   // = media_status_sd[23]（scan_done）
    input  wire [7:0]  sector_error,  // = wav_sec_error（adapter 扇区错误）
    input  wire        sector_done,   // = media_sec_done（扇区完成脉冲）
    input  wire        sector_busy,   // = media_sec_busy（扇区事务忙，冗余观测）

    // ---- 控制/上报输出 ----
    output reg         sd_rst_n,        // 低有效，复位 SD 媒体子系统
    output reg  [7:0]  media_err_code,  // 集中错误码（sticky，最近非零）
    output reg         media_err_toggle,// 错误码变化翻转标志（跨域捆绑握手）
    output reg  [7:0]  media_epoch,     // 恢复代次（每次 SD 复位递增）
    output reg  [15:0] cnt_sd_reset,    // SD 复位次数（饱和）
    output reg  [15:0] cnt_sector_err   // 扇区错误次数（饱和）
);

    localparam [7:0] ERR_NONE   = 8'h00;
    localparam [7:0] ERR_MOUNT  = 8'h01;  // Err-01 挂载失败
    localparam [7:0] ERR_RD_TMO = 8'h05;  // Err-05 读超时

    localparam [2:0] ST_WAIT_MOUNT  = 3'd0;
    localparam [2:0] ST_RESET_PULSE = 3'd1;
    localparam [2:0] ST_COOLDOWN    = 3'd2;

    localparam integer MOUNT_CYCLES    = (CLK_FREQ_HZ / 1000) * MOUNT_TIMEOUT_MS;
    localparam integer COOLDOWN_CYCLES = (CLK_FREQ_HZ / 1000) * REMOUNT_COOLDOWN_MS;
    localparam integer MOUNT_W         = $clog2(MOUNT_CYCLES + 1);
    localparam integer COOLDOWN_W      = $clog2(COOLDOWN_CYCLES + 1);
    localparam integer PULSE_W         = $clog2(RESET_PULSE_CYCLES + 1);
    localparam [2:0]  RETRY_LIMIT      = MOUNT_RETRY_MAX[2:0];

    reg [2:0]          state;
    reg [MOUNT_W-1:0]  mount_cnt;
    reg [COOLDOWN_W-1:0] cool_cnt;
    reg [PULSE_W-1:0]  pulse_cnt;
    reg [2:0]          mount_attempt;
    reg                sd_rst_n_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_WAIT_MOUNT;
            mount_cnt      <= {MOUNT_W{1'b0}};
            cool_cnt       <= {COOLDOWN_W{1'b0}};
            pulse_cnt      <= {PULSE_W{1'b0}};
            mount_attempt  <= 3'd0;
            sd_rst_n       <= 1'b1;
            media_err_code <= ERR_NONE;
            media_err_toggle <= 1'b0;
            cnt_sector_err <= 16'd0;
        end else begin
            // ---- 扇区事务错误（最高优先级）：adapter 超时返回 -> 复位恢复 ----
            if (sector_done && (sector_error != 8'd0)) begin
                if (cnt_sector_err != 16'hFFFF)
                    cnt_sector_err <= cnt_sector_err + 16'd1;
                if (media_err_code != ERR_RD_TMO) begin
                    media_err_code   <= ERR_RD_TMO;
                    media_err_toggle <= ~media_err_toggle;
                end
                if (state != ST_RESET_PULSE && state != ST_COOLDOWN) begin
                    state     <= ST_RESET_PULSE;
                    pulse_cnt <= {PULSE_W{1'b0}};
                    sd_rst_n  <= 1'b0;
                    mount_cnt <= {MOUNT_W{1'b0}};
                end
            end else begin
                // ---- 挂载看门狗状态机 ----
                case (state)
                ST_WAIT_MOUNT: begin
                    if (media_ready) begin
                        mount_cnt     <= {MOUNT_W{1'b0}};
                        mount_attempt <= 3'd0;
                    end else begin
                        if (mount_cnt >= (MOUNT_CYCLES - 1)) begin
                            mount_cnt <= {MOUNT_W{1'b0}};
                            if (media_err_code != ERR_MOUNT) begin
                                media_err_code   <= ERR_MOUNT;
                                media_err_toggle <= ~media_err_toggle;
                            end
                            if (mount_attempt >= RETRY_LIMIT) begin
                                mount_attempt <= 3'd0;
                                state  <= ST_COOLDOWN;
                                cool_cnt <= {COOLDOWN_W{1'b0}};
                            end else begin
                                mount_attempt <= mount_attempt + 3'd1;
                                state  <= ST_RESET_PULSE;
                                pulse_cnt <= {PULSE_W{1'b0}};
                                sd_rst_n <= 1'b0;
                            end
                        end else begin
                            mount_cnt <= mount_cnt + 1'b1;
                        end
                    end
                end
                ST_RESET_PULSE: begin
                    if (pulse_cnt >= (RESET_PULSE_CYCLES - 1)) begin
                        sd_rst_n  <= 1'b1;
                        pulse_cnt <= {PULSE_W{1'b0}};
                        mount_cnt <= {MOUNT_W{1'b0}};
                        state     <= ST_WAIT_MOUNT;
                    end else begin
                        pulse_cnt <= pulse_cnt + 1'b1;
                    end
                end
                ST_COOLDOWN: begin
                    if (cool_cnt >= (COOLDOWN_CYCLES - 1)) begin
                        cool_cnt <= {COOLDOWN_W{1'b0}};
                        mount_attempt <= 3'd0;
                        state  <= ST_RESET_PULSE;
                        pulse_cnt <= {PULSE_W{1'b0}};
                        sd_rst_n <= 1'b0;
                    end else begin
                        cool_cnt <= cool_cnt + 1'b1;
                    end
                end
                default: state <= ST_WAIT_MOUNT;
                endcase
            end
        end
    end

    // 恢复代次与复位计数：在 sd_rst_n 下降沿（复位脉冲开始）各计一次。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_rst_n_q  <= 1'b1;
            media_epoch <= 8'd0;
            cnt_sd_reset <= 16'd0;
        end else begin
            sd_rst_n_q <= sd_rst_n;
            if (sd_rst_n_q && !sd_rst_n) begin
                media_epoch <= media_epoch + 8'd1;
                if (cnt_sd_reset != 16'hFFFF)
                    cnt_sd_reset <= cnt_sd_reset + 16'd1;
            end
        end
    end

endmodule
`endif
