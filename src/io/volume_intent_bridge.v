`ifndef EXP_VOLUME_INTENT_BRIDGE_V
`define EXP_VOLUME_INTENT_BRIDGE_V
// Eight-entry asynchronous FIFO carrying accepted PLAY-domain volume directions.
module volume_intent_bridge (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_valid,
    input  wire src_up,
    output wire src_ready,
    output reg  src_overflow,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_valid,
    output wire dst_up,
    input  wire dst_ready
);
    localparam integer ADDR_W = 3;
    localparam integer PTR_W  = ADDR_W + 1;

    reg [0:0] direction_mem [0:7];
    reg [PTR_W-1:0] wr_bin;
    reg [PTR_W-1:0] wr_gray;
    reg [PTR_W-1:0] rd_bin;
    reg [PTR_W-1:0] rd_gray;
    (* async_reg = "true" *) reg [PTR_W-1:0] rd_gray_src_meta;
    (* async_reg = "true" *) reg [PTR_W-1:0] rd_gray_src_sync;
    (* async_reg = "true" *) reg [PTR_W-1:0] wr_gray_dst_meta;
    (* async_reg = "true" *) reg [PTR_W-1:0] wr_gray_dst_sync;

    wire [PTR_W-1:0] wr_bin_next  = wr_bin + 1'b1;
    wire [PTR_W-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire fifo_full = (wr_gray == {~rd_gray_src_sync[PTR_W-1:PTR_W-2],
                                   rd_gray_src_sync[PTR_W-3:0]});
    wire fifo_empty = (rd_gray == wr_gray_dst_sync);
    wire [ADDR_W-1:0] rd_addr = rd_bin[ADDR_W-1:0];

    assign src_ready = !fifo_full;
    assign dst_valid = !fifo_empty;
    assign dst_up    = direction_mem[rd_addr];

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            wr_bin          <= {PTR_W{1'b0}};
            wr_gray         <= {PTR_W{1'b0}};
            rd_gray_src_meta<= {PTR_W{1'b0}};
            rd_gray_src_sync<= {PTR_W{1'b0}};
            src_overflow    <= 1'b0;
        end else begin
            rd_gray_src_meta <= rd_gray;
            rd_gray_src_sync <= rd_gray_src_meta;
            if (src_valid && src_ready) begin
                direction_mem[wr_bin[ADDR_W-1:0]] <= src_up;
                wr_bin  <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
            if (src_valid && !src_ready)
                src_overflow <= 1'b1;
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            rd_bin          <= {PTR_W{1'b0}};
            rd_gray         <= {PTR_W{1'b0}};
            wr_gray_dst_meta<= {PTR_W{1'b0}};
            wr_gray_dst_sync<= {PTR_W{1'b0}};
        end else begin
            wr_gray_dst_meta <= wr_gray;
            wr_gray_dst_sync <= wr_gray_dst_meta;
            if (dst_valid && dst_ready) begin
                rd_bin  <= rd_bin + 1'b1;
                rd_gray <= ((rd_bin + 1'b1) >> 1) ^ (rd_bin + 1'b1);
            end
        end
    end
endmodule
`endif
