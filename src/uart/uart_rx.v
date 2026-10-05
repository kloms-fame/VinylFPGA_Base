`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            data      <= 8'd0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (!rx) begin
                        clk_count <= CLKS_PER_BIT / 2;
                        state     <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_count == 16'd0) begin
                        if (!rx) begin
                            clk_count <= CLKS_PER_BIT - 1;
                            state     <= ST_DATA;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count - 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count == 16'd0) begin
                        shift_reg[bit_index] <= rx;
                        clk_count <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_index <= bit_index + 3'd1;
                    end else begin
                        clk_count <= clk_count - 16'd1;
                    end
                end

                default: begin
                    if (clk_count == 16'd0) begin
                        if (rx) begin
                            data  <= shift_reg;
                            valid <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end else begin
                        clk_count <= clk_count - 16'd1;
                    end
                end
            endcase
        end
    end
endmodule
