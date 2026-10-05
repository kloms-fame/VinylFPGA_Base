`ifndef EXP_EXP_ECHO_REPORTER_V
`define EXP_EXP_ECHO_REPORTER_V
// =============================================================================
// exp_echo_reporter —— S1 硬件回显（loopback）串口上报器
//
// 通过顶层参数 ECHO_TEST_ENABLE 切换：
//   1 = 上电打印一次 "VINYL EXPHUB S1"，之后**只在动作发生时**逐事件打印
//       KEY/DIP/ENC/IR 行；静止时完全无输出（不再周期性刷屏）；
//   0 = 完全静默，uart_tx 保持空闲高电平（主链路功能不受影响）。
//
// 串口：沿用 J2 标定工程配置 115200 8N1（板载 USB 转 UART，tx=D12）。
// 事件行格式（全部以 CRLF 结束）：
//   KEY nn DOWN / KEY nn UP          nn=01..12（=端口数组位+1）
//   DIP n v                          n=1..6，v=当前消抖电平（上拨=1）
//   ENCx +/- hhhh                    x=1/2，+递增 / -递减，hhhh=16 位计数
//   ENCx SW DOWN / ENCx SW UP
//   IR hhhhhhhh CMD hh               hhhhhhhh=32 位 NEC 码，hh=命令字节 code[15:8]
//   IR REPEAT
// =============================================================================
module exp_echo_reporter #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter         ECHO_ENABLE = 1'b1
)(
    input  wire        clk,
    input  wire        rst_n,

    // 统一事件流（来自 ui_event_bus）
    input  wire        ev_valid,
    input  wire [3:0]  ev_code,
    input  wire [15:0] ev_arg,
    input  wire [15:0] ev_aux,

    output wire        uart_tx
);
    `include "exp_event_defs.vh"

    localparam [2:0] ST_BANNER = 3'd0,
                     ST_IDLE   = 3'd1,
                     ST_EVENT  = 3'd2,
                     ST_SEND   = 3'd3;

    localparam integer MSG_MAX = 96;

    reg [7:0]  msg [0:MSG_MAX-1];
    reg [7:0]  msg_len;
    reg [7:0]  tx_index;
    reg [2:0]  state;
    reg        tx_start;
    reg [7:0]  tx_data;
    reg        tx_issued;

    // 事件小队列（深度 8）；溢出只翻标志，不覆盖已有事件
    reg [3:0]  q_code [0:7];
    reg [15:0] q_arg  [0:7];
    reg [15:0] q_aux  [0:7];
    reg [2:0]  q_rd;
    reg [2:0]  q_wr;
    reg [3:0]  q_count;
    reg        q_overflow;

    reg [3:0]   cur_code;
    reg [15:0]  cur_arg;
    reg [15:0]  cur_aux;
    wire [31:0] cur_ir_code = {cur_aux, cur_arg};

    wire       baud_tick_pulse;
    wire       tx_busy;
    wire       tx_done;
    integer    i;

    exp_baud_tick #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) u_baud_tick (
        .clk   (clk),
        .rst_n (rst_n),
        .tick  (baud_tick_pulse)
    );

    exp_uart_tx u_uart_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .tick  (baud_tick_pulse),
        .start (tx_start),
        .data  (tx_data),
        .tx    (uart_tx),
        .busy  (tx_busy),
        .done  (tx_done)
    );

    // ---- 报文拼装工具（阻塞式，参考 J2 event_reporter 的写法）----
    function [7:0] hex_digit;
        input [3:0] v;
        begin
            if (v < 4'd10)
                hex_digit = 8'd48 + {4'd0, v};
            else
                hex_digit = 8'd55 + {4'd0, v};
        end
    endfunction

    task put_byte;
        input [7:0] b;
        begin
            if (msg_len < MSG_MAX[7:0]) begin
                msg[msg_len] = b;
                msg_len = msg_len + 8'd1;
            end
        end
    endtask

    task put_hex8;
        input [7:0] v;
        begin
            put_byte(hex_digit(v[7:4]));
            put_byte(hex_digit(v[3:0]));
        end
    endtask

    task put_hex16;
        input [15:0] v;
        begin
            put_hex8(v[15:8]);
            put_hex8(v[7:0]);
        end
    endtask

    task put_hex32;
        input [31:0] v;
        begin
            put_hex16(v[31:16]);
            put_hex16(v[15:0]);
        end
    endtask

    task put_bit;
        input v;
        begin
            put_byte(v ? 8'h31 : 8'h30);
        end
    endtask

    task put_dec2;
        input [7:0] v;
        begin
            put_byte(8'd48 + ((v / 8'd10) % 8'd10));
            put_byte(8'd48 + (v % 8'd10));
        end
    endtask

    task put_dec1;
        input [7:0] v;
        begin
            put_byte(8'd48 + (v % 8'd10));
        end
    endtask

    task put_crlf;
        begin
            put_byte(8'h0D);
            put_byte(8'h0A);
        end
    endtask

    task fmt_banner;
        begin
            put_byte("V"); put_byte("I"); put_byte("N"); put_byte("Y"); put_byte("L");
            put_byte(" ");
            put_byte("E"); put_byte("X"); put_byte("P"); put_byte("H"); put_byte("U"); put_byte("B");
            put_byte(" ");
            put_byte("S"); put_byte("1");
            put_crlf();
        end
    endtask

    task fmt_key_event;
        input is_down;
        begin
            put_byte("K"); put_byte("E"); put_byte("Y"); put_byte(" ");
            put_dec2(cur_arg[7:0] + 8'd1);
            put_byte(" ");
            if (is_down) begin
                put_byte("D"); put_byte("O"); put_byte("W"); put_byte("N");
            end else begin
                put_byte("U"); put_byte("P");
            end
            put_crlf();
        end
    endtask

    task fmt_dip_event;
        begin
            put_byte("D"); put_byte("I"); put_byte("P"); put_byte(" ");
            put_dec1({5'd0, cur_arg[2:0]} + 8'd1);
            put_byte(" ");
            put_bit(cur_arg[3]);
            put_crlf();
        end
    endtask

    task fmt_enc_step;
        begin
            put_byte("E"); put_byte("N"); put_byte("C");
            put_byte(cur_aux[1] ? "2" : "1");
            put_byte(" ");
            put_byte(cur_aux[0] ? "-" : "+");
            put_byte(" ");
            put_hex16(cur_arg);
            put_crlf();
        end
    endtask

    task fmt_enc_sw;
        begin
            put_byte("E"); put_byte("N"); put_byte("C");
            put_byte(cur_aux[1] ? "2" : "1");
            put_byte(" ");
            put_byte("S"); put_byte("W"); put_byte(" ");
            if (cur_arg[0]) begin
                put_byte("U"); put_byte("P");
            end else begin
                put_byte("D"); put_byte("O"); put_byte("W"); put_byte("N");
            end
            put_crlf();
        end
    endtask

    task fmt_ir_frame;
        begin
            put_byte("I"); put_byte("R"); put_byte(" ");
            put_hex32(cur_ir_code);
            put_byte(" ");
            put_byte("C"); put_byte("M"); put_byte("D"); put_byte(" ");
            // NEC 帧布局 {Addr, ~Addr, Cmd, ~Cmd}：命令字节位于 code[15:8]
            put_hex8(cur_ir_code[15:8]);
            put_crlf();
        end
    endtask

    task fmt_ir_repeat;
        begin
            put_byte("I"); put_byte("R"); put_byte(" ");
            put_byte("R"); put_byte("E"); put_byte("P"); put_byte("E");
            put_byte("A"); put_byte("T");
            put_crlf();
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_BANNER;
            msg_len        <= 8'd0;
            tx_index       <= 8'd0;
            tx_start       <= 1'b0;
            tx_data        <= 8'd0;
            tx_issued      <= 1'b0;
            q_rd           <= 3'd0;
            q_wr           <= 3'd0;
            q_count        <= 4'd0;
            q_overflow     <= 1'b0;
            cur_code       <= EV_NONE;
            cur_arg        <= 16'd0;
            cur_aux        <= 16'd0;
        end else begin
            tx_start    <= 1'b0;

            // ---- 事件入队 + 按键事件计数 ----
            if (ev_valid) begin
                if (q_count < 4'd8) begin
                    q_code[q_wr] <= ev_code;
                    q_arg[q_wr]  <= ev_arg;
                    q_aux[q_wr]  <= ev_aux;
                    q_wr         <= q_wr + 3'd1;
                    q_count      <= q_count + 4'd1;
                end else begin
                    q_overflow <= ~q_overflow;
                end
            end

            // ---- 上报状态机 ----
            case (state)
                ST_BANNER: begin
                    if (!ECHO_ENABLE) begin
                        state <= ST_IDLE;
                    end else begin
                        msg_len  = 8'd0;
                        fmt_banner();
                        tx_index <= 8'd0;
                        state    <= ST_SEND;
                    end
                end

                ST_IDLE: begin
                    tx_issued <= 1'b0;
                    if (ECHO_ENABLE && (q_count != 4'd0)) begin
                        cur_code <= q_code[q_rd];
                        cur_arg  <= q_arg[q_rd];
                        cur_aux  <= q_aux[q_rd];
                        q_rd     <= q_rd + 3'd1;
                        q_count  <= q_count - 4'd1;
                        state    <= ST_EVENT;
                    end
                end

                ST_EVENT: begin
                    msg_len = 8'd0;
                    case (cur_code)
                        EV_KEY_DOWN:   fmt_key_event(1'b1);
                        EV_KEY_UP:     fmt_key_event(1'b0);
                        EV_DIP_CHANGE: fmt_dip_event();
                        EV_ENC_STEP:   fmt_enc_step();
                        EV_ENC_SW:     fmt_enc_sw();
                        EV_IR_FRAME:   fmt_ir_frame();
                        EV_IR_REPEAT:  fmt_ir_repeat();
                        default: begin
                            put_byte("E"); put_byte("V"); put_byte("T"); put_byte(" ");
                            put_hex8({4'd0, cur_code});
                            put_crlf();
                        end
                    endcase
                    tx_index <= 8'd0;
                    state    <= ST_SEND;
                end

                ST_SEND: begin
                    // 每字节只触发一次 start；等 done 再推进索引，避免同拍重发
                    if (!tx_issued && !tx_busy) begin
                        tx_data   <= msg[tx_index];
                        tx_start  <= 1'b1;
                        tx_issued <= 1'b1;
                    end

                    if (tx_done) begin
                        tx_issued <= 1'b0;
                        if (tx_index == (msg_len - 8'd1)) begin
                            tx_index <= 8'd0;
                            state    <= ST_IDLE;
                        end else begin
                            tx_index <= tx_index + 8'd1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`endif
