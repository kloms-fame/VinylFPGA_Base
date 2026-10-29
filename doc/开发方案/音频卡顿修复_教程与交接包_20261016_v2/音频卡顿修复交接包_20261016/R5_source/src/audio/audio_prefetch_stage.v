`ifndef VINYL_AUDIO_PREFETCH_STAGE_V
`define VINYL_AUDIO_PREFETCH_STAGE_V
`timescale 1ns/1ps
// One BRAM32K, shared by held-data mailboxes. No bulk RAM reset is needed:
// a complete sector is published only after its writer acknowledges completion.
module audio_prefetch_stage (
    input a_clk, a_en, a_we,
    input [9:0] a_addr,
    input [7:0] a_din,
    output [7:0] a_dout,
    input b_clk, b_en, b_we,
    input [9:0] b_addr,
    input [7:0] b_din,
    output [7:0] b_dout
);
`ifdef VINYL_AUDIO_CACHE_SIM
    reg [15:0] memory [0:2047];
    reg [7:0] qa=0, qb=0;
    assign a_dout=qa;
    assign b_dout=qb;
    always @(posedge a_clk) begin
        if (a_en) begin
            if (a_we) memory[{1'b0,a_addr}] <= {8'd0,a_din};
            else qa <= memory[{1'b0,a_addr}][7:0];
        end
    end
    always @(posedge b_clk) begin
        if (b_en) begin
            if (b_we) memory[{1'b0,b_addr}] <= {8'd0,b_din};
            else qb <= memory[{1'b0,b_addr}][7:0];
        end
    end
`else
    wire [15:0] qa,qb;
    assign a_dout=qa[7:0];
    assign b_dout=qb[7:0];
    EG_PHY_BRAM32K #(
        .MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.SRMODE("SYNC")
    ) storage (
        .clka(a_clk),.csa(a_en),.wea(a_we),.addra({1'b0,a_addr}),
        .dia({8'd0,a_din}),.doa(qa),.bytea(1'b0),.bytewea(1'b0),
        .rsta(1'b0),.ocea(1'b1),
        .clkb(b_clk),.csb(b_en),.web(b_we),.addrb({1'b0,b_addr}),
        .dib({8'd0,b_din}),.dob(qb),.byteb(1'b0),.byteweb(1'b0),
        .rstb(1'b0),.oceb(1'b1)
    );
`endif
endmodule
`endif
