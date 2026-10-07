`ifndef EXP_DEBOUNCE_BANK_V
`define EXP_DEBOUNCE_BANK_V
// The first tick arms a channel; STABLE_TICKS complete intervals follow.
// Between ticks, every synchronized return to level cancels that channel.
module debounce_bank #(
    parameter integer CHANNELS = 1,
    parameter integer STABLE_TICKS = 80,
    parameter INITIAL_LEVEL = 1'b1
)(
    input wire clk,
    input wire rst_n,
    input wire tick_ce,
    input wire [CHANNELS-1:0] async_in,
    output reg [CHANNELS-1:0] level = {CHANNELS{INITIAL_LEVEL}},
    output reg [CHANNELS-1:0] fall_pulse = 0,
    output reg [CHANNELS-1:0] rise_pulse = 0
);
    localparam integer COUNT_W = (STABLE_TICKS > 1) ? $clog2(STABLE_TICKS+1) : 1;
    reg [CHANNELS-1:0] sync_meta = {CHANNELS{INITIAL_LEVEL}};
    reg [CHANNELS-1:0] sync_value = {CHANNELS{INITIAL_LEVEL}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_meta <= {CHANNELS{INITIAL_LEVEL}};
        else
            sync_meta <= async_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_value <= {CHANNELS{INITIAL_LEVEL}};
        else
            sync_value <= sync_meta;
    end

    genvar channel;
    generate
        for (channel = 0; channel < CHANNELS; channel = channel + 1) begin: g_channel
            // Zero also represents unarmed, so no extra candidate/armed FF is needed.
            reg [COUNT_W-1:0] stable_count = 0;
            wire accept = tick_ce && (sync_value[channel] != level[channel]) &&
                          (stable_count == STABLE_TICKS);

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    stable_count <= 0;
                else if ((sync_value[channel] == level[channel]) || accept)
                    stable_count <= 0;
                else if (tick_ce)
                    stable_count <= stable_count + 1'b1;
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    level[channel] <= INITIAL_LEVEL;
                else if (accept)
                    level[channel] <= sync_value[channel];
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    fall_pulse[channel] <= 1'b0;
                else
                    fall_pulse[channel] <= accept && !sync_value[channel];
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    rise_pulse[channel] <= 1'b0;
                else
                    rise_pulse[channel] <= accept && sync_value[channel];
            end
        end
    endgenerate
endmodule
`endif
