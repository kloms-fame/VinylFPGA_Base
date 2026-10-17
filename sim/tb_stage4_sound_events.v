`timescale 1ns/1ps
// Directed integration regression for the one-register sound-event bundle.
// Force only hub/board decoded events; production RTL and buzzer stay real.
module tb_stage4_sound_events;
    reg clk=0,rst_n=0;
    always #10 clk=~clk; // real 50 MHz
    reg [11:0] keys=0;
    reg board_key=0;
    reg [5:0] dips=0,dip_levels=0;
    reg [2:0] dip_index=0,board_index=0;
    reg [3:0] board_changes=0,board_levels=0;
    reg e1=0,e2=0,d1=0,d2=0,s1=0,s2=0,ir=0,ir_repeat=0,slide=0;
    wire buzzer_n;
    integer checks=0,cases=0;
    expansion_integration dut (
        .clk(clk),.rst_n(rst_n),.exp_key_n(12'hfff),.exp_dip_n(6'h3f),
        .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
        .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),
        .exp_ir_rx(1'b1),.key3(1'b1),.sw1(1'b1),.sw2(1'b1),.sw3(1'b1),.sw4(1'b1),
        .underrun_pulse(1'b0),.wav_buffer_low(1'b0),.wav_stream_active(1'b0),
        .mv_failed(1'b0),.osd_err_valid(1'b0),.osd_err_code(8'd0),
        .slideshow_beep_event(slide),.pcm_level(8'd0),.ws_brightness_level(3'd0),
        .mv_mode_active(1'b0),.ws_mode_tgl(1'b0),.board_buzzer_n(buzzer_n));
    task check;
        input ok;
        input [511:0] message;
        begin
            checks=checks+1;
            if(ok!==1'b1) begin
                $display("FAIL case=%0d check=%0d %0s q=%b event=%0d",cases,checks,message,dut.sound_events_q,dut.u_buzzer_feedback.current_event);
                $finish_and_return(1);
            end
        end
    endtask
    task ports_match;
        input [9:0] expected;
        begin
            check({dut.u_buzzer_feedback.key_press,dut.u_buzzer_feedback.dip_change,
                   dut.u_buzzer_feedback.dip_target,dut.u_buzzer_feedback.encoder_step,
                   dut.u_buzzer_feedback.encoder_direction,dut.u_buzzer_feedback.encoder_source,
                   dut.u_buzzer_feedback.encoder_switch,dut.u_buzzer_feedback.encoder_switch_source,
                   dut.u_buzzer_feedback.ir_event,dut.u_buzzer_feedback.slideshow_event}===expected,
                  "all ten registered bits reach correct buzzer ports");
            check(dut.u_buzzer_feedback.ir_action===2'd0,"IR tone action remains zero");
        end
    endtask
    task clear_sources;
        begin
            keys=0;board_key=0;dips=0;dip_levels=0;dip_index=0;
            board_changes=0;board_levels=0;board_index=0;
            e1=0;e2=0;d1=0;d2=0;s1=0;s2=0;ir=0;ir_repeat=0;slide=0;
        end
    endtask
    task reset_case;
        begin
            @(negedge clk);rst_n=0;clear_sources;
            #1;check(dut.sound_events_q===10'd0,"asynchronous reset clears entire bundle");
            ports_match(10'd0);
            repeat(2) @(negedge clk);
            rst_n=1;@(posedge clk);#1;
            check(dut.sound_events_q===10'd0 && !dut.u_buzzer_feedback.busy,"idle after reset");
            @(negedge clk);cases=cases+1;
        end
    endtask
    task pulse;
        input [9:0] expected;
        input [3:0] expected_event;
        input [31:0] expected_period;
        begin
            #1;check(dut.sound_events_q===10'd0,"no combinational bypass before register");ports_match(10'd0);
            @(posedge clk);#1;
            check(dut.sound_events_q===expected,"one edge captures entire event bundle");ports_match(expected);
            check(!dut.u_buzzer_feedback.busy,"buzzer cannot consume new q before next edge");
            @(negedge clk);clear_sources;
            #1;check(dut.sound_events_q===expected,"q retains event for full 50 MHz cycle");ports_match(expected);
            @(posedge clk);#1;
            check(dut.sound_events_q===10'd0,"single input pulse produces exactly one q cycle");ports_match(10'd0);
            check(dut.u_buzzer_feedback.current_event===expected_event,"priority preserved with exactly one added cycle");
            check(dut.u_buzzer_feedback.busy===(expected_event!=0),"filtered events leave buzzer idle");
            if(expected_event!=0)
                check(dut.u_buzzer_feedback.half_period_cycles===
                      ((expected_period<=1) ? 32'd0 : expected_period-32'd1),
                      "tone terminal count stays aligned with event");
            @(posedge clk);#1;check(dut.sound_events_q===10'd0,"no second register or replay");
        end
    endtask
    task all_sources;
        begin
            keys=12'hfff;board_key=1;dips=6'h3f;dip_levels=6'h3f;
            e1=1;e2=1;d1=1;d2=0;s1=1;s2=1;ir=1;slide=1;
        end
    endtask
    initial begin
        force dut.key_fall_pulse=keys;
        force dut.board_key_fall_pulse=board_key;
        force dut.dip_change_pulse=dips;
        force dut.dip_level=dip_levels;
        force dut.dip_change_index=dip_index;
        force dut.board_sw_change_pulse=board_changes;
        force dut.board_sw_level=board_levels;
        force dut.board_sw_change_index=board_index;
        force dut.enc1_step_pulse=e1;force dut.enc2_step_pulse=e2;
        force dut.enc1_direction=d1;force dut.enc2_direction=d2;
        force dut.enc1_sw_fall_pulse=s1;force dut.enc2_sw_fall_pulse=s2;
        force dut.ir_event=ir;force dut.ir_repeat_event=ir_repeat;
        reset_case;keys=12'h800;pulse(10'd512,4'd2,32'd12500);
        reset_case;board_key=1;pulse(10'd512,4'd2,32'd12500);
        reset_case;dips=6'b000100;dip_index=2;dip_levels=6'b000100;pulse(10'd384,4'd3,32'd10000);
        reset_case;dips=6'b001000;dip_index=3;pulse(10'd256,4'd3,32'd16667);
        reset_case;board_changes=4'b1000;board_index=3;board_levels=4'b1000;
        dips=1;dip_levels=0;pulse(10'd384,4'd3,32'd10000); // board target wins
        reset_case;board_changes=1;board_levels=0;dips=1;dip_levels=1;
        pulse(10'd256,4'd3,32'd16667); // board target zero wins too
        reset_case;e1=1;pulse(10'd64,4'd1,32'd8333);
        reset_case;e1=1;d1=1;pulse(10'd96,4'd1,32'd13889);
        reset_case;e2=1;pulse(10'd80,4'd1,32'd20833);
        reset_case;e2=1;d2=1;pulse(10'd112,4'd1,32'd10417);
        reset_case;e1=1;e2=1;d1=1;d2=0;pulse(10'd112,4'd1,32'd10417);
        // Existing simultaneous semantics: EC1 direction, EC2 source tag.
        reset_case;s1=1;pulse(10'd8,4'd5,32'd20833);
        reset_case;s2=1;pulse(10'd12,4'd5,32'd9615);
        reset_case;s1=1;s2=1;pulse(10'd12,4'd5,32'd9615);
        reset_case;ir=1;dip_levels=6'b010000;pulse(10'd2,4'd4,32'd31250);
        reset_case;ir=1;ir_repeat=1;dip_levels=6'b010000;pulse(10'd0,4'd0,32'd0);
        reset_case;ir=1;pulse(10'd0,4'd0,32'd0); // DIP5 disabled
        reset_case;slide=1;pulse(10'd1,4'd6,32'd6250);
        reset_case;all_sources;pulse(10'd1023,4'd6,32'd6250);
        reset_case;all_sources;slide=0;pulse(10'd1022,4'd5,32'd9615);
        reset_case;all_sources;slide=0;s1=0;s2=0;pulse(10'd1010,4'd4,32'd31250);
        reset_case;all_sources;slide=0;s1=0;s2=0;ir_repeat=1;pulse(10'd1008,4'd3,32'd10000);
        reset_case;keys=1;e2=1;d2=1;pulse(10'd624,4'd2,32'd12500);
        reset_case;keys=1;ir=1;dip_levels=6'b010000;pulse(10'd514,4'd4,32'd31250);
        $display("PASS stage4_sound_events: cases=%0d checks=%0d q10 mapping, one 20ns register delay, key/dip/EC direction+source/switch/IR filter/slideshow/simultaneous priority",cases,checks);
        $finish;
    end
    initial begin #100000;$fatal(1,"sound events timeout");end
endmodule
