`timescale 1ns/1ps
module tb_system_sound_scheduler;
    reg clk=0,rst_n=0,tick_1ms=0,enable=0,media=0,nvm=0,success=0,busy=0,operation=0;
    wire tone,chime;
    wire [1:0] action,save_action;
    integer notes=0,saves=0,checks=0;
    reg prev_tone=0,prev_chime=0;
    reg [1:0] actions[0:15];
    reg [1:0] save_actions[0:31];
    always #10 clk=~clk;
    system_sound_scheduler dut(.clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
        .alarm_enable(enable),.media_fault(media),.nvm_fault(nvm),.save_success(success),
        .buzzer_busy(busy),.operation_pending(operation),.fault_tone_event(tone),
        .fault_tone_action(action),.save_chime_event(chime),.save_tone_action(save_action));
    task tick;begin @(negedge clk);end endtask
    task check;
        input ok;
        input [511:0] message;
        begin checks=checks+1;if(ok!==1'b1) $fatal(1,"%0s",message);end
    endtask
    task ms;
        begin tick_1ms=1;tick;tick_1ms=0;repeat(7) tick;end
    endtask
    task save;
        begin success=1;tick;success=0;tick;end
    endtask
    always @(posedge clk) begin
        if(rst_n) begin
            if(tone && prev_tone) $fatal(1,"fault event longer than one cycle");
            if(chime && prev_chime) $fatal(1,"save event longer than one cycle");
            if(tone && chime) $fatal(1,"two system events issued together");
            if(tone) begin actions[notes]=action;notes=notes+1;end
            if(chime) begin save_actions[saves]=save_action;saves=saves+1;end
        end
        prev_tone=tone;prev_chime=chime;
    end
    initial begin
        repeat(3) tick;rst_n=1;enable=1;
        repeat(1100) ms;
        check(notes==0 && saves==0,"healthy startup must be silent");
        media=1;repeat(130) ms;
        check(notes==3,"three-note alarm must start when media fails");
        check(actions[0]==0 && actions[1]==2 && actions[2]==1,"ascending existing voices must be selected");
        repeat(894) ms;check(notes==3,"alarm must not repeat early");
        ms;check(notes==4,"persistent fault repeats at 1024 ms");
        enable=0;repeat(200) ms;check(notes==4,"disabled SW4 suppresses alarm");
        media=0;enable=1;nvm=1;repeat(130) ms;
        check(notes==7,"Flash fault also produces three notes");
        nvm=0;repeat(1100) ms;check(notes==7,"fault recovery stops repetition");
        enable=0;busy=1;save;repeat(20) tick;
        check(saves==0,"save waits for a busy buzzer");
        busy=0;operation=1;repeat(20) tick;
        check(saves==0,"save waits for queued user operation");
        operation=0;repeat(8) tick;
        check(saves==3,"pending save phrase is delivered with SW4 off");
        check(save_actions[0]==0 && save_actions[1]==2 && save_actions[2]==1,
              "save phrase uses the three existing ascending alarm voices");
        repeat(100) tick;check(saves==3,"completed phrase is not replayed");
        busy=1;save;save;save;busy=0;repeat(8) tick;
        check(saves==6,"multiple completions while busy coalesce into one phrase without a FIFO");
        // Busy/operation collisions drop a periodic note, never a save.
        enable=1;media=1;operation=1;ms;operation=0;repeat(63) ms;
        check(notes==7,"operation at first slot suppresses the note");
        ms;check(notes==8,"subsequent fault slot still sounds");
        media=0;busy=1;save;rst_n=0;repeat(2) tick;
        rst_n=1;busy=0;repeat(10) tick;
        check(saves==6 && tone===0 && chime===0,"reset clears pending feedback");
        save;busy=1;repeat(3) tick;
        check(saves==7,"first note issued before mid-phrase reset");
        rst_n=0;repeat(2) tick;rst_n=1;busy=0;repeat(10) tick;
        check(saves==7,"reset cancels the unfinished phrase");
        save;repeat(10) tick;
        check(saves==10 && save_actions[7]==0 && save_actions[8]==2 && save_actions[9]==1,
              "save after reset starts a fresh complete phrase");
        $display("TEST_PASS scheduler: %0d checks, one-shot events, repeat, recovery, arbitration, pending save",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"scheduler watchdog");end
endmodule
