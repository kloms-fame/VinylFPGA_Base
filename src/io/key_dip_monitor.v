`ifndef EXP_KEY_DIP_MONITOR_V
`define EXP_KEY_DIP_MONITOR_V
module key_dip_monitor #(
    parameter integer KEY_COUNT       = 12,
    parameter integer DIP_COUNT       = 6,
    parameter integer DEBOUNCE_CYCLES = 400_000,
    parameter integer DEBOUNCE_TICK_CYCLES = (DEBOUNCE_CYCLES < 5000) ? 1 : 5000,
    parameter integer USE_EXTERNAL_TICK = 0
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                debounce_ce,
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
    localparam integer STABLE_TICKS = (DEBOUNCE_CYCLES + DEBOUNCE_TICK_CYCLES - 1) / DEBOUNCE_TICK_CYCLES;
    localparam integer SETTLE_CYCLES = (STABLE_TICKS + 1) * DEBOUNCE_TICK_CYCLES + 8;
    localparam integer SETTLE_W = $clog2(SETTLE_CYCLES + 1);
    reg [SETTLE_W-1:0] settle_count = 0;
    reg dip_initialized = 1'b0;
    integer              i;

    wire local_ce;
    wire tick_ce;
    generate
        if (USE_EXTERNAL_TICK) begin: g_external_tick
            assign local_ce = 1'b0;
        end else begin: g_local_tick
            debounce_tick #(.TICK_CYCLES(DEBOUNCE_TICK_CYCLES)) u_tick (
                .clk(clk), .rst_n(rst_n), .tick_ce(local_ce)
            );
        end
    endgenerate
    assign tick_ce = USE_EXTERNAL_TICK ? debounce_ce : local_ce;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            settle_count <= 0;
        else if (!dip_initialized)
            settle_count <= settle_count + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dip_initialized <= 1'b0;
        else if (settle_count == SETTLE_CYCLES-1)
            dip_initialized <= 1'b1;
    end

    debounce_bank #(
        .CHANNELS(KEY_COUNT + DIP_COUNT),
        .STABLE_TICKS(STABLE_TICKS),
        .INITIAL_LEVEL(1'b1)
    ) u_debounce_bank (
        .clk(clk), .rst_n(rst_n), .tick_ce(tick_ce),
        .async_in({dip_async, key_async}),
        .level({dip_level, key_level}),
        .fall_pulse({dip_fall_pulse, key_fall_pulse}),
        .rise_pulse({dip_rise_pulse, key_rise_pulse})
    );

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
