`ifndef EXP_DEBOUNCE_TICK_V
`define EXP_DEBOUNCE_TICK_V
// Shared clock enable. All users remain in the clk domain.
module debounce_tick #(
    parameter integer TICK_CYCLES = 5000
)(
    input wire clk,
    input wire rst_n,
    output wire tick_ce
);
    localparam integer COUNT_W = (TICK_CYCLES > 1) ? $clog2(TICK_CYCLES) : 1;
    reg [COUNT_W-1:0] count = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 0;
        else if (count == TICK_CYCLES-1)
            count <= 0;
        else
            count <= count + 1'b1;
    end

    assign tick_ce = rst_n && (count == TICK_CYCLES-1);
endmodule
`endif
