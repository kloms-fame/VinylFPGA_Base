`ifndef EXP_SYNC_BIT_V
`define EXP_SYNC_BIT_V
module sync_bit (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);
    reg meta;
    reg sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            meta <= 1'b1;
        else
            meta <= async_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync <= 1'b1;
        else
            sync <= meta;
    end

    assign sync_out = sync;
endmodule
`endif
