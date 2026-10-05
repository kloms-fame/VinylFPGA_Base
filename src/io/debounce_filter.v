`ifndef EXP_DEBOUNCE_FILTER_V
`define EXP_DEBOUNCE_FILTER_V
module debounce_filter #(
    parameter integer DEBOUNCE_CYCLES = 400_000,
    parameter         INITIAL_LEVEL   = 1'b1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output reg  level,
    output reg  fall_pulse,
    output reg  rise_pulse
);
    wire       sync_value;
    reg [19:0] stable_cnt;

    sync_bit u_sync_bit (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (async_in),
        .sync_out (sync_value)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level      <= INITIAL_LEVEL;
            stable_cnt <= 20'd0;
            fall_pulse <= 1'b0;
            rise_pulse <= 1'b0;
        end else begin
            fall_pulse <= 1'b0;
            rise_pulse <= 1'b0;

            if (sync_value == level) begin
                stable_cnt <= 20'd0;
            end else if (stable_cnt == DEBOUNCE_CYCLES - 1) begin
                stable_cnt <= 20'd0;
                level      <= sync_value;
                if (sync_value)
                    rise_pulse <= 1'b1;
                else
                    fall_pulse <= 1'b1;
            end else begin
                stable_cnt <= stable_cnt + 1'b1;
            end
        end
    end
endmodule
`endif
