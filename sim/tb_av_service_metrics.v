`timescale 1ns/1ps
// Quantify the baseline shared-SD audio/MV service contract.
// Timing is scaled 61.27x from 100 MHz / 48 kHz / 10 fps: one PCM sample
// every 34 clocks and one frame every 163200 clocks. The byte source models
// the payload-floor case: 300 MV sectors plus audio sectors fit with no spare
// command/response time; byte_gap=2 models a slower card under pressure.
module tb_av_service_metrics;
    localparam integer FRAME_PERIOD = 163200;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg audio_enable = 0;
    reg mv_enable = 0;
    reg mv_restart = 0;
    reg [31:0] start_lba = 32'd100;
    reg [31:0] sample_base = 0;
    reg [15:0] seek_frame = 0;
    reg [31:0] time_ms = 0;
    reg [15:0] frame_count = 16'd512;
    reg [18:0] frame_divider = 0;
    reg frame_start = 0;
    integer service_byte_gap = 1;
    integer service_gap_count = 0;

    wire wav_req;
    wire [31:0] wav_lba;
    wire wav_busy, wav_valid, wav_done;
    wire [7:0] wav_error;
    wire [7:0] wav_byte;
    wire [8:0] wav_byte_index;
    wire signed [15:0] pcm_data;
    wire pcm_valid, wav_active, wav_end, wav_low, underrun;
    wire [31:0] sample_counter;
    wire [31:0] total_samples = 32'd4000000;
    wire [31:0] total_sectors = 32'd16000;

    reg [5:0] sample_divider = 0;
    reg sample_tick = 0;
    reg [1:0] audio_low_sync = 2'b11;

    wire video_req;
    wire [31:0] video_lba;
    wire video_busy, video_valid, video_done;
    wire [31:0] sector_lba;
    wire sector_req;
    wire audio_busy, background_busy, background_grant;
    wire audio_valid, audio_done, background_valid, background_done;

    reg sector_busy = 0;
    reg sector_valid = 0;
    reg sector_done = 0;
    reg [7:0] sector_byte = 0;
    reg [8:0] sector_byte_index = 0;
    reg [8:0] service_index = 0;
    reg service_active = 0;

    wire mv_request_toggle;
    wire [31:0] mv_request_lba;
    wire [1:0] mv_request_bank;
    wire mv_display_valid;
    wire [1:0] mv_display_bank;
    wire [15:0] mv_display_frame;
    wire mv_waiting;
    reg mv_done_toggle = 0;
    reg mv_failed = 0;
    reg [2:0] request_sync = 0;
    reg request_seen = 0;
    reg mv_fetch_active = 0;
    reg [8:0] mv_sector_number = 0;
    reg [31:0] mv_frame_base = 0;
    reg seek_request_seen = 0;
    reg seek_check_active = 0;

    integer phase = 0;
    integer min_level [0:3];
    integer max_level [0:3];
    integer pcm_valid_count [0:3];
    integer pcm_data_count [0:3];
    integer pcm_silence_count [0:3];
    integer underrun_count [0:3];
    integer audio_sector_count [0:3];
    integer video_sector_count [0:3];
    integer audio_block_cycles [0:3];
    integer audio_wait_run = 0;
    integer audio_wait_max [0:3];
    integer video_block_cycles [0:3];
    integer video_wait_run = 0;
    integer video_wait_max [0:3];
    integer mv_request_count [0:3];
    integer mv_frame_done_count [0:3];
    integer mv_display_update_count [0:3];
    integer mv_display_hold_frames [0:3];
    integer frame_tick_count = 0;
    reg [15:0] last_display_frame = 0;
    integer i;

    wav_stream_player #(.ADDR_WIDTH(12), .SAMPLES_PER_SECTOR(256)) wav (
        .wr_clk(clk), .wr_rst_n(rst_n), .play_enable(audio_enable),
        .start_lba(start_lba), .total_sectors(total_sectors),
        .valid_samples(total_samples), .skip_samples(8'd0),
        .sd_req(wav_req), .sd_lba(wav_lba), .sd_busy(wav_busy),
        .sd_valid(wav_valid), .sd_byte(wav_byte),
        .sd_byte_index(wav_byte_index), .sd_done(wav_done), .sd_error(wav_error),
        .rd_clk(clk), .rd_rst_n(rst_n), .sample_tick(sample_tick),
        .sample_out(pcm_data), .sample_valid(pcm_valid), .sample_ready(1'b1),
        .sample_counter(sample_counter), .stream_active(wav_active),
        .stream_end(wav_end), .reader_idle(), .sample_consumed(),
        .buffer_low(wav_low), .sample_base(sample_base), .underrun_pulse(underrun)
    );

    background_sector_mux sector_mux (
        .clk(clk), .rst_n(rst_n),
        .audio_req(wav_req), .audio_lba(wav_lba),
        .audio_urgent(1'b0),
        .video_req(video_req), .video_lba(video_lba),
        .background_req(1'b0), .background_lba(32'd0),
        .background_start(1'b0),
        .allow_video(!audio_enable || !audio_low_sync[1]),
        .allow_background(1'b0),
        .audio_busy(audio_busy), .video_busy(video_busy),
        .background_busy(background_busy), .background_grant(background_grant),
        .audio_valid(audio_valid), .video_valid(video_valid),
        .background_valid(background_valid), .audio_done(audio_done),
        .video_done(video_done), .background_done(background_done),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_busy(sector_busy), .sector_valid(sector_valid),
        .sector_done(sector_done)
    );

    mv_frame_scheduler scheduler (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .enable(mv_enable), .paused(1'b0), .restart(mv_restart),
        .time_ms(time_ms), .start_lba(start_lba + 32'd50000),
        .frame_count(frame_count), .seek_frame(seek_frame),
        .done_toggle(mv_done_toggle), .failed(mv_failed), .retain_display(1'b1),
        .request_toggle(mv_request_toggle), .request_lba(mv_request_lba),
        .request_bank(mv_request_bank), .display_valid(mv_display_valid),
        .display_bank(mv_display_bank), .display_frame(mv_display_frame),
        .waiting(mv_waiting)
    );

    assign video_req = mv_fetch_active;
    assign video_lba = mv_frame_base + {23'd0, mv_sector_number};
    assign wav_busy = audio_busy;
    assign wav_valid = audio_valid;
    assign wav_done = audio_done;
    assign wav_byte = sector_byte;
    assign wav_byte_index = sector_byte_index;
    assign wav_error = 8'd0;

    // A deterministic sector source. It models command/byte service time and
    // returns non-zero little-endian PCM samples for the audio client.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            service_active <= 0;
            service_index <= 0;
            service_gap_count <= 0;
            sector_busy <= 0;
            sector_valid <= 0;
            sector_done <= 0;
            sector_byte <= 0;
            sector_byte_index <= 0;
        end else begin
            sector_valid <= 0;
            sector_done <= 0;
            if (!service_active && sector_req && !sector_busy) begin
                service_active <= 1;
                service_index <= 0;
                service_gap_count <= 0;
                sector_busy <= 1;
            end else if (service_active) begin
                if (service_gap_count + 1 >= service_byte_gap) begin
                    service_gap_count <= 0;
                    sector_valid <= 1;
                    sector_byte_index <= service_index;
                    sector_byte <= service_index[0] ? 8'hA5 : 8'h5A;
                    if (service_index == 9'd511) begin
                        service_active <= 0;
                        sector_busy <= 0;
                        sector_done <= 1;
                    end else begin
                        service_index <= service_index + 1'b1;
                    end
                end else begin
                    service_gap_count <= service_gap_count + 1;
                end
            end
        end
    end

    // Scale the board's 48 kHz sample tick and 10 fps frame edge by 32.5x.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_divider <= 0;
            sample_tick <= 0;
        end else begin
            sample_tick <= (sample_divider == 6'd33);
            sample_divider <= (sample_divider == 6'd33) ? 0 : sample_divider + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) audio_low_sync <= 2'b11;
        else audio_low_sync <= {audio_low_sync[0], wav_low};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_divider <= 0;
            frame_start <= 0;
            time_ms <= 0;
            frame_tick_count <= 0;
        end else if (frame_divider == FRAME_PERIOD-1) begin
            frame_divider <= 0;
            frame_start <= 1;
            time_ms <= time_ms + 32'd100;
            frame_tick_count <= frame_tick_count + 1;
        end else begin
            frame_divider <= frame_divider + 1'b1;
            frame_start <= 0;
        end
    end

    // A minimal MV client reads 300 whole sectors per requested frame and
    // acknowledges only after the last sector, like mv_stream_player's contract.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_sync <= 0;
            request_seen <= 0;
            mv_fetch_active <= 0;
            mv_sector_number <= 0;
            mv_frame_base <= 0;
            mv_done_toggle <= 0;
        end else begin
            request_sync <= {request_sync[1:0], mv_request_toggle};
            if (!mv_fetch_active && request_sync[2] != request_seen) begin
                request_seen <= request_sync[2];
                mv_frame_base <= mv_request_lba;
                mv_sector_number <= 0;
                mv_fetch_active <= 1;
                mv_request_count[phase] = mv_request_count[phase] + 1;
                if (phase == 3)
                    $display("AV_REQUEST phase=seek lba=%0d wanted=%0d frame=%0d target=%0d time_ms=%0d seek=%0d",
                             mv_request_lba, start_lba + 32'd55100,
                             scheduler.requested_frame, scheduler.target_frame,
                             time_ms, seek_frame);
                if (seek_check_active &&
                    (mv_request_lba >= start_lba + 32'd55100) &&
                    (((mv_request_lba - (start_lba + 32'd55100)) % 32'd300) == 0))
                    seek_request_seen <= 1;
                if (mv_request_lba == (start_lba + 32'd55100))
                    seek_request_seen <= 1;
            end else if (mv_fetch_active && video_done) begin
                if (mv_sector_number == 9'd299) begin
                    mv_fetch_active <= 0;
                    mv_done_toggle <= request_seen;
                    mv_frame_done_count[phase] = mv_frame_done_count[phase] + 1;
                end else begin
                    mv_sector_number <= mv_sector_number + 1'b1;
                end
            end
        end
    end

    // Counters are simulation-only: measure FIFO range, valid/data/silence
    // distinction, blocked request cycles and completed/displayed MV frames.
    always @(negedge clk) begin
        if (rst_n) begin
            if (wav.level_rd < min_level[phase]) min_level[phase] = wav.level_rd;
            if (wav.level_rd > max_level[phase]) max_level[phase] = wav.level_rd;
            if (pcm_valid) begin
                pcm_valid_count[phase] = pcm_valid_count[phase] + 1;
                if (pcm_data != 0) pcm_data_count[phase] = pcm_data_count[phase] + 1;
                else pcm_silence_count[phase] = pcm_silence_count[phase] + 1;
            end
            if (underrun) underrun_count[phase] = underrun_count[phase] + 1;
            if (audio_done) audio_sector_count[phase] = audio_sector_count[phase] + 1;
            if (video_done) video_sector_count[phase] = video_sector_count[phase] + 1;

            if (wav_req && !(sector_mux.owner_valid && sector_mux.owner == 2'd0)) begin
                audio_wait_run = audio_wait_run + 1;
                audio_block_cycles[phase] = audio_block_cycles[phase] + 1;
                if (audio_wait_run > audio_wait_max[phase]) audio_wait_max[phase] = audio_wait_run;
            end else audio_wait_run = 0;

            if (video_req && !(sector_mux.owner_valid && sector_mux.owner == 2'd1)) begin
                video_wait_run = video_wait_run + 1;
                video_block_cycles[phase] = video_block_cycles[phase] + 1;
                if (video_wait_run > video_wait_max[phase]) video_wait_max[phase] = video_wait_run;
            end else video_wait_run = 0;

            if (mv_display_valid && (mv_display_frame != last_display_frame)) begin
                mv_display_update_count[phase] = mv_display_update_count[phase] + 1;
                last_display_frame = mv_display_frame;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && frame_start) begin
            if (mv_display_valid && mv_display_frame == last_display_frame)
                mv_display_hold_frames[phase] = mv_display_hold_frames[phase] + 1;
        end
    end

    task print_metrics;
        input integer which_phase;
        input [8*30-1:0] label_text;
        begin
            $display("METRIC %-30s fifo_min=%0d fifo_max=%0d pcm_valid=%0d pcm_data=%0d pcm_zero_or_empty=%0d underrun=%0d audio_sector=%0d audio_wait_max=%0d audio_wait_cycles=%0d video_sector=%0d video_wait_max=%0d video_wait_cycles=%0d mv_req=%0d mv_done=%0d mv_display_updates=%0d mv_hold_frames=%0d",
                label_text, min_level[which_phase], max_level[which_phase],
                pcm_valid_count[which_phase],
                pcm_data_count[which_phase], pcm_silence_count[which_phase],
                underrun_count[which_phase], audio_sector_count[which_phase],
                audio_wait_max[which_phase], audio_block_cycles[which_phase],
                video_sector_count[which_phase], video_wait_max[which_phase],
                video_block_cycles[which_phase], mv_request_count[which_phase],
                mv_frame_done_count[which_phase], mv_display_update_count[which_phase],
                mv_display_hold_frames[which_phase]);
        end
    endtask

    task run_frames;
        input integer count;
        integer finish_at;
        begin
            finish_at = frame_tick_count + count;
            wait (frame_tick_count >= finish_at);
            repeat (32) @(negedge clk);
        end
    endtask

    initial begin
        for (i=0; i<4; i=i+1) begin
            min_level[i]=8191; max_level[i]=0;
            pcm_valid_count[i]=0; pcm_data_count[i]=0;
            pcm_silence_count[i]=0; underrun_count[i]=0;
            audio_sector_count[i]=0; video_sector_count[i]=0;
            audio_block_cycles[i]=0; audio_wait_max[i]=0;
            video_block_cycles[i]=0; video_wait_max[i]=0;
            mv_request_count[i]=0; mv_frame_done_count[i]=0;
            mv_display_update_count[i]=0; mv_display_hold_frames[i]=0;
        end

        repeat (8) @(negedge clk); rst_n=1; audio_enable=1;
        phase=0; run_frames(10); print_metrics(0, "audio_only_1s");

        phase=1; time_ms=0; mv_enable=1; service_byte_gap=1;
        run_frames(20); print_metrics(1, "audio_plus_mv_2s_payload_floor");

        phase=2; service_byte_gap=2;
        run_frames(10); print_metrics(2, "audio_plus_mv_1s_half_rate");

        // Track change, then a non-zero seek target, both with in-flight work
        // allowed to drain through the sector boundary.
        phase=3;
        audio_enable=0; mv_restart=1; start_lba=32'd100000;
        time_ms=0; seek_frame=0; sample_base=0;
        repeat (4) @(negedge clk); mv_restart=0; audio_enable=1;
        run_frames(5);
        mv_restart=1; time_ms=32'd1700;
        seek_frame=16'd17; sample_base=32'd816000;
        seek_request_seen=0; seek_check_active=1;
        repeat (4) @(negedge clk); mv_restart=0;
        run_frames(5); print_metrics(3, "track_change_and_seek");

        if (underrun_count[0] != 0 || underrun_count[1] != 0 || underrun_count[2] != 0)
            $fatal(1, "unexpected sustained-playback underrun in scaled SD model");
        if (audio_sector_count[0] == 0 || video_sector_count[1] == 0 ||
            mv_display_update_count[1] == 0)
            $fatal(1, "missing audio/MV service or displayed-frame coverage");
        if (!seek_request_seen)
            $fatal(1, "seek-target MV request LBA was not observed");
        $display("PASS AV service metrics: audio-only, MV, 5s sustained, half-rate stress, track restart and seek");
        $finish;
    end

    initial begin
        #400_000_000_000;
        $fatal(1, "AV service metric watchdog timeout");
    end
endmodule
