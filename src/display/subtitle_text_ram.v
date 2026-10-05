`timescale 1ns/1ps

// Two banks x 32 five-bit glyph slot indexes.
module subtitle_text_ram (
    input  wire       wr_clk,
    input  wire       wr_en,
    input  wire [5:0] wr_addr,
    input  wire [4:0] wr_data,
    input  wire [5:0] rd_addr,
    output wire [4:0] rd_data
);
    reg [4:0] mem [0:63];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    assign rd_data = mem[rd_addr];
endmodule
