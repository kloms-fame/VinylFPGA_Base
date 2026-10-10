`ifndef EXP_EC2_PARAM_CONTROLLER_V
`define EXP_EC2_PARAM_CONTROLLER_V
// EC2 panel state and one-entry held parameter request, all in the 50 MHz UI domain.
module ec2_param_controller #(
    parameter integer HIDE_TIMEOUT_MS = 1800
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       tick_1ms,
    input  wire       step_valid,
    input  wire       step_up,
    output wire       step_ready,
    input  wire       press_event,
    input  wire       external_volume_event,
    output reg        param_req_valid,
    output reg  [1:0] param_req_id,
    output reg        param_req_up,
    input  wire       param_req_ready,
    output reg  [1:0] selected_param,
    output reg  [1:0] ui_state,
    output reg        ui_update
);
    localparam [1:0] STATE_HIDDEN = 2'd0;
    localparam [1:0] STATE_SELECT = 2'd1;
    localparam [1:0] STATE_ADJUST = 2'd2;

    localparam [1:0] PARAM_VOL = 2'd0;
    localparam [1:0] PARAM_BRI = 2'd1;
    localparam [1:0] PARAM_CON = 2'd2;

    localparam integer TIMEOUT_W = 11;
    reg [TIMEOUT_W-1:0] idle_ms;

    // SELECT旋转只选参数；隐藏态与ADJUST态的旋转需要CSR接收请求。
    wire select_only_step = (ui_state == STATE_SELECT);
    assign step_ready = enable && !param_req_valid && !press_event &&
                        !external_volume_event &&
                        (select_only_step || param_req_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_ms       <= {TIMEOUT_W{1'b0}};
            ui_state      <= STATE_HIDDEN;
            selected_param <= PARAM_VOL;
            param_req_valid <= 1'b0;
            param_req_id  <= PARAM_VOL;
            param_req_up  <= 1'b0;
            ui_update     <= 1'b0;
        end else begin
            ui_update <= 1'b0;

            if (!enable) begin
                if ((ui_state != STATE_HIDDEN) || (selected_param != PARAM_VOL))
                    ui_update <= 1'b1;
                idle_ms        <= {TIMEOUT_W{1'b0}};
                ui_state       <= STATE_HIDDEN;
                selected_param <= PARAM_VOL;
                param_req_valid <= 1'b0;
            end else begin
                if (param_req_valid && param_req_ready)
                    param_req_valid <= 1'b0;

                if (external_volume_event) begin
                    idle_ms        <= {TIMEOUT_W{1'b0}};
                    ui_state       <= STATE_SELECT;
                    selected_param <= PARAM_VOL;
                    ui_update      <= 1'b1;
                end else if (press_event) begin
                    idle_ms   <= {TIMEOUT_W{1'b0}};
                    ui_update <= 1'b1;
                    case (ui_state)
                        STATE_HIDDEN: ui_state <= STATE_SELECT;
                        STATE_SELECT: ui_state <= STATE_ADJUST;
                        default:      ui_state <= STATE_SELECT;
                    endcase
                end else if (step_valid && step_ready) begin
                    idle_ms   <= {TIMEOUT_W{1'b0}};
                    ui_update <= 1'b1;
                    case (ui_state)
                        STATE_HIDDEN: begin
                            ui_state       <= STATE_ADJUST;
                            param_req_valid <= 1'b1;
                            param_req_id   <= PARAM_VOL;
                            param_req_up   <= step_up;
                        end
                        STATE_SELECT: begin
                            if (step_up)
                                selected_param <= (selected_param == PARAM_CON)
                                                ? PARAM_VOL : selected_param + 2'd1;
                            else
                                selected_param <= (selected_param == PARAM_VOL)
                                                ? PARAM_CON : selected_param - 2'd1;
                        end
                        STATE_ADJUST: begin
                            param_req_valid <= 1'b1;
                            param_req_id   <= selected_param;
                            param_req_up   <= step_up;
                        end
                        default: begin
                            ui_state <= STATE_HIDDEN;
                        end
                    endcase
                end else if (tick_1ms && !param_req_valid) begin
                    if (idle_ms >= HIDE_TIMEOUT_MS - 1) begin
                        idle_ms   <= {TIMEOUT_W{1'b0}};
                        ui_state  <= STATE_HIDDEN;
                        ui_update <= 1'b1;
                    end else begin
                        idle_ms <= idle_ms + 1'b1;
                    end
                end
            end
        end
    end
endmodule
`endif
