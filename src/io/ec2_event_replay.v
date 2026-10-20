`ifndef EXP_EC2_EVENT_REPLAY_V
`define EXP_EC2_EVENT_REPLAY_V
// Replays accepted EC2 count deltas one step at a time in the 50 MHz UI domain.
module ec2_event_replay (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [15:0] count_current,
    input  wire        ev_valid,
    input  wire [3:0]  ev_code,
    input  wire [15:0] ev_arg,
    input  wire [15:0] ev_aux,
    output wire        step_valid,
    output wire        step_up,
    input  wire        step_ready,
    output reg         press_event
);
    `include "exp_event_defs.vh"

    wire is_enc2_step = (ev_code == EV_ENC_STEP) && ev_aux[1];
    wire is_enc2_baseline = (ev_code == EV_ENC_BASELINE) && ev_aux[1];
    wire is_enc2_down = (ev_code == EV_ENC_SW) && ev_aux[1] &&
                        (ev_arg[0] == 1'b0);

    reg        enable_d;
    reg        enc_seen;
    reg [15:0] enc_target;
    reg [15:0] enc_delivered;
    reg [2:0]  enc_gap;

    wire [15:0] enc_delta = enc_target - enc_delivered;
    wire emit_step = enable && enc_seen && (enc_gap == 0) &&
                     (enc_delta != 0) && !ev_valid;

    assign step_valid = emit_step;
    assign step_up    = !enc_delta[15];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_d      <= 1'b0;
            enc_seen      <= 1'b0;
            enc_target    <= 16'd0;
            enc_delivered <= 16'd0;
            enc_gap       <= 3'd0;
            press_event   <= 1'b0;
        end else begin
            enable_d    <= enable;
            press_event <= 1'b0;

            if (!enable || !enable_d) begin
                // Keep disabled-period and first-enable activity as the baseline.
                enc_target    <= count_current;
                enc_delivered <= count_current;
                enc_seen      <= 1'b1;
                enc_gap       <= 3'd0;
            end else begin
                if (enc_gap != 0)
                    enc_gap <= enc_gap - 1'b1;

                if (ev_valid && is_enc2_down)
                    press_event <= 1'b1;

                if (ev_valid && is_enc2_baseline) begin
                    enc_target <= ev_arg;
                    enc_delivered <= ev_arg;
                    enc_seen <= 1'b1;
                    enc_gap <= 3'd0;
                end else if (ev_valid && is_enc2_step)
                    enc_target <= ev_arg;

                if (emit_step && step_ready) begin
                    if (enc_delta[15])
                        enc_delivered <= enc_delivered - 1'b1;
                    else
                        enc_delivered <= enc_delivered + 1'b1;
                    enc_gap <= 3'd7;
                end
            end
        end
    end
endmodule
`endif
