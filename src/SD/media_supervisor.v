`ifndef VINYL_MEDIA_SUPERVISOR_V
`define VINYL_MEDIA_SUPERVISOR_V
// =============================================================================
// media_supervisor —— S7-02 媒体故障恢复监督器（sd_card_clk 域）
//
// SD-domain lifecycle supervision. media_ready means validated metadata AND
// completed cover preload, never scan_done alone. Top distributes sd_rst_n to
// the loader, WAV/MV clients, mux and synchronized pixel-domain media reset.
// Specific FAT/index/read errors survive retry resets and clear only on success.
// No physical detect pin: idle probes and bounded sector timeouts detect loss.
module media_supervisor #(
    parameter integer CLK_FREQ_HZ         = 100_000_000,
    parameter integer MOUNT_TIMEOUT_MS    = 5000,    // 挂载总期限
    parameter integer MOUNT_RETRY_MAX     = 3,       // 单轮挂载重试上限
    parameter integer REMOUNT_COOLDOWN_MS = 30000,   // 连续失败后重挂冷却
    parameter integer RESET_PULSE_CYCLES  = 100      // SD 复位脉冲宽度
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 观测输入（全部 sd_card_clk 域）----
    input  wire        media_ready,   // validated mount + complete cover preload
    input  wire [7:0]  mount_error,   // validated FAT/index/load error; zero while mounting
    input  wire [7:0]  sector_error,  // physical adapter error (all clients)
    input  wire        sector_done,   // physical adapter completion (all clients)
    input  wire        sector_busy,   // = media_sec_busy（扇区事务忙，冗余观测）

    // ---- 控制/上报输出 ----
    output reg         sd_rst_n,        // 低有效，复位 SD 媒体子系统
    output reg  [7:0]  media_err_code,  // current fault, retained until successful recovery
    output reg         media_err_toggle // 错误码变化翻转标志（跨域捆绑握手）
);

    localparam [7:0] ERR_NONE   = 8'h00;
    localparam [7:0] ERR_MOUNT  = 8'h01;  // Err-01 挂载失败
    localparam [7:0] ERR_RD_TMO = 8'h05;  // Err-05 读超时

    localparam [2:0] ST_WAIT_MOUNT  = 3'd0;
    localparam [2:0] ST_RESET_PULSE = 3'd1;
    localparam [2:0] ST_COOLDOWN    = 3'd2;

    // 共享 1kHz 毫秒预分频，把挂载/冷却两个长计时器从周期计数压缩成毫秒计数，
    // 明显降低寄存器与比较逻辑资源占用，同时保持误差在 1ms 量级。
    localparam integer PRE_DIV  = CLK_FREQ_HZ / 1000;         // 100000 @100MHz
    localparam integer PRE_W    = $clog2(PRE_DIV);            // 17
    localparam integer MOUNT_W  = $clog2(MOUNT_TIMEOUT_MS);   // 13 (5000)
    localparam integer COOL_W   = $clog2(REMOUNT_COOLDOWN_MS);// 15 (30000)
    localparam integer PULSE_W  = $clog2(RESET_PULSE_CYCLES); // 7  (100)
    localparam [2:0]  RETRY_LIMIT = MOUNT_RETRY_MAX[2:0];

    reg [2:0]          state;
    reg [PRE_W-1:0]    pre_cnt;
    wire               ms_tick = (pre_cnt >= (PRE_DIV - 1));
    reg [MOUNT_W-1:0]  mount_cnt;
    reg [COOL_W-1:0]   cool_cnt;
    reg [PULSE_W-1:0]  pulse_cnt;
    reg [2:0]          mount_attempt;

    // 毫秒预分频器。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pre_cnt <= {PRE_W{1'b0}};
        else if (ms_tick)
            pre_cnt <= {PRE_W{1'b0}};
        else
            pre_cnt <= pre_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_WAIT_MOUNT;
            mount_cnt       <= {MOUNT_W{1'b0}};
            cool_cnt        <= {COOL_W{1'b0}};
            pulse_cnt       <= {PULSE_W{1'b0}};
            mount_attempt   <= 3'd0;
            sd_rst_n        <= 1'b1;
            media_err_code  <= ERR_NONE;
            media_err_toggle<= 1'b0;
        end else begin
            if ((state == ST_WAIT_MOUNT) && (mount_error != 8'd0) &&
                (mount_error != media_err_code)) begin
                media_err_code <= mount_error;
                media_err_toggle <= ~media_err_toggle;
            end
            // ---- 扇区事务错误（最高优先级）：adapter 超时返回 -> 复位恢复 ----
            if (sector_done && (sector_error != 8'd0)) begin
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
                        if (media_err_code != ERR_NONE) begin
                            media_err_code <= ERR_NONE;
                            media_err_toggle <= ~media_err_toggle;
                        end
                    end else if (ms_tick) begin
                        if (mount_cnt >= (MOUNT_TIMEOUT_MS - 1)) begin
                            mount_cnt <= {MOUNT_W{1'b0}};
                            // Preserve the concrete CRC/FAT/read failure during retry.
                            if (media_err_code == ERR_NONE && mount_error == 8'd0) begin
                                media_err_code   <= ERR_MOUNT;
                                media_err_toggle <= ~media_err_toggle;
                            end
                            if (mount_attempt >= RETRY_LIMIT) begin
                                mount_attempt <= 3'd0;
                                state   <= ST_COOLDOWN;
                                cool_cnt<= {COOL_W{1'b0}};
                            end else begin
                                mount_attempt <= mount_attempt + 3'd1;
                                state   <= ST_RESET_PULSE;
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
                    if (ms_tick) begin
                        if (cool_cnt >= (REMOUNT_COOLDOWN_MS - 1)) begin
                            cool_cnt <= {COOL_W{1'b0}};
                            mount_attempt <= 3'd0;
                            state   <= ST_RESET_PULSE;
                            pulse_cnt <= {PULSE_W{1'b0}};
                            sd_rst_n <= 1'b0;
                        end else begin
                            cool_cnt <= cool_cnt + 1'b1;
                        end
                    end
                end
                default: state <= ST_WAIT_MOUNT;
                endcase
            end
        end
    end

endmodule
`endif
