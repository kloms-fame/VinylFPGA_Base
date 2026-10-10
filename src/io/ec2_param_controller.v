`ifndef EXP_EC2_PARAM_CONTROLLER_V
`define EXP_EC2_PARAM_CONTROLLER_V
// D3's VOL-only EC2 state machine and one-entry held CSR request.
module ec2_param_controller #(
    parameter integer HIDE_TIMEOUT_MS = 1800
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire tick_1ms,
    input  wire step_valid,
    input  wire step_up,
    output wire step_ready,
    input  wire press_event,
    input  wire external_volume_event,
    output reg  vol_req_valid,
    output reg  vol_req_up,
    input  wire vol_req_ready,
    output reg  [1:0] ui_state
);
    localparam [1:0] STATE_HIDDEN  = 2'd0;
    localparam [1:0] STATE_SELECT  = 2'd1;
    localparam [1:0] STATE_ADJUST  = 2'd2;

    localparam integer TIMEOUT_W = 11;
    reg [TIMEOUT_W-1:0] idle_ms;

    assign step_ready = enable && !vol_req_valid && !press_event &&
                        !external_volume_event;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_ms       <= {TIMEOUT_W{1'b0}};
            ui_state      <= STATE_HIDDEN;
            vol_req_valid <= 1'b0;
            vol_req_up    <= 1'b0;
        end else if (!enable) begin
            idle_ms       <= {TIMEOUT_W{1'b0}};
            ui_state      <= STATE_HIDDEN;
            vol_req_valid <= 1'b0;
            vol_req_up    <= 1'b0;
        end else begin
            if (vol_req_valid && vol_req_ready)
                vol_req_valid <= 1'b0;

            if (external_volume_event) begin
                idle_ms  <= {TIMEOUT_W{1'b0}};
                ui_state <= STATE_SELECT;
            end else if (press_event) begin
                idle_ms <= {TIMEOUT_W{1'b0}};
                case (ui_state)
                    STATE_HIDDEN: ui_state <= STATE_SELECT;
                    STATE_SELECT: ui_state <= STATE_ADJUST;
                    default:      ui_state <= STATE_SELECT;
                endcase
            end else if (step_valid && step_ready) begin
                idle_ms <= {TIMEOUT_W{1'b0}};
                if (ui_state == STATE_HIDDEN) begin
                    ui_state      <= STATE_ADJUST;
                    vol_req_valid <= 1'b1;
                    vol_req_up    <= step_up;
                end else if (ui_state == STATE_ADJUST) begin
                    vol_req_valid <= 1'b1;
                    vol_req_up    <= step_up;
                end
            end else if (tick_1ms) begin
                if (idle_ms >= HIDE_TIMEOUT_MS - 1) begin
                    idle_ms  <= {TIMEOUT_W{1'b0}};
                    ui_state <= STATE_HIDDEN;
                end else begin
                    idle_ms <= idle_ms + 1'b1;
                end
            end
        end
    end
endmodule
`endif
