`timescale 1ns/1ps
// Real top-level wiring. Vendor clocks/reset and media/Flash result boundaries
// are controlled; the input debounce, sound arbitration and buzzer remain real.
module tb_system_sound_top #(
    parameter integer IR_CYCLES=8
);
    reg clk=0, rst=0, sw4=1, done=0, flash_fault=0;
    reg [7:0] media_fault=0;
    integer mode=0, notes=0, saves=0, edges=0, limit=0, phrase_note=0;
    integer cycles=0, save_idle_cycle=0;
    always #10 clk=~clk;
    top dut(.clk(clk),.rst_n(1'b0),.key2(1'b1),.key3(1'b1),.key4(1'b1),
      .sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(sw4),.needle_sense_n(1'b1),
      .sd_miso(1'b1),.flash_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h3f),
      .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
      .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
    defparam dut.u_expansion_integration.DEBOUNCE_CYCLES=4;
    defparam dut.u_expansion_integration.DEBOUNCE_TICK_CYCLES=1;
    defparam dut.u_expansion_integration.u_buzzer_feedback.IR_DURATION_CYCLES=IR_CYCLES;
    defparam dut.u_expansion_integration.u_buzzer_feedback.DIP_TONE_DURATION_CYCLES=8;
    task tick;begin @(negedge clk);end endtask
    task wait_idle;
        integer n;
        begin
            n=0;
            while(dut.u_expansion_integration.u_buzzer_feedback.busy && n<600010) begin tick;n=n+1;end
            if(n>=600010) $fatal(1,"buzzer failed to return idle");
            repeat(8) tick;
        end
    endtask
    reg was_busy=0, save_voice=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(dut.u_expansion_integration.save_chime_event) save_voice=1;
        else if(dut.u_expansion_integration.fault_tone_event) save_voice=0;
        if(save_voice && was_busy && !dut.u_expansion_integration.u_buzzer_feedback.busy)
            save_idle_cycle=cycles;
        if(rst && dut.u_expansion_integration.u_buzzer_feedback.busy && !was_busy) begin
            if(dut.u_expansion_integration.u_buzzer_feedback.current_event==4 && save_voice) begin
                if((saves%3)!=0 && cycles-save_idle_cycle>4)
                    $fatal(1,"save phrase has an audible gap between notes");
                case (saves%3)
                    0: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd31249)
                           $fatal(1,"save phrase must start at 800 Hz");
                    1: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd22726)
                           $fatal(1,"save phrase second note must be 1100 Hz");
                    2: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd9614)
                           $fatal(1,"save phrase third note must be 2600 Hz");
                endcase
                saves=saves+1;
            end
            else if(dut.u_expansion_integration.u_buzzer_feedback.current_event==4) begin
                case (notes % 3)
                    0: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd31249)
                           $fatal(1,"first alarm voice is not 800 Hz");
                    1: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd22726)
                           $fatal(1,"second alarm voice is not 1100 Hz");
                    2: if(dut.u_expansion_integration.u_buzzer_feedback.half_period_cycles!==32'd9614)
                           $fatal(1,"third alarm voice is not 2600 Hz");
                endcase
                notes=notes+1;
            end
            if(dut.u_expansion_integration.u_buzzer_feedback.current_event==6) saves=saves+1;
        end
        was_busy=dut.u_expansion_integration.u_buzzer_feedback.busy;
    end
    initial begin
        if($value$plusargs("mode=%d",mode)) begin end
        force dut.video_clk=clk;force dut.sd_card_clk=clk;force dut.ext_mem_clk=clk;
        force dut.video_rst_n=rst;force dut.media_video_rst_n=rst;
        force dut.sdcard_rst_n=rst;force dut.sd_media_rst_n=rst;
        force dut.mem_rst_n=rst;force dut.exp_rst_n=rst;
        force dut.media_err_code_clk=media_fault;
        force dut.merged_err_valid=1'b1;
        force dut.u_ui_param_persistence.store_fault=flash_fault;
        force dut.u_ui_param_persistence.store_done=done;
        // One enable per clock accelerates millisecond scheduling only.
        force dut.u_expansion_integration.ui_tick_1ms=1'b1;
        repeat(4) tick;rst=1;repeat(100) tick;wait_idle;
        if(notes!=0 || saves!=0) $fatal(1,"healthy startup made a system sound");
        if(mode==3) begin
            media_fault=1;
            limit=0;
            while(!dut.u_expansion_integration.u_buzzer_feedback.busy && limit<200) begin
                tick;limit=limit+1;
            end
            if(limit==200) $fatal(1,"alarm did not start before queued-save test");
            done=1;tick;done=0;repeat(60) tick;
            if(saves!=3) $fatal(1,"save phrase lost while an alarm note was busy");
            media_fault=0;repeat(200) tick;
            if(saves!=3) $fatal(1,"queued save phrase repeated");
            $display("TEST_PASS top: save waits for busy alarm, plays one continuous three-note phrase, never replays");
            $finish;
        end
        if(mode!=2) begin
            media_fault=1;repeat(160) tick;
            if(notes!=3) $fatal(1,"MISSING_ALARM: SW4 enabled, expected three fault notes, got %0d",notes);
            sw4=0;repeat(100) tick;wait_idle;notes=0;
            repeat(1200) tick;
            if(notes!=0) $fatal(1,"SW4 disabled did not stop repeating alarm");
            media_fault=0;sw4=1;repeat(100) tick;wait_idle;notes=0;
            flash_fault=1;repeat(160) tick;
            if(notes!=3) $fatal(1,"Flash fault did not reach SW4 alarm");
            flash_fault=0;wait_idle;notes=0;repeat(1200) tick;
            if(notes!=0) $fatal(1,"cleared fault still repeated");
            $display("PASS top SW4: media/Flash alarm, off, recovery, healthy startup");
        end
        if(mode!=1) begin
            // A durable save success must be audible even with SW4 off.
            sw4=0;repeat(100) tick;wait_idle;
            done=1;tick;done=0;repeat(20) tick;
            if(saves!=1 || dut.u_expansion_integration.u_buzzer_feedback.busy!==1)
                $fatal(1,"MISSING_SAVE_SOUND: durable save produced %0d chimes",saves);
            for(phrase_note=0;phrase_note<3;phrase_note=phrase_note+1) begin
                if(dut.u_expansion_integration.u_buzzer_feedback.busy!==1 || saves!=phrase_note+1)
                    $fatal(1,"SAVE_PHRASE_MISSING: expected note %0d of three, got %0d",phrase_note+1,saves);
                if(dut.u_expansion_integration.u_buzzer_feedback.duration_cycles!==32'd1749999)
                    $fatal(1,"each save note must retain the alarm's 35 ms duration");
                // ModelSim NOR integration runs the full 105 ms phrase.
                force dut.u_expansion_integration.u_buzzer_feedback.duration_count=32'd1749999;
                tick;
                release dut.u_expansion_integration.u_buzzer_feedback.duration_count;
                repeat(8) tick;
            end
            wait_idle;repeat(100) tick;
            if(saves!=3) $fatal(1,"save success phrase replayed");
            $display("PASS top save: 800/1100/2600 Hz continuous phrase, 105 ms total, SW4 independent, no replay");
        end
        $display("TEST_PASS tb_system_sound_top mode=%0d",mode);$finish;
    end
    initial begin #20000000;$fatal(1,"system sound top watchdog");end
endmodule
