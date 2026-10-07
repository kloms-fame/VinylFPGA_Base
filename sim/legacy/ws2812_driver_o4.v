// Frozen from 6ffce23; module/include guards renamed only.
`ifndef EXP_WS2812_DRIVER_O4_V
`define EXP_WS2812_DRIVER_O4_V
// =============================================================================
// ws2812_driver_o4 —— X1B：WS2812 单线 NRZ 串行器（8 颗串联）
//
// 移植自 D:\Data_Backup\VinylFPGA_Workspace_Base\资源\Expansion_Board_Test\src\
// ws2812_driver_o4.v 的时序状态机（RESET -> BIT_HIGH -> BIT_LOW -> RESET），
// 但把接口从"逐像素/全屏单色写命令"改为"整帧锁存":
//   load=1 时锁存 grb_in（PIXEL_COUNT*24 bit，已做 RGB->GRB 转换），
//   随后自动按 800 kHz 时序把整条灯带推完，busy 拉低表示本帧结束。
//
// 50 MHz 时钟下的时序取值（对标 WS2812B：T0H 0.4us / T1H 0.8us / T 1.25us）：
//   BIT_CYCLES   = 63 -> 1.260 us/bit -> 793.7 kHz（-0.8%，在灯珠容差内）
//   T0H_CYCLES   = 18 -> 0.360 us
//   T1H_CYCLES   = 35 -> 0.700 us
//   RESET_CYCLES = 3000 -> 60 us（> 50 us 锁存门限）
// =============================================================================
module ws2812_driver_o4 #(
    parameter integer PIXEL_COUNT  = 8,
    parameter integer BIT_CYCLES   = 63,
    parameter integer T0H_CYCLES   = 18,
    parameter integer T1H_CYCLES   = 35,
    parameter integer RESET_CYCLES = 3000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load,                             // 1 拍：锁存整帧并开始发射
    input  wire [PIXEL_COUNT*24-1:0] grb_in,             // GRB 顺序，高位先发
    output reg         busy,
    output reg         dout
);
    localparam [2:0] ST_IDLE         = 3'd0;
    localparam [2:0] ST_RESET_BEFORE = 3'd1;
    localparam [2:0] ST_BIT_HIGH     = 3'd2;
    localparam [2:0] ST_BIT_LOW      = 3'd3;
    localparam [2:0] ST_RESET_AFTER  = 3'd4;

    localparam integer PIX_W = (PIXEL_COUNT <= 2)  ? 1 :
                              (PIXEL_COUNT <= 4)  ? 2 :
                              (PIXEL_COUNT <= 8)  ? 3 :
                              (PIXEL_COUNT <= 16) ? 4 : 5;

    reg [23:0]       pixel_mem [0:PIXEL_COUNT-1];
    reg [2:0]        state;
    reg [PIX_W-1:0]  pixel_index;
    reg [4:0]        bit_in_pixel;
    reg [7:0]        cycle_count;
    reg [7:0]        low_cycles;
    reg [15:0]       reset_count;
    integer          i;

    wire [23:0] current_color = pixel_mem[pixel_index];
    wire        current_bit   = current_color[5'd23 - bit_in_pixel];
    wire [7:0]  high_cycles   = current_bit ? T1H_CYCLES[7:0] : T0H_CYCLES[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            pixel_index  <= {PIX_W{1'b0}};
            bit_in_pixel <= 5'd0;
            cycle_count  <= 8'd0;
            low_cycles   <= 8'd0;
            reset_count  <= 16'd0;
            busy         <= 1'b0;
            dout         <= 1'b0;
            for (i = 0; i < PIXEL_COUNT; i = i + 1)
                pixel_mem[i] <= 24'd0;
        end else begin
            if (load && (state == ST_IDLE)) begin
                for (i = 0; i < PIXEL_COUNT; i = i + 1)
                    pixel_mem[i] <= grb_in[i*24 +: 24];
            end

            case (state)
                ST_IDLE: begin
                    dout        <= 1'b0;
                    cycle_count <= 8'd0;
                    if (load) begin
                        state       <= ST_RESET_BEFORE;
                        busy        <= 1'b1;
                        reset_count <= 16'd0;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                ST_RESET_BEFORE: begin
                    dout <= 1'b0;
                    if (reset_count == (RESET_CYCLES - 1)) begin
                        reset_count  <= 16'd0;
                        pixel_index  <= {PIX_W{1'b0}};
                        bit_in_pixel <= 5'd0;
                        state        <= ST_BIT_HIGH;
                    end else begin
                        reset_count <= reset_count + 1'b1;
                    end
                end

                ST_BIT_HIGH: begin
                    dout <= 1'b1;
                    if (cycle_count == (high_cycles - 1'b1)) begin
                        cycle_count <= 8'd0;
                        low_cycles  <= BIT_CYCLES[7:0] - high_cycles;
                        state       <= ST_BIT_LOW;
                    end else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                ST_BIT_LOW: begin
                    dout <= 1'b0;
                    if (cycle_count == (low_cycles - 1'b1)) begin
                        cycle_count <= 8'd0;
                        if ((pixel_index == (PIXEL_COUNT - 1)) &&
                            (bit_in_pixel == 5'd23)) begin
                            state <= ST_RESET_AFTER;
                        end else begin
                            state <= ST_BIT_HIGH;
                            if (bit_in_pixel == 5'd23) begin
                                bit_in_pixel <= 5'd0;
                                pixel_index  <= pixel_index + 1'b1;
                            end else begin
                                bit_in_pixel <= bit_in_pixel + 1'b1;
                            end
                        end
                    end else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                ST_RESET_AFTER: begin
                    dout <= 1'b0;
                    if (reset_count == (RESET_CYCLES - 1)) begin
                        reset_count <= 16'd0;
                        state       <= ST_IDLE;
                        busy        <= 1'b0;
                    end else begin
                        reset_count <= reset_count + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    dout  <= 1'b0;
                end
            endcase
        end
    end
endmodule
`endif
