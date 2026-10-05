
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 24'd2;
parameter BUF3_ADDR     = FRAME_PIXELS * 24'd3;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] transition_rgb;
wire [23:0] osd_rgb_out;
wire [23:0] waveform_rgb_out;
wire        osd_de_out;
wire        osd_active;
wire        waveform_active;
wire        display_valid;
wire        auto_play_en_out;
wire [7:0]  osd_error_code;
wire        osd_error_toggle;
wire        switch_abort_toggle;

// 第十讲：图片转场控制与像素应用
wire        key_next_transition_press;
wire        fade_next_event;
wire        fade_busy;
wire [7:0]  fade_alpha;
wire        fade_active;
wire        wipe_active;
wire [4:0]  wipe_ramp;
wire [1:0]  transition_kind;
wire        frame_start;

// ===================== 第十四讲：亮度/对比度参数 =====================
// 参数菜单控制器在 sd_card_clk 域，现有 KEY1/KEY2 的低有效键流先经过它。
wire        key1_eff_n;
wire        key2_eff_n;
wire [7:0]  cfg_brightness_ctrl;
wire [7:0]  cfg_contrast_ctrl;
wire        cfg_param_update;
wire        cfg_menu_event;
wire [1:0]  cfg_menu_kind;
wire [3:0]  cfg_menu_level;
wire        cfg_menu_active;

reg  [7:0]  cfg_brightness_sync1;
reg  [7:0]  cfg_brightness_sync2;
reg  [7:0]  cfg_contrast_sync1;
reg  [7:0]  cfg_contrast_sync2;
reg         cfg_menu_active_sync1;
reg         cfg_menu_active_sync2;
reg  [7:0]  brightness_frame;
reg  [7:0]  contrast_frame;
reg         menu_active_frame;
wire [23:0] adjusted_rgb;
wire        adjusted_de;
reg  [9:0]  adjusted_pixel_x;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
reg  [1:0]  sd_card_write_req_ack_sync;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

// ===================== 第十三/十五讲：图片缩略图与交互选择 =====================
// 第十五讲在第十三讲取像链路上增加 thumbnail_controller。控制器位于
// sd_card_clk 域，只负责 view_mode/focus_index/active_index/transition_req；
// 视频域仍在 frame_start 整帧提交，避免像素链路半帧换图。
wire        key_view_hold;          // KEY1 长按脉冲：进入/退出缩略图
wire        key2_thumb_press;       // KEY2 短按脉冲：缩略图焦点左移
wire        key2_thumb_hold;        // KEY2 长按脉冲：缩略图确认

wire        thumb_mode_sd;          // thumbnail_controller 输出（sd 域）
wire [1:0]  thumb_focus_index_sd;
wire [1:0]  thumb_active_index_sd;
wire        thumb_transition_req_sd;
wire        thumb_confirm_event_sd;

wire        key_next_request_sd;    // 全屏模式 KEY1 短按：下一张
wire        fade_start_event_sd;    // 送 video_fade_transition 的淡出请求
wire        key2_to_sd;             // 缩略图模式下屏蔽原 KEY2 功能
reg         key2_thumb_lock_sd;     // 锁定到 KEY2 松开，防止确认后误触发上一张

reg         thumb_select_pending_sd;
reg         thumb_select_hold_sd;
reg  [1:0]  thumb_select_index_hold_sd;
wire        thumb_select_req_sd;
wire [1:0]  thumb_select_index_sd;
wire        sd_select_ack;

reg         frame_start_toggle_vid;
reg  [2:0]  frame_start_tgl_sd;
wire        frame_start_sd;

reg         view_mode_sd_sync1;
reg         view_mode_sd_sync2;
reg         view_mode_frame;
wire        thumb_view;

reg  [1:0]  thumb_focus_sync1;
reg  [1:0]  thumb_focus_sync2;
reg  [1:0]  thumb_focus_frame;

wire [3:0]  image_ready_sd;         // sd_card_clk 域：四个 bank 就绪标记
reg  [3:0]  image_ready_sync1;
reg  [3:0]  image_ready_sync2;      // video 域：缩略图 image_complete

wire        thumb_active;           // 当前像素属于缩略图区域
wire [23:0] thumb_rgb;              // 缩略图像素（含焦点边框色）
wire        thumb_focus_border;
wire        thumb_line_mismatch;    // 行首一致性校验失败（可上 ILA 观察）
wire [23:0] view_rgb;               // 叠加缩略图之后的像素源

wire        thumb_rd_req;
wire [ADDR_BITS-1:0] thumb_rd_addr;
wire        thumb_rd_valid;
wire [31:0] thumb_rd_dout;
wire        thumb_mem_enable;       // mem 域：缩略图取像允许发请求

wire        frw_app_rd_en;          // frame_read_write -> 仲裁器
wire [ADDR_BITS-1:0] frw_app_rd_addr;
wire        frw_rd_valid;           // 仲裁器 -> frame_read_write 的 Sdr_rd_en
wire        rd_arb_mode_active;     // 1=缩略图取像占用 SDRAM 读口
wire        rd_arb_mem_idle;        // 1=读口无待切换
wire        frw_read_en_gated;      // 帧读 FIFO 消费使能（缩略图模式下关断）
reg         frw_resume;             // 回到全屏后等一次新的帧读握手再放行

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;
wire [1:0]  media_id;
wire [7:0]  audio_volume;
wire        audio_sample_overflow;
wire        audio_contract_error;
wire        audio_blip_active;

// 第十一讲：AUDIO.PCM 流式播放相关信号
wire        audio_file_valid;
wire [31:0] audio_start_lba;
wire [31:0] audio_total_sectors;
wire        audio_play_enable;
wire        wav_sec_req;
wire [31:0] wav_sec_lba;
wire        wav_sec_busy;
wire        wav_sec_valid;
wire [7:0]  wav_sec_byte;
wire [8:0]  wav_sec_byte_index;
wire        wav_sec_done;
wire [7:0]  wav_sec_error;
wire        wav_sample_valid;
wire        wav_sample_ready;
wire signed [15:0] wav_sample_left;
wire signed [15:0] wav_sample_right;
wire        wav_stream_active;
wire        wav_stream_end;
wire        wav_buffer_low;
wire [31:0] wav_sample_counter;
wire [7:0]  wav_fade_gain;
wire        wav_scaled_valid;
wire signed [15:0] wav_scaled_left;
wire signed [15:0] wav_scaled_right;
wire        arp_sample_valid;
wire        arp_sample_ready;
wire signed [15:0] arp_sample_left;
wire signed [15:0] arp_sample_right;
wire        mix_sample_valid;
wire        mix_sample_ready;
wire signed [15:0] mix_sample_left;
wire signed [15:0] mix_sample_right;
reg  [31:0] wav_tick_acc;
reg         wav_sample_tick;

