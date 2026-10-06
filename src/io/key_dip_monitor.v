`ifndef EXP_KEY_DIP_MONITOR_V
`define EXP_KEY_DIP_MONITOR_V
module key_dip_monitor #(
    parameter integer KEY_COUNT       = 12,
    parameter integer DIP_COUNT       = 6,
    parameter integer DEBOUNCE_CYCLES = 400_000
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [KEY_COUNT-1:0] key_async,
    input  wire [DIP_COUNT-1:0] dip_async,
    output wire [KEY_COUNT-1:0] key_level,
    output wire [KEY_COUNT-1:0] key_fall_pulse,
    output wire [KEY_COUNT-1:0] key_rise_pulse,
    output wire [DIP_COUNT-1:0] dip_level,
    output wire [DIP_COUNT-1:0] dip_change_pulse,
    output reg  [2:0]           dip_change_index
);
    wire [DIP_COUNT-1:0] dip_fall_pulse;
    wire [DIP_COUNT-1:0] dip_rise_pulse;
    // Reset settling establishes initial configuration, not a user action.
    localparam integer SETTLE_CYCLES = DEBOUNCE_CYCLES + 8;
    localparam integer SETTLE_W = $clog2(SETTLE_CYCLES + 1);
    reg [SETTLE_W-1:0] settle_count;
    reg dip_initialized;
    integer              i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            settle_count <= 0;
            dip_initialized <= 1'b0;
        end else if (!dip_initialized) begin
            if (settle_count == SETTLE_CYCLES-1)
                dip_initialized <= 1'b1;
            else
                settle_count <= settle_count + 1'b1;
        end
    end

    genvar key_index;
    generate
        for (key_index = 0; key_index < KEY_COUNT; key_index = key_index + 1) begin: g_key_filter
            debounce_filter #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
                .INITIAL_LEVEL  (1'b1)
            ) u_debounce (
                .clk       (clk),
                .rst_n     (rst_n),
                .async_in  (key_async[key_index]),
                .level     (key_level[key_index]),
                .fall_pulse(key_fall_pulse[key_index]),
                .rise_pulse(key_rise_pulse[key_index])
            );
        end
    endgenerate

    genvar dip_index;
    generate
        for (dip_index = 0; dip_index < DIP_COUNT; dip_index = dip_index + 1) begin: g_dip_filter
            debounce_filter #(
                .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
                .INITIAL_LEVEL  (1'b1)
            ) u_debounce (
                .clk       (clk),
                .rst_n     (rst_n),
                .async_in  (dip_async[dip_index]),
                .level     (dip_level[dip_index]),
                .fall_pulse(dip_fall_pulse[dip_index]),
                .rise_pulse(dip_rise_pulse[dip_index])
            );
        end
    endgenerate

    assign dip_change_pulse = (dip_fall_pulse | dip_rise_pulse) & {DIP_COUNT{dip_initialized}};

    always @* begin
        dip_change_index = 3'd0;
        for (i = DIP_COUNT - 1; i >= 0; i = i - 1) begin
            if (dip_change_pulse[i])
                dip_change_index = i[2:0];
        end
    end
endmodule
`endif
