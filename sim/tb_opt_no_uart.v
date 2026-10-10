`timescale 1ns/1ps
module tb_opt_no_uart;
 reg clk=0,rst=0;
 reg [11:0] keys=12'hfff;
 reg [5:0] dips=6'h37;
 reg key3=1,ur=0,low=0,active=0,vf=0,err_valid=0;
 reg [7:0] err=0;
 wire uart,valid,skip,buzzer; wire [3:0] code,flags,led;
 wire [15:0] arg,aux; wire [5:0] ext;
 integer cmds=0,k;
 always #10 clk=~clk;
 expansion_integration #(.CLK_FREQ_HZ(2000),.DEBOUNCE_CYCLES(4),
 .AB_STABLE_CYCLES(2),.IR_CLK_FREQ_HZ(50000000)) dut(
 .clk(clk),.rst_n(rst),.exp_key_n(keys),.exp_dip_n(dips),
 .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1),
 .key3(key3),.sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),
 .uart_tx(uart),.ui_event_valid(valid),.ui_event_code(code),.ui_event_arg(arg),.ui_event_aux(aux),
 .ui_ev_valid(skip),.board_buzzer_n(buzzer),.exp_ext_o(ext),.exp_led_n(led),
 .underrun_pulse(ur),.wav_buffer_low(low),.wav_stream_active(active),.mv_failed(vf),
 .osd_err_valid(err_valid),.osd_err_code(err),.fault_flags(flags),
 .pcm_level(8'd0),.mv_mode_active(1'b0),.ws_mode_tgl(1'b0));
 always @(negedge clk) begin
  if(uart!==1'b1) $fatal(1,"FAIL UART must stay idle including reset");
  if(rst && valid && code==1) cmds=cmds+1;
  if(rst && ext[5:1]!==0) $fatal(1,"FAIL spare expansion outputs");
 end
 task cycles;input integer n; repeat(n) @(negedge clk);endtask
 initial begin
  cycles(4);rst=1;cycles(80);
  for(k=0;k<12;k=k+1) begin keys[k]=0;cycles(24);keys[k]=1;cycles(24);end
  if(cmds!=12) $fatal(1,"FAIL J2 commands lost %0d",cmds);
  cycles(1100);key3=0;cycles(24);key3=1;cycles(24);
  low=1;cycles(2);if(flags!=0)$fatal(1,"FAIL idle low water flagged");
  active=1;cycles(2);if(flags!=0)$fatal(1,"FAIL startup low water flagged");
  low=0;cycles(2);low=1;ur=1;vf=1;err_valid=1;err=8'h34;cycles(2);
  ur=0;vf=0;active=0;low=0;err_valid=0;cycles(2);
  if(flags[2:0]!=7 || dut.err_code!=8'h34)$fatal(1,"FAIL faults missing");
  force dut.ev_overflow_bus=1'b1;cycles(2);release dut.ev_overflow_bus;
  err_valid=1;err=0;cycles(2);err_valid=0;cycles(2);
  if(flags!=15 || dut.err_code!=0)$fatal(1,"FAIL recovery/history contract");
  dips[0]=0;cycles(80);if(dut.exp_actions_ready)$fatal(1,"FAIL detach gating");
  dips[0]=1;cycles(80);if(!dut.exp_actions_ready)$fatal(1,"FAIL attach gating");
  rst=0;cycles(3);if(flags!=0)$fatal(1,"FAIL reset history");
  $display("PASS UART idle, 12 J2 keys, recovery, fault history, hotplug");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL no_uart timeout");end
endmodule
