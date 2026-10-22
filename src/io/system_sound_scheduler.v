`ifndef SYSTEM_SOUND_SCHEDULER_V
`define SYSTEM_SOUND_SCHEDULER_V
// 50 MHz domain. Reuse the shared millisecond enable and existing buzzer
// voices: no audio datapath, oscillator, RAM, DSP or new clock divider.
module system_sound_scheduler (
    input wire clk, rst_n, tick_1ms,
    input wire alarm_enable, media_fault, nvm_fault, save_success,
    input wire buzzer_busy, operation_pending,
    output reg fault_tone_event = 1'b0,
    output wire [1:0] fault_tone_action,
    output reg save_chime_event = 1'b0,
    output wire [1:0] save_tone_action
);
    wire alarm_active = alarm_enable && (media_fault || nvm_fault);
    reg [9:0] alarm_ms = 10'd0;
    // At a note slot the low six bits advance 0 -> 1; these upper bits
    // remain stable through the event-consumption edge. Reversing them
    // selects existing voices 0/2/1 without an action register or decoder.
    assign fault_tone_action = {alarm_ms[6], alarm_ms[7]};
    reg save_pending = 1'b0;
    reg [2:0] save_note_index = 3'd0;
    // Shift through 100/010/001. Voice selection is direct register wiring;
    // there is no adder or output decoder on the buzzer's action path.
    assign save_tone_action = save_note_index[1:0];
    wire sound_idle = !buzzer_busy && !operation_pending &&
                      !fault_tone_event && !save_chime_event;
    wire take_save = save_pending && sound_idle;
    // Three 35 ms notes at 0/64/128 ms, repeated every 1024 ms.
    // Missing slots during user feedback are skipped, avoiding an event FIFO.
    wire take_fault = alarm_active && tick_1ms && sound_idle && !save_pending &&
                      (alarm_ms[5:0] == 6'd0) && (alarm_ms[9:6] < 4'd3);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) alarm_ms <= 10'd0;
        else if (!alarm_active) alarm_ms <= 10'd0;
        else if (tick_1ms) alarm_ms <= alarm_ms + 1'b1;
    end
    // Hold completion until all three notes have been issued. Each next note
    // waits for the same buzzer to finish; no extra duration timer is needed.
    // Multiple completions while busy coalesce into one confirmation phrase.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) save_pending <= 1'b0;
        else if (save_success) save_pending <= 1'b1;
        else if (take_save && save_note_index[1]) save_pending <= 1'b0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) save_note_index <= 2'd0;
        else if (take_save)
            save_note_index <= {~(save_note_index[2] | save_note_index[1]), save_note_index[2:1]};
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) save_chime_event <= 1'b0;
        else save_chime_event <= take_save;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) fault_tone_event <= 1'b0;
        else fault_tone_event <= take_fault;
    end
endmodule
`endif
