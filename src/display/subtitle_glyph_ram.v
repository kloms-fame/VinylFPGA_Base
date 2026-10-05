`timescale 1ns/1ps

// Two banks x 32 slots x 16 rows x 16 bits.
module subtitle_glyph_ram (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [9:0]  wr_addr,
    input  wire [15:0] wr_data,
    input  wire        rd_clk,
    input  wire [9:0]  rd_addr,
    output reg  [15:0] rd_data
);
    (* ram_style = "bram" *)
    reg [15:0] mem [0:1023];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule
