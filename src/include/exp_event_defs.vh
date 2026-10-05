// =============================================================================
// exp_event_defs.vh —— S1 拓展板统一 UI 事件编码（单一事实来源）
//
// 由 ui_event_bus 产生、由消费侧（S1 为 exp_echo_reporter，S2+ 为业务）解读。
// 事件为单拍有效，一次只分发一个事件；脉冲型边沿若不与其它事件同拍则不会丢失。
//
//   ev_code  ev_arg[15:0]                         ev_aux[15:0]
//   -------  ----------------------------------   ------------------------------
//   KEY_DOWN key_index (0..11)                    0
//   KEY_UP   key_index (0..11)                    0
//   DIP      {12'b0, dip_level, dip_index[2:0]}   0
//   ENC_STEP enc_count                             {14'b0, enc_id, direction}
//   ENC_SW   {15'b0, pressed}                      {15'b0, enc_id}
//   IR_FRAME ir_code[15:0]                         ir_code[31:16]
//   IR_REPEAT ir_code[15:0]                        ir_code[31:16]
//
// 约定：enc_id 0=EC1 1=EC2；direction 0=递增(+) 1=递减(-)；pressed 1=按下。
//       NEC 帧布局 = {Addr[31:24], ~Addr[23:16], Cmd[15:8], ~Cmd[7:0]}；
//       命令字节由 code[15:8] 取得，遥控按键区分用高 8 位地址 code[31:24]。
// =============================================================================
// 注意：本头文件使用 module 作用域的 localparam，且**不能**加 `ifndef 包含保护。
// TD 的预处理器是全局的（宏定义跨源文件保留），加保护会导致第二个包含它的
// 模块拿不到这些常量（HDL-8007 not declared）。每个模块各自包含一次即可。
// =============================================================================

localparam [3:0] EV_NONE       = 4'd0;
localparam [3:0] EV_KEY_DOWN   = 4'd1;
localparam [3:0] EV_KEY_UP     = 4'd2;
localparam [3:0] EV_DIP_CHANGE = 4'd3;
localparam [3:0] EV_ENC_STEP   = 4'd4;
localparam [3:0] EV_ENC_SW     = 4'd5;
localparam [3:0] EV_IR_FRAME   = 4'd6;
localparam [3:0] EV_IR_REPEAT  = 4'd7;
