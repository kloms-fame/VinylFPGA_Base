
// ==========================================================================
// S1 拓展板实现（expansion_integration 及其全部子模块）随 top 一起编译：
// 直接在本编译单元内 include，避免 TD 工程文件列表条目缺失/路径失效时把
// expansion_integration 当成 black box。独立源文件仍保留，供 lint 与
// iverilog 单模块仿真使用；每个文件都带模块级包含保护，因此即使 .al 同时
// 单独列出这些文件，也不会重复定义。
// ==========================================================================
`include "io/sync_bit.v"
`include "io/debounce_tick.v"
`include "io/debounce_bank.v"
`include "io/key_dip_monitor.v"
`include "io/quadrature_decoder.v"
`include "io/encoder_monitor.v"
`include "io/ir_nec_decoder.v"
`include "io/expansion_io_hub.v"
`include "io/ui_event_bus.v"
`include "io/ui_command_router.v"
`include "io/ui_ms_tick.v"
`include "io/health_monitor.v"
`include "io/buzzer_feedback.v"
`include "io/expansion_integration.v"
`include "io/ui_event_bridge.v"
`include "io/ui_param_csr.v"
`include "io/ec2_param_controller.v"
`include "io/ec2_event_replay.v"
`include "io/volume_intent_bridge.v"
// X1：状态反馈执行器（LED / WS2812 / 数码管业务 mux）
`include "io/led_business_driver.v"
`include "io/ws2812_driver.v"
`include "io/ws2812_effects.v"
`include "audio/pcm_tap.v"
`include "display/seg_business_mux.v"
`include "io/browse_fsm.v"

// ==========================================================================
// S2 开机 Logo/动画实现（boot_logo_rom + boot_layer）随 top 一起编译，
// 与上面 S1 的兜底方式一致：独立源文件保留给 lint / iverilog，
// 模块级包含保护保证不会重复定义。
// ==========================================================================
`include "boot/boot_logo_rom.v"
`include "boot/boot_layer.v"

// ==========================================================================
// S5 音频播放与歌词渲染实现随 top 一起编译（与 S1/S2 同样的兜底方式）。
// ==========================================================================
`include "audio/timebase_48k.v"
`include "audio/play_ctrl.v"
`include "audio/stream_session.v"
`include "audio/seek_controller.v"
`include "io/cover_navigation.v"
`include "io/slideshow_controller.v"
`include "SD/media_probe.v"
// Keep S4/S5 dependencies visible even if the GUI project list is stale.
`include "SD/song_index_db.v"
`include "display/lrc_lines_rom.v"
`include "display/lrc_font_rom.v"
`include "display/song_text_rom.v"
`include "display/song_font_rom.v"
`include "display/lrc_osd.v"
`include "display/lrc_multisong_osd.v"
`include "display/lrc_window_controller.v"
`include "display/lrc_scroll_controller.v"
`include "display/lrc_five_osd.v"
`include "display/brightness_contrast_steps.v"
`include "display/ascii_font_rom.v"
`include "display/playback_progress.v"
`include "display/playback_page.v"
`include "display/ec2_param_osd.v"
`include "video/mv_sector_mux.v"
`include "video/mv_stream_player.v"
`include "video/mv_frame_scheduler.v"
`include "video/s6_video_layer.v"
`include "SD/media_supervisor.v"

