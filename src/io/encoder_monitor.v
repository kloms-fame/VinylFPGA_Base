`ifndef EXP_ENCODER_MONITOR_V
`define EXP_ENCODER_MONITOR_V
module encoder_monitor #(
    parameter integer DEBOUNCE_CYCLES  = 400_000,
    parameter integer AB_STABLE_CYCLES = 50_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enc1_a_async,
    input  wire        enc1_b_async,
    input  wire        enc1_sw_async,
    input  wire        enc2_a_async,
    input  wire        enc2_b_async,
    input  wire        enc2_sw_async,
    output wire        enc1_step_pulse,
    output wire        enc1_direction,
    output wire [15:0] enc1_count,
    output wire        enc1_sw_level,
    output wire        enc1_sw_fall_pulse,
    output wire        enc1_sw_rise_pulse,
    output wire        enc2_step_pulse,
    output wire        enc2_direction,
    output wire [15:0] enc2_count,
    output wire        enc2_sw_level,
    output wire        enc2_sw_fall_pulse,
    output wire        enc2_sw_rise_pulse
);
    quadrature_decoder #(
        .STABLE_CYCLES(AB_STABLE_CYCLES)
    ) u_enc1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .a_async    (enc1_a_async),
        .b_async    (enc1_b_async),
        .step_pulse (enc1_step_pulse),
        .direction  (enc1_direction),
        .count      (enc1_count)
    );

    quadrature_decoder #(
        .STABLE_CYCLES(AB_STABLE_CYCLES)
    ) u_enc2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .a_async    (enc2_a_async),
        .b_async    (enc2_b_async),
        .step_pulse (enc2_step_pulse),
        .direction  (enc2_direction),
        .count      (enc2_count)
    );

    debounce_filter #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .INITIAL_LEVEL  (1'b1)
    ) u_enc1_sw (
        .clk       (clk),
        .rst_n     (rst_n),
        .async_in  (enc1_sw_async),
        .level     (enc1_sw_level),
        .fall_pulse(enc1_sw_fall_pulse),
        .rise_pulse(enc1_sw_rise_pulse)
    );

    debounce_filter #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .INITIAL_LEVEL  (1'b1)
    ) u_enc2_sw (
        .clk       (clk),
        .rst_n     (rst_n),
        .async_in  (enc2_sw_async),
        .level     (enc2_sw_level),
        .fall_pulse(enc2_sw_fall_pulse),
        .rise_pulse(enc2_sw_rise_pulse)
    );
endmodule
`endif