reg [3:0]   media_state_code_sync1;
reg [3:0]   media_state_code_sync2;
reg [3:0]   media_state_code_sync3;
reg         display_valid_sync1;
reg         display_valid_sync2;
reg         audio_play_enable_sync1;
reg         audio_play_enable_sync2;
reg         auto_enabled_sync1;
reg         auto_enabled_sync2;
reg [7:0]   osd_error_code_sync1;
reg [7:0]   osd_error_code_sync2;
reg         osd_error_toggle_sync1;
reg         osd_error_toggle_sync2;
reg         osd_error_toggle_seen;
reg         osd_error_update_pending;
reg [7:0]   osd_error_code_frame;
reg [9:0]   osd_pixel_x;
reg         vs_q;
reg         transition_armed;
reg         index_change_pending;
reg         index_commit_pulse;
reg [2:0]   switch_abort_sync;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 第六讲：复位源由外部复位按键和两个 PLL 锁定共同决定。
// 第3课起音频复用像素时钟，因此这里只等待 sys_pll 与 video_pll。
wire sys_pll_lock;
wire video_pll_lock;
wire ext_rst_n;
wire sdcard_rst_n;
wire mem_rst_n;
wire video_rst_n;
wire Sdr_init_done_sd;

assign ext_rst_n = rst_n & sys_pll_lock & video_pll_lock;

