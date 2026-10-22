`timescale 1ns/1ps
// Real board KEY3 -> UI save pulse -> persistence -> bit-level NOR model.
// Observe the actual buzzer while proving the write transaction completes.
module tb_system_sound_flash #(
    parameter integer FULL_TONE_RUN=1
);
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key3=1,update=0;
    reg [19:0] params={3'd4,3'd2,3'd2,3'd3,8'd200};
    wire save_pulse,tick_ms,buzzer_n,success;
    integer chimes=0;reg chime_prev=0,deny_wren=0,save_voice=0;
    wire [3:0] nvm_led;
    wire [3:0] board_levels;
    wire auto_enable=board_levels[2];
    wire cs_n,sclk,mosi,miso;
    integer requests=0,done_count=0,manual_beeps=0,auto_beeps=0,phase=0,limit=0;
    integer cycles=0,tone_start=0,tone_end=0;
    expansion_integration #(.CLK_FREQ_HZ(100000),.DEBOUNCE_CYCLES(4),
       .DEBOUNCE_TICK_CYCLES(1),.AB_STABLE_CYCLES(4),.IR_CLK_FREQ_HZ(1000000)) ui (
       .clk(clk),.rst_n(rst_n),.exp_key_n(12'hfff),.exp_dip_n(6'h3f),
       .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
       .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1),
       .play_active_async(1'b0),.paused_async(1'b0),.needle_sense_n(1'b1),
       .key2(1'b1),.key3(key3),.key4(1'b1),.sw1(1'b1),.sw2(1'b1),.sw3(1'b1),.sw4(1'b1),
       .save_success(success),.nvm_fault(nvm_led[3]),.board_buzzer_n(buzzer_n),.key3_save_pulse(save_pulse),.ui_tick_1ms(tick_ms),.board_sw_level(board_levels),
       .underrun_pulse(1'b0),.wav_buffer_low(1'b0),.wav_stream_active(1'b0),
       .mv_failed(1'b0),.osd_err_valid(1'b0),.osd_err_code(8'd0),.slideshow_beep_event(1'b0),
       .pcm_level(8'd0),.ws_brightness_level(3'd4),.mv_mode_active(1'b0),.ws_mode_tgl(1'b0));
    // Keep physical SW3 enabled throughout; its real debounced level controls
    // persistence, avoiding a DIP operation beep during the save observation.
    ui_param_persistence #(.AUTO_SAVE_MS(5),.SPI_HALF_CYCLES(4)) nvm (
       .clk(clk),.rst_n(rst_n),.tick_1ms(tick_ms),.current_params(params),
       .param_update(update),.user_write(update),.defaults_req(1'b0),
       .manual_save(save_pulse),.auto_enable(auto_enable),.led_status(nvm_led),.save_success(success),
       .flash_cs_n(cs_n),.flash_sclk(sclk),.flash_mosi(mosi),.flash_miso(miso));
    nvm_test_flash flash(.clk(clk),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso),
       .absent(1'b0),.wrong_id(1'b0),.deny_wren(deny_wren),.protect(1'b0));
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(ui.save_chime_event) save_voice=1;
        else if(ui.fault_tone_event) save_voice=0;
        if(ui.u_buzzer_feedback.busy && !chime_prev &&
           ui.u_buzzer_feedback.current_event==4 && save_voice) begin
            if(FULL_TONE_RUN && (chimes%3)!=0 && cycles-tone_end>4)
                $fatal(1,"save phrase has an audible inter-note gap");
            case(chimes%3)
                0: if(ui.u_buzzer_feedback.half_period_cycles!==32'd31249) $fatal(1,"save voice 1");
                1: if(ui.u_buzzer_feedback.half_period_cycles!==32'd22726) $fatal(1,"save voice 2");
                2: if(ui.u_buzzer_feedback.half_period_cycles!==32'd9614) $fatal(1,"save voice 3");
            endcase
            if(ui.u_buzzer_feedback.duration_cycles!==32'd1749999) $fatal(1,"save note duration register");
            chimes=chimes+1;tone_start=cycles;
        end
        if(save_voice && chime_prev && !ui.u_buzzer_feedback.busy) begin
            if(FULL_TONE_RUN && cycles-tone_start!=1750000) $fatal(1,"actual note duration is not 35 ms");
            tone_end=cycles;
        end
        chime_prev=ui.u_buzzer_feedback.busy;
        if(ui.save_chime_event && done_count==0) $fatal(1,"chime before durable save");
        if(save_pulse) requests=requests+1;
        if(nvm.store_done) done_count=done_count+1;
        if(phase==1 && ui.u_buzzer_feedback.busy) manual_beeps=manual_beeps+1;
        if(phase==2 && ui.u_buzzer_feedback.busy) auto_beeps=auto_beeps+1;
    end
    task tick;begin @(negedge clk);end endtask
    task drain_chime;
        integer note,n;
        begin
            // ModelSim runs the complete 105 ms phrase. For slower Icarus runs,
            // the monitor first checks the real frequency/duration registers,
            // then only the already-validated tone-expiry wait is accelerated.
            if(FULL_TONE_RUN) repeat(5250030) tick;
            else begin
                for(note=0;note<3;note=note+1) begin
                    n=0;
                    while(!ui.u_buzzer_feedback.busy && n<32) begin tick;n=n+1;end
                    if(n==32 || ui.u_buzzer_feedback.current_event!=4) $fatal(1,"missing save phrase note");
                    force ui.u_buzzer_feedback.duration_count=32'd1749999;
                    tick;
                    release ui.u_buzzer_feedback.duration_count;
                    repeat(8) tick;
                end
            end
        end
    endtask
    task wait_saved;
        input integer count;
        begin
            limit=0;
            while((done_count<count || nvm_led[1]!==1) && limit<50000) begin tick;limit=limit+1;end
            if(limit>=50000 || nvm_led[3]!==0 || nvm.saved_params!==params)
                $fatal(1,"save transaction failed: state=%0d led=%b",nvm.u_store.state,nvm_led);
            repeat(100) tick;
        end
    endtask
    initial begin
        if(!FULL_TONE_RUN) begin
            $dumpfile("save_sound_probe.vcd");
            $dumpvars(0,clk,rst_n,key3,params,update,auto_enable,save_pulse,nvm_led,
                         buzzer_n,nvm.store_done,nvm.save_start,ui.u_buzzer_feedback.busy);
        end
        repeat(4) tick;rst_n=1;repeat(51000) tick;
        if(!ui.skip_guard_done || !nvm.store_ready) $fatal(1,"startup not settled");
        phase=1;params[7:0]=8'd184;update=1;tick;update=0;repeat(4) tick;
        key3=0;repeat(16) tick;key3=1;repeat(16) tick;
        if(requests!=1) $fatal(1,"KEY3 save request not accepted");
        wait_saved(1);
        if(manual_beeps==0 || chimes!=1) $fatal(1,"manual durable save missing confirmation");
        $display("PASS manual KEY3 request_count=%0d save_done=%0d saved_VOL=%0d saved_LED=%b buzzer_busy_cycles=%0d",
                 requests,done_count,nvm.saved_params[7:0],nvm_led[1],manual_beeps);
        phase=0;drain_chime;
        if(ui.u_buzzer_feedback.busy || chimes!=3) $fatal(1,"manual phrase did not finish once");
        // Unchanged KEY3 save is a no-op, not a durable write/success event.
        key3=0;repeat(16) tick;key3=1;repeat(1000) tick;
        if(done_count!=1 || chimes!=3) $fatal(1,"no-op save made a false success");
        phase=2;params[7:0]=8'd168;update=1;tick;update=0;
        wait_saved(2);
        if(auto_beeps==0 || chimes!=4 || requests!=2)
            $fatal(1,"unexpected auto completion sound or extra manual request");
        $display("PASS auto save_done=%0d saved_VOL=%0d saved_LED=%b programs=%0d buzzer_busy_cycles=%0d",
                 done_count,nvm.saved_params[7:0],nvm_led[1],flash.program_count,auto_beeps);
        phase=0;drain_chime;
        if(ui.u_buzzer_feedback.busy || chimes!=6) $fatal(1,"auto phrase did not finish once");
        deny_wren=1;params[7:0]=8'd152;update=1;tick;update=0;
        limit=0;while(!nvm_led[3] && limit<50000) begin tick;limit=limit+1;end
        if(!nvm_led[3] || done_count!=2 || chimes!=6)
            $fatal(1,"failed NOR write generated a success or was not detected");
        $display("TEST_PASS real NOR: one continuous 105 ms phrase per manual/auto commit, no-op silent, failed write has no success");
        $finish;
    end
    initial begin #400000000;$fatal(1,"save sound probe watchdog");end
endmodule
