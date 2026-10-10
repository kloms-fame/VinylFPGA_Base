`ifndef EXP_UI_MS_TICK_V
`define EXP_UI_MS_TICK_V
// Shared 1 ms clock enable for the 50 MHz UI/control domain.
module ui_ms_tick #(
    parameter integer CYCLES_PER_MS = 50000
)(
    input  wire clk,
    input  wire rst_n,
    output wire tick_1ms
);
    reg [15:0] cycle_count;

    assign tick_1ms = rst_n && (cycle_count == CYCLES_PER_MS - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 16'd0;
        else if (cycle_count >= CYCLES_PER_MS - 1)
            cycle_count <= 16'd0;
        else
            cycle_count <= cycle_count + 1'b1;
    end
endmodule
`endif
