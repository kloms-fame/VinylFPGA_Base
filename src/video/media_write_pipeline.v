`ifndef VINYL_MEDIA_WRITE_PIPELINE_V
`define VINYL_MEDIA_WRITE_PIPELINE_V
// One SD-clock stage for the shared FIFO write token. Owner arbitration and
// writer completion remain upstream; valid and its pixel always move together.
module media_write_pipeline (
    input wire clk, rst_n, background_owner, mv_owner,
    input wire background_valid, mv_valid, cover_valid,
    input wire [31:0] background_data, mv_data, cover_data,
    output reg pixel_valid = 1'b0,
    output reg [31:0] pixel_data = 32'd0
);
    wire selected_valid = background_owner ? background_valid :
                          mv_owner ? mv_valid : cover_valid;
    wire [31:0] selected_data = background_owner ? background_data :
                               mv_owner ? mv_data : cover_data;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pixel_valid <= 1'b0;
        else pixel_valid <= selected_valid;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pixel_data <= 32'd0;
        else pixel_data <= selected_data;
    end
endmodule
`endif