module top(
    input                       clk,
    input                       rst_n,
    input                       key3,           // 母板按键 3（B1），用于操作反馈音
    input                       sw1,            // 母板拨码 SW1（C8），用于操作反馈音
    input                       sw2,            // 母板拨码 SW2（C7）
    input                       sw3,            // 母板拨码 SW3（C6）
    input                       sw4,            // 母板拨码 SW4（C5）

    output [7:0]                seg_sel,
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
    input                       sd_miso,

    // ===================== S1：J2 拓展板（IDC40）输入 =====================
    input  [11:0]               exp_key_n,       // KEY1..KEY12，低有效
    input  [5:0]                exp_dip_n,       // DIP1..DIP6
    input                       exp_enc1_a,      // EC1 A 相
    input                       exp_enc1_b,      // EC1 B 相
    input                       exp_enc1_sw_n,   // EC1 按压，低有效
    input                       exp_enc2_a,      // EC2 A 相
    input                       exp_enc2_b,      // EC2 B 相
    input                       exp_enc2_sw_n,   // EC2 按压，低有效
    input                       exp_ir_rx,       // NEC 红外接收

    // ===================== S1：J2 拓展板输出 =====================
    output [3:0]                exp_led_n,       // LED1..LED4，低有效点亮
    output                      exp_ws2812_data, // WS2812 数据线（S1 静态全灭）
    output [5:0]                exp_ext_o,       // EXT1=反馈音波形，EXT2..EXT6=0

    // ===================== 母板蜂鸣器 =====================
    output                      board_buzzer_n,  // H11，PNP 驱动，低电平鸣叫（SW5 硬件通断）

    // ===================== S1：板载 USB 转串口 =====================
    output                      uart_tx          // 115200 8N1 回显输出
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 24'd2;
parameter BUF3_ADDR     = FRAME_PIXELS * 24'd3;

// 按键/拨码/编码器/红外 操作反馈音总开关：1=开启（母板蜂鸣器 + 拓展板 EXT1），0=静音。
// 母板蜂鸣器还需硬件 SW5 拨至接通档才会发声。
parameter BUZZER_FEEDBACK_ENABLE = 1'b1;

// ===================== S2：开机 Logo/启动画面 =====================
// S2_BOOT_ENABLE=1 时上电进入 STATE_BOOT，先显示片内 Logo 再交给主链路；
// =0 时整层旁路，顶层行为与 S1 完全一致（回滚开关）。
// 图源：doc/资源/VinylFPGA_640x480.jpg，由 tools/gen_boot_logo.py 生成
//      src/boot/boot_logo_rom.v + src/include/boot_logo_geom.vh。
parameter S2_BOOT_ENABLE = 1'b1;
parameter integer BOOT_HOLD_MS = 6000;
parameter integer BOOT_SKIP_MIN_MS = 4000;
parameter integer BOOT_TIMEOUT_MS = 8000;

// ===================== S3：主界面选歌（J2 事件迁移） =====================
// S3_J2_BROWSE_ENABLE=1：EC1 旋转/方向键/EC1 按压/KEY07 事件接入选曲业务；
// 母板 KEY1/KEY2 已撤销；=0 时关闭 J2 选曲事件，仅供隔离诊断。
parameter S3_J2_BROWSE_ENABLE = 1'b1;

// ===================== S5：音频播放与歌词渲染 =====================
// S5_PLAY_ENABLE=1：确认中央封面后进入播放态，音频/歌词只在该状态推进；
//                   EC1 按压暂停/恢复、播放中 EC1 旋转 Seek、KEY04/05 音量。
// =0：整层旁路，音频回到 S0~S4 的"扫描完成即播放"行为（回滚开关）。
parameter S5_PLAY_ENABLE = 1'b1;
parameter S6_VIDEO_ENABLE = 1'b1;
// SDRAM word addresses: covers [0,1228800), MV [1228800,1459200).
localparam [20:0] MV_ADDR0=21'd1228800, MV_ADDR1=21'd1305600, MV_ADDR2=21'd1382400;
wire [63:0] mv_metadata_sd;
wire [63:0] mv_metadata_video;
wire media_preloaded_sd, media_preloaded_vid;
wire mv_visual_tgl, mv_req_tgl, mv_done_tgl, mv_failed;
wire [31:0] mv_request_lba;
wire [1:0] mv_request_bank, mv_write_bank, mv_read_bank;
wire mv_writer_active,mv_write_req,mv_pixel_valid;
wire mv_writer_mem;
wire frw_write_busy;
wire [31:0] mv_pixel_data;
wire mv_sec_req,mv_sec_busy,mv_sec_valid,mv_sec_done;
wire [31:0] mv_sec_lba;
wire media_sec_req,media_sec_busy,media_sec_valid,media_sec_done;
wire [31:0] media_sec_lba;
wire mv_read_active,mv_fifo_read_allowed,mv_window_visible;
wire [23:0] s6_rgb;
reg [1:0] mv_audio_low_sync;
reg [5:0] s6_read_wait;
wire s6_frame_read_req;


wire exp_rst_n; // 50 MHz reset, asynchronous assertion / synchronized release
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
wire        waveform_active;
reg         waveform_enable_frame;
wire        display_valid;
wire [7:0]  osd_error_code;
wire [23:0] media_status_sd; // Slow scan metadata, settled before serial reporting
reg [23:0] media_status_v1, media_status_v2;
wire        osd_error_toggle;
wire        switch_abort_toggle;

// S7-02：媒体故障恢复监督器信号（sd_card_clk 域）
wire        media_sd_rst_n;       // 监督器驱动的 SD 媒体子系统复位（低有效）
wire [7:0]  media_err_code;       // 集中错误码 Err-01..09（sticky）
wire        media_err_toggle;     // 错误码变化翻转标志（跨域捆绑握手）
wire        sd_media_rst_n;       // 合并后的 SD 媒体子系统复位（低有效）

// 第十讲：图片转场控制与像素应用
wire        fade_next_event;
wire        fade_busy;
wire [7:0]  fade_alpha;
wire        fade_active;
wire        wipe_active;
wire [4:0]  wipe_ramp;
wire [1:0]  transition_kind;
wire        frame_start;

// Transition alpha stays at full-scale brightness; image BRI/CON are applied
// in the following registered, frame-snapshotted pixel stage.
wire [7:0] brightness_frame = 8'd255;
wire [23:0] adjusted_rgb;
wire        adjusted_de;
reg  [9:0]  adjusted_pixel_x;
wire        ec2_panel_vs;
wire        ec2_panel_de;
wire [9:0]  ec2_panel_x;
wire [23:0] ec2_panel_rgb;
reg  [7:0]  volume_frame;
reg  [11:0] volume_bcd_frame;
reg  [2:0]  brightness_level_frame;
reg  [2:0]  contrast_level_frame;
reg  [2:0]  rotation_level_frame;
reg  [2:0]  ws_brightness_level_frame;
reg  [1:0]  ec2_state_frame;
reg  [2:0]  ec2_selected_frame;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack_mem;
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

wire        fade_start_event_sd;    // 送 video_fade_transition 的淡出请求

wire        cover_select_req_sd;
wire [1:0]  cover_select_index_sd;
wire        sd_select_ack;

wire [3:0]  image_ready_sd;         // sd_card_clk 域：四个 bank 就绪标记
wire [23:0] view_rgb;               // 播放 MV 遮罩后的像素源

// ===================== S2：开机 Logo/启动画面 =====================
// 事件握手：ui_ev_valid（clk 域单拍）-> 翻转电平 -> video 域同步/边沿检测。
// 状态回读：boot_active（video 域电平）-> 两级同步到 clk 域。
wire        ui_ev_valid;
reg         boot_skip_toggle_clk;
wire        boot_active;
reg  [1:0]  boot_active_clk_sync;
wire [23:0] boot_rgb;
wire [23:0] final_rgb;

// ===================== S3：主界面选歌（事件迁移） =====================
// clk 域：expansion_integration 引出的统一事件 + ui_event_bridge 解码出的四路电平翻转。
wire        ui_event_valid;
wire [3:0]  ui_event_code;
wire [15:0] ui_event_arg;
wire [15:0] ui_event_aux;
wire [15:0] exp_enc2_count_raw;
wire        ui_actions_ready_clk;
wire        restart_confirm_active_clk;
// S7-03：运行时状态 / 使能冻结输出（clk 域）
wire        blank_active;   // 消隐激活（DIP4 自动 + 遥控息屏手动）
wire        led_enable;     // DIP3 LED 总使能（S7-05 接入执行器）
wire        ws_enable;      // DIP6 WS 总使能（S7-05 接入执行器）
wire        restart_req;    // 重启确认后一拍脉冲（软复位请求）
wire        dip2_slideshow_enable_clk;
wire        dip2_slideshow_enable_sd;
wire        slideshow_auto_next_sd;
wire        slideshow_auto_switch_ack_sd;
reg         slideshow_beep_toggle_sd;
wire        slideshow_beep_toggle_clk;
reg         slideshow_beep_toggle_clk_d;
wire        slideshow_beep_event_clk = slideshow_beep_toggle_clk ^ slideshow_beep_toggle_clk_d;
wire        slideshow_enable_sd;
wire        brw_ev_prev_tgl;
wire        brw_ev_next_tgl;
wire        brw_ev_confirm_tgl;
wire        brw_ev_mode_tgl;
wire brw_ev_home_tgl,brw_ev_effect_tgl,brw_ev_end_mode_tgl;
wire brw_play_start,brw_play_stop;
wire [1:0] play_end_mode;
wire play_restart_request,cover_busy,cover_direction;
wire wav_reader_idle,wav_sample_consumed;
wire stream_enable_sd;
reg [1:0] stream_enable_vid;
reg [2:0] eof_sync;
reg [2:0] effect_sync;
reg [1:0] effect_mode;

wire media_video_rst_n;
wire storage_done;
wire [7:0] storage_error;
wire probe_card_req,probe_card_busy,probe_card_valid,probe_card_done;
wire [31:0] probe_card_lba;
wire media_mount_ok = media_status_sd[23] && media_preloaded_sd &&
                     (|image_ready_sd) && media_status_sd[15:0]==16'd0 && osd_error_code==0;
// media_mount_ok 由 image_ready/media_status 等多路状态组合而成；这些状态
// 只在扫描或预加载完成时变化，打一拍用于导航器可切断 100 MHz 组合长路径。
wire play_media_lost = !media_sd_rst_n || media_err_code!=0;
reg media_mount_ok_sd;
reg play_media_lost_sd;
wire ec2_control_enable;
always @(posedge sd_card_clk or negedge sd_media_rst_n) begin
    if (!sd_media_rst_n) begin
        media_mount_ok_sd <= 1'b0;
        play_media_lost_sd <= 1'b1;
    end else begin
        media_mount_ok_sd <= media_mount_ok;
        play_media_lost_sd <= play_media_lost;
    end
end
reg [1:0] media_ready_clk_sync;
always @(posedge clk or negedge exp_rst_n) begin
    if (!exp_rst_n) begin
        media_ready_clk_sync <= 2'b00;
        boot_active_clk_sync <= 2'b11;
    end else begin
        media_ready_clk_sync <= {media_ready_clk_sync[0], media_mount_ok_sd};
        boot_active_clk_sync <= {boot_active_clk_sync[0], boot_active};
    end
end
assign ec2_control_enable = media_ready_clk_sync[1] &&
                            !boot_active_clk_sync[1] && !blank_active &&
                            ui_actions_ready_clk && !restart_confirm_active_clk;

// sd 域：browse_fsm 还原/路由出的控制脉冲。
wire        brw_fs_next;        // 全屏：下一张
wire        brw_fs_prev;        // 全屏：上一张
// S5：播放控制额外事件（clk 域 toggle）
wire        brw_ev_enc_cw_tgl;
wire        brw_ev_enc_ccw_tgl;
wire        brw_ev_key_up_tgl;
wire        brw_ev_key_down_tgl;
// X2：Seek / 重播事件（clk 域翻转电平，seek_controller 内部 3FF 还原）
wire        brw_ev_seek_fwd5_tgl;
wire        brw_ev_seek_bwd5_tgl;
wire        brw_ev_replay_tgl;
wire        brw_ev_seek_fwd2_tgl;
wire        brw_ev_seek_bwd2_tgl;

// ===================== S5：播放态（sd_card_clk 域） =====================
wire        play_active_sd;
wire        paused_sd;
wire [1:0]  play_sel_song_sd;
wire        play_volume_intent_valid_sd;
wire        play_volume_intent_up_sd;
wire        play_track_step_sd;
wire        play_track_dir_sd;
wire [2:0]  song_total_sd;
wire        audio_play_enable_gated;
// X2：Seek 目标与重启握手（sd 域）
wire [31:0] play_seek_target_sd;
wire        play_seek_restart_sd;
wire        play_seek_clear_sd;
reg  [31:0] seek_cur_sample_sd;
// Seek 目标 -> video 域（稳定窗口内 2FF）
reg  [31:0] play_seek_target_v1, play_seek_target_v2;
// 目标样本 -> 目标帧：4800 样本/帧。用低频常量步进累减替代 32x15 乘法，
// 最坏 32 位目标也远小于预缓冲窗口；视频域逐帧推进只使用寄存器路径。
reg  [31:0] seek_frame_rem, seek_frame_target_d;
reg  [19:0] seek_frame_calc_reg;
reg         seek_frame_busy;
wire [31:0] seek_frame_rem_next = seek_frame_rem - 32'd4800;
wire [19:0] seek_frame_calc = seek_frame_calc_reg;
wire [15:0] seek_frame_vid  = (seek_frame_calc > 20'h0FFFF) ? 16'hFFFF :
                              seek_frame_calc[15:0];
// 播放状态位 -> video 域（两级同步）；用户参数与面板状态共享原子快照。
reg         play_active_v1, play_active_v2;
reg         paused_v1, paused_v2;
wire [7:0] play_volume_video;
wire [7:0] play_volume_csr;
wire [2:0] brightness_level_csr;
wire [2:0] contrast_level_csr;
wire [2:0] rotation_level_csr;
wire [2:0] ws_brightness_level_csr;
wire       param_update_csr;
wire [24:0] params_bundle_csr;
wire [24:0] params_bundle_video;
wire [2:0] rotation_level_sd;
wire       ui_tick_1ms;
wire       ec2_step_valid;
wire       ec2_step_up;
wire       ec2_step_ready;
wire       ec2_press_event;
wire       ec2_param_req_valid;
wire [2:0] ec2_param_req_id;
wire       ec2_param_req_up;
wire       ec2_param_req_ready;
wire [2:0] ec2_selected_param;
wire [1:0] ec2_ui_state;
wire       ec2_ui_update;
wire       volume_bridge_src_ready;
wire       volume_bridge_src_overflow;
wire       volume_bridge_dst_valid;
wire       volume_bridge_dst_up;
wire       volume_bridge_dst_ready;
wire       param_csr_wr_valid;
wire [2:0] param_csr_wr_id;
wire       param_csr_wr_up;
wire       volume_bridge_async_rst_n;
wire       volume_bridge_src_rst_n;
wire       volume_bridge_dst_rst_n;
// 切曲 -> video 域时基复位（电平翻转 + 边沿检测）
wire        play_track_tgl_sd;
reg         play_track_tgl_v1, play_track_tgl_v2, play_track_tgl_v3;
wire        play_track_restart_vid = play_track_tgl_v2 ^ play_track_tgl_v3;
wire        play_running_vid = play_active_v2 & ~paused_v2;
wire [31:0] lyric_time_ms;
wire [31:0] lyric_sample_count;

// ==========================================================================
// X1：状态反馈执行器信号
//   X1A：LED1~4 全部在 expansion_integration（clk 域）内部接线；
//   X1B：PCM 包络在视频域产生并跨到 clk 域；KEY10 在 ui_event_bridge 翻转；
//   X1C：数码管业务 mux 与 seg_scan 同在 sd_card_clk 域；SW1 使能经 2FF 同步。
//        数码管固定显示 MM-SS 空白 NN，SW3 不再切换诊断页。
// ==========================================================================
wire [7:0]  x1b_level_vid;          // pcm_tap 包络
wire        x1b_upd_tgl_vid;        // 包络更新翻转（数据已稳定后才翻转）
reg         x1b_upd_tgl_s1, x1b_upd_tgl_s2, x1b_upd_tgl_seen;
reg  [7:0]  pcm_level_clk;          // 包络 clk 域快照
wire        ws_mode_tgl;            // KEY10 全灭/VU 切换（clk 域）
wire [3:0]  board_sw_level_clk;     // 母板 SW1-4 消抖后电平（clk 域）
wire        disp_mode_tgl_clk;      // 母板 KEY3(B1) 翻转电平（clk 域）

// Display controls and sample position stay in sd_card_clk.
reg [1:0] sd_sw1_sync;
wire [3:0] fault_flags_clk;

wire [7:0] seg_biz_0,seg_biz_1,seg_biz_2,seg_biz_3,seg_biz_4,seg_biz_5,seg_biz_6,seg_biz_7;
wire [1:0] display_song_sd = play_active_sd ? play_sel_song_sd : disp_buf_idx;
// Isolate view/focus selection from the indexed cluster/length arithmetic.
// stream_session waits 32 idle cycles before starting a generation, so the
// extra metadata cycle settles before either WAV or MV consumes the result.
reg [1:0] metadata_song_sd;
reg [1:0] metadata_song_update_d;
wire [2:0] song_metadata_src = {play_track_tgl_sd, metadata_song_sd};
reg  [2:0] song_metadata_src_d;
wire       song_metadata_update_sd = (song_metadata_src != song_metadata_src_d);
wire [2:0] song_metadata_video;
reg media_scan_done_update_d, media_preloaded_update_d;
wire mv_metadata_update_sd =
    (metadata_song_sd != metadata_song_update_d) ||
    (media_status_sd[23] && !media_scan_done_update_d) ||
    (media_preloaded_sd && !media_preloaded_update_d);
wire        frw_read_en_gated;

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
wire [31:0] audio_size_bytes;
// X2：本曲真实样本总数（连续 PCM 布局，16 bit 单声道）；末扇区填充字节
// 不再计入时间基、进度和 Seek 范围。
wire [31:0] play_total_samples = {1'b0, audio_size_bytes[31:1]};
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
wire        wav_underrun_pulse;   // S7-01B：音频欠载单拍脉冲（video_clk 域）
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
// S7-02：media_supervisor 错误码 -> video_clk 域同步（数据 2FF + toggle 边沿）
reg [7:0]   media_err_code_sync1;
reg [7:0]   media_err_code_sync2;
reg         media_err_toggle_sync1;
reg         media_err_toggle_sync2;
reg         media_err_toggle_seen;
reg         media_err_update_pending;
reg [7:0]   media_err_code_frame;
// S7-01B：错误码/欠载/低水位/流式/MV失败 -> clk 域的同步链
reg [7:0]   osd_error_code_c1;
reg [7:0]   osd_error_code_c2;
reg         osd_error_toggle_c1;
reg         osd_error_toggle_c2;
reg         osd_error_toggle_cseen;
reg         osd_err_valid_clk;
reg [7:0]   osd_err_code_clk;
// S7-02：media_supervisor 错误码 -> clk 域同步（数据 2FF + toggle 边沿）
reg [7:0]   media_err_code_c1;
reg [7:0]   media_err_code_c2;
reg         media_err_toggle_c1;
reg         media_err_toggle_c2;
reg         media_err_toggle_cseen;
reg         media_err_valid_clk;
reg [7:0]   media_err_code_clk;
reg         underrun_tgl;          // video_clk 域：欠载脉冲转电平翻转
reg         underrun_tgl_c1;
reg         underrun_tgl_c2;
reg         wav_buffer_low_c1;
reg         wav_buffer_low_c2;
reg         wav_stream_active_c1;
reg         wav_stream_active_c2;
reg         mv_failed_c1;
reg         mv_failed_c2;
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

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) metadata_song_sd <= 2'd0;
    else metadata_song_sd <= display_song_sd;
end
always @(posedge sd_card_clk or negedge sd_media_rst_n) begin
    if (!sd_media_rst_n) begin
        metadata_song_update_d <= 2'd0;
        media_scan_done_update_d <= 1'b0;
        media_preloaded_update_d <= 1'b0;
    end else begin
        metadata_song_update_d <= metadata_song_sd;
        media_scan_done_update_d <= media_status_sd[23];
        media_preloaded_update_d <= media_preloaded_sd;
    end
end

// S7-03：重启确认软复位（clk 域）。restart_req 触发拉低 soft_rst_n 一段时间，
// 经 ext_rst_n 异步断言、各域 reset_sync 同步释放；计数器用外部 rst_n 复位，
// 避免被自身触发的域复位卡死在低电平。640 ns（32 拍 @ 50 MHz）已足够最慢
// video_clk 域完成异步断言 + 两级同步释放，用 5 位计数器替代 16 位长计数器。
localparam integer SOFT_RST_CYCLES = 32; // 640 ns @ 50 MHz
localparam integer SOFT_RST_W      = $clog2(SOFT_RST_CYCLES);
reg soft_rst_n;
reg [SOFT_RST_W-1:0] soft_rst_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        soft_rst_n   <= 1'b1;
        soft_rst_cnt <= {SOFT_RST_W{1'b0}};
    end else if (restart_req) begin
        soft_rst_n   <= 1'b0;
        soft_rst_cnt <= {SOFT_RST_W{1'b0}};
    end else if (!soft_rst_n) begin
        if (soft_rst_cnt >= (SOFT_RST_CYCLES - 1))
            soft_rst_n <= 1'b1;
        else
            soft_rst_cnt <= soft_rst_cnt + 1'b1;
    end
end

assign ext_rst_n = rst_n & sys_pll_lock & video_pll_lock & soft_rst_n;
// S7-02：媒体监督器复位与域复位合并，仅复位 SD 媒体子系统（sd_card_bmp/sd_card_top）。
assign sd_media_rst_n = sdcard_rst_n & media_sd_rst_n;
// SD->video metadata is a bundled payload: hold the selected 64-bit record in
// the source domain until the pixel domain captures and acknowledges it.
cdc_bundle_latest #(.WIDTH(64)) u_mv_metadata_cdc(
    .src_clk(sd_card_clk),.src_rst_n(sd_media_rst_n),.src_data(mv_metadata_sd),.src_update(mv_metadata_update_sd),
    .dst_clk(video_clk),.dst_rst_n(media_video_rst_n),.dst_data(mv_metadata_video));

// D9: atomically transfer the selected song and playback generation. The
// video domain samples the bundle at frame start alongside its local audio time.
always @(posedge sd_card_clk or negedge sd_media_rst_n) begin
    if (!sd_media_rst_n)
        song_metadata_src_d <= 3'd0;
    else
        song_metadata_src_d <= song_metadata_src;
end
cdc_bundle_latest #(.WIDTH(3)) u_song_metadata_cdc(
    .src_clk(sd_card_clk),.src_rst_n(sd_media_rst_n),.src_data(song_metadata_src),
    .src_update(song_metadata_update_sd),.dst_clk(video_clk),
    .dst_rst_n(media_video_rst_n),.dst_data(song_metadata_video));
// One parameter CSR lives in the 50 MHz UI domain. PLAY-domain volume intents
// return through the existing FIFO; FIFO traffic wins over a simultaneous EC2 write.
assign volume_bridge_async_rst_n = exp_rst_n;
reset_sync u_volume_bridge_src_reset(
    .clk(sd_card_clk), .ext_rst_n(volume_bridge_async_rst_n),
    .rst_n_sync(volume_bridge_src_rst_n));
reset_sync u_volume_bridge_dst_reset(
    .clk(clk), .ext_rst_n(volume_bridge_async_rst_n),
    .rst_n_sync(volume_bridge_dst_rst_n));

volume_intent_bridge u_volume_intent_bridge(
    .src_clk(sd_card_clk), .src_rst_n(volume_bridge_src_rst_n),
    .src_valid(play_volume_intent_valid_sd), .src_up(play_volume_intent_up_sd),
    .src_ready(volume_bridge_src_ready), .src_overflow(volume_bridge_src_overflow),
    .dst_clk(clk), .dst_rst_n(volume_bridge_dst_rst_n),
    .dst_valid(volume_bridge_dst_valid), .dst_up(volume_bridge_dst_up),
    .dst_ready(volume_bridge_dst_ready));

assign volume_bridge_dst_ready = volume_bridge_dst_valid;
assign ec2_param_req_ready = !volume_bridge_dst_valid;
assign param_csr_wr_valid = volume_bridge_dst_valid || ec2_param_req_valid;
assign param_csr_wr_id = volume_bridge_dst_valid ? 3'd0 : ec2_param_req_id;
assign param_csr_wr_up = volume_bridge_dst_valid ? volume_bridge_dst_up
                                                 : ec2_param_req_up;

ui_param_csr u_ui_param_csr(
    .clk(clk), .rst_n(exp_rst_n),
    .wr_valid(param_csr_wr_valid), .wr_id(param_csr_wr_id), .wr_up(param_csr_wr_up),
    .volume(play_volume_csr), .brightness_level(brightness_level_csr),
    .contrast_level(contrast_level_csr), .rotation_level(rotation_level_csr),
    .ws_level(ws_brightness_level_csr),
    .param_update(param_update_csr));

// Atomic video snapshot: {ui_state, selection, WSL, ROT, CON, BRI, VOL}.
assign params_bundle_csr = {ec2_ui_state, ec2_selected_param, ws_brightness_level_csr,
                            rotation_level_csr, contrast_level_csr,
                            brightness_level_csr, play_volume_csr};
assign play_volume_video = params_bundle_video[7:0];
cdc_bundle_latest #(.WIDTH(25)) u_ui_params_cdc(
    .src_clk(clk), .src_rst_n(exp_rst_n), .src_data(params_bundle_csr),
    .src_update(param_update_csr | ec2_ui_update), .dst_clk(video_clk),
    .dst_rst_n(media_video_rst_n), .dst_data(params_bundle_video));

// ROT has its own reliable latest-value bridge into the 100 MHz scheduler.
cdc_bundle_latest #(.WIDTH(3)) u_rotation_param_cdc(
    .src_clk(clk), .src_rst_n(exp_rst_n), .src_data(rotation_level_csr),
    .src_update(param_update_csr), .dst_clk(sd_card_clk),
    .dst_rst_n(sd_media_rst_n), .dst_data(rotation_level_sd));

function [11:0] volume_to_bcd;
    input [7:0] value;
    reg [11:0] bcd;
    integer bit_idx;
    begin
        bcd = 12'd0;
        for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            if (bcd[3:0] >= 4'd5)   bcd[3:0]   = bcd[3:0]   + 4'd3;
            if (bcd[7:4] >= 4'd5)   bcd[7:4]   = bcd[7:4]   + 4'd3;
            if (bcd[11:8] >= 4'd5)  bcd[11:8]  = bcd[11:8]  + 4'd3;
            bcd = {bcd[10:0], value[bit_idx]};
        end
        volume_to_bcd = bcd;
    end
endfunction

// Pixel parameters and overlay controls change together only at frame_start.
always @(posedge video_clk or negedge media_video_rst_n) begin
    if (!media_video_rst_n) begin
        volume_frame          <= 8'd200;
        volume_bcd_frame      <= 12'h200;
        brightness_level_frame<= 3'd3;
        contrast_level_frame  <= 3'd2;
        rotation_level_frame  <= 3'd2;
        ws_brightness_level_frame <= 3'd4;
        ec2_state_frame       <= 2'd0;
        ec2_selected_frame    <= 3'd0;
    end else if (frame_start) begin
        volume_frame           <= params_bundle_video[7:0];
        volume_bcd_frame       <= volume_to_bcd(params_bundle_video[7:0]);
        brightness_level_frame <= params_bundle_video[10:8];
        contrast_level_frame   <= params_bundle_video[13:11];
        rotation_level_frame   <= params_bundle_video[16:14];
        ws_brightness_level_frame <= params_bundle_video[19:17];
        ec2_selected_frame     <= params_bundle_video[22:20];
        ec2_state_frame        <= params_bundle_video[24:23];
    end
end
reset_sync u_media_video_reset(.clk(video_clk),
 .ext_rst_n(video_rst_n & media_sd_rst_n),.rst_n_sync(media_video_rst_n));
always @(posedge video_clk or negedge media_video_rst_n) begin
 if(!media_video_rst_n) stream_enable_vid<=0;
 else stream_enable_vid<={stream_enable_vid[0],stream_enable_sd};
end
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
 if(!sdcard_rst_n) begin eof_sync<=0; effect_sync<=0; effect_mode<=0; end
 else begin
  eof_sync<={eof_sync[1:0],wav_stream_end};
  effect_sync<={effect_sync[1:0],brw_ev_effect_tgl};
  if(effect_sync[2]^effect_sync[1]) effect_mode<=(effect_mode==2)?0:effect_mode+1'b1;
 end
end

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
wire [23:0] wave_rgb_eff      = pat_mode ? osd_rgb_eff : osd_rgb_out;

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
    .rst               (~sd_media_rst_n),
    .sdr_init_done     (Sdr_init_done_sd),
    // 切图统一经过转场控制器与 select_req 握手。
    .next_event        (1'b0),
    .prev_event        (1'b0),
    .select_req        (cover_select_req_sd),
    .select_index      (cover_select_index_sd),
    .select_ack        (sd_select_ack),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .song_sel          (metadata_song_sd),
    .display_valid     (display_valid),
    .storage_done      (storage_done),
    .storage_error     (storage_error),
    .media_status      (media_status_sd),
    .osd_error_code    (osd_error_code),
    .osd_error_toggle  (osd_error_toggle),
    .switch_abort_toggle(switch_abort_toggle),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .image_ready_out   (image_ready_sd),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack_sync[1] && !mv_writer_active),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .mv_metadata       (mv_metadata_sd),
    .media_preloaded    (media_preloaded_sd),
    .audio_file_valid  (audio_file_valid),
    .audio_start_lba   (audio_start_lba),
    .audio_total_sectors(audio_total_sectors),
    .audio_size_bytes  (audio_size_bytes),
    .audio_play_enable (audio_play_enable),
    .audio_sec_req     (probe_card_req),
    .audio_sec_lba     (probe_card_lba),
    .audio_sec_busy    (probe_card_busy),
    .audio_sec_valid   (probe_card_valid),
    .audio_sec_byte    (wav_sec_byte),
    .audio_sec_byte_index(wav_sec_byte_index),
    .audio_sec_done    (probe_card_done),
    .audio_sec_error   (wav_sec_error)
);

media_probe u_media_probe(
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),.ready(media_mount_ok_sd),
 .client_req(media_sec_req),.client_lba(media_sec_lba),
 .client_busy(media_sec_busy),.client_valid(media_sec_valid),.client_done(media_sec_done),
 .card_req(probe_card_req),.card_lba(probe_card_lba),
 .card_busy(probe_card_busy),.card_valid(probe_card_valid),.card_done(probe_card_done));
// ===================== S7-02：媒体故障恢复监督器 =====================
// Validated media lifecycle; every storage client participates in reset/recovery.
media_supervisor #(
    .CLK_FREQ_HZ         (100_000_000),
    // Mount success includes all four cover banks. Allow initialization/FAT
    // walks and slow-card preload; per-sector failure still times out at 250 ms.
    .MOUNT_TIMEOUT_MS    (15000),
    .MOUNT_RETRY_MAX     (3),
    .REMOUNT_COOLDOWN_MS (3000),
    .RESET_PULSE_CYCLES  (100)
) u_media_supervisor (
    .clk            (sd_card_clk),
    .rst_n          (sdcard_rst_n),
    .media_ready    (media_mount_ok_sd),
    .mount_error    (osd_error_code),
    .sector_error   (storage_error),
    .sector_done    (storage_done),
    .sector_busy    (media_sec_busy),
    .sd_rst_n       (media_sd_rst_n),
    .media_err_code (media_err_code),
    .media_err_toggle(media_err_toggle)
);

// S5：可播放曲目数 = 已就绪 bank 数（索引模式下等于索引曲目数）
assign song_total_sd = {2'b0, image_ready_sd[0]} + {2'b0, image_ready_sd[1]} +
                       {2'b0, image_ready_sd[2]} + {2'b0, image_ready_sd[3]};

// S5：播放态控制（sd_card_clk 域，与选曲/取数同域，事件侧沿用 3FF 同步）
play_ctrl u_play_ctrl (
    .clk           (sd_card_clk),
    .rst_n         (sdcard_rst_n),
    .song_total    (song_total_sd),
    .song_confirm  (brw_play_start && media_mount_ok_sd && !cover_busy),
    .focus_index   (disp_buf_idx),
    .enc_cw_tgl    (brw_ev_enc_cw_tgl),
    .enc_ccw_tgl   (brw_ev_enc_ccw_tgl),
    .confirm_tgl   (brw_ev_confirm_tgl),
    .key_up_tgl    (brw_ev_key_up_tgl),
    .key_down_tgl  (brw_ev_key_down_tgl),
    .stop_tgl      (1'b0),
    .stop_request  (brw_play_stop),
    .media_lost    (play_media_lost_sd),
    .stream_end    (eof_sync[2] && stream_enable_sd),
    .end_mode_tgl  (brw_ev_end_mode_tgl),
    .end_mode      (play_end_mode),
    .restart_request(play_restart_request),
    .play_active   (play_active_sd),
    .paused        (paused_sd),
    .sel_song      (play_sel_song_sd),
    .volume_intent_valid(play_volume_intent_valid_sd),
    .volume_intent_up   (play_volume_intent_up_sd),
    .track_step    (play_track_step_sd),
    .track_dir     (play_track_dir_sd),
    .seek_restart_in (play_seek_restart_sd),
    .seek_clear    (play_seek_clear_sd)
);

// ==========================================================================
// X2：Seek / 重播控制器（sd 域）。只算目标样本位置并请求重启事务，
// 真正的"停发新请求 / 等在途 / 清 FIFO / 预缓冲"仍由 stream_session 完成。
// ==========================================================================
seek_controller u_seek_controller (
    .clk            (sd_card_clk),
    .rst_n          (sdcard_rst_n),
    .play_active    (play_active_sd),
    .cur_sample     (seek_cur_sample_sd),
    .total_samples  (play_total_samples),
    .clear_pulse    (play_seek_clear_sd),
    .seek_fwd5_tgl  (brw_ev_seek_fwd5_tgl),
    .seek_bwd5_tgl  (brw_ev_seek_bwd5_tgl),
    .seek_fwd2_tgl  (brw_ev_seek_fwd2_tgl),
    .seek_bwd2_tgl  (brw_ev_seek_bwd2_tgl),
    .replay_tgl     (brw_ev_replay_tgl),
    .target_sample  (play_seek_target_sd),
    .restart_req    (play_seek_restart_sd)
);

// 读侧样本位置 wav_sample_counter（video_clk）-> sd 域：
// 每个被真实消费的 PCM 样本只翻转一次电平，sd 域 3FF 后还原单拍递增。
// 不再跨域搬运 32 位格雷码并在 100 MHz 域做 32 级 XOR 解码；32 位影子
// 计数只在 sd 域做窄加法，既保持单比特 CDC，也把 Seek 基准路径缩短。
reg         wav_consumed_tgl_vid;
reg         wav_consumed_tgl_sd1, wav_consumed_tgl_sd2, wav_consumed_tgl_sd3;
wire        seek_sample_step_sd = stream_enable_sd &&
                                  (wav_consumed_tgl_sd2 ^ wav_consumed_tgl_sd3);
reg         seek_restart_sd_d;
reg  [31:0] seek_target_sd_d;

always @(posedge video_clk or negedge media_video_rst_n) begin
    if (!media_video_rst_n)
        wav_consumed_tgl_vid <= 1'b0;
    else if (!stream_enable_vid[1])
        wav_consumed_tgl_vid <= 1'b0;
    else if (wav_sample_consumed)
        wav_consumed_tgl_vid <= ~wav_consumed_tgl_vid;
end

always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        wav_consumed_tgl_sd1 <= 1'b0;
        wav_consumed_tgl_sd2 <= 1'b0;
        wav_consumed_tgl_sd3 <= 1'b0;
    end else begin
        wav_consumed_tgl_sd1 <= wav_consumed_tgl_vid;
        wav_consumed_tgl_sd2 <= wav_consumed_tgl_sd1;
        wav_consumed_tgl_sd3 <= wav_consumed_tgl_sd2;
    end
end

// Seek 重启脉冲后一拍，把影子位置对齐到最终目标；之后只按真实样本消费递增。
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        seek_cur_sample_sd <= 32'd0;
        seek_restart_sd_d  <= 1'b0;
        seek_target_sd_d   <= 32'd0;
    end else begin
        seek_restart_sd_d <= play_seek_restart_sd;
        seek_target_sd_d  <= play_seek_target_sd;
        if (play_seek_clear_sd) begin
            seek_cur_sample_sd <= 32'd0;
        end else if (seek_restart_sd_d) begin
            seek_cur_sample_sd <= seek_target_sd_d;
        end else if (seek_sample_step_sd && (play_total_samples != 32'd0) &&
                     (seek_cur_sample_sd < play_total_samples)) begin
            seek_cur_sample_sd <= seek_cur_sample_sd + 32'd1;
        end
    end
end

// Seek 目标 sd -> video（目标在整段停流窗口内保持稳定，2FF 足够）。
always @(posedge video_clk or negedge media_video_rst_n) begin
    if (!media_video_rst_n) begin
        play_seek_target_v1 <= 32'd0;
        play_seek_target_v2 <= 32'd0;
    end else begin
        play_seek_target_v1 <= play_seek_target_sd;
        play_seek_target_v2 <= play_seek_target_v1;
    end
end

// 目标样本 / 4800 的串行定位器。seek 事务期间目标保持不变；每个视频时钟
// 做一次常量减法，完成后把帧号交给 MV 调度器。
always @(posedge video_clk or negedge media_video_rst_n) begin
    if (!media_video_rst_n) begin
        seek_frame_rem       <= 32'd0;
        seek_frame_target_d  <= 32'd0;
        seek_frame_calc_reg  <= 20'd0;
        seek_frame_busy      <= 1'b0;
    end else if (play_seek_target_v2 != seek_frame_target_d) begin
        seek_frame_target_d <= play_seek_target_v2;
        seek_frame_rem      <= play_seek_target_v2;
        seek_frame_calc_reg <= 20'd0;
        seek_frame_busy     <= (play_seek_target_v2 >= 32'd4800);
    end else if (seek_frame_busy) begin
        if (seek_frame_rem >= 32'd4800) begin
            seek_frame_rem      <= seek_frame_rem_next;
            seek_frame_calc_reg <= seek_frame_calc_reg + 1'b1;
        end else begin
            seek_frame_busy <= 1'b0;
        end
    end
end

// S5：播放态切曲复用既有"下一张/上一张"通路（browse_fsm 在播放态被抑制）
wire play_fs_next_sd = play_track_step_sd &  play_track_dir_sd;
wire play_fs_prev_sd = play_track_step_sd & ~play_track_dir_sd;

// Restart transaction: drain clients and acknowledge read-side pointer reset.
stream_session u_stream_session(
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),
 .requested(audio_play_enable && play_active_sd && media_mount_ok_sd && !cover_busy),
 .restart(play_restart_request),.storage_busy(wav_sec_busy),
 .video_busy(mv_writer_active),.reader_idle(wav_reader_idle),
 .enable(stream_enable_sd),.start_toggle(play_track_tgl_sd));
assign audio_play_enable_gated = S5_PLAY_ENABLE ? stream_enable_sd : audio_play_enable;

// 中央大图的下一张来自 J2 浏览事件或播放结束策略。

// S3：选曲事件适配层（sd_card_clk 域）。事件侧(clk 域 toggle)在此同步/边沿还原，
// 方向事件始终浏览中央大图；KEY7/KEY11 在播放态均返回选曲页。
browse_fsm #(
    .J2_BROWSE_ENABLE (S3_J2_BROWSE_ENABLE)
) u_browse_fsm (
    .clk             (sd_card_clk),
    .rst_n           (sdcard_rst_n),
    .ev_prev_tgl     (brw_ev_prev_tgl),
    .ev_next_tgl     (brw_ev_next_tgl),
    .ev_confirm_tgl  (brw_ev_confirm_tgl),
    .ev_mode_tgl     (brw_ev_mode_tgl),
    .ev_home_tgl     (brw_ev_home_tgl),
    .play_start      (brw_play_start),
    .play_stop       (brw_play_stop),
    .mode_play       (play_active_sd),
    .fs_next         (brw_fs_next),
    .fs_prev         (brw_fs_prev)
);


// Accumulate desired bank while a previous transition is in flight.
wire key_prev_request_sd = brw_fs_prev | play_fs_prev_sd;
sync_2ff u_slideshow_dip2_sync (
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),
 .async_in(dip2_slideshow_enable_clk),.sync_out(dip2_slideshow_enable_sd));
assign slideshow_enable_sd = dip2_slideshow_enable_sd && media_mount_ok_sd &&
                             display_valid && !play_active_sd &&
                             (song_total_sd > 3'd1);
slideshow_controller #(
 .CLK_FREQ_HZ(100_000_000)
) u_slideshow_controller (
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),.enable(slideshow_enable_sd),
 .busy(cover_busy),
 .manual_action(brw_fs_next || brw_fs_prev),
 .period_level(rotation_level_sd),
 .auto_next(slideshow_auto_next_sd));

 cover_navigation u_cover_navigation(
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),.ready(media_mount_ok_sd),
 .count(song_total_sd),.displayed(disp_buf_idx),
 .next_step(brw_fs_next),.prev_step(brw_fs_prev),.auto_next(slideshow_auto_next_sd),
 .choose(play_track_step_sd),
 .chosen(play_sel_song_sd),
 .chosen_direction(play_track_dir_sd),
 .transition_busy(fade_busy),.transition_commit(fade_next_event),.select_ack(sd_select_ack),
 .transition_start(fade_start_event_sd),.direction(cover_direction),
 .select_req(cover_select_req_sd),.select_index(cover_select_index_sd),.busy(cover_busy),
 .auto_switch_ack(slideshow_auto_switch_ack_sd));

// Keep the event toggle across media-only resets so a reset transition cannot sound like a switch.
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)
        slideshow_beep_toggle_sd <= 1'b0;
    else if (slideshow_auto_switch_ack_sd)
        slideshow_beep_toggle_sd <= ~slideshow_beep_toggle_sd;
end

sync_2ff u_slideshow_beep_event_sync (
    .clk(clk), .rst_n(exp_rst_n),
    .async_in(slideshow_beep_toggle_sd), .sync_out(slideshow_beep_toggle_clk)
);
always @(posedge clk or negedge exp_rst_n) begin
    if (!exp_rst_n)
        slideshow_beep_toggle_clk_d <= 1'b0;
    else
        slideshow_beep_toggle_clk_d <= slideshow_beep_toggle_clk;
end
video_fade_transition #(
    .FADE_FRAMES (8)
) u_video_fade_transition (
    .ctrl_clk        (sd_card_clk),
    .ctrl_rst_n      (sd_media_rst_n),
    .next_event_in   (fade_start_event_sd),
    .direction_in    (cover_direction),
    .effect_mode     (effect_mode),
    .next_event_out  (fade_next_event),
    .fade_busy       (fade_busy),

    .pix_clk         (video_clk),
    .pix_rst_n       (media_video_rst_n),
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
// ==========================================================================
// MM-SS blank NN: the blank digit is unlit, not an ampersand glyph.
// Pair the track number with the metadata pipeline producing its duration.
// Eight digits: browsing shows the focused song duration, PLAY shows consumed
// sample position. Pause/Seek/replay/EOF all share the transport timeline.
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
 if(!sdcard_rst_n) sd_sw1_sync<=0;
 else sd_sw1_sync<={sd_sw1_sync[0],board_sw_level_clk[0]};
end
seg_business_mux u_seg_business_mux(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),.display_enable(sd_sw1_sync[1]),
 .sample_position(audio_file_valid ?
                  (play_active_sd ? seek_cur_sample_sd : play_total_samples) : 32'd0),
 .song_index(metadata_song_sd),
 .seg_data_0(seg_biz_0),.seg_data_1(seg_biz_1),.seg_data_2(seg_biz_2),.seg_data_3(seg_biz_3),
 .seg_data_4(seg_biz_4),.seg_data_5(seg_biz_5),.seg_data_6(seg_biz_6),.seg_data_7(seg_biz_7));
seg_scan #(.CLK_FREQ(100_000_000)) seg_scan_m0(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),.seg_sel(seg_sel),.seg_data(seg_data),
 .seg_data_0(seg_biz_0),.seg_data_1(seg_biz_1),.seg_data_2(seg_biz_2),.seg_data_3(seg_biz_3),
 .seg_data_4(seg_biz_4),.seg_data_5(seg_biz_5),.seg_data_6(seg_biz_6),.seg_data_7(seg_biz_7));

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

