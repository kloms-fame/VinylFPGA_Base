`ifndef EXP_UI_PARAM_CSR_V
`define EXP_UI_PARAM_CSR_V
// The sole writable volume register. op_up=1 increments; op_up=0 decrements.
module ui_param_csr #(
    parameter [7:0] DEFAULT_VOLUME = 8'd200,
    parameter [7:0] VOLUME_STEP    = 8'd16
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_valid,
    input  wire       wr_up,
    output reg  [7:0] volume,
    output reg        volume_update
);
    wire [8:0] volume_up_sum = {1'b0, volume} + {1'b0, VOLUME_STEP};
    wire [7:0] volume_up_next = (volume_up_sum > 9'd255) ? 8'd255 : volume_up_sum[7:0];
    wire [7:0] volume_dn_next = ({1'b0, volume} < {1'b0, VOLUME_STEP})
                              ? 8'd0 : volume - VOLUME_STEP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            volume        <= DEFAULT_VOLUME;
            volume_update <= 1'b0;
        end else begin
            volume_update <= 1'b0;
            if (wr_valid) begin
                if (wr_up && (volume_up_next != volume)) begin
                    volume        <= volume_up_next;
                    volume_update <= 1'b1;
                end else if (!wr_up && (volume_dn_next != volume)) begin
                    volume        <= volume_dn_next;
                    volume_update <= 1'b1;
                end
            end
        end
    end
endmodule
`endif
