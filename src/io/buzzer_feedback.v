`ifndef EXP_BUZZER_FEEDBACK_V
`define EXP_BUZZER_FEEDBACK_V
// Low-active board-buzzer feedback mixer for the standalone interaction demo.
// Audible classes: KEY, DIP, EC1, EC2, encoder push and IR command.
module buzzer_feedback #(
    parameter integer KEY_HALF_PERIOD_CYCLES         = 12_500,
    parameter integer KEY_DURATION_CYCLES            = 1_500_000,
    parameter integer DIP_LOW_HALF_PERIOD_CYCLES     = 16_667,
    parameter integer DIP_HIGH_HALF_PERIOD_CYCLES    = 10_000,
    parameter integer DIP_TONE_DURATION_CYCLES       = 1_250_000,
    // Legacy names are retained so the existing unit-test fixture remains valid.
    parameter integer ENCODER_POS_HALF_PERIOD_CYCLES = 8_333,
    parameter integer ENCODER_NEG_HALF_PERIOD_CYCLES = 13_889,
    parameter integer ENCODER_SWITCH_HALF_PERIOD_CYCLES = 20_833,
    parameter integer EC1_POS_HALF_PERIOD_CYCLES     = ENCODER_POS_HALF_PERIOD_CYCLES,
    parameter integer EC1_NEG_HALF_PERIOD_CYCLES     = ENCODER_NEG_HALF_PERIOD_CYCLES,
    parameter integer EC2_POS_HALF_PERIOD_CYCLES     = 20_833,
    parameter integer EC2_NEG_HALF_PERIOD_CYCLES     = 10_417,
    parameter integer ENCODER_STEP_DURATION_CYCLES   = 400_000,
    parameter integer EC1_SWITCH_HALF_PERIOD_CYCLES  = ENCODER_SWITCH_HALF_PERIOD_CYCLES,
    parameter integer EC2_SWITCH_HALF_PERIOD_CYCLES  = 9_615,
    parameter integer ENCODER_SWITCH_DURATION_CYCLES = 3_000_000,
    parameter integer IR_DURATION_CYCLES             = 1_750_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sound_enable,
    input  wire       key_press,
    input  wire       dip_change,
    input  wire       dip_target,
    input  wire       encoder_step,
    input  wire       encoder_direction,
    input  wire       encoder_source,
    input  wire       encoder_switch,
    input  wire       encoder_switch_source,
    input  wire       ir_event,
    input  wire [1:0] ir_action,
    output reg        buzzer_n,
    output reg        busy
);
    localparam [3:0] EV_NONE = 4'd0, EV_STEP = 4'd1, EV_KEY = 4'd2,
                     EV_DIP = 4'd3, EV_IR = 4'd4, EV_SWITCH = 4'd5;

    reg key_d, dip_d, step_d, switch_d, ir_d;
    reg [3:0] current_event;
    reg dip_target_latched, dip_second_phase;
    reg [31:0] half_period_cycles, duration_cycles;
    reg [31:0] half_period_count, duration_count;

    wire key_rise    = key_press && !key_d;
    wire dip_rise    = dip_change && !dip_d;
    wire step_rise   = encoder_step && !step_d;
    wire switch_rise = encoder_switch && !switch_d;
    wire ir_rise     = ir_event && !ir_d;
    wire [3:0] requested_event = switch_rise ? EV_SWITCH :
                                  ir_rise ? EV_IR :
                                  dip_rise ? EV_DIP :
                                  key_rise ? EV_KEY :
                                  step_rise ? EV_STEP : EV_NONE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buzzer_n <= 1'b1; busy <= 1'b0; current_event <= EV_NONE;
            key_d <= 1'b0; dip_d <= 1'b0; step_d <= 1'b0; switch_d <= 1'b0; ir_d <= 1'b0;
            dip_target_latched <= 1'b0; dip_second_phase <= 1'b0;
            half_period_cycles <= 32'd1; duration_cycles <= 32'd1;
            half_period_count <= 32'd0; duration_count <= 32'd0;
        end else if (!sound_enable) begin
            key_d <= key_press; dip_d <= dip_change; step_d <= encoder_step;
            switch_d <= encoder_switch; ir_d <= ir_event;
            buzzer_n <= 1'b1; busy <= 1'b0; current_event <= EV_NONE;
            dip_second_phase <= 1'b0; half_period_count <= 32'd0; duration_count <= 32'd0;
        end else if ((requested_event != EV_NONE) && ((!busy) || (requested_event > current_event))) begin
            key_d <= key_press; dip_d <= dip_change; step_d <= encoder_step;
            switch_d <= encoder_switch; ir_d <= ir_event;
            buzzer_n <= 1'b0; busy <= 1'b1; current_event <= requested_event;
            dip_target_latched <= dip_target; dip_second_phase <= 1'b0;
            half_period_count <= 32'd0; duration_count <= 32'd0;
            case (requested_event)
                EV_SWITCH: begin
                    half_period_cycles <= encoder_switch_source ? EC2_SWITCH_HALF_PERIOD_CYCLES : EC1_SWITCH_HALF_PERIOD_CYCLES;
                    duration_cycles <= ENCODER_SWITCH_DURATION_CYCLES;
                end
                EV_IR: begin
                    case (ir_action)
                        2'd0: half_period_cycles <= 31_250; // brightness down
                        2'd1: half_period_cycles <= 9_615;  // brightness up
                        2'd2: half_period_cycles <= 22_727; // speed down
                        default: half_period_cycles <= 7_813; // speed up
                    endcase
                    duration_cycles <= IR_DURATION_CYCLES;
                end
                EV_DIP: begin
                    half_period_cycles <= dip_target ? DIP_HIGH_HALF_PERIOD_CYCLES : DIP_LOW_HALF_PERIOD_CYCLES;
                    duration_cycles <= DIP_TONE_DURATION_CYCLES;
                end
                EV_KEY: begin
                    half_period_cycles <= KEY_HALF_PERIOD_CYCLES;
                    duration_cycles <= KEY_DURATION_CYCLES;
                end
                default: begin
                    if (encoder_source)
                        half_period_cycles <= encoder_direction ? EC2_NEG_HALF_PERIOD_CYCLES : EC2_POS_HALF_PERIOD_CYCLES;
                    else
                        half_period_cycles <= encoder_direction ? EC1_NEG_HALF_PERIOD_CYCLES : EC1_POS_HALF_PERIOD_CYCLES;
                    duration_cycles <= ENCODER_STEP_DURATION_CYCLES;
                end
            endcase
        end else if (busy) begin
            key_d <= key_press; dip_d <= dip_change; step_d <= encoder_step;
            switch_d <= encoder_switch; ir_d <= ir_event;
            if ((duration_cycles <= 1) || (duration_count >= duration_cycles - 1'b1)) begin
                if ((current_event == EV_DIP) && !dip_second_phase) begin
                    buzzer_n <= 1'b0; dip_second_phase <= 1'b1;
                    half_period_count <= 32'd0; duration_count <= 32'd0;
                    half_period_cycles <= dip_target_latched ? DIP_LOW_HALF_PERIOD_CYCLES : DIP_HIGH_HALF_PERIOD_CYCLES;
                end else begin
                    buzzer_n <= 1'b1; busy <= 1'b0; current_event <= EV_NONE;
                    half_period_count <= 32'd0; duration_count <= 32'd0;
                end
            end else begin
                duration_count <= duration_count + 1'b1;
                if ((half_period_cycles <= 1) || (half_period_count >= half_period_cycles - 1'b1)) begin
                    half_period_count <= 32'd0; buzzer_n <= ~buzzer_n;
                end else begin
                    half_period_count <= half_period_count + 1'b1;
                end
            end
        end else begin
            key_d <= key_press; dip_d <= dip_change; step_d <= encoder_step;
            switch_d <= encoder_switch; ir_d <= ir_event; buzzer_n <= 1'b1;
        end
    end
endmodule
`endif
