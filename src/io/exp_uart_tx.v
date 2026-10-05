`ifndef EXP_EXP_UART_TX_V
`define EXP_EXP_UART_TX_V
// =============================================================================
// exp_uart_tx —— UART 发送字节引擎（移植自 J2 标定工程 uart_tx.v）
//
// 8N1，低有效起始位；tick 为 1 波特率节拍，start 单拍触发，done 单拍结束。
// 与 J2 标定工程逐字一致，仅模块名加 exp_ 前缀。
// =============================================================================
module exp_uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done
);
    reg [3:0] phase;
    reg [7:0] data_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx           <= 1'b1;
            busy         <= 1'b0;
            done         <= 1'b0;
            phase        <= 4'd0;
            data_latched <= 8'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                tx <= 1'b1;
                if (start) begin
                    data_latched <= data;
                    busy         <= 1'b1;
                    phase        <= 4'd0;
                end
            end else if (tick) begin
                case (phase)
                    4'd0: begin
                        tx    <= 1'b0;
                        phase <= 4'd1;
                    end
                    4'd1, 4'd2, 4'd3, 4'd4,
                    4'd5, 4'd6, 4'd7, 4'd8: begin
                        tx    <= data_latched[phase-1'b1];
                        phase <= phase + 1'b1;
                    end
                    4'd9: begin
                        tx    <= 1'b1;
                        phase <= 4'd10;
                    end
                    default: begin
                        tx    <= 1'b1;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        phase <= 4'd0;
                    end
                endcase
            end
        end
    end
endmodule
`endif
