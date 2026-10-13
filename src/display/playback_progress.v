`timescale 1ns/1ps
`ifndef EXP_PLAYBACK_PROGRESS_V
`define EXP_PLAYBACK_PROGRESS_V
// Frame-snapshot progress/time formatter. All division and BCD conversion
// runs in vertical blanking; the pixel path only reads registered ASCII data.
module playback_progress (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         vs,
    input  wire [31:0]  elapsed_samples,
    input  wire [31:0]  total_samples,
    output reg  [8:0]   progress_fill,
    output reg  [39:0]  elapsed_time_ascii,
    output reg  [47:0]  remaining_time_ascii,
    output reg  [39:0]  total_time_ascii,
    output reg          time_known
);
    localparam [3:0] ST_IDLE                = 4'd0;
    localparam [3:0] ST_DIV_PROGRESS        = 4'd1;
    localparam [3:0] ST_DIV_ELAPSED_SECONDS = 4'd2;
    localparam [3:0] ST_DIV_TOTAL_SECONDS   = 4'd3;
    localparam [3:0] ST_DIV_ELAPSED_MINUTES = 4'd4;
    localparam [3:0] ST_DIV_TOTAL_MINUTES   = 4'd5;
    localparam [3:0] ST_DIV_REMAINING_MINUTES = 4'd6;
    localparam [3:0] ST_BCD_ELAPSED_MINUTES = 4'd7;
    localparam [3:0] ST_BCD_TOTAL_MINUTES   = 4'd8;
    localparam [3:0] ST_BCD_REMAINING_MINUTES = 4'd9;
    localparam [39:0] UNKNOWN_MSS_ASCII = {
        8'h2D,8'h2D,8'h3A,8'h2D,8'h2D
    };
    localparam [47:0] UNKNOWN_REMAINING_ASCII = {
        8'h20,8'h2D,8'h2D,8'h3A,8'h2D,8'h2D
    };

    reg [3:0] state;
    reg vs_q;
    wire frame_start = vs_q && !vs;

    reg [31:0] elapsed_snapshot;
    reg [31:0] total_snapshot;
    reg [40:0] div_work;
    reg [32:0] remainder_work;
    reg [31:0] divisor_work;
    reg [5:0] div_count;
    wire [32:0] div_trial = {remainder_work[31:0], div_work[40]};
    wire div_subtract = div_trial >= {1'b0, divisor_work};
    wire [32:0] div_remainder_next = div_subtract
                                   ? div_trial - {1'b0, divisor_work}
                                   : div_trial;
    wire [40:0] div_quotient_next = {div_work[39:0], div_subtract};

    reg [16:0] elapsed_seconds_binary;
    reg [16:0] total_seconds_binary;
    reg [16:0] remaining_seconds_binary;
    reg [10:0] elapsed_minutes_binary;
    reg [10:0] total_minutes_binary;
    reg [10:0] remaining_minutes_binary;
    reg [5:0] elapsed_seconds_display;
    reg [5:0] total_seconds_display;
    reg [5:0] remaining_seconds_display;

    reg [10:0] bcd_binary_work;
    reg [11:0] bcd_work;
    reg [11:0] elapsed_minutes_bcd;
    reg [11:0] total_minutes_bcd;
    reg [3:0] bcd_count;
    reg [3:0] ones_adjusted;
    reg [3:0] tens_adjusted;
    reg [3:0] hundreds_adjusted;
    reg [11:0] bcd_adjusted;
    wire [11:0] bcd_next = {bcd_adjusted[10:0], bcd_binary_work[10]};

    function [7:0] seconds_to_bcd;
        input [5:0] seconds;
        reg [3:0] tens;
        reg [5:0] ones;
        begin
            tens = 4'd0;
            ones = seconds;
            if (seconds >= 6'd50) begin tens = 4'd5; ones = seconds - 6'd50; end
            else if (seconds >= 6'd40) begin tens = 4'd4; ones = seconds - 6'd40; end
            else if (seconds >= 6'd30) begin tens = 4'd3; ones = seconds - 6'd30; end
            else if (seconds >= 6'd20) begin tens = 4'd2; ones = seconds - 6'd20; end
            else if (seconds >= 6'd10) begin tens = 4'd1; ones = seconds - 6'd10; end
            seconds_to_bcd = {tens, ones[3:0]};
        end
    endfunction

    wire [7:0] elapsed_seconds_bcd = seconds_to_bcd(elapsed_seconds_display);
    wire [7:0] total_seconds_bcd = seconds_to_bcd(total_seconds_display);
    wire [7:0] remaining_seconds_bcd = seconds_to_bcd(remaining_seconds_display);

    reg [31:0] elapsed_clamped_input;
    reg [40:0] elapsed_extended;
    reg [40:0] progress_numerator;
    always @* begin
        elapsed_clamped_input = (elapsed_samples > total_samples)
                              ? total_samples : elapsed_samples;
        elapsed_extended = {9'd0, elapsed_clamped_input};
        // 320 = 256 + 64. Keep all 41 product bits for a 32-bit sample count.
        progress_numerator = (elapsed_extended << 8) +
                             (elapsed_extended << 6);

        ones_adjusted = bcd_work[3:0];
        tens_adjusted = bcd_work[7:4];
        hundreds_adjusted = bcd_work[11:8];
        if (ones_adjusted >= 4'd5) ones_adjusted = ones_adjusted + 4'd3;
        if (tens_adjusted >= 4'd5) tens_adjusted = tens_adjusted + 4'd3;
        if (hundreds_adjusted >= 4'd5) hundreds_adjusted = hundreds_adjusted + 4'd3;
        bcd_adjusted = {hundreds_adjusted, tens_adjusted, ones_adjusted};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            vs_q <= 1'b1;
            elapsed_snapshot <= 32'd0;
            total_snapshot <= 32'd0;
            div_work <= 41'd0;
            remainder_work <= 33'd0;
            divisor_work <= 32'd0;
            div_count <= 6'd0;
            progress_fill <= 9'd0;
            elapsed_time_ascii <= UNKNOWN_MSS_ASCII;
            remaining_time_ascii <= UNKNOWN_REMAINING_ASCII;
            total_time_ascii <= UNKNOWN_MSS_ASCII;
            time_known <= 1'b0;
            elapsed_seconds_binary <= 17'd0;
            total_seconds_binary <= 17'd0;
            remaining_seconds_binary <= 17'd0;
            elapsed_minutes_binary <= 11'd0;
            total_minutes_binary <= 11'd0;
            remaining_minutes_binary <= 11'd0;
            elapsed_seconds_display <= 6'd0;
            total_seconds_display <= 6'd0;
            remaining_seconds_display <= 6'd0;
            bcd_binary_work <= 11'd0;
            bcd_work <= 12'd0;
            elapsed_minutes_bcd <= 12'd0;
            total_minutes_bcd <= 12'd0;
            bcd_count <= 4'd0;
        end else begin
            vs_q <= vs;

            if (frame_start) begin
                if (total_samples == 0) begin
                    progress_fill <= 9'd0;
                    elapsed_time_ascii <= UNKNOWN_MSS_ASCII;
                    remaining_time_ascii <= UNKNOWN_REMAINING_ASCII;
                    total_time_ascii <= UNKNOWN_MSS_ASCII;
                    time_known <= 1'b0;
                    state <= ST_IDLE;
                    div_count <= 6'd0;
                end else begin
                    elapsed_snapshot <= elapsed_clamped_input;
                    total_snapshot <= total_samples;
                    div_work <= progress_numerator;
                    remainder_work <= 33'd0;
                    divisor_work <= total_samples;
                    div_count <= 6'd41;
                    state <= ST_DIV_PROGRESS;
                end
            end else begin
                case (state)
                    ST_DIV_PROGRESS,
                    ST_DIV_ELAPSED_SECONDS,
                    ST_DIV_TOTAL_SECONDS,
                    ST_DIV_ELAPSED_MINUTES,
                    ST_DIV_TOTAL_MINUTES,
                    ST_DIV_REMAINING_MINUTES: begin
                        if (div_count != 0) begin
                            if (div_count == 1) begin
                                case (state)
                                    ST_DIV_PROGRESS: begin
                                        if ((div_quotient_next[40:9] != 0) ||
                                            (div_quotient_next[8:0] > 9'd320))
                                            progress_fill <= 9'd320;
                                        else
                                            progress_fill <= div_quotient_next[8:0];
                                        div_work <= {9'd0, elapsed_snapshot};
                                        remainder_work <= 33'd0;
                                        divisor_work <= 32'd48000;
                                        div_count <= 6'd41;
                                        state <= ST_DIV_ELAPSED_SECONDS;
                                    end
                                    ST_DIV_ELAPSED_SECONDS: begin
                                        elapsed_seconds_binary <= div_quotient_next[16:0];
                                        div_work <= {9'd0, total_snapshot};
                                        remainder_work <= 33'd0;
                                        divisor_work <= 32'd48000;
                                        div_count <= 6'd41;
                                        state <= ST_DIV_TOTAL_SECONDS;
                                    end
                                    ST_DIV_TOTAL_SECONDS: begin
                                        total_seconds_binary <= div_quotient_next[16:0];
                                        if (div_quotient_next[16:0] > elapsed_seconds_binary)
                                            remaining_seconds_binary <=
                                                div_quotient_next[16:0] - elapsed_seconds_binary;
                                        else
                                            remaining_seconds_binary <= 17'd0;
                                        div_work <= {24'd0, elapsed_seconds_binary};
                                        remainder_work <= 33'd0;
                                        divisor_work <= 32'd60;
                                        div_count <= 6'd41;
                                        state <= ST_DIV_ELAPSED_MINUTES;
                                    end
                                    ST_DIV_ELAPSED_MINUTES: begin
                                        elapsed_minutes_binary <= div_quotient_next[10:0];
                                        elapsed_seconds_display <= div_remainder_next[5:0];
                                        div_work <= {24'd0, total_seconds_binary};
                                        remainder_work <= 33'd0;
                                        divisor_work <= 32'd60;
                                        div_count <= 6'd41;
                                        state <= ST_DIV_TOTAL_MINUTES;
                                    end
                                    ST_DIV_TOTAL_MINUTES: begin
                                        total_minutes_binary <= div_quotient_next[10:0];
                                        total_seconds_display <= div_remainder_next[5:0];
                                        div_work <= {24'd0, remaining_seconds_binary};
                                        remainder_work <= 33'd0;
                                        divisor_work <= 32'd60;
                                        div_count <= 6'd41;
                                        state <= ST_DIV_REMAINING_MINUTES;
                                    end
                                    default: begin
                                        remaining_minutes_binary <= div_quotient_next[10:0];
                                        remaining_seconds_display <= div_remainder_next[5:0];
                                        bcd_binary_work <= (elapsed_minutes_binary > 11'd99)
                                                         ? 11'd99 : elapsed_minutes_binary;
                                        bcd_work <= 12'd0;
                                        bcd_count <= 4'd11;
                                        state <= ST_BCD_ELAPSED_MINUTES;
                                    end
                                endcase
                            end else begin
                                div_work <= div_quotient_next;
                                remainder_work <= div_remainder_next;
                                div_count <= div_count - 6'd1;
                            end
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                    ST_BCD_ELAPSED_MINUTES,
                    ST_BCD_TOTAL_MINUTES,
                    ST_BCD_REMAINING_MINUTES: begin
                        bcd_work <= bcd_next;
                        bcd_binary_work <= {bcd_binary_work[9:0], 1'b0};
                        if (bcd_count == 1) begin
                            if (state == ST_BCD_ELAPSED_MINUTES) begin
                                elapsed_minutes_bcd <= bcd_next;
                                bcd_binary_work <= (total_minutes_binary > 11'd99)
                                                 ? 11'd99 : total_minutes_binary;
                                bcd_work <= 12'd0;
                                bcd_count <= 4'd11;
                                state <= ST_BCD_TOTAL_MINUTES;
                            end else if (state == ST_BCD_TOTAL_MINUTES) begin
                                total_minutes_bcd <= bcd_next;
                                bcd_binary_work <= (remaining_minutes_binary > 11'd99)
                                                 ? 11'd99 : remaining_minutes_binary;
                                bcd_work <= 12'd0;
                                bcd_count <= 4'd11;
                                state <= ST_BCD_REMAINING_MINUTES;
                            end else begin
                                elapsed_time_ascii <=
                                    (elapsed_minutes_bcd[7:4] == 4'd0)
                                    ? {8'd48 + {4'd0, elapsed_minutes_bcd[3:0]},
                                       8'h3A,
                                       8'd48 + {4'd0, elapsed_seconds_bcd[7:4]},
                                       8'd48 + {4'd0, elapsed_seconds_bcd[3:0]},
                                       8'h20}
                                    : {8'd48 + {4'd0, elapsed_minutes_bcd[7:4]},
                                       8'd48 + {4'd0, elapsed_minutes_bcd[3:0]},
                                       8'h3A,
                                       8'd48 + {4'd0, elapsed_seconds_bcd[7:4]},
                                       8'd48 + {4'd0, elapsed_seconds_bcd[3:0]}};
                                remaining_time_ascii <=
                                    (bcd_next[7:4] == 4'd0)
                                    ? {8'h20, 8'h2D,
                                       8'd48 + {4'd0, bcd_next[3:0]},
                                       8'h3A,
                                       8'd48 + {4'd0, remaining_seconds_bcd[7:4]},
                                       8'd48 + {4'd0, remaining_seconds_bcd[3:0]}}
                                    : {8'h2D,
                                       8'd48 + {4'd0, bcd_next[7:4]},
                                       8'd48 + {4'd0, bcd_next[3:0]},
                                       8'h3A,
                                       8'd48 + {4'd0, remaining_seconds_bcd[7:4]},
                                       8'd48 + {4'd0, remaining_seconds_bcd[3:0]}};
                                total_time_ascii <= {
                                    8'd48 + {4'd0, total_minutes_bcd[7:4]},
                                    8'd48 + {4'd0, total_minutes_bcd[3:0]},
                                    8'h3A,
                                    8'd48 + {4'd0, total_seconds_bcd[7:4]},
                                    8'd48 + {4'd0, total_seconds_bcd[3:0]}
                                };
                                time_known <= 1'b1;
                                bcd_count <= 4'd0;
                                state <= ST_IDLE;
                            end
                        end else begin
                            bcd_count <= bcd_count - 4'd1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
`endif