// 播放页波形可见性在帧边界提交，避免画面叠加状态半帧变化。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        waveform_enable_frame <= 1'b0;
    end else begin
        if (frame_start) begin
            // Commit visibility with the view, including cached bars/baseline.
            waveform_enable_frame <= audio_play_enable_sync2 &&
                                     play_active_v2;
        end
    end
end

// 实验B 切断 SDRAM 帧读；诊断D 在自检图案落盘前也不发帧读请求。
assign video_read_req_eff = (`DIAG_LOCAL_PATTERN) ? 1'b0
                          : (pat_read_gate_req ? 1'b0
                           : s6_frame_read_req);

// frame_read_write is the sole SDRAM read client; retain its request ACK CDC for
// the video layer's request handshake.
sync_2ff u_video_read_ack_sync(
    .clk(video_clk),.rst_n(video_rst_n),.async_in(video_read_req_ack_mem),
    .sync_out(video_read_req_ack));

assign frw_read_en_gated = video_read_en & mv_fifo_read_allowed;

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

// MV 未覆盖的像素显示中央封面；保持像素和 HDMI 时序链不变。
assign view_rgb = (mv_read_active && !mv_window_visible) ? 24'd0 : vout_data;

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
    .wipe_reverse(transition_kind[0]),
    .wipe_ramp   (wipe_ramp),
    .pixel_x     (osd_pixel_x),
    .rgb_out     (transition_rgb)
);

// D4/D5: integer shift-add levels, one pixel register, saturating channels.
brightness_contrast_steps u_brightness_contrast_steps (
    .clk              (video_clk),
    .rst_n            (video_rst_n),
    .in_de            (de),
    .rgb_in           (transition_rgb),
    .brightness_level (brightness_level_frame),
    .contrast_level   (contrast_level_frame),
    .out_de           (adjusted_de),
    .rgb_out          (adjusted_rgb)
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

// Retain the startup error background; the three debug text rows are retired.
assign osd_rgb_out = (!display_valid_sync2 && media_err_code_frame != 0) ? 24'h201018 : adjusted_rgb;




frame_read_write #(
    .DYNAMIC_LINEAR   (1),
    .EXTERNAL_READ_BUSY(0),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .linear_write      (mv_writer_active),
    .external_read_busy(1'b0),
    .app_write_busy    (frw_write_busy),
    .mem_clk           (ext_mem_clk),
    .rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    // 中央封面/MV 共用 frame_read_write 顺序读口，直接连接 SDRAM。
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req_eff),
    .read_req_ack      (video_read_req_ack_mem),
    .read_finish       (),
    .read_addr_0       (mv_read_active ? MV_ADDR0 : BUF0_ADDR),
    .read_addr_1       (mv_read_active ? MV_ADDR1 : BUF1_ADDR),
    .read_addr_2       (mv_read_active ? MV_ADDR2 : BUF2_ADDR),
    .read_addr_3       (mv_read_active ? MV_ADDR0 : BUF3_ADDR),
    .read_addr_index   (mv_read_active ? mv_read_bank : disp_buf_idx_eff),
    .read_len          (mv_read_active ? 24'd76800 : FRAME_PIXELS),
    .read_en           (frw_read_en_gated),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (mv_writer_active ? mv_write_req : sd_write_req_eff),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (mv_writer_mem ? MV_ADDR0 : BUF0_ADDR),
    .write_addr_1      (mv_writer_mem ? MV_ADDR1 : BUF1_ADDR),
    .write_addr_2      (mv_writer_mem ? MV_ADDR2 : BUF2_ADDR),
    .write_addr_3      (mv_writer_mem ? MV_ADDR0 : BUF3_ADDR),
    .write_addr_index  (mv_writer_active ? mv_write_bank : write_buf_idx_eff),
    .write_len         (mv_writer_active ? 24'd76800 : FRAME_PIXELS),
    .write_en          (mv_writer_active ? mv_pixel_valid : sd_write_en_eff),
    .write_data        (mv_writer_active ? mv_pixel_data : sd_write_data_eff)
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
        media_err_code_sync1   <= 8'd0;
        media_err_code_sync2   <= 8'd0;
        media_err_toggle_sync1 <= 1'b0;
        media_err_toggle_sync2 <= 1'b0;
        media_err_toggle_seen  <= 1'b0;
        media_err_update_pending <= 1'b0;
        media_err_code_frame   <= 8'd0;
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
        vs_q                   <= vs;
        index_commit_pulse     <= 1'b0;
        switch_abort_sync      <= {switch_abort_sync[1:0], switch_abort_toggle};

        // error_code 是低频8位状态，用toggle作为捆绑数据更新标志。
        // 等待toggle同步完成后的下一拍再提交数据，避免多位同时变化时
        // 视频域采到中间值。


        // S7-02：media_supervisor 错误码同步到 video 域，供最小屏幕状态提示。
        media_err_code_sync1   <= media_err_code;
        media_err_code_sync2   <= media_err_code_sync1;
        media_err_toggle_sync1 <= media_err_toggle;
        media_err_toggle_sync2 <= media_err_toggle_sync1;
        if (media_err_toggle_sync2 != media_err_toggle_seen) begin
            media_err_toggle_seen   <= media_err_toggle_sync2;
            media_err_update_pending <= 1'b1;
        end else if (media_err_update_pending) begin
            media_err_code_frame    <= media_err_code_sync2;
            media_err_update_pending <= 1'b0;
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

// Scan diagnostics are quasi-static; video consumes single-bit status flags.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        media_status_v1 <= 24'd0;
        media_status_v2 <= 24'd0;
    end else begin
        media_status_v1 <= media_status_sd;
        media_status_v2 <= media_status_v1;
    end
end

// ===================== S7-01B：遥测信号跨域同步 =====================
// 音频欠载是 video_clk 域的单拍脉冲，转成电平翻转再跨到 clk 域边沿还原；
// 缓冲低水位/流式状态/MV 失败是慢变电平，直接两级同步；
// osd_error_code 是低频 8 位数据，复用其 toggle 作为捆绑更新标志。
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        underrun_tgl <= 1'b0;
    else if (wav_underrun_pulse)
        underrun_tgl <= ~underrun_tgl;
end

always @(posedge clk or negedge exp_rst_n) begin
    if (!exp_rst_n) begin
        underrun_tgl_c1      <= 1'b0;
        underrun_tgl_c2      <= 1'b0;
        wav_buffer_low_c1    <= 1'b0;
        wav_buffer_low_c2    <= 1'b0;
        wav_stream_active_c1 <= 1'b0;
        wav_stream_active_c2 <= 1'b0;
        mv_failed_c1         <= 1'b0;
        mv_failed_c2         <= 1'b0;
        osd_error_code_c1    <= 8'd0;
        osd_error_code_c2    <= 8'd0;
        osd_error_toggle_c1  <= 1'b0;
        osd_error_toggle_c2  <= 1'b0;
        osd_error_toggle_cseen <= 1'b0;
        osd_err_valid_clk    <= 1'b0;
        osd_err_code_clk     <= 8'd0;
        media_err_code_c1    <= 8'd0;
        media_err_code_c2    <= 8'd0;
        media_err_toggle_c1  <= 1'b0;
        media_err_toggle_c2  <= 1'b0;
        media_err_toggle_cseen <= 1'b0;
        media_err_valid_clk  <= 1'b0;
        media_err_code_clk   <= 8'd0;
    end else begin
        underrun_tgl_c1      <= underrun_tgl;
        underrun_tgl_c2      <= underrun_tgl_c1;
        wav_buffer_low_c1    <= wav_buffer_low;
        wav_buffer_low_c2    <= wav_buffer_low_c1;
        wav_stream_active_c1 <= wav_stream_active;
        wav_stream_active_c2 <= wav_stream_active_c1;
        mv_failed_c1         <= mv_failed;
        mv_failed_c2         <= mv_failed_c1;
        osd_error_code_c1    <= osd_error_code;
        osd_error_code_c2    <= osd_error_code_c1;
        osd_error_toggle_c1  <= osd_error_toggle;
        osd_error_toggle_c2  <= osd_error_toggle_c1;
        osd_err_valid_clk    <= 1'b0;
        if (osd_error_toggle_c2 != osd_error_toggle_cseen) begin
            osd_error_toggle_cseen <= osd_error_toggle_c2;
            osd_err_valid_clk      <= 1'b1;
            osd_err_code_clk       <= osd_error_code_c2;
        end
        media_err_code_c1    <= media_err_code;
        media_err_code_c2    <= media_err_code_c1;
        media_err_toggle_c1  <= media_err_toggle;
        media_err_toggle_c2  <= media_err_toggle_c1;
        media_err_valid_clk  <= 1'b0;
        if (media_err_toggle_c2 != media_err_toggle_cseen) begin
            media_err_toggle_cseen <= media_err_toggle_c2;
            media_err_valid_clk    <= 1'b1;
            media_err_code_clk     <= media_err_code_c2;
        end
    end
end

wire underrun_pulse_clk = underrun_tgl_c1 ^ underrun_tgl_c2;

// S7-02：合并媒体错误与既有 OSD 错误，集中错误码优先，交给 health_monitor 上报。
wire        merged_err_valid = media_err_valid_clk;
// 集中错误码优先：媒体错误脉冲当拍抢占；其余时刻保留 OSD/FAT 错误，
// 避免 sticky 的媒体错误码长期遮蔽后续不同的 OSD 错误。
wire [7:0]  merged_err_code  = media_err_code_clk;

// Silent 48 kHz samples cover startup, browsing, pause and track prefetch.
// Media failures are silent; the legacy generator supplies zero-sample cadence.
wire media_audio_available = media_status_v2[20] && (|media_status_v2[19:16]);
wire audio_silent = boot_active || (S5_PLAY_ENABLE &&
                    (paused_v2 || !play_active_v2 ||
                     !stream_enable_vid[1] || !wav_stream_active));

// 16点正弦 LUT 峰值约 12000，200/255 缩放后仍保留足够余量，避免削波爆音。
// EC2、KEY/IR 与音频增益均只读写同一份 VOL CSR；暂停/启动静音仍沿用原门控。
wire [7:0] audio_volume_eff = audio_silent ? 8'd0 : play_volume_video;
assign audio_volume = audio_volume_eff;

// S5：暂停时冻结播放器采样节拍（音频位置与歌词时基同时停住），
// 并用 force_arpeggio 保持 48 kHz 静音流，避免 HDMI 音频饿死。
wire wav_sample_tick_eff = wav_sample_tick & ~(S5_PLAY_ENABLE & paused_v2);
wire audio_force_arp     = audio_silent; // Tone generator supplies cadence, output samples are zero

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

// X2：Seek 后起始 LBA / 剩余扇区。target 已在 seek_controller 内钳位到
// [0,total_samples-1]，所以 offset_sectors <= total_sectors-1，剩余至少 1 个扇区。
// 这些派生量再寄存一拍，避免 32 位 target 直接穿进播放器的组合寻址与
// 突发判断（r12 布线后最后 -0.156 ns 违例：target_sample -> wstate）。
wire [31:0] wav_seek_sector = {24'd0, play_seek_target_sd[31:8]};
reg  [31:0] wav_start_lba_eff;
reg  [31:0] wav_total_sectors_eff;
reg  [31:0] wav_valid_samples;
reg  [7:0]  wav_skip_samples;
always @(posedge sd_card_clk or negedge sd_media_rst_n) begin
    if (!sd_media_rst_n) begin
        wav_start_lba_eff     <= 32'd0;
        wav_total_sectors_eff <= 32'd0;
        wav_valid_samples     <= 32'd0;
        wav_skip_samples      <= 8'd0;
    end else begin
        wav_start_lba_eff     <= audio_start_lba + wav_seek_sector;
        wav_total_sectors_eff <= audio_total_sectors - wav_seek_sector;
        wav_valid_samples     <= play_total_samples - play_seek_target_sd;
        wav_skip_samples      <= play_seek_target_sd[7:0];
    end
end

// 第十一讲核心：从 AUDIO.PCM 的连续扇区流式播放。
wav_stream_player #(
    .ADDR_WIDTH        (12),
    .SAMPLES_PER_SECTOR(256)
) u_wav_stream_player (
    .wr_clk            (sd_card_clk),
    .wr_rst_n          (sd_media_rst_n),
    .play_enable       (audio_play_enable_gated),
    .start_lba         (wav_start_lba_eff),
    .total_sectors     (wav_total_sectors_eff),
    .valid_samples     (wav_valid_samples),
    .skip_samples      (wav_skip_samples),
    .sd_req            (wav_sec_req),
    .sd_lba            (wav_sec_lba),
    .sd_busy           (wav_sec_busy),
    .sd_valid          (wav_sec_valid),
    .sd_byte           (wav_sec_byte),
    .sd_byte_index     (wav_sec_byte_index),
    .sd_done           (wav_sec_done),
    .sd_error          (wav_sec_error),

    .rd_clk            (video_clk),
    .rd_rst_n          (media_video_rst_n),
    .sample_tick       (wav_sample_tick_eff),
    .sample_out        (wav_sample_left),
    .sample_valid      (wav_sample_valid),
    .sample_ready      (wav_sample_ready),
    .sample_counter    (wav_sample_counter),
    .stream_active     (wav_stream_active),
    .stream_end        (wav_stream_end),
    .reader_idle       (wav_reader_idle),
    .sample_consumed   (wav_sample_consumed),
    .buffer_low        (wav_buffer_low),
    .sample_base       (play_seek_target_v2),
    .underrun_pulse    (wav_underrun_pulse)
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
    .arp_left       (audio_silent ? 16'sd0 : arp_sample_left),
    .arp_right      (audio_silent ? 16'sd0 : arp_sample_right),
    .force_arpeggio (audio_force_arp),
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

// ==========================================================================
// X1B：PCM 包络只读旁路（视频域），不反压音频
//   包络直接挂在最终混音（hdmi 音源）上，音量/静音/转场淡入淡出都会体现，
//   因此不需要额外的 mute 端口。
// ==========================================================================
// Faster visual envelope: roughly 85 ms full-scale release at 48 kHz.
pcm_tap #(.DECAY_DIV(64), .DECAY_STEP(4)) u_pcm_tap (
    .clk          (video_clk),
    .rst_n        (media_video_rst_n),
    .sample_valid (mix_sample_valid && mix_sample_ready),
    .sample_left  (mix_sample_left),
    .sample_right (mix_sample_right),
    .level        (x1b_level_vid),
    .upd_tgl      (x1b_upd_tgl_vid)
);

// 包络更新跨到 clk 域（板级 50 MHz）。
// 包络翻转由 pcm_tap 保证发生在数据稳定之后，50 MHz 域同步采到的一定是完整值。
always @(posedge clk or negedge exp_rst_n) begin
    if (!exp_rst_n) begin
        x1b_upd_tgl_s1 <= 1'b0;
        x1b_upd_tgl_s2 <= 1'b0;
        x1b_upd_tgl_seen <= 1'b0;
        pcm_level_clk <= 8'd0;
    end else begin
        x1b_upd_tgl_s1 <= x1b_upd_tgl_vid;
        x1b_upd_tgl_s2 <= x1b_upd_tgl_s1;
        if (x1b_upd_tgl_s2 != x1b_upd_tgl_seen) begin
            x1b_upd_tgl_seen <= x1b_upd_tgl_s2;
            pcm_level_clk <= x1b_level_vid;
        end
    end
end

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
// ===================== S2：开机 Logo 图层（末级像素替换）=====================
// 位置：EC2 参数浮窗之后、RGB->AXIS 之前。boot_active=1 时整屏由 Logo 接管，
// 盒外为纯黑；boot_active=0 时 final_rgb 完全等于 EC2 输出，
// de/vs 节拍一行不改，因此不影响 HDMI 时序与音频数据岛调度。
boot_layer #(
    .BOOT_ENABLE  (S2_BOOT_ENABLE),
    .CLK_FREQ_HZ  (25_000_000),   // video_clk
    .HOLD_MS      (BOOT_HOLD_MS),         // Default: 6 s from stable video reset release
    .SKIP_MIN_MS  (BOOT_SKIP_MIN_MS), // Ignore early skip until monitor acquisition budget
    .TIMEOUT_MS   (BOOT_TIMEOUT_MS),         // 无事件/无首图时 8 s 兜底进入浏览态
    .BREATH_FLOOR (192)           // 呼吸最暗增益 192/256
) u_boot_layer (
    .clk               (video_clk),
    .rst_n             (video_rst_n),
    .vs                (ec2_panel_vs),
    .de                (ec2_panel_de),
    .pixel_x           (ec2_panel_x),
    .skip_toggle       (boot_skip_toggle_clk),
    .first_image_ready (display_valid_sync2),
    .boot_active       (boot_active),
    .rgb               (boot_rgb)
);

// S2 总开关（含诊断模式旁路）：=0 或不生效时整层旁路，回到 S1 像素。
wire s2_boot_on = S2_BOOT_ENABLE && !pat_mode;

// S6 reuses the existing SD client and frame FIFOs. No new clocks or IO.
sync_2ff u_mv_preloaded_sync(.clk(video_clk),.rst_n(video_rst_n),
 .async_in(media_preloaded_sd),.sync_out(media_preloaded_vid));
sync_2ff u_mv_writer_sync(.clk(ext_mem_clk),.rst_n(mem_rst_n),
 .async_in(mv_writer_active),.sync_out(mv_writer_mem));
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
 if(!sdcard_rst_n) mv_audio_low_sync<=2'b11;
 else mv_audio_low_sync<={mv_audio_low_sync[0],wav_buffer_low};
end
mv_sector_mux u_mv_sector_mux(
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),.audio_req(wav_sec_req),.audio_lba(wav_sec_lba),
 .video_req(mv_sec_req),.video_lba(mv_sec_lba),
 .allow_video(!audio_play_enable_gated || !mv_audio_low_sync[1]),
 .audio_busy(wav_sec_busy),.video_busy(mv_sec_busy),
 .audio_valid(wav_sec_valid),.video_valid(mv_sec_valid),
 .audio_done(wav_sec_done),.video_done(mv_sec_done),
 .sector_req(media_sec_req),.sector_lba(media_sec_lba),.sector_busy(media_sec_busy),
 .sector_valid(media_sec_valid),.sector_done(media_sec_done));
mv_stream_player u_mv_stream_player(
 .clk(sd_card_clk),.rst_n(sd_media_rst_n),.abort_request(!stream_enable_sd),.request_toggle(mv_req_tgl),
 .request_lba(mv_request_lba),.request_bank(mv_request_bank),
 .done_toggle(mv_done_tgl),.failed(mv_failed),.writer_active(mv_writer_active),
 .write_req(mv_write_req),.write_ack(sd_card_write_req_ack),
 .write_finish_toggle(frame_write_toggle_mem),.write_bank(mv_write_bank),
 .pixel_valid(mv_pixel_valid),.pixel_data(mv_pixel_data),
 .sector_req(mv_sec_req),.sector_lba(mv_sec_lba),.sector_busy(mv_sec_busy),
 .sector_valid(mv_sec_valid),.sector_byte(wav_sec_byte),.sector_byte_index(wav_sec_byte_index),
 .sector_done(mv_sec_done),.sector_error(wav_sec_error));
// Original timing issues read_req before delayed vs/frame_start. In PLAY wait
// 32 pixels (1.28 us of vertical blank) for committed MV base and length.
// BROWSE keeps its original request and full-frame read sequence.
always @(posedge video_clk or negedge video_rst_n) begin
 if(!video_rst_n) s6_read_wait<=0;
 else if(!video_read_req) s6_read_wait<=0;
 else if(s6_read_wait!=63) s6_read_wait<=s6_read_wait+1'b1;
end
assign s6_frame_read_req=video_read_req &&
 (!S6_VIDEO_ENABLE || (!play_active_v2 && !mv_read_active) || s6_read_wait>=32);
s6_video_layer #(.ENABLE(S6_VIDEO_ENABLE)) u_s6_video_layer(
 .clk(video_clk),.rst_n(media_video_rst_n),.frame_start(frame_start),
 .play_active(S5_PLAY_ENABLE && play_active_v2),.paused(paused_v2),
 .restart(play_track_restart_vid),.diagnostic(pat_mode),
 .transport_ready(stream_enable_vid[1] && !seek_frame_busy),.covers_ready(media_preloaded_vid),.metadata_async(mv_metadata_video),.time_ms(lyric_time_ms),
 .seek_frame(seek_frame_vid),
 .visual_toggle(mv_visual_tgl),.raw_read_en(video_read_en),.out_de(de),.out_x(osd_pixel_x),
 .adjusted_de(adjusted_de),.adjusted_x(adjusted_pixel_x),.rgb_in(wave_rgb_eff),.rgb_out(s6_rgb),
 .mv_read_active(mv_read_active),.mv_read_bank(mv_read_bank),
 .fifo_read_allowed(mv_fifo_read_allowed),.mv_window_visible(mv_window_visible),
 .request_toggle(mv_req_tgl),.request_lba(mv_request_lba),.request_bank(mv_request_bank),
 .done_toggle(mv_done_tgl),.failed(mv_failed));

// ===================== D11/D12：六槽歌词窗口与单口字库像素仲裁 ================
wire [23:0] lrc_rgb;
wire [1:0] song_id_frame;
wire       song_generation_frame;
wire [6:0] song_line_rom_index;
wire [7:0] song_line_count_rom;
wire       song_line_rom_valid;
wire [31:0] song_line_rom_time_ms;
wire [4:0] song_line_rom_length;
wire [127:0] song_line_rom_glyphs;
wire [127:0] song_no_lyrics_glyphs;
wire [7:0] song_ui_glyph;
wire [4:0] song_title_length;
wire [4:0] song_artist_length;
wire [127:0] song_title_glyphs;
wire [127:0] song_artist_glyphs;
wire song_text_valid;
wire [7:0] song_page_ascii_code;
wire [7:0] song_line_count_frame;
wire lyric_target_valid;
wire [6:0] lyric_target_index;
wire lyric_window_valid;
wire lyric_window_ready;
wire [6:0] lyric_window_center;
wire [29:0] lyric_row_lengths;
wire [767:0] lyric_row_glyphs;
wire lyric_scroll_active;
wire [5:0] lyric_scroll_offset;
wire [6:0] lyric_highlight_index;
wire lyric_scroll_commit;
assign lrc_rgb = s6_rgb;
song_text_rom u_song_text_rom (
    .clk(video_clk),.song_id(song_id_frame),.line_index(song_line_rom_index),
    .line_count(song_line_count_rom),.line_valid(song_line_rom_valid),
    .line_time_ms(song_line_rom_time_ms),.line_length(song_line_rom_length),
    .line_glyphs(song_line_rom_glyphs),.song_text_valid(song_text_valid),
    .title_length(song_title_length),.artist_length(song_artist_length),
    .title_glyphs(song_title_glyphs),.artist_glyphs(song_artist_glyphs),
    .no_lyrics_glyphs(song_no_lyrics_glyphs),.ui_ascii_code(song_page_ascii_code),
    .ui_glyph(song_ui_glyph)
);
lrc_window_controller u_lrc_window_controller (
    .clk(video_clk),.rst_n(video_rst_n),.vs(vs),
    .enable(S5_PLAY_ENABLE && play_active_v2 && !pat_mode),
    .time_ms(lyric_time_ms),.song_id_async(song_metadata_video[1:0]),
    .generation_async(song_metadata_video[2]),
    .rom_line_count(song_line_count_rom),.rom_line_valid(song_line_rom_valid),
    .rom_line_time_ms(song_line_rom_time_ms),.rom_line_length(song_line_rom_length),
    .rom_line_glyphs(song_line_rom_glyphs),
    .scroll_active(lyric_scroll_active),.scroll_target_index(lyric_highlight_index),
    .scroll_commit(lyric_scroll_commit),
    .song_id_frame(song_id_frame),.generation_frame(song_generation_frame),
    .rom_line_index(song_line_rom_index),.song_line_count_frame(song_line_count_frame),
    .target_valid(lyric_target_valid),.target_index(lyric_target_index),
    .window_valid(lyric_window_valid),.window_ready(lyric_window_ready),
    .window_center_index(lyric_window_center),
    .row_lengths(lyric_row_lengths),
    .row_glyphs(lyric_row_glyphs)
);
lrc_scroll_controller u_lrc_scroll_controller (
    .clk(video_clk),.rst_n(video_rst_n),.vs(vs),
    .enable(S5_PLAY_ENABLE && play_active_v2 && !pat_mode),.paused(paused_v2),
    .song_id(song_id_frame),.generation(song_generation_frame),
    .target_valid(lyric_target_valid),.target_index(lyric_target_index),
    .window_valid(lyric_window_valid),.window_ready(lyric_window_ready),
    .window_center_index(lyric_window_center),
    .scroll_active(lyric_scroll_active),
    .scroll_offset(lyric_scroll_offset),.highlight_index(lyric_highlight_index),
    .scroll_commit(lyric_scroll_commit)
);

// D10a: exact 240-pixel progress and elapsed/total text are updated in the
// vertical blank interval from the same consumed-sample timebase as lyrics.
wire [7:0] playback_progress_fill;
wire [103:0] playback_time_ascii;
wire playback_time_known;
playback_progress u_playback_progress (
    .clk(video_clk),.rst_n(video_rst_n),.vs(vs),
    .elapsed_samples(lyric_sample_count),.total_samples(play_total_samples),
    .progress_fill(playback_progress_fill),.time_ascii(playback_time_ascii),
    .time_known(playback_time_known)
);

// D10b: static playback page is one aligned RGB/DE/VS/x stage before EC2.
wire playback_page_vs;
wire playback_page_de;
wire [9:0] playback_page_x;
wire [23:0] playback_page_rgb;
playback_page u_playback_page (
    .clk(video_clk),.rst_n(video_rst_n),.vs(vs),.de(adjusted_de),
    .pixel_x(adjusted_pixel_x),
    .enable(S5_PLAY_ENABLE && play_active_v2 && !pat_mode),.rgb_in(lrc_rgb),
    .song_id(song_id_frame),.title_length(song_title_length),
    .artist_length(song_artist_length),.title_glyphs(song_title_glyphs),
    .artist_glyphs(song_artist_glyphs),.line_count(song_line_count_frame),
    .lyric_window_valid(lyric_window_valid),
    .lyric_scroll_active(lyric_scroll_active),
    .lyric_row_lengths(lyric_row_lengths),
    .lyric_row_glyphs(lyric_row_glyphs),
    .lyric_scroll_offset(lyric_scroll_offset),
    .no_lyrics_glyphs(song_no_lyrics_glyphs),
    .progress_fill(playback_progress_fill),.time_ascii(playback_time_ascii),
    .ascii_glyph(song_ui_glyph),.ascii_code(song_page_ascii_code),
    .out_vs(playback_page_vs),.out_de(playback_page_de),
    .out_pixel_x(playback_page_x),.out_rgb(playback_page_rgb)
);

// The page first paints an opaque canvas around the media window. Composite
// the live waveform afterwards so cover pixels cannot show through its bars.
// This is a combinational RGB overlay and keeps the aligned DE/VS/x stage.
promax_audio_waveform #(
    .WAVE_X      (64),
    .WAVE_Y      (376),
    .WAVE_WIDTH  (512),
    .WAVE_HEIGHT (96),
    .DECIMATE    (12)
) u_promax_audio_waveform (
    .clk             (video_clk),
    .rst_n           (video_rst_n),
    .vsync           (playback_page_vs),
    .de              (playback_page_de),
    .rgb_in          (playback_page_rgb),
    .pixel_x         (playback_page_x),
    .enable          (waveform_enable_frame && !pat_mode),
    .pcm_tap_valid   (wav_sample_valid),
    .pcm_tap_left    (wav_sample_left),
    .rgb_out         (waveform_rgb_out),
    .waveform_active (waveform_active)
);

// D6: one frame-coherent overlay snapshot, above user media layers and below
// Boot/blank priority. Its synchronous ASCII ROM adds one aligned RGB/DE/VS beat.
ec2_param_osd u_ec2_param_osd (
    .clk              (video_clk),
    .rst_n            (video_rst_n),
    .vs               (playback_page_vs),
    .de               (playback_page_de),
    .pixel_x          (playback_page_x),
    .rgb_in           (waveform_rgb_out),
    .visible          ((ec2_state_frame != 2'd0) && !pat_mode),
    .ui_state         (ec2_state_frame),
    .selected_param   (ec2_selected_frame),
    .volume           (volume_frame),
    .volume_bcd       (volume_bcd_frame),
    .brightness_level (brightness_level_frame),
    .contrast_level   (contrast_level_frame),
    .rotation_level   (rotation_level_frame),
    .ws_level         (ws_brightness_level_frame),
    .out_vs           (ec2_panel_vs),
    .out_de           (ec2_panel_de),
    .out_pixel_x      (ec2_panel_x),
    .out_rgb          (ec2_panel_rgb)
);

// S7-03：消隐（clk 域 blank_active）跨到 video_clk 域，末级像素替换为纯黑。
// 消隐只改像素，不动 HS/VS/DE 与 HDMI 音频数据岛，HDMI/音频锁定与节拍不变。
reg blank_v1, blank_v2;
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        blank_v1 <= 1'b0;
        blank_v2 <= 1'b0;
    end else begin
        blank_v1 <= blank_active;
        blank_v2 <= blank_v1;
    end
end
wire blank_active_vid = blank_v2;

assign final_rgb = blank_active_vid ? 24'h000000 :
                   (s2_boot_on && boot_active) ? boot_rgb : ec2_panel_rgb;

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_vs          (ec2_panel_vs),
    .I_de          (ec2_panel_de),
    .I_rgb         (final_rgb),
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

// ==========================================================================
// S1：拓展板移植集成（J2 / IDC40）
//
//   输入驱动整体移植自 J2 标定工程（资源/Expansion_Board_Test/src），处理顺序、
//   时序参数与行为逐条保持不变；本层运行在板级 clk(50 MHz) 域，与标定工程
//   sys_clk 同频，因此 8 ms 消抖 / 1 ms 正交稳定 / 50 MHz 红外解码无需换算，
//   也不占用 sd_card_clk(100 MHz) 的时序预算。
//
//   S1 只验证物理通路，不把事件接到切歌/播放/歌词/MV 等后续业务。
// ==========================================================================

reset_sync u_exp_reset (
    .clk        (clk),
    .ext_rst_n  (ext_rst_n),
    .rst_n_sync (exp_rst_n)
);

expansion_integration #(
    .CLK_FREQ_HZ      (50_000_000),
    .DEBOUNCE_CYCLES  (400_000),
    .AB_STABLE_CYCLES (50_000),
    .IR_CLK_FREQ_HZ   (50_000_000),
    .BUZZER_ENABLE    (BUZZER_FEEDBACK_ENABLE)
) u_expansion_integration (
    .clk              (clk),
    .rst_n            (exp_rst_n),
    .exp_key_n        (exp_key_n),
    .exp_dip_n        (exp_dip_n),
    .exp_enc1_a       (exp_enc1_a),
    .exp_enc1_b       (exp_enc1_b),
    .exp_enc1_sw_n    (exp_enc1_sw_n),
    .exp_enc2_a       (exp_enc2_a),
    .exp_enc2_b       (exp_enc2_b),
    .exp_enc2_sw_n    (exp_enc2_sw_n),
    .exp_ir_rx        (exp_ir_rx),
    .key3             (key3),
    .sw1              (sw1),
    .sw2              (sw2),
    .sw3              (sw3),
    .sw4              (sw4),
    .exp_led_n        (exp_led_n),
    .exp_ws2812_data  (exp_ws2812_data),
    .exp_ext_o        (exp_ext_o),
    .board_buzzer_n   (board_buzzer_n),
    .uart_tx          (uart_tx),
    .fault_flags      (fault_flags_clk),
    .ui_ev_valid      (ui_ev_valid),
    .underrun_pulse   (underrun_pulse_clk),
    .wav_buffer_low   (wav_buffer_low_c2),
    .wav_stream_active(wav_stream_active_c2),
    .mv_failed        (mv_failed_c2),
    .osd_err_valid    (merged_err_valid),
    .osd_err_code     (merged_err_code),
    .slideshow_beep_event(slideshow_beep_event_clk),
    .ui_event_valid   (ui_event_valid),
    .ui_event_code    (ui_event_code),
    .ui_event_arg     (ui_event_arg),
    .ui_event_aux     (ui_event_aux),
    .blank_active     (blank_active),
    .led_enable       (led_enable),
    .ws_enable        (ws_enable),
    .restart_req      (restart_req),
    // X1：状态反馈执行器接线
    .pcm_level        (pcm_level_clk),
    .ws_brightness_level(ws_brightness_level_csr),
    .mv_mode_active   (mv_read_active),
    .ws_mode_tgl      (ws_mode_tgl),
    .board_sw_level   (board_sw_level_clk),
    .disp_mode_tgl    (disp_mode_tgl_clk),
    .dip2_slideshow_enable(dip2_slideshow_enable_clk),
    .ui_tick_1ms      (ui_tick_1ms),
    .enc2_count_raw   (exp_enc2_count_raw),
    .ui_actions_ready (ui_actions_ready_clk),
    .restart_confirm_active(restart_confirm_active_clk)
);

// ==========================================================================
// S3：主界面选歌事件解码（板级 clk 域）
//   把统一事件总线里的选曲事件（EC1 旋转、方向键、EC1 按压、KEY07）
//   解码成四路电平翻转；随后由 sd 域的 browse_fsm 同步/边沿还原。
//   事件流的物理通路与反馈音保留，启动控制只读消费事件。
// ==========================================================================
ui_event_bridge u_ui_event_bridge (
    .clk          (clk),
    .rst_n        (exp_rst_n),
    .ev_valid     (ui_event_valid),
    .ev_code      (ui_event_code),
    .ev_arg       (ui_event_arg),
    .ev_aux       (ui_event_aux),
    .prev_tgl     (brw_ev_prev_tgl),
    .next_tgl     (brw_ev_next_tgl),
    .confirm_tgl  (brw_ev_confirm_tgl),
    .mode_tgl     (brw_ev_mode_tgl),
    .home_tgl     (brw_ev_home_tgl),
    .effect_tgl   (brw_ev_effect_tgl),
    .end_mode_tgl (brw_ev_end_mode_tgl),
    .enc_cw_tgl   (brw_ev_enc_cw_tgl),
    .enc_ccw_tgl  (brw_ev_enc_ccw_tgl),
    .key_up_tgl   (brw_ev_key_up_tgl),
    .visual_tgl   (mv_visual_tgl),
    .key_down_tgl (brw_ev_key_down_tgl),
    .ws_mode_tgl  (ws_mode_tgl),
    .seek_fwd5_tgl(brw_ev_seek_fwd5_tgl),
    .seek_bwd5_tgl(brw_ev_seek_bwd5_tgl),
    .replay_tgl   (brw_ev_replay_tgl),
    .seek_fwd2_tgl(brw_ev_seek_fwd2_tgl),
    .seek_bwd2_tgl(brw_ev_seek_bwd2_tgl)
);

// EC2 consumes only events that survived the existing UI router. The live
// counter is sampled as the disabled-period baseline so wake/recovery motion
// cannot be replayed later as volume changes.
ec2_event_replay u_ec2_event_replay(
    .clk(clk), .rst_n(exp_rst_n), .enable(ec2_control_enable),
    .count_current(exp_enc2_count_raw),
    .ev_valid(ui_event_valid), .ev_code(ui_event_code),
    .ev_arg(ui_event_arg), .ev_aux(ui_event_aux),
    .step_valid(ec2_step_valid), .step_up(ec2_step_up),
    .step_ready(ec2_step_ready), .press_event(ec2_press_event));

ec2_param_controller #(.PARAM_COUNT(5)) u_ec2_param_controller(
    .clk(clk), .rst_n(exp_rst_n), .enable(ec2_control_enable),
    .tick_1ms(ui_tick_1ms), .step_valid(ec2_step_valid),
    .step_up(ec2_step_up), .step_ready(ec2_step_ready),
    .press_event(ec2_press_event),
    .external_volume_event(volume_bridge_dst_valid),
    .param_req_valid(ec2_param_req_valid), .param_req_id(ec2_param_req_id),
    .param_req_up(ec2_param_req_up), .param_req_ready(ec2_param_req_ready),
    .selected_param(ec2_selected_param), .ui_state(ec2_ui_state),
    .ui_update(ec2_ui_update));

// ==========================================================================
// S2：Boot 状态跨域握手
//   1) clk 域：任一已确认事件 -> 翻转电平（单比特电平翻转是标准 CDC 手法，
//      不会因事件密集而丢脉冲，也不需要事件总线整体跨域）；
//   2) video 域：boot_layer 内两级同步 + 边沿检测，一次事件只消费一次；
//   3) 反向：boot_active 为慢变单比特电平，两级同步回 clk 域。
// ==========================================================================
always @(posedge clk or negedge exp_rst_n) begin
    if (!exp_rst_n) begin
        boot_skip_toggle_clk <= 1'b0;
    end else begin
        if (ui_ev_valid)
            boot_skip_toggle_clk <= ~boot_skip_toggle_clk;

    end
end

// ==========================================================================
// S5：播放态跨越 sd_card_clk -> video_clk
//   play_active/paused 是慢变单比特电平，使用两级同步；唯一 VOL CSR 位于
//   50 MHz UI 域，经 u_play_volume_cdc 的 bundled-data 握手原子送到音频域；
//   track_step 是单拍事件，用"电平翻转 + 目标域边沿检测"搬过去做时基复位。
// ==========================================================================
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        play_active_v1    <= 1'b0;
        play_active_v2    <= 1'b0;
        paused_v1         <= 1'b0;
        paused_v2         <= 1'b0;
        play_track_tgl_v1 <= 1'b0;
        play_track_tgl_v2 <= 1'b0;
        play_track_tgl_v3 <= 1'b0;
    end else begin
        play_active_v1    <= play_active_sd;
        play_active_v2    <= play_active_v1;
        paused_v1         <= paused_sd;
        paused_v2         <= paused_v1;
        play_track_tgl_v1 <= play_track_tgl_sd;
        play_track_tgl_v2 <= play_track_tgl_v1;
        play_track_tgl_v3 <= play_track_tgl_v2;
    end
end

// ==========================================================================
// S5：全工程唯一的 48 kHz 毫秒时基（歌词/进度只认它）
// ==========================================================================
timebase_48k u_timebase_48k (
    .clk          (video_clk),
    .rst_n        (media_video_rst_n),
    .sample_tick  (wav_sample_consumed),
    .running      (play_running_vid),
    .restart      (play_track_restart_vid),
    .load         (play_track_restart_vid),
    .load_sample  (play_seek_target_v2),
    .sample_count (lyric_sample_count),
    .cur_time_ms  (lyric_time_ms),
    .sub_sample   ()
);

endmodule
