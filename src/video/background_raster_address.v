`ifndef VINYL_BACKGROUND_RASTER_ADDRESS_V
`define VINYL_BACKGROUND_RASTER_ADDRESS_V
// Memory-clock raster advances on accepted read commands, independent of
// video FIFO consumption. A frame transaction freezes all address choices.
module background_raster_address (
    input wire clk, rst_n, latch, advance,
    input wire enable, media_mv, epoch,
    input wire [20:0] media_base, background_base,
    output reg enabled = 1'b0,
    output reg epoch_ack = 1'b0,
    output wire [20:0] address,
    output wire [8:0] contiguous_words,
    output reg span_ready = 1'b0,
    output wire cover_words,
    output wire background_words
);
    reg mv_q = 1'b0;
    reg [20:0] media_cursor = 21'd0;
    reg [20:0] background_cursor = 21'd0;
    reg [9:0] x = 10'd0;
    reg [8:0] y = 9'd0;
    reg cover_pair = 1'b0;
    wire in_media = x >= 10'd16 && x < 10'd336 &&
                    y >= 9'd48 && y < 9'd288;
    // Absolute cursors remove base+offset carry chains from the SDRAM port.
    // Covers read each even source row contiguously. Keep its even columns
    // before the read FIFO: two source commands produce one screen pixel.
    assign cover_words = enabled && !mv_q && in_media;
    assign background_words = enabled && !in_media;
    wire screen_advance = advance && (!cover_words || cover_pair);
    assign address = in_media ? media_cursor : background_cursor;
    // End a burst before switching source slot, screen row or physical
    // SDRAM column row. Each burst stays contiguous through the controller.
    wire media_row = y >= 9'd48 && y < 9'd288;
    wire [9:0] next_boundary = (media_row && x < 10'd16) ? 10'd16 :
                              (media_row && x < 10'd336) ? 10'd336 : 10'd640;
    wire [9:0] screen_span = next_boundary - x;
    wire [9:0] command_span = cover_words
        ? {screen_span[8:0],1'b0} - {9'd0,cover_pair} : screen_span;
    reg [7:0] column_index_q = 8'd0;
    reg [9:0] screen_span_q = 10'd0;
    // Burst preparation happens after the existing 10-cycle drain. Register
    // the span inputs there instead of placing add/subtract/compare in one
    // 125 MHz path. These registers never delay the issued pixel address.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) column_index_q <= 8'd0;
        else column_index_q <= address[7:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) screen_span_q <= 10'd0;
        else screen_span_q <= command_span;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) span_ready <= 1'b0;
        else span_ready <= !latch && !advance;
    end
    wire [8:0] column_span = 9'd256 - {1'b0,column_index_q};
    assign contiguous_words = (screen_span_q < {1'b0,column_span})
                             ? screen_span_q[8:0] : column_span;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enabled <= 1'b0;
        else if (latch) enabled <= enable;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) epoch_ack <= 1'b0;
        else if (latch) epoch_ack <= epoch;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mv_q <= 1'b0;
        else if (latch) mv_q <= media_mv;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) media_cursor <= 21'd0;
        else if (latch) media_cursor <= media_base;
        else if (advance && in_media)
            media_cursor <= media_cursor +
                ((cover_words && cover_pair && x == 10'd335) ? 21'd641 : 21'd1);
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cover_pair <= 1'b0;
        else if (latch) cover_pair <= 1'b0;
        else if (advance && cover_words) cover_pair <= !cover_pair;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) background_cursor <= 21'd0;
        else if (latch) background_cursor <= background_base;
        else if (screen_advance) background_cursor <= background_cursor + 21'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) x <= 10'd0;
        else if (latch) x <= 10'd0;
        else if (screen_advance) x <= (x == 10'd639) ? 10'd0 : x + 10'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) y <= 9'd0;
        else if (latch) y <= 9'd0;
        else if (screen_advance && x == 10'd639) y <= y + 9'd1;
    end
endmodule
`endif
