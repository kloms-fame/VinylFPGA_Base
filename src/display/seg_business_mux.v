`ifndef EXP_SEG_BUSINESS_MUX_V
`define EXP_SEG_BUSINESS_MUX_V
// =============================================================================
// seg_business_mux —— X1C：6 位数码管业务 mux（sd_card_clk 域）
//
// 与 seg_scan 同域（sd_card_clk），直接给出 6 位段码，避免在扫描器上再引入
// 跨时钟域路径。段码约定与 seg_scan/工程既有 hex7seg 完全一致：
//   seg_data[7]   = 小数点（1=灭）
//   seg_data[6:0] = a..g 段，低有效（0=点亮）
//
// 位编号约定（待上板按丝印核对）：seg_data_0 = 最左，seg_data_5 = 最右。
//
// 显示优先级（《方案》X1C）：
//   1. 当前故障码      ：error_code != 0 -> "E" + 2 位十六进制；恢复 0 后退出；
//   2. 2 s 参数临时值  ：param_valid 保持期间及之后 2 s（X5 前 valid 恒 0）；
//   3. 选择项          ：KEY3 在 MM:SS / 曲目编号 / 诊断项之间循环；
//                        未播放时无论选择项一律显示曲目编号；
//                        诊断项受 SW3(debug_sw) 控制，故障页不受 SW3 影响。
//
// MM:SS 用 BCD 计数器直接维护（不引入除法器），在 99:59 饱和；
// 计时只在 play_active && !paused 时推进，track_step 单拍归零。
// display_enable=0（SW1 关）时 6 位全灭，且不推进计时。
// =============================================================================
module seg_business_mux #(
    parameter integer CLK_FREQ_HZ   = 100_000_000,
    parameter integer PARAM_HOLD_MS = 2000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        display_enable,   // SW1 归一化后：1=点亮数码管
    input  wire        mode_tgl,         // KEY3 翻转电平（本域，内部再做边沿检测）
    input  wire        debug_sw,         // SW3：诊断项显示开关

    input  wire [7:0]  error_code,       // 本域当前故障码（0=无故障）
    input  wire        param_valid,      // 参数临时显示请求（X5 前恒 0）
    input  wire [15:0] param_value,

    input  wire        play_active,      // 本域：播放中
    input  wire        paused,           // 本域：暂停
    input  wire        track_step,       // 本域：切曲单拍 -> 计时归零
    input  wire [1:0]  song_index,       // 本域：当前曲目 0..3

    output reg  [7:0]  seg_data_0,
    output reg  [7:0]  seg_data_1,
    output reg  [7:0]  seg_data_2,
    output reg  [7:0]  seg_data_3,
    output reg  [7:0]  seg_data_4,
    output reg  [7:0]  seg_data_5
);
    localparam [6:0] SEG_BLANK = 7'b111_1111;

    function [6:0] hex7seg;
        input [3:0] v;
        begin
            case (v)
                4'h0:    hex7seg = 7'b100_0000;
                4'h1:    hex7seg = 7'b111_1001;
                4'h2:    hex7seg = 7'b010_0100;
                4'h3:    hex7seg = 7'b011_0000;
                4'h4:    hex7seg = 7'b001_1001;
                4'h5:    hex7seg = 7'b001_0010;
                4'h6:    hex7seg = 7'b000_0010;
                4'h7:    hex7seg = 7'b111_1000;
                4'h8:    hex7seg = 7'b000_0000;
                4'h9:    hex7seg = 7'b001_0000;
                4'ha:    hex7seg = 7'b000_1000;
                4'hb:    hex7seg = 7'b000_0011;
                4'hc:    hex7seg = 7'b100_0110;
                4'hd:    hex7seg = 7'b010_0001;
                4'he:    hex7seg = 7'b000_0110;
                default: hex7seg = 7'b000_1110;   // F
            endcase
        end
    endfunction

    // ---- KEY3：电平翻转 -> 本域边沿 -> 显示项循环 ----
    reg [2:0] mode_sync;
    reg [1:0] mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode_sync <= 3'd0;
        else        mode_sync <= {mode_sync[1:0], mode_tgl};
    end
    wire mode_event = mode_sync[2] ^ mode_sync[1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            mode <= 2'd0;
        else if (mode_event)   mode <= (mode == 2'd2) ? 2'd0 : mode + 1'b1;
    end

    // ---- 1 ms 节拍 ----
    localparam integer MS_CYCLES = CLK_FREQ_HZ / 1000;
    localparam integer MS_W      = $clog2(MS_CYCLES + 1);
    localparam integer PH_W      = $clog2(PARAM_HOLD_MS + 1);
    reg [MS_W-1:0] ms_div;
    wire ms_div_full = (ms_div >= (MS_CYCLES - 1));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                       ms_div <= {MS_W{1'b0}};
        else if (ms_div_full)             ms_div <= {MS_W{1'b0}};
        else                              ms_div <= ms_div + 1'b1;
    end
    // 节拍打一拍：避免 ms_div 归零与 ms_tick 变换落在同一 delta，
    // 形成零宽脉冲（仿真可通过、时序网表可能丢失）。
    reg ms_tick_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             ms_tick_r <= 1'b0;
        else                    ms_tick_r <= ms_div_full;
    end
    wire ms_tick = ms_tick_r;

    // ---- ms -> s 分频：1000 个 ms 节拍 = 1 秒 ----
    // 说明：MM:SS 是"秒"单位的显示，必须先把 1 ms 节拍累加成分频秒边界，
    // 否则会把每个 ms 当作 1 s（1000 倍显示错误）。
    localparam integer SEC_MS = 1000;
    localparam integer SEC_MS_W = $clog2(SEC_MS + 1);
    reg [SEC_MS_W-1:0] ms_cnt;
    wire sec_tick = (ms_cnt >= (SEC_MS - 1));
    wire time_run = play_active && !paused;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                        ms_cnt <= {SEC_MS_W{1'b0}};
        else if (track_step)               ms_cnt <= {SEC_MS_W{1'b0}};
        else if (ms_tick && time_run && display_enable) begin
            if (sec_tick)                  ms_cnt <= {SEC_MS_W{1'b0}};
            else                           ms_cnt <= ms_cnt + 1'b1;
        end
    end

    // ---- MM:SS BCD 计时（99:59 饱和），只在秒边界进位 ----
    reg [3:0] bcd_mmh, bcd_mml, bcd_ssh, bcd_ssl;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcd_mmh <= 4'd0; bcd_mml <= 4'd0;
            bcd_ssh <= 4'd0; bcd_ssl <= 4'd0;
        end else if (track_step) begin
            bcd_mmh <= 4'd0; bcd_mml <= 4'd0;
            bcd_ssh <= 4'd0; bcd_ssl <= 4'd0;
        end else if (sec_tick && ms_tick && time_run && display_enable) begin
            if (bcd_ssl != 4'd9) begin
                bcd_ssl <= bcd_ssl + 4'd1;
            end else begin
                bcd_ssl <= 4'd0;
                if (bcd_ssh != 4'd5) begin
                    bcd_ssh <= bcd_ssh + 4'd1;
                end else begin
                    bcd_ssh <= 4'd0;
                    if (bcd_mml != 4'd9) begin
                        bcd_mml <= bcd_mml + 4'd1;
                    end else begin
                        bcd_mml <= 4'd0;
                        if (bcd_mmh != 4'd9)
                            bcd_mmh <= bcd_mmh + 4'd1;
                        // 99:59 饱和：mmh 已到 9 时保持不变
                    end
                end
            end
        end
    end

    // ---- 2 s 参数临时值保持 ----
    reg [PH_W-1:0] param_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                              param_hold <= {PH_W{1'b0}};
        else if (param_valid)                    param_hold <= PARAM_HOLD_MS[PH_W-1:0];
        else if (ms_tick && param_hold != {PH_W{1'b0}})
                                                 param_hold <= param_hold - 1'b1;
    end

    wire show_error = (error_code != 8'd0);
    wire show_param = !show_error && (param_hold != {PH_W{1'b0}});

    // ---- 段码组合（优先级：故障 > 参数 > 选择项）----
    always @* begin
        // 默认全灭
        seg_data_0 = {1'b1, SEG_BLANK};
        seg_data_1 = {1'b1, SEG_BLANK};
        seg_data_2 = {1'b1, SEG_BLANK};
        seg_data_3 = {1'b1, SEG_BLANK};
        seg_data_4 = {1'b1, SEG_BLANK};
        seg_data_5 = {1'b1, SEG_BLANK};

        if (display_enable) begin
            if (show_error) begin
                // E + HH + LL
                seg_data_5 = {1'b1, hex7seg(4'he)};
                seg_data_4 = {1'b1, hex7seg(error_code[7:4])};
                seg_data_3 = {1'b1, hex7seg(error_code[3:0])};
            end else if (show_param) begin
                // 4 位十六进制参数值（X5 前 valid 恒 0，此处为接口预验证）
                seg_data_5 = {1'b1, hex7seg(param_value[15:12])};
                seg_data_4 = {1'b1, hex7seg(param_value[11:8])};
                seg_data_3 = {1'b1, hex7seg(param_value[7:4])};
                seg_data_2 = {1'b1, hex7seg(param_value[3:0])};
            end else if (!play_active) begin
                // 未播放：显示曲目编号 1..4
                seg_data_5 = {1'b1, hex7seg({2'b0, song_index} + 4'd1)};
            end else if (mode == 2'd1) begin
                // 曲目编号
                seg_data_5 = {1'b1, hex7seg({2'b0, song_index} + 4'd1)};
            end else if (mode == 2'd2) begin
                // 诊断项：受 SW3 控制，不得覆盖故障页（故障页不进入本分支）
                if (debug_sw) begin
                    seg_data_5 = {1'b1, hex7seg(4'hd)};
                    seg_data_4 = {1'b1, hex7seg(error_code[7:4])};
                    seg_data_3 = {1'b1, hex7seg(error_code[3:0])};
                end
            end else begin
                // MM:SS：左两位分钟，中间两位灭（充当冒号），右两位秒
                seg_data_0 = {1'b1, hex7seg(bcd_mmh)};
                seg_data_1 = {1'b1, hex7seg(bcd_mml)};
                seg_data_4 = {1'b1, hex7seg(bcd_ssh)};
                seg_data_5 = {1'b1, hex7seg(bcd_ssl)};
            end
        end
    end
endmodule
`endif
