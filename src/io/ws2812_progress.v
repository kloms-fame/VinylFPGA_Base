`ifndef EXP_WS2812_PROGRESS_V
`define EXP_WS2812_PROGRESS_V
// Exact floor(8 * position / total), saturated to 0..8. Three serial
// fractional division steps share a subtractor; no combinational divider.
// Source inputs belong to src_clk. Hold the result until dst_clk acknowledges.
module ws2812_progress (
    input wire src_clk, src_rst_n,
    input wire [31:0] position, total,
    input wire dst_clk, dst_rst_n,
    output reg [3:0] progress
);
    localparam IDLE=0, SUBTRACT=1, ACCUMULATE=2, PUBLISH=3;
    reg [1:0] state;
    reg [31:0] remaining, denominator;
    reg [33:0] difference;
    reg [1:0] step;
    reg [2:0] fraction;
    reg [3:0] payload;
    reg request, acknowledge;
    reg [1:0] ack_sync, req_sync;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) ack_sync <= 0;
        else ack_sync <= {ack_sync[0],acknowledge};
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) req_sync <= 0;
        else req_sync <= {req_sync[0],request};
    end
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            state<=IDLE; remaining<=0; denominator<=0; difference<=0;
            step<=0; fraction<=0; payload<=0; request<=0;
        end else case (state)
            IDLE: if (ack_sync[1] == request) begin
                remaining<=position; denominator<=total; fraction<=0; step<=0;
                if (total == 0 || position >= total) begin
                    payload <= total == 0 ? 4'd0 : 4'd8;
                    state <= PUBLISH;
                end else state <= SUBTRACT;
            end
            SUBTRACT: begin
                difference <= {1'b0,remaining,1'b0} - {2'b0,denominator};
                state <= ACCUMULATE;
            end
            ACCUMULATE: begin
                remaining <= difference[33] ? {remaining[30:0],1'b0} : difference[31:0];
                fraction <= {fraction[1:0],!difference[33]};
                if (step == 2) begin
                    payload <= {1'b0,fraction[1:0],!difference[33]};
                    state <= PUBLISH;
                end else begin step <= step + 1'b1; state <= SUBTRACT; end
            end
            PUBLISH: begin request <= ~request; state <= IDLE; end
            default: state <= IDLE;
        endcase
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) acknowledge <= 0;
        else if (req_sync[1] != acknowledge) acknowledge <= req_sync[1];
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) progress <= 0;
        else if (req_sync[1] != acknowledge) progress <= payload;
    end
endmodule
`endif
