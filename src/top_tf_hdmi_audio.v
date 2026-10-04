
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
    .next_event        (fade_next_event),
    .key_auto          (key2),
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
key_press_debounce #(
    .CLK_FREQ_HZ (100_000_000),
    .DEBOUNCE_MS (20)
) u_key_next_transition (
    .clk              (sd_card_clk),
    .rst              (~sdcard_rst_n),
    .button_in        (key1),
    .press_pulse      (key_next_transition_press),
    .button_stable_out()
);

video_fade_transition #(
    .FADE_FRAMES (16)
) u_video_fade_transition (
    .ctrl_clk        (sd_card_clk),
    .ctrl_rst_n      (sdcard_rst_n),
    .next_event_in   (key_next_transition_press),
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

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
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
assign vout_data = display_valid ? vout_data_raw : 24'd0;

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

// 第十讲：先做转场处理，再送入OSD；OSD永远位于最上层。
video_transition_apply #(
    .WIPE_STEP (40)
) u_video_transition_apply (
    .rgb_in      (vout_data),
    .alpha       (fade_alpha),
    .wipe_active (wipe_active),
    .wipe_ramp   (wipe_ramp),
    .pixel_x     (osd_pixel_x),
    .rgb_out     (transition_rgb)
);

osd_overlay_24 #(
    .OSD_X(8),
    .OSD_Y(8)
) u_osd_overlay_24 (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (vs),
    .de           (de),
    .rgb_in       (transition_rgb),
    .pixel_x      (osd_pixel_x),
    .active_index (media_id),
    .auto_enabled (auto_enabled_sync2),
    .error_code   (osd_error_code_frame),
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
    .de              (de),
    .rgb_in          (osd_rgb_out),
    .pixel_x         (osd_pixel_x),
    .enable          (audio_play_enable),
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

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
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
    .I_de          (de),
    .I_rgb         (waveform_rgb_out),
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
