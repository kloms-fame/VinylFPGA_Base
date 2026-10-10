`timescale 1ns/1ps
`ifndef EXP_LRC_WINDOW_CONTROLLER_V
`define EXP_LRC_WINDOW_CONTROLLER_V

// D11: scan the timestamp table once per frame, then maintain one coherent
// six-row window around the selected lyric.  The six rows share the existing
// single synchronous song_text_rom read port.
module lrc_window_controller (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          vs,
    input  wire          enable,
    input  wire [31:0]   time_ms,
    input  wire [1:0]    song_id_async,
    input  wire          generation_async,
    input  wire [7:0]    rom_line_count,
    input  wire          rom_line_valid,
    input  wire [31:0]   rom_line_time_ms,
    input  wire [4:0]    rom_line_length,
    input  wire [127:0] rom_line_glyphs,
    input  wire          scroll_active,
    input  wire [6:0]    scroll_target_index,
    input  wire          scroll_commit,
    output reg  [1:0]    song_id_frame,
    output reg           generation_frame,
    output reg  [6:0]    rom_line_index,
    output reg  [7:0]    song_line_count_frame,
    output reg           target_valid,
    output reg  [6:0]    target_index,
    output reg           window_valid,
    output reg           window_ready,
    output reg  [6:0]    window_center_index,
    output reg  [5:0]    row_valid,
    output reg  [41:0]   row_indices,
    output reg  [29:0]   row_lengths,
    output reg  [767:0]  row_glyphs
);
    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_PREP       = 3'd1;
    localparam [2:0] ST_SCAN       = 3'd2;
    localparam [2:0] ST_FILL_ISSUE = 3'd3;
    localparam [2:0] ST_FILL_WAIT  = 3'd4;
    localparam [2:0] ST_TAIL_ISSUE = 3'd5;
    localparam [2:0] ST_TAIL_WAIT  = 3'd6;

    reg [2:0] state;
    reg vs_q;
    reg [31:0] frame_time_ms;
    reg [7:0] scan_issue_index;
    reg [6:0] scan_pending_index;
    reg scan_pending_valid;
    reg scan_selected_valid;
    reg [6:0] scan_selected_index;
    reg [6:0] fill_center_index;
    reg [2:0] fill_slot;
    reg tail_pending;

    wire frame_start = vs_q && !vs;
    wire scan_hit = scan_pending_valid && rom_line_valid &&
                    (rom_line_time_ms <= frame_time_ms);
    wire scan_final_valid = scan_selected_valid || scan_hit;
    wire [6:0] scan_final_index = scan_hit ? scan_pending_index : scan_selected_index;
    wire [7:0] center_plus_one = {1'b0, window_center_index} + 8'd1;
    wire scan_is_normal_next = ({1'b0, scan_final_index} == center_plus_one);
    wire scan_holds_window = window_valid &&
        ((scan_final_index == window_center_index) ||
         (scroll_active && (scan_final_index == scroll_target_index)) ||
         (!scroll_active && scan_is_normal_next));

    wire signed [8:0] fill_index_math =
        $signed({2'b00, fill_center_index}) + $signed({6'd0, fill_slot}) - 9'sd2;
    wire fill_index_in_range = (fill_index_math >= 9'sd0) &&
        (fill_index_math < $signed({1'b0, song_line_count_frame}));
    wire signed [8:0] tail_index_math =
        $signed({2'b00, window_center_index}) + 9'sd4;
    wire tail_index_in_range = (tail_index_math >= 9'sd0) &&
        (tail_index_math < $signed({1'b0, song_line_count_frame}));

    always @* begin
        rom_line_index = 7'd0;
        case (state)
            ST_SCAN: begin
                if (scan_issue_index < song_line_count_frame)
                    rom_line_index = scan_issue_index[6:0];
            end
            ST_FILL_ISSUE: begin
                if (fill_index_in_range)
                    rom_line_index = fill_index_math[6:0];
            end
            ST_TAIL_ISSUE: begin
                if (tail_index_in_range)
                    rom_line_index = tail_index_math[6:0];
            end
            default: rom_line_index = 7'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            vs_q <= 1'b1;
            frame_time_ms <= 32'd0;
            song_id_frame <= 2'd0;
            generation_frame <= 1'b0;
            song_line_count_frame <= 8'd0;
            scan_issue_index <= 8'd0;
            scan_pending_index <= 7'd0;
            scan_pending_valid <= 1'b0;
            scan_selected_valid <= 1'b0;
            scan_selected_index <= 7'd0;
            target_valid <= 1'b0;
            target_index <= 7'd0;
            window_valid <= 1'b0;
            window_ready <= 1'b0;
            window_center_index <= 7'd0;
            row_valid <= 6'd0;
            row_indices <= 42'd0;
            row_lengths <= 30'd0;
            row_glyphs <= 768'd0;
            fill_center_index <= 7'd0;
            fill_slot <= 3'd0;
            tail_pending <= 1'b0;
        end else begin
            vs_q <= vs;

            // The horizontal sync scan and any subsequent row fill complete
            // early in the vertical blank interval.  A new frame restarts an
            // interrupted scan without publishing a partially updated window.
            if (frame_start) begin
                song_id_frame <= song_id_async;
                generation_frame <= generation_async;
                frame_time_ms <= time_ms;
                state <= enable ? ST_PREP : ST_IDLE;
                scan_issue_index <= 8'd0;
                scan_pending_valid <= 1'b0;
                scan_selected_valid <= 1'b0;
                tail_pending <= 1'b0;
                if (!enable || (song_id_async != song_id_frame) ||
                    (generation_async != generation_frame)) begin
                    target_valid <= 1'b0;
                    window_valid <= 1'b0;
                    window_ready <= 1'b0;
                    row_valid <= 6'd0;
                end
            end else begin
                if (scroll_commit && window_valid) begin
                    row_glyphs <= row_glyphs >> 128;
                    row_lengths <= row_lengths >> 5;
                    row_indices <= row_indices >> 7;
                    row_valid <= {1'b0, row_valid[5:1]};
                    row_glyphs[767:640] <= 128'd0;
                    row_lengths[29:25] <= 5'd0;
                    row_indices[41:35] <= 7'd0;
                    window_center_index <= window_center_index + 7'd1;
                    window_ready <= 1'b0;
                    tail_pending <= 1'b1;
                end

                case (state)
                    ST_PREP: begin
                        song_line_count_frame <= rom_line_count;
                        scan_issue_index <= 8'd1;
                        scan_pending_index <= 7'd0;
                        scan_pending_valid <= (rom_line_count != 0);
                        scan_selected_valid <= 1'b0;
                        scan_selected_index <= 7'd0;
                        if (rom_line_count == 0) begin
                            target_valid <= 1'b0;
                            window_valid <= 1'b0;
                            window_ready <= 1'b0;
                            row_valid <= 6'd0;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_SCAN;
                        end
                    end

                    ST_SCAN: begin
                        if (scan_hit) begin
                            scan_selected_valid <= 1'b1;
                            scan_selected_index <= scan_pending_index;
                        end

                        if (scan_issue_index < song_line_count_frame) begin
                            scan_pending_index <= scan_issue_index[6:0];
                            scan_pending_valid <= 1'b1;
                            scan_issue_index <= scan_issue_index + 8'd1;
                        end else begin
                            scan_pending_valid <= 1'b0;
                            target_valid <= scan_final_valid;
                            if (scan_final_valid)
                                target_index <= scan_final_index;

                            if (!scan_final_valid) begin
                                window_valid <= 1'b0;
                                window_ready <= 1'b0;
                                row_valid <= 6'd0;
                                tail_pending <= 1'b0;
                                state <= ST_IDLE;
                            end else if (scan_holds_window) begin
                                if (tail_pending) begin
                                    state <= ST_TAIL_ISSUE;
                                end else begin
                                    state <= ST_IDLE;
                                end
                            end else begin
                                fill_center_index <= scan_final_index;
                                window_center_index <= scan_final_index;
                                window_valid <= 1'b0;
                                window_ready <= 1'b0;
                                row_valid <= 6'd0;
                                row_indices <= 42'd0;
                                row_lengths <= 30'd0;
                                row_glyphs <= 768'd0;
                                fill_slot <= 3'd0;
                                tail_pending <= 1'b0;
                                state <= ST_FILL_ISSUE;
                            end
                        end
                    end

                    ST_FILL_ISSUE: begin
                        if (!fill_index_in_range) begin
                            row_valid[fill_slot] <= 1'b0;
                            row_indices[fill_slot*7 +: 7] <= 7'd0;
                            row_lengths[fill_slot*5 +: 5] <= 5'd0;
                            row_glyphs[fill_slot*128 +: 128] <= 128'd0;
                            if (fill_slot == 3'd5) begin
                                window_valid <= 1'b1;
                                window_ready <= 1'b1;
                                state <= ST_IDLE;
                            end else begin
                                fill_slot <= fill_slot + 3'd1;
                            end
                        end else begin
                            state <= ST_FILL_WAIT;
                        end
                    end

                    ST_FILL_WAIT: begin
                        row_valid[fill_slot] <= rom_line_valid;
                        row_indices[fill_slot*7 +: 7] <= fill_index_math[6:0];
                        row_lengths[fill_slot*5 +: 5] <= rom_line_valid ? rom_line_length : 5'd0;
                        row_glyphs[fill_slot*128 +: 128] <= rom_line_valid ? rom_line_glyphs : 128'd0;
                        if (fill_slot == 3'd5) begin
                            window_valid <= 1'b1;
                            window_ready <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            fill_slot <= fill_slot + 3'd1;
                            state <= ST_FILL_ISSUE;
                        end
                    end

                    ST_TAIL_ISSUE: begin
                        if (!tail_index_in_range) begin
                            row_valid[5] <= 1'b0;
                            row_indices[41:35] <= 7'd0;
                            row_lengths[29:25] <= 5'd0;
                            row_glyphs[767:640] <= 128'd0;
                            window_ready <= 1'b1;
                            tail_pending <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_TAIL_WAIT;
                        end
                    end

                    ST_TAIL_WAIT: begin
                        row_valid[5] <= rom_line_valid;
                        row_indices[41:35] <= tail_index_math[6:0];
                        row_lengths[29:25] <= rom_line_valid ? rom_line_length : 5'd0;
                        row_glyphs[767:640] <= rom_line_valid ? rom_line_glyphs : 128'd0;
                        window_ready <= 1'b1;
                        tail_pending <= 1'b0;
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
`endif
