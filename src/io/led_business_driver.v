`ifndef EXP_LED_BUSINESS_DRIVER_V
`define EXP_LED_BUSINESS_DRIVER_V
// Physical board: LED4 RUN heartbeat/fault, LED3 IR pulse,
// LED2 MV active, LED1 accepted operation pulse. All active low; DIP3 gates all.
module led_business_driver #(
    parameter integer CLK_FREQ_HZ  = 50_000_000,
    parameter integer PULSE_MS     = 80,   // LED1/LED2 单次亮灯时长
    parameter integer HEARTBEAT_MS = 500   // LED3 半周期（500 ms -> 1 Hz）
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       en,            // DIP3 LED 总使能（上拨=1）
    input  wire       ir_accepted,   // 有效红外（反码+白名单+DIP5 通过）单拍
    input  wire       biz_accepted,  // 已接受业务动作单拍
    input  wire       mv_active,
    input  wire       fault,         // 当前故障（err_code != 0）

    output reg  [3:0] led_n          // LED1..LED4，低有效点亮
);
    localparam integer MS_CYCLES = CLK_FREQ_HZ / 1000;
    localparam integer MS_W      = $clog2(MS_CYCLES + 1);
    localparam integer PULSE_W   = $clog2(PULSE_MS + 1);
    localparam integer HB_W      = $clog2(HEARTBEAT_MS * 2 + 1);
    localparam integer HB_HALF   = HEARTBEAT_MS;

    reg [MS_W-1:0]    ms_div;
    reg [PULSE_W-1:0] ir_ms;
    reg [PULSE_W-1:0] biz_ms;
    reg [HB_W-1:0]    hb_ms;

    wire ms_tick = (ms_div >= (MS_CYCLES - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div   <= {MS_W{1'b0}};
            ir_ms    <= {PULSE_W{1'b0}};
            biz_ms   <= {PULSE_W{1'b0}};
            hb_ms    <= {HB_W{1'b0}};
        end else if (!en) begin
            // DIP3 关闭：清计时，保证重新打开时没有残留脉冲
            ms_div  <= {MS_W{1'b0}};
            ir_ms   <= {PULSE_W{1'b0}};
            biz_ms  <= {PULSE_W{1'b0}};
            hb_ms   <= {HB_W{1'b0}};
        end else begin
            if (ms_tick)
                ms_div <= {MS_W{1'b0}};
            else
                ms_div <= ms_div + 1'b1;

            if (ir_accepted)
                ir_ms <= PULSE_MS[PULSE_W-1:0];
            else if (ms_tick && ir_ms != {PULSE_W{1'b0}})
                ir_ms <= ir_ms - 1'b1;

            if (biz_accepted)
                biz_ms <= PULSE_MS[PULSE_W-1:0];
            else if (ms_tick && biz_ms != {PULSE_W{1'b0}})
                biz_ms <= biz_ms - 1'b1;

            if (ms_tick) begin
                if (hb_ms >= (HEARTBEAT_MS * 2 - 1))
                    hb_ms <= {HB_W{1'b0}};
                else
                    hb_ms <= hb_ms + 1'b1;
            end
        end
    end

    wire ir_on = (ir_ms  != {PULSE_W{1'b0}});
    wire bi_on = (biz_ms != {PULSE_W{1'b0}});
    wire hb_on = (hb_ms < HB_HALF);

    // Board silk: bit3=LED4 RUN (heartbeat/fault), bit2=LED3 IR, bit1=LED2 MV, bit0=LED1 ACTION.
    always @* begin
        if (!en)
            led_n = 4'hF;
        else
            led_n = ~{(fault | hb_on), ir_on, mv_active, bi_on};
    end
endmodule
`endif