// 每个实际时钟域独立做“异步复位、同步释放”。
reset_sync u_sdcard_reset (
    .clk        (sd_card_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (sdcard_rst_n)
);

reset_sync u_mem_reset (
    .clk        (ext_mem_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (mem_rst_n)
);

reset_sync u_video_reset (
    .clk        (video_clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (video_rst_n)
);

// Sdr_init_done 位于 ext_mem_clk 域，进入 sd_card_bmp 前做两级同步。
sync_2ff u_sdram_init_sync (
    .clk        (sd_card_clk),
    .rst_n      (sdcard_rst_n),
    .async_in   (Sdr_init_done),
    .sync_out   (Sdr_init_done_sd)
);

// ===================== 第十四讲：参数菜单入口 =====================
// 教程的完赛工程用 KEY4；本工程物理上只有 KEY1/KEY2，因此按教程 2.4
// 的“组合键扩展”方案，用双键长按进入/退出菜单。菜单外两路键完全直通，
// 原有 KEY1/KEY2 行为不变。
param_menu_controller #(
    .CLK_FREQ_HZ     (100_000_000),
    .DEBOUNCE_MS     (20),
    .COMBO_HOLD_MS   (1000),
    .LONG_HOLD_MS    (1000),
    .MENU_TIMEOUT_MS (10000)
) u_param_menu_controller (
    .clk              (sd_card_clk),
    .rst_n            (sdcard_rst_n),
    .key1_n           (key1),
    .key2_n           (key2),
    .key1_out_n       (key1_eff_n),
    .key2_out_n       (key2_eff_n),
    .cfg_brightness   (cfg_brightness_ctrl),
    .cfg_contrast     (cfg_contrast_ctrl),
    .cfg_update_valid (cfg_param_update),
    .menu_event       (cfg_menu_event),
    .menu_kind        (cfg_menu_kind),
    .menu_level       (cfg_menu_level),
    .menu_active      (cfg_menu_active)
);

// =========================================================================
// 第十二讲彩点排查 诊断 D：SDRAM 帧缓存"已知图案写入 + 读回自检"
//
// 这一级隔离回答的问题是：帧缓存的“写一次、永远读”这条数据通路，
// 在长时间运行中会不会自己把数据读错/存坏。
//   唯一变量：诊断模式下显示的像素不再来自 SD 卡装载的照片，而是由 FPGA
//             直接向 bank0 写入一个已知的水平渐变图案（R=x[7:0]，
//             G=~x[7:0]，B=0x80），随后整帧反复读回。
//   保持不变：时钟、复位、SDRAM IP、读写 FIFO、时序发生器、HDMI 核全部不变。
//   预期A：7 段管计数长期保持 0（画面也无杂点）→ SDRAM 帧缓存数据通路干净，
//          彩点来自像素域之后的显示链路。
//   预期B：7 段管计数不再为 0（画面上同时把错误像素标成品红）→ 彩点根因
//          就在 SDRAM 帧缓存读/存链路，可直接用它做修复回归。
//
// 自证（隔离是否真的生效）：
//   - 诊断模式下 frame_read_write 的 .write_req/.write_en/.write_data/
//     .write_addr_index 全部由本图案发生器驱动，SD 装载器的写端口被真正切断；
//   - 图案送入 write_buf 异步 FIFO 后由原 frame_fifo_write 落盘，路径与
//     真实加载完全一致，因此本测试同时覆盖写入与读回；
//   - 读回数据在 video_clk 域与“按像素位置重建的期望值”逐像素比较，
//     vout_data_raw 是 video_delay 的输出，也就是真正送进 HDMI 核之前的像素。
//   - 整个测试不需要 SD 卡，所以“拔卡后仍出彩点”这条复现路径被完全继承。
// =========================================================================
`ifndef DIAG_SDRAM_PATTERN
`define DIAG_SDRAM_PATTERN 0
`endif

wire pat_mode = `DIAG_SDRAM_PATTERN;

// 图案写入器（sd_card_clk 域，握手与 sd_card_bmp 的写路径同构）
reg         pat_wr_req;
reg         pat_wr_en;
reg  [31:0] pat_wr_data;
reg  [9:0]  pat_x;
reg  [8:0]  pat_y;
reg  [5:0]  pat_div;
reg  [1:0]  pat_state;
reg  [15:0] pat_done_cnt;
reg         pat_done;

// 读回自检（video_clk 域）
reg         pat_done_s1;
reg         pat_done_s2;
reg         pat_de_q;
reg  [12:0] pat_line_cnt;
reg         pat_chk_en;
reg  [31:0] pat_err_cnt;

wire [23:0] pat_expect = {osd_pixel_x[7:0], ~osd_pixel_x[7:0], 8'h80};
wire        pat_bad    = pat_mode && pat_chk_en && de && (vout_data_raw != pat_expect);

// 诊断模式下：显示固定 bank0、切断 SD 装载器写端口、用自检图案驱动写端口
wire [1:0]  disp_buf_idx_eff  = pat_mode ? 2'd0 : disp_buf_idx;
wire [1:0]  write_buf_idx_eff = pat_mode ? 2'd0 : write_buf_idx;
wire        sd_write_req_eff  = pat_mode ? pat_wr_req  : sd_card_write_req;
wire        sd_write_en_eff   = pat_mode ? pat_wr_en   : sd_card_write_en;
wire [31:0] sd_write_data_eff = pat_mode ? pat_wr_data : sd_card_write_data;

// 图案写完之前不发帧读请求，让写入和读回在时间上分开（与真实"先加载再显示"一致）
wire        pat_read_gate_req = pat_mode && !pat_done_s2;
wire        display_ok        = pat_mode ? pat_done_s2 : display_valid_sync2;

// 诊断模式下把 OSD / 转场 / 波形逐级旁路，屏幕上只留 SDRAM 读回数据本身
wire [23:0] trans_rgb_eff     = pat_mode ? vout_data : transition_rgb;
wire [23:0] osd_rgb_eff       = pat_mode ? trans_rgb_eff : osd_rgb_out;
wire [23:0] wave_rgb_eff      = pat_mode ? osd_rgb_eff : waveform_rgb_out;

localparam PAT_IDLE   = 2'd0;
localparam PAT_REQ    = 2'd1;
localparam PAT_STREAM = 2'd2;
localparam PAT_DONE   = 2'd3;

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        pat_wr_req   <= 1'b0;
        pat_wr_en    <= 1'b0;
        pat_wr_data  <= 32'd0;
        pat_x        <= 10'd0;
        pat_y        <= 9'd0;
        pat_div      <= 6'd0;
        pat_state    <= PAT_IDLE;
        pat_done_cnt <= 16'd0;
        pat_done     <= 1'b0;
    end else if (pat_mode) begin
        pat_wr_en <= 1'b0;
        case (pat_state)
            PAT_IDLE: begin
                if (Sdr_init_done_sd) begin
                    pat_wr_req <= 1'b1;
                    pat_state  <= PAT_REQ;
                end
            end
            // 与 SD 装载器同样的写请求握手：sdr 侧 S_ACK 会异步清零写 FIFO，
            // 因此必须等 ack 之后再多等 64 拍才允许第一个字进 FIFO。
            PAT_REQ: begin
                if (sd_card_write_req_ack_sync[1]) begin
                    pat_wr_req <= 1'b0;
                    pat_x      <= 10'd0;
                    pat_y      <= 9'd0;
                    pat_div    <= 6'd63;
                    pat_state  <= PAT_STREAM;
                end
            end
            // 1 字 / 32 拍（约 3.1M word/s），远低于 SDRAM 写突发吞吐，
            // 保证 512 深写 FIFO 不会溢出。
            PAT_STREAM: begin
                if (pat_div != 6'd0)
                    pat_div <= pat_div - 6'd1;
                else begin
                    pat_wr_en   <= 1'b1;
                    pat_wr_data <= {pat_x[7:0], ~pat_x[7:0], 8'h80, 8'h00};
                    pat_div     <= 6'd31;
                    if (pat_x == 10'd639) begin
                        pat_x <= 10'd0;
                        if (pat_y == 9'd479)
                            pat_state <= PAT_DONE;
                        else
                            pat_y <= pat_y + 9'd1;
                    end else begin
                        pat_x <= pat_x + 10'd1;
                    end
                end
            end
            // 最后一个字只是进了 FIFO，SDRAM 落盘还要几十微秒，多等 655us
            PAT_DONE: begin
                pat_wr_en <= 1'b0;
                if (pat_done_cnt == 16'hFFFF)
                    pat_done <= 1'b1;
                else
                    pat_done_cnt <= pat_done_cnt + 16'd1;
            end
            default: pat_state <= PAT_IDLE;
        endcase
    end
end

// 读回自检：等图案落盘并完整读回若干帧后，逐像素比对并按 6 位十六进制计数
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        pat_done_s1  <= 1'b0;
        pat_done_s2  <= 1'b0;
        pat_de_q     <= 1'b0;
        pat_line_cnt <= 13'd0;
        pat_chk_en   <= 1'b0;
        pat_err_cnt  <= 32'd0;
    end else if (pat_mode) begin
        pat_done_s1 <= pat_done;
        pat_done_s2 <= pat_done_s1;
        pat_de_q    <= de;
        if (!pat_done_s2) begin
            pat_line_cnt <= 13'd0;
            pat_chk_en   <= 1'b0;
        end else if (!pat_chk_en) begin
            // 等约 8 个整帧（4000 行）再开始计数，跳过首帧建立过程
            if (pat_de_q && !de) begin
                if (pat_line_cnt >= 13'd4000)
                    pat_chk_en <= 1'b1;
                else
                    pat_line_cnt <= pat_line_cnt + 13'd1;
            end
        end else if (de && (vout_data_raw != pat_expect)) begin
            pat_err_cnt <= pat_err_cnt + 32'd1;
        end
    end
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (~rst_n),
    .locked     (sys_pll_lock)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (~rst_n),
    .locked     (video_pll_lock)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or negedge mem_rst_n) begin
    if (!mem_rst_n)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// write_req_ack 来自 ext_mem_clk 域。先在 sd_card_clk 域做两级同步，
// 再交给 bmp_read 的写请求握手，避免长组合路径直接跨域采样。
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)
        sd_card_write_req_ack_sync <= 2'b00;
    else
        sd_card_write_req_ack_sync <= {sd_card_write_req_ack_sync[0], sd_card_write_req_ack};
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (~sdcard_rst_n),
    .sdr_init_done     (Sdr_init_done_sd),
    // 第十讲：KEY1先进入转场控制器，淡出完成后再用next_event触发切换。
    .key_next          (1'b1),
    .next_event        (fade_next_event && !thumb_select_pending_sd),
    .select_req        (thumb_select_req_sd),
    .select_index      (thumb_select_index_sd),
    .select_ack        (sd_select_ack),
    .key_auto          (key2_to_sd),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .auto_play_en_out  (auto_play_en_out),
    .osd_error_code    (osd_error_code),
    .osd_error_toggle  (osd_error_toggle),
    .switch_abort_toggle(switch_abort_toggle),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .image_ready_out   (image_ready_sd),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack_sync[1]),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .audio_file_valid  (audio_file_valid),
    .audio_start_lba   (audio_start_lba),
    .audio_total_sectors(audio_total_sectors),
    .audio_play_enable (audio_play_enable),
    .audio_sec_req     (wav_sec_req),
    .audio_sec_lba     (wav_sec_lba),
    .audio_sec_busy    (wav_sec_busy),
    .audio_sec_valid   (wav_sec_valid),
    .audio_sec_byte    (wav_sec_byte),
    .audio_sec_byte_index(wav_sec_byte_index),
    .audio_sec_done    (wav_sec_done),
    .audio_sec_error   (wav_sec_error)
);

// 第十讲：KEY1外部消抖后送转场控制器，避免被sd_card_bmp内部硬切逻辑抢先响应。
// 第十三讲：换成“短按/长按判别”版本。
//   - 短按（松开时）仍输出 next 脉冲，行为等价原来的 KEY1“下一张”；
//   - 长按 1s 输出 hold 脉冲，用于切换“缩略图 / 全屏”视图，且不会同时触发
//     下一张。KEY2 的消抖模块仍用原 key_press_debounce，行为完全不变。
key_press_hold #(
    .CLK_FREQ_HZ (100_000_000),
    .DEBOUNCE_MS (20),
    .HOLD_MS     (1000)
) u_key_next_transition (
    .clk              (sd_card_clk),
    .rst              (~sdcard_rst_n),
    .button_in        (key1_eff_n),
    .press_pulse      (key_next_transition_press),
    .hold_pulse       (key_view_hold),
    .button_stable_out()
);

// 第十五讲：KEY2 短/长按判别只用于缩略图模式（左移/确认）；全屏模式下
// KEY2 仍原样直通 sd_card_bmp，自动轮播开关和长按上一张保持不变。
key_press_hold #(
    .CLK_FREQ_HZ (100_000_000),
    .DEBOUNCE_MS (20),
    .HOLD_MS     (1000)
) u_key_thumb_left_confirm (
    .clk              (sd_card_clk),
    .rst              (~sdcard_rst_n),
    .button_in        (key2_eff_n),
    .press_pulse      (key2_thumb_press),
    .hold_pulse       (key2_thumb_hold),
    .button_stable_out()
);

assign key_next_request_sd   = key_next_transition_press && !thumb_mode_sd;
assign key2_to_sd            = (thumb_mode_sd || key2_thumb_lock_sd) ? 1'b1 : key2_eff_n;
assign thumb_confirm_event_sd = key2_thumb_hold && thumb_mode_sd;
assign thumb_select_req_sd   = thumb_select_hold_sd;
assign thumb_select_index_sd = thumb_select_index_hold_sd;

// 教程 thumbnail_controller：控制域按键 -> view/focus/active/transition_req。
// key_mode=KEY1长按；缩略图下 KEY1短按=右移、KEY2短按=左移、KEY2长按=确认。
thumbnail_controller u_thumbnail_controller (
    .clk             (sd_card_clk),
    .rst_n           (sdcard_rst_n),
    .key_right       (key_next_transition_press && thumb_mode_sd),
    .key_left        (key2_thumb_press && thumb_mode_sd),
    .key_confirm     (thumb_confirm_event_sd),
    .key_mode        (key_view_hold),
    .image_complete  (image_ready_sd),
    .frame_start     (frame_start_sd),
    .view_mode       (thumb_mode_sd),
    .focus_index     (thumb_focus_index_sd),
    .active_index    (thumb_active_index_sd),
    .transition_req  (thumb_transition_req_sd)
);

// video 域 frame_start 单拍 -> sd 域单拍，供 controller 在帧边界提交转场请求。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        frame_start_toggle_vid <= 1'b0;
    else if (frame_start)
        frame_start_toggle_vid <= ~frame_start_toggle_vid;
end

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)
        frame_start_tgl_sd <= 3'b000;
    else
        frame_start_tgl_sd <= {frame_start_tgl_sd[1:0], frame_start_toggle_vid};
end

assign frame_start_sd = frame_start_tgl_sd[2] ^ frame_start_tgl_sd[1];

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)
        key2_thumb_lock_sd <= 1'b0;
    else if (key2_eff_n)
        key2_thumb_lock_sd <= 1'b0;
    else if (thumb_mode_sd)
        key2_thumb_lock_sd <= 1'b1;
end

// 快速选择：确认后在淡出完成的 next_event 边界发出保持请求，直到
// sd_card_bmp 的 select_ack 接受，避免预加载忙时丢失一次选图请求。
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        thumb_select_pending_sd    <= 1'b0;
        thumb_select_hold_sd       <= 1'b0;
        thumb_select_index_hold_sd <= 2'd0;
    end else begin
        if (thumb_confirm_event_sd)
            thumb_select_pending_sd <= 1'b1;

        if (thumb_select_pending_sd)
            thumb_select_index_hold_sd <= thumb_active_index_sd;

        if (fade_next_event && thumb_select_pending_sd) begin
            thumb_select_hold_sd    <= 1'b1;
            thumb_select_pending_sd <= 1'b0;
        end

        if (sd_select_ack)
            thumb_select_hold_sd <= 1'b0;
    end
end

assign fade_start_event_sd = key_next_request_sd ||
                             (thumb_transition_req_sd && thumb_select_pending_sd);

video_fade_transition #(
    .FADE_FRAMES (16)
) u_video_fade_transition (
    .ctrl_clk        (sd_card_clk),
    .ctrl_rst_n      (sdcard_rst_n),
    .next_event_in   (fade_start_event_sd),
    .next_event_out  (fade_next_event),
    .fade_busy       (fade_busy),

    .pix_clk         (video_clk),
    .pix_rst_n       (video_rst_n),
    .player_active   (display_valid_sync2),
    .frame_start     (frame_start),
    .index_commit    (index_commit_pulse),
    .active_index    (media_id),
    .alpha_out       (fade_alpha),
    .fade_active     (fade_active),
    .wipe_active     (wipe_active),
    .ramp_out        (wipe_ramp),
    .transition_kind (transition_kind)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

// 诊断 D：自检模式下 7 段管显示"读回不一致像素计数"的 6 位十六进制
function [6:0] hex7seg;
    input [3:0] v;
    begin
        case (v)
            4'h0:    hex7seg = 7'b100_0000;
            4'h1:    hex7seg = 7'b111_1001;
            4'h2:    hex7seg = 7'b010_0100;
            4'h3:    hex7seg = 7'b011_0000;
            4'h4:    hex7seg = 7'b001_1001;
            4'h5:    hex7seg = 7'b001_0010;
            4'h6:    hex7seg = 7'b000_0010;
            4'h7:    hex7seg = 7'b111_1000;
            4'h8:    hex7seg = 7'b000_0000;
            4'h9:    hex7seg = 7'b001_0000;
            4'ha:    hex7seg = 7'b000_1000;
            4'hb:    hex7seg = 7'b000_0011;
            4'hc:    hex7seg = 7'b100_0110;
            4'hd:    hex7seg = 7'b010_0001;
            4'he:    hex7seg = 7'b000_0110;
            default: hex7seg = 7'b000_1110;
        endcase
    end
endfunction

// 第十二讲时序修正：扫描器原先用 50MHz 原始 clk，而显示的 state_code 由
// sd_card_clk(100MHz) 域产生，构成真实跨时钟域路径；TD final 时序把它报成
// hold WNS -0.738ns（12 个终点，时钟偏斜 1.615ns）。这里把扫描器整体搬进
// sd_card_clk 域并把 CLK_FREQ 同步改成 100MHz，刷新率仍为 200Hz/位，
// 跨域路径消失，也不再需要额外的约束豁免。
seg_scan #(
    .CLK_FREQ          (100_000_000)
) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (sdcard_rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[3:0])}   : {1'b1,7'b1111_111}),
    .seg_data_1        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[7:4])}   : {1'b1,7'b1111_111}),
    .seg_data_2        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[11:8])}  : {1'b1,7'b1111_111}),
    .seg_data_3        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[15:12])} : {1'b1,7'b1111_111}),
    .seg_data_4        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[19:16])} : {1'b1,7'b1111_111}),
    .seg_data_5        (pat_mode ? {1'b1,hex7seg(pat_err_cnt[23:20])} : {1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
// ------------------------------------------------------------
// 第十二讲彩点排查 诊断开关（默认 0，正式工程行为完全不变）
//
// DIAG_LOCAL_PATTERN = 1 时同时做两件事，用于“单变量隔离”：
//   (1) 像素域改用本地彩条 local_pattern_rgb，不再使用 SDRAM 读回数据；
//   (2) frame_read_write 的帧读请求输入被硬接 0（在消费者侧切断）。
// 自证：video_read_req_eff 接 0 后，frame_fifo_read 的 S_IDLE 永远不满足
// `read_req_d2 == 1'b1 && Sdr_init_done`（见 frame_fifo_read.v S_IDLE），
// 状态机停在 S_IDLE，App_rd_en 恒为 0，SDRAM 帧读突发被真正切断，
// 而不是“设置了诊断位但其实还在读”。
// ------------------------------------------------------------
`ifndef DIAG_LOCAL_PATTERN
`define DIAG_LOCAL_PATTERN 0
`endif

wire        video_read_req_eff;
reg  [23:0] local_pattern_rgb;

// ===================== 第十三/十五讲：缩略图/全屏视图切换 =====================
// controller 的 view_mode/focus_index 位于 sd_card_clk 域；两级同步后只在
// frame_start 整帧提交，避免半帧切换坐标或焦点边框造成撕裂。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        view_mode_sd_sync1 <= 1'b0;
        view_mode_sd_sync2 <= 1'b0;
        view_mode_frame    <= 1'b0;
        thumb_focus_sync1  <= 2'd0;
        thumb_focus_sync2  <= 2'd0;
        thumb_focus_frame  <= 2'd0;
    end else begin
        view_mode_sd_sync1 <= thumb_mode_sd;
        view_mode_sd_sync2 <= view_mode_sd_sync1;
        thumb_focus_sync1  <= thumb_focus_index_sd;
        thumb_focus_sync2  <= thumb_focus_sync1;

        if (frame_start) begin
            view_mode_frame   <= view_mode_sd_sync2;
            thumb_focus_frame <= thumb_focus_sync2;
        end
    end
end

// 诊断模式（DIAG_SDRAM_PATTERN）下保持原行为，缩略图视图强制关闭。
assign thumb_view = view_mode_frame & ~pat_mode;

// 实验B 切断 SDRAM 帧读；诊断D 在自检图案落盘前也不发帧读请求。
// 第十三讲：缩略图视图下同样不发整帧读请求，把 SDRAM 读口让给按坐标取像。
assign video_read_req_eff = (`DIAG_LOCAL_PATTERN) ? 1'b0
                          : (pat_read_gate_req ? 1'b0
                          : (thumb_view ? 1'b0 : video_read_req));

// 缩略图模式关断帧读 FIFO 的消费使能，使 frame_fifo_read 填满后停在
// S_CHECK_FIFO（App_rd_en 拉低），读口得以安全换手。
// 回到全屏后等一次新的读请求握手（read_req_ack）再放行，保证从整帧起点
// 重新开始读，避免半帧错位。全屏稳态下 frw_resume 恒为 1，等价直通。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        frw_resume <= 1'b1;
    else if (thumb_view)
        frw_resume <= 1'b0;
    else if (video_read_req_ack)
        frw_resume <= 1'b1;
end

assign frw_read_en_gated = video_read_en & frw_resume;

// 8~10 段竖彩条：大块纯色区域最容易暴露单像素彩点。
always @(*) begin
    case (osd_pixel_x[9:6])
        4'd0:    local_pattern_rgb = 24'hFF_FF_FF;  // 白
        4'd1:    local_pattern_rgb = 24'hFF_FF_00;  // 黄
        4'd2:    local_pattern_rgb = 24'h00_FF_FF;  // 青
        4'd3:    local_pattern_rgb = 24'h00_FF_00;  // 绿
        4'd4:    local_pattern_rgb = 24'hFF_00_FF;  // 品红
        4'd5:    local_pattern_rgb = 24'hFF_00_00;  // 红
        4'd6:    local_pattern_rgb = 24'h00_00_FF;  // 蓝
        4'd7:    local_pattern_rgb = 24'h00_00_00;  // 黑
        4'd8:    local_pattern_rgb = 24'h80_80_80;  // 中灰
        default: local_pattern_rgb = 24'h40_40_40;  // 深灰
    endcase
end

video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// 诊断模式下直接输出本地彩条（不依赖 display_valid，便于上电即观察）。
// 诊断D 把“读回数据与已知图案不一致”的像素直接标成品红，肉眼即可定位。
assign vout_data = (`DIAG_LOCAL_PATTERN) ? local_pattern_rgb
                 : (pat_bad ? 24'hff_00_ff
                            : (display_ok ? vout_data_raw : 24'd0));

// 第十三讲：缩略图视图只是个像素级替换层——
//   - 缩略图区域内显示按坐标取回的源图像素（含焦点边框色）；
//   - 其余区域输出黑（与教程 thumbnail_layout 的 thumb_de 语义一致）；
//   - 完全不碰 de/vs 节拍，也不影响 HDMI 音频数据岛调度。
assign view_rgb = thumb_view ? (thumb_active ? thumb_rgb : 24'd0)
                             : vout_data;

// ===================== 第十四讲：亮度/对比度像素调节 =====================
// 控制域参数先做两级同步，再在 frame_start 整帧锁存。默认值
// brightness=255、contrast=128 时模块严格旁路，因此不改动既有画面。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        cfg_brightness_sync1  <= 8'd255;
        cfg_brightness_sync2  <= 8'd255;
        cfg_contrast_sync1    <= 8'd128;
        cfg_contrast_sync2    <= 8'd128;
        cfg_menu_active_sync1 <= 1'b0;
        cfg_menu_active_sync2 <= 1'b0;
        brightness_frame      <= 8'd255;
        contrast_frame        <= 8'd128;
        menu_active_frame     <= 1'b0;
    end else begin
        cfg_brightness_sync1  <= cfg_brightness_ctrl;
        cfg_brightness_sync2  <= cfg_brightness_sync1;
        cfg_contrast_sync1    <= cfg_contrast_ctrl;
        cfg_contrast_sync2    <= cfg_contrast_sync1;
        cfg_menu_active_sync1 <= cfg_menu_active;
        cfg_menu_active_sync2 <= cfg_menu_active_sync1;

        if (frame_start) begin
            brightness_frame  <= cfg_brightness_sync2;
            contrast_frame    <= cfg_contrast_sync2;
            menu_active_frame <= cfg_menu_active_sync2;
        end
    end
end

// ===================== 第九讲：OSD状态字幕叠加 =====================
// OSD 紧跟在黑屏屏蔽之后、video_rgb_to_axis 之前，纯组合替换像素，
// 不改变现有 de/vs 的节拍，也不影响 HDMI 音频数据岛调度。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        osd_pixel_x <= 10'd0;
    else if (!de)
        osd_pixel_x <= 10'd0;
    else
        osd_pixel_x <= osd_pixel_x + 10'd1;
end

// 第十四讲教程 2.1：亮度折进转场 alpha，只增加一次乘法；brightness=255
// 时 effective_alpha 与原有 fade_alpha 完全相同，不改变第十讲既有行为。
video_transition_apply #(
    .WIPE_STEP (40)
) u_video_transition_apply (
    .rgb_in      (view_rgb),
    .alpha       (fade_alpha),
    .brightness  (brightness_frame),
    .wipe_active (wipe_active),
    .wipe_ramp   (wipe_ramp),
    .pixel_x     (osd_pixel_x),
    .rgb_out     (transition_rgb)
);

// 第十四讲教程 3.2.2：对比度采用参考答案的 signed 乘法、算术右移和
// 饱和截断。亮度已按教程 2.1 折进转场上式，因此这里固定为满亮度，
// 单独模块自身的亮度通路仍保留，便于按教程做独立仿真和扩展。
brightness_contrast_adjust u_brightness_contrast_adjust (
    .clk        (video_clk),
    .rst_n      (video_rst_n),
    .in_de      (de),
    .rgb_in     (transition_rgb),
    .brightness (8'd255),
    .contrast   (contrast_frame),
    .out_de     (adjusted_de),
    .rgb_out    (adjusted_rgb)
);

// 对比度模块内部有一拍流水线，像素 x 坐标同步后移一拍，保证 OSD/波形
// 仍与 rgb 对齐。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        adjusted_pixel_x <= 10'd0;
    else if (!adjusted_de)
        adjusted_pixel_x <= 10'd0;
    else
        adjusted_pixel_x <= adjusted_pixel_x + 10'd1;
end

osd_overlay_24 #(
    .OSD_X(8),
    .OSD_Y(8)
) u_osd_overlay_24 (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (vs),
    .de           (adjusted_de),
    .rgb_in       (adjusted_rgb),
    .pixel_x      (adjusted_pixel_x),
    .active_index (media_id),
    .auto_enabled (auto_enabled_sync2),
    .error_code   (osd_error_code_frame),
    .brightness   (brightness_frame),
    .contrast     (contrast_frame),
    .menu_active  (menu_active_frame),
    .rgb_out      (osd_rgb_out),
    .de_out       (osd_de_out),
    .osd_active   (osd_active)
);

// 第十二讲：音频波形+峰值条叠加。位于OSD之后、RGB转AXIS之前，
// 纯像素级组合替换，不改变de/vs节拍，不影响HDMI音频数据岛调度。
promax_audio_waveform #(
    .WAVE_X      (64),
    .WAVE_Y      (376),
    .WAVE_WIDTH  (512),
    .WAVE_HEIGHT (96),
    .DECIMATE    (12)
) u_promax_audio_waveform (
    .clk             (video_clk),
    .rst_n           (video_rst_n),
    .vsync           (vs),
    .de              (adjusted_de),
    .rgb_in          (osd_rgb_out),
    .pixel_x         (adjusted_pixel_x),
    .enable          (audio_play_enable_sync2),
    .pcm_tap_valid   (wav_sample_valid),
    .pcm_tap_left    (wav_sample_left),
    .rgb_out         (waveform_rgb_out),
    .waveform_active (waveform_active)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    // 第十三讲：帧读请求先送 sdram_rd_arbiter，再由仲裁器与缩略图取像
    // 二选一驱动 SDRAM 的唯一只读口。全屏模式下该仲裁器是纯组合直通。
    .App_rd_en         (frw_app_rd_en),
    .App_rd_addr       (frw_app_rd_addr),
    .Sdr_rd_en         (frw_rd_valid),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req_eff),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (disp_buf_idx_eff),
    .read_len          (FRAME_PIXELS),
    .read_en           (frw_read_en_gated),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_write_req_eff),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx_eff),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_write_en_eff),
    .write_data        (sd_write_data_eff)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 第十三讲：缩略图取像与 SDRAM 读口换手 =====================
// 一、把 sd_card_bmp 的 bank 就绪标记同步到 video 域，作为 thumbnail_layout
//     的 image_complete。四位标记每次只置一位，两拍同步即可。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        image_ready_sync1 <= 4'd0;
        image_ready_sync2 <= 4'd0;
    end else begin
        image_ready_sync1 <= image_ready_sd;
        image_ready_sync2 <= image_ready_sync1;
    end
end

// 二、读口仲裁器：全屏模式下 app_rd_en/app_rd_addr/frw_rd_valid 都是纯组合
//     直通，和改动前完全一致；只在缩略图视图下把读口交给取像引擎。
sdram_rd_arbiter #(
    .ADDR_WIDTH   (ADDR_BITS),
    .QUIET_CYCLES (64)
) u_sdram_rd_arbiter (
    .clk            (ext_mem_clk),
    .rst            (~mem_rst_n),
    .view_mode_req  (thumb_view),

    .frw_rd_en      (frw_app_rd_en),
    .frw_rd_addr    (frw_app_rd_addr),
    .frw_rd_valid   (frw_rd_valid),

    .thumb_rd_req   (thumb_rd_req),
    .thumb_rd_addr  (thumb_rd_addr),
    .thumb_rd_valid (thumb_rd_valid),
    .thumb_rd_dout  (thumb_rd_dout),

    .app_rd_en      (App_rd_en),
    .app_rd_addr    (App_rd_addr),
    .sdr_rd_en      (Sdr_rd_en),
    .sdr_rd_dout    (Sdr_rd_dout),

    .mode_active    (rd_arb_mode_active),
    .mem_idle       (rd_arb_mem_idle)
);

// 三、缩略图取像引擎：教程 thumbnail_layout 只做坐标映射，这里按第八讲
//     media_frame_reader 的职责边界补一个“按坐标取一个像素”的读取器。
//     enable=0（全屏）时其内部 FIFO 持续复位，不占用 SDRAM 读口。
// 第十二讲 78dbb17 的彩点修复已经证明：SDRAM 读口不能在
// Sdr_init_ref_vld / Sdr_busy 窗口内新起读操作。缩略图取像是随机单字读，
// 更容易撞上刷新窗口；这里复用同一套边界，只在仲裁完成且控制器空闲时
// 才允许从地址 FIFO 发出一笔取像请求。
wire thumb_ctrl_quiet = ~Sdr_init_ref_vld & ~Sdr_busy & Sdr_init_done;
assign thumb_mem_enable = rd_arb_mem_idle & rd_arb_mode_active & thumb_ctrl_quiet;

thumbnail_view_reader #(
    .DISPLAY_WIDTH  (640),
    .DISPLAY_HEIGHT (480),
    .ADDR_WIDTH     (ADDR_BITS),
    .BANK_WORDS     (307200),
    .THUMB_WIDTH    (160),
    .THUMB_HEIGHT   (120),
    .BORDER_RGB     (24'hff_ff_00)
) u_thumbnail_view_reader (
    .pix_clk        (video_clk),
    .pix_rst_n      (video_rst_n),
    .mem_clk        (ext_mem_clk),
    .mem_rst_n      (mem_rst_n),

    .enable         (thumb_view),
    .mem_enable     (thumb_mem_enable),
    .frame_start    (frame_start),
    .focus_index    (thumb_focus_frame),
    .image_complete (image_ready_sync2),
    .pixel_x        (osd_pixel_x),
    .in_de          (de),

    .thumb_active   (thumb_active),
    .pixel_rgb      (thumb_rgb),
    .focus_border   (thumb_focus_border),
    .line_mismatch  (thumb_line_mismatch),

    .rd_req         (thumb_rd_req),
    .rd_addr        (thumb_rd_addr),
    .rd_valid       (thumb_rd_valid),
    .rd_data        (thumb_rd_dout)
);

// ===================== 音频：第3课正弦媒体音调 =====================
// state_code 在第二讲中已改为“当前图片编号 1~4”，这里减 1 得到 media_id 0~3。
// 两拍同步把 100MHz sd_card_clk 域的图片编号安全地带到 25MHz video_clk 域。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        media_state_code_sync1 <= 4'd0;
        media_state_code_sync2 <= 4'd0;
        media_state_code_sync3 <= 4'd0;
        display_valid_sync1    <= 1'b0;
        display_valid_sync2    <= 1'b0;
        audio_play_enable_sync1 <= 1'b0;
        audio_play_enable_sync2 <= 1'b0;
        auto_enabled_sync1     <= 1'b0;
        auto_enabled_sync2     <= 1'b0;
        osd_error_code_sync1   <= 8'd0;
        osd_error_code_sync2   <= 8'd0;
        osd_error_toggle_sync1 <= 1'b0;
        osd_error_toggle_sync2 <= 1'b0;
        osd_error_toggle_seen  <= 1'b0;
        osd_error_update_pending <= 1'b0;
        osd_error_code_frame   <= 8'd0;
        vs_q                   <= 1'b1;
        transition_armed       <= 1'b0;
        index_change_pending   <= 1'b0;
        index_commit_pulse     <= 1'b0;
        switch_abort_sync      <= 3'b000;
    end else begin
        media_state_code_sync1 <= state_code;
        media_state_code_sync2 <= media_state_code_sync1;
        media_state_code_sync3 <= media_state_code_sync2;
        display_valid_sync1    <= display_valid;
        display_valid_sync2    <= display_valid_sync1;
        audio_play_enable_sync1 <= audio_play_enable;
        audio_play_enable_sync2 <= audio_play_enable_sync1;
        auto_enabled_sync1     <= auto_play_en_out;
        auto_enabled_sync2     <= auto_enabled_sync1;
        vs_q                   <= vs;
        index_commit_pulse     <= 1'b0;
        switch_abort_sync      <= {switch_abort_sync[1:0], switch_abort_toggle};

        // error_code 是低频8位状态，用toggle作为捆绑数据更新标志。
        // 等待toggle同步完成后的下一拍再提交数据，避免多位同时变化时
        // 视频域采到中间值。
        osd_error_code_sync1   <= osd_error_code;
        osd_error_code_sync2   <= osd_error_code_sync1;
        osd_error_toggle_sync1 <= osd_error_toggle;
        osd_error_toggle_sync2 <= osd_error_toggle_sync1;
        if (osd_error_toggle_sync2 != osd_error_toggle_seen) begin
            osd_error_toggle_seen   <= osd_error_toggle_sync2;
            osd_error_update_pending <= 1'b1;
        end else if (osd_error_update_pending) begin
            osd_error_code_frame    <= osd_error_code_sync2;
            osd_error_update_pending <= 1'b0;
        end

        // 第十讲：首图提交只用于“武装”转场控制器，不触发转场。
        // 后续每次显示图片号变化都在下一个frame_start提交给转场模块，
        // 手动切换此时处于S_HOLD走淡入，自动轮播在S_IDLE走Wipe。
        if (display_valid_sync2 &&
            media_state_code_sync2 >= 4'd1 &&
            media_state_code_sync2 <= 4'd4) begin
            if (!transition_armed) begin
                transition_armed <= 1'b1;
            end else if (media_state_code_sync2 != media_state_code_sync3) begin
                index_change_pending <= 1'b1;
            end
        end

        if (frame_start && index_change_pending) begin
            index_commit_pulse <= 1'b1;
            index_change_pending <= 1'b0;
        end

        // 手动切换加载失败时，释放转场状态机，避免一直停在黑场。
        if (switch_abort_sync[2] ^ switch_abort_sync[1])
            index_commit_pulse <= 1'b1;
    end
end

assign frame_start = vs_q && !vs;

// display_valid 置位后 state_code 稳定为 1~4；首图提交前固定使用 media_id=0。
assign media_id = (display_valid_sync2 &&
                   media_state_code_sync2 >= 4'd1 &&
                   media_state_code_sync2 <= 4'd4)
                ? (media_state_code_sync2[1:0] - 2'd1)
                : 2'd0;

// 16点正弦 LUT 峰值约 12000，200/255 缩放后仍保留足够余量，避免削波爆音。
assign audio_volume = 8'd200;

// 48kHz WAV 采样节拍。video_clk=25MHz，与 pcm_media_tone 使用同一
// 分数累加器算法，保证 WAV 与原琶音音源的采样率一致。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        wav_tick_acc    <= 32'd0;
        wav_sample_tick <= 1'b0;
    end else begin
        wav_sample_tick <= 1'b0;
        if (wav_tick_acc >= (32'd25_000_000 - 32'd48_000)) begin
            wav_tick_acc    <= wav_tick_acc + 32'd48_000 - 32'd25_000_000;
            wav_sample_tick <= 1'b1;
        end else begin
            wav_tick_acc <= wav_tick_acc + 32'd48_000;
        end
    end
end

// 第十一讲核心：从 AUDIO.PCM 的连续扇区流式播放。
wav_stream_player #(
    .ADDR_WIDTH        (12),
    .SAMPLES_PER_SECTOR(256)
) u_wav_stream_player (
    .wr_clk            (sd_card_clk),
    .wr_rst_n          (sdcard_rst_n),
    .play_enable       (audio_play_enable),
    .start_lba         (audio_start_lba),
    .total_sectors     (audio_total_sectors),
    .sd_req            (wav_sec_req),
    .sd_lba            (wav_sec_lba),
    .sd_busy           (wav_sec_busy),
    .sd_valid          (wav_sec_valid),
    .sd_byte           (wav_sec_byte),
    .sd_byte_index     (wav_sec_byte_index),
    .sd_done           (wav_sec_done),
    .sd_error          (wav_sec_error),

    .rd_clk            (video_clk),
    .rd_rst_n          (video_rst_n),
    .sample_tick       (wav_sample_tick),
    .sample_out        (wav_sample_left),
    .sample_valid      (wav_sample_valid),
    .sample_ready      (wav_sample_ready),
    .sample_counter    (wav_sample_counter),
    .stream_active     (wav_stream_active),
    .stream_end        (wav_stream_end),
    .buffer_low        (wav_buffer_low)
);

// 单声道 PCM 左右声道使用同一数据。
assign wav_sample_right = wav_sample_left;

// 转场 alpha -> 音频域增益。只作用于 WAV，保留原切图提示音不受影响。
sync_fade_gain u_sync_fade_gain (
    .pix_clk    (video_clk),
    .pix_rst_n  (video_rst_n),
    .frame_start(frame_start),
    .alpha_pix  (fade_alpha),
    .fade_active(fade_active),
    .aud_clk    (video_clk),
    .aud_rst_n  (video_rst_n),
    .gain_aud   (wav_fade_gain)
);

// 用户音量 200/255 与转场增益一起缩放 WAV。
pcm_volume_fade u_pcm_volume_fade (
    .sample_valid (wav_sample_valid),
    .sample_ready (wav_sample_ready),
    .sample_left  (wav_sample_left),
    .sample_right (wav_sample_right),
    .volume       (audio_volume),
    .fade_gain    (wav_fade_gain),
    .out_valid    (wav_scaled_valid),
    .out_ready    (),
    .out_left     (wav_scaled_left),
    .out_right    (wav_scaled_right)
);

// 保留第四讲已有的媒体琶音音源；WAV 活跃时由 audio_source_mux 抢占。
pcm_media_tone #(
    .CLOCK_HZ  (25_000_000),
    .SAMPLE_HZ (48_000)
) u_pcm_media_tone (
    .clk             (video_clk),
    .rst_n           (video_rst_n),
    .media_id        (media_id),
    .volume          (audio_volume),
    .sample_valid    (arp_sample_valid),
    .sample_ready    (arp_sample_ready),
    .sample_left     (arp_sample_left),
    .sample_right    (arp_sample_right),
    .overflow        (audio_sample_overflow),
    .blip_active     (audio_blip_active)
);

audio_source_mux u_audio_source_mux (
    .clk            (video_clk),
    .rst_n          (video_rst_n),
    .wav_valid      (wav_scaled_valid),
    .wav_ready      (wav_sample_ready),
    .wav_left       (wav_scaled_left),
    .wav_right      (wav_scaled_right),
    .wav_active     (wav_stream_active),
    .arp_valid      (arp_sample_valid),
    .arp_ready      (arp_sample_ready),
    .arp_left       (arp_sample_left),
    .arp_right      (arp_sample_right),
    .force_arpeggio (1'b0),
    .out_valid      (mix_sample_valid),
    .out_ready      (mix_sample_ready),
    .out_left       (mix_sample_left),
    .out_right      (mix_sample_right)
);

hdmi_pcm_source_bridge u_hdmi_pcm_source_bridge (
    .clk            (video_clk),
    .rst_n          (video_rst_n),
    .source_valid   (mix_sample_valid),
    .source_ready   (mix_sample_ready),
    .source_left    (mix_sample_left),
    .source_right   (mix_sample_right),
    .audio_valid    (audio_valid),
    .audio_left     (audio_left_data),
    .audio_right    (audio_right_data),
    .contract_error (audio_contract_error)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_vs          (vs),
    .I_de          (pat_mode ? de : adjusted_de),
    .I_rgb         (wave_rgb_eff),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (~video_rst_n),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    // 第十二讲彩点排查：主线保持 TPG 关闭。实验C 曾临时改为 "Enable"
    // （产物 VinylFPGA_expC_tpg.bit），此处已恢复正式行为。
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (~video_rst_n),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (~video_rst_n),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
