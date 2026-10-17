`ifndef EXP_VINYL_PLAYBACK_EFFECTS_V
`define EXP_VINYL_PLAYBACK_EFFECTS_V
// Vinyl turntable motor and independent 8-pixel WS2812 strip.
// All control and serialization run from the existing 50 MHz UI clock.
module vinyl_playback_effects #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer REFRESH_MS  = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire play_active_async,
    input  wire paused_async,
    input  wire needle_sense_n,
    input  wire ws_enable,
    input  wire [2:0] brightness_level, // Shared OSD WSL: 0/25/50/75/100%.
    input  wire tick_1ms,
    output wire motor_enable,
    output wire ws_data
);
    localparam integer BIT_CYCLES   = (CLK_FREQ_HZ >= 50_000_000) ? 63 : 31;
    localparam integer T0H_CYCLES   = (CLK_FREQ_HZ >= 50_000_000) ? 18 : 10;
    localparam integer T1H_CYCLES   = (CLK_FREQ_HZ >= 50_000_000) ? 35 : 19;
    localparam integer RESET_CYCLES = (CLK_FREQ_HZ >= 50_000_000) ? 3000 : 1250;

    reg play_active_s1;
    reg play_active_s2;
    reg paused_s1;
    reg paused_s2;
    reg needle_s1;
    reg needle_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) play_active_s1 <= 1'b0;
        else        play_active_s1 <= play_active_async;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) play_active_s2 <= 1'b0;
        else        play_active_s2 <= play_active_s1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) paused_s1 <= 1'b0;
        else        paused_s1 <= paused_async;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) paused_s2 <= 1'b0;
        else        paused_s2 <= paused_s1;
    end
    // G12 has an external pull-up and closes to ground when the needle is ON.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) needle_s1 <= 1'b1;
        else        needle_s1 <= needle_sense_n;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) needle_s2 <= 1'b1;
        else        needle_s2 <= needle_s1;
    end

    wire playback_run = play_active_s2 && !paused_s2 && !needle_s2;
    wire strip_run = ws_enable && playback_run;
    assign motor_enable = rst_n && playback_run;

    reg [6:0] position_ms;
    reg [2:0] color_phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) position_ms <= 7'd0;
        else if (!strip_run) position_ms <= 7'd0;
        else if (tick_1ms) begin
            if (position_ms == 7'd124) position_ms <= 7'd0;
            else                      position_ms <= position_ms + 7'd1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) color_phase <= 3'd0;
        else if (!strip_run) color_phase <= 3'd0;
        else if (tick_1ms && position_ms == 7'd124)
            color_phase <= color_phase + 3'd1;
    end

    localparam integer REFRESH_W = (REFRESH_MS < 2) ? 1 : $clog2(REFRESH_MS);
    reg [REFRESH_W-1:0] refresh_ms;
    wire refresh_pulse = tick_1ms && (refresh_ms == REFRESH_MS-1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) refresh_ms <= 0;
        else if (!strip_run) refresh_ms <= 0;
        else if (tick_1ms) begin
            if (refresh_pulse) refresh_ms <= 0;
            else               refresh_ms <= refresh_ms + 1'b1;
        end
    end

    reg frame_active;
    reg [2:0] frame_phase;
    reg [2:0] brightness_frame = 3'd4;
    reg black_sent;
    reg load_req;
    wire busy;
    wire accept_frame = load_req && !busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_active <= 1'b0;
        else if (accept_frame) frame_active <= strip_run;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_phase <= 3'd0;
        else if (accept_frame) frame_phase <= color_phase;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) brightness_frame <= 3'd4;
        else if (accept_frame) brightness_frame <= brightness_level;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) black_sent <= 1'b0;
        else if (strip_run) black_sent <= 1'b0;
        else if (accept_frame) black_sent <= 1'b1;
    end
    always @* begin
        if (strip_run) load_req = refresh_pulse && !busy;
        else           load_req = !busy && !black_sent;
    end

    wire [4:0] pixel_index;
    wire [2:0] color_index = pixel_index[2:0] + frame_phase;
    // Scale the two constant palette amplitudes before color selection.
    // floor(115 * WSL / 4) equals floor(floor(230 * WSL / 4) / 2),
    // so a single small decode and wiring replace three RGB arithmetic paths.
    reg [7:0] full_level;
    wire [7:0] half_level = {1'b0, full_level[7:1]};
    always @* begin
        case (brightness_frame)
            3'd1: full_level = 8'd57;
            3'd2: full_level = 8'd115;
            3'd3: full_level = 8'd172;
            3'd4: full_level = 8'd230;
            default: full_level = 8'd0;
        endcase
    end
    reg [7:0] red;
    reg [7:0] green;
    reg [7:0] blue;
    always @* begin
        red   = 8'd0;
        green = 8'd0;
        blue  = 8'd0;
        if (frame_active) begin
            case (color_index)
                3'd0: red   = full_level;                            // red
                3'd1: begin red=full_level; green=half_level; end     // orange
                3'd2: begin red=full_level; green=full_level; end     // yellow
                3'd3: green = full_level;                            // green
                3'd4: begin green=full_level; blue=full_level; end    // cyan
                3'd5: blue  = full_level;                            // blue
                3'd6: begin red=half_level; blue=full_level; end      // purple
                3'd7: begin red=full_level; blue=full_level; end      // magenta
                default: ;
            endcase
        end
    end
    wire [23:0] stream_grb = {green, red, blue};

    ws2812_driver #(
        .PIXEL_COUNT  (8),
        .BIT_CYCLES   (BIT_CYCLES),
        .T0H_CYCLES   (T0H_CYCLES),
        .T1H_CYCLES   (T1H_CYCLES),
        .RESET_CYCLES (RESET_CYCLES),
        .STREAMING    (1)
    ) u_vinyl_ws2812_driver (
        .clk                 (clk),
        .rst_n               (rst_n),
        .load                (load_req),
        .grb_in              (192'd0),
        .stream_grb          (stream_grb),
        .stream_pixel_index  (pixel_index),
        .busy                (busy),
        .dout                (ws_data)
    );
endmodule
`endif
