`ifndef VINYL_AUDIO_SDRAM_ARBITER_V
`define VINYL_AUDIO_SDRAM_ARBITER_V
`timescale 1ns/1ps
// The encrypted controller applies App_wr_dm to READ outputs too. Keep the
// selected mask through queued writes, then clear it before allowing any read.
module audio_sdram_arbiter #(
    parameter integer WRITE_DRAIN_CYCLES=16
)(
    input mem_clk,rst_n,controller_busy,refresh_active,mem_read_valid,
    input audio_lock,audio_read_owner,
    input graphics_wr_en,graphics_rd_en,
    input [20:0] graphics_wr_addr,graphics_rd_addr,
    input [31:0] graphics_wr_data,
    input audio_wr_en,audio_rd_en,
    input [20:0] audio_wr_addr,audio_rd_addr,
    input [31:0] audio_wr_data,
    input [3:0] audio_wr_mask,
    output graphics_stall,write_tail_busy,graphics_read_valid,
    output mem_wr_en,mem_rd_en,
    output [20:0] mem_wr_addr,mem_rd_addr,
    output [31:0] mem_wr_data,
    output [3:0] mem_wr_mask
);
    localparam integer COUNT_BITS=(WRITE_DRAIN_CYCLES<2)?1:$clog2(WRITE_DRAIN_CYCLES+1);
    reg [COUNT_BITS-1:0] quiet_count=0;
    reg [3:0] held_mask=0;
    reg tail_active=0;
    wire wr=graphics_wr_en || audio_wr_en;
    wire quiet=!controller_busy && !refresh_active && !mem_read_valid && !wr;
    wire drained=quiet && quiet_count>=WRITE_DRAIN_CYCLES-1;
    assign graphics_stall=audio_lock || write_tail_busy;
    assign write_tail_busy=tail_active || wr;
    assign graphics_read_valid=mem_read_valid && !audio_read_owner;
    // Lock acquisition does not interrupt a graphics burst already in flight.
    // Select only actual audio strobes, never the lock itself.
    assign mem_wr_en=wr;
    assign mem_wr_addr=audio_wr_en ? audio_wr_addr : graphics_wr_addr;
    assign mem_wr_data=audio_wr_en ? audio_wr_data : graphics_wr_data;
    assign mem_wr_mask=audio_wr_en ? audio_wr_mask :
                       graphics_wr_en ? 4'b0001 : tail_active ? held_mask : 4'b0000;
    assign mem_rd_en=graphics_rd_en || audio_rd_en;
    assign mem_rd_addr=audio_rd_en ? audio_rd_addr : graphics_rd_addr;
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) tail_active<=0;
        else if (wr) tail_active<=1;
        else if (drained) tail_active<=0;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) held_mask<=0;
        else if (wr) held_mask<=audio_wr_en ? audio_wr_mask : 4'b0001;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) quiet_count<=0;
        else if (!tail_active || !quiet) quiet_count<=0;
        else if (!drained) quiet_count<=quiet_count+1'b1;
    end
endmodule
`endif
