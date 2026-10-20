`timescale 1ns/1ps
module tb_final_ui_boundaries;
    reg clk=0; always #10 clk=~clk;
    reg rst=0, tick=0, press=0, step=0;
    wire ready,pvalid; wire [2:0] pid,selected; wire [1:0] state;
    ec2_param_controller #(.HIDE_TIMEOUT_MS(4),.PARAM_COUNT(5)) ec2(
        .clk(clk),.rst_n(rst),.enable(1'b1),.tick_1ms(tick),.step_valid(step),.step_up(1'b1),
        .step_ready(ready),.press_event(press),.external_volume_event(1'b0),
        .param_req_valid(pvalid),.param_req_id(pid),.param_req_up(),.param_req_ready(1'b1),
        .selected_param(selected),.ui_state(state),.ui_update());
    reg valid=0; reg [3:0] code=0; reg [15:0] arg=0,aux=0; reg [5:0] dip=6'b110111;
    wire cmd; wire [3:0] cmdcode; wire [15:0] cmdarg,cmdaux; wire blank,biz;
    ui_command_router #(.USE_EXTERNAL_MS_TICK(1),.BLANK_TIMEOUT_MS(4)) router(
        .clk(clk),.rst_n(rst),.ev_valid(valid),.ev_code(code),.ev_arg(arg),.ev_aux(aux),
        .dip_level(dip),.tick_1ms(tick),.cmd_valid(cmd),.cmd_code(cmdcode),.cmd_arg(cmdarg),.cmd_aux(cmdaux),
        .blank_active(blank),.biz_accepted(biz));
    wire nxt,prev; reg nxtprev=0,prevprev=0; integer next_count=0,prev_count=0;
    ui_event_bridge bridge(.clk(clk),.rst_n(rst),.ev_valid(cmd),.ev_code(cmdcode),
        .ev_arg(cmdarg),.ev_aux(cmdaux),.next_tgl(nxt),.prev_tgl(prev));
    reg enc2_allow=1;
    reg [15:0] enc2_count=0;
    wire enc2_enable=enc2_allow && !blank;
    wire step2,up2,ready2,press2,req2;
    wire [2:0] param2;
    integer req2_count=0;
    ec2_event_replay replay(.clk(clk),.rst_n(rst),.enable(enc2_enable),.count_current(enc2_count),
        .ev_valid(cmd),.ev_code(cmdcode),.ev_arg(cmdarg),.ev_aux(cmdaux),
        .step_valid(step2),.step_up(up2),.step_ready(ready2),.press_event(press2));
    ec2_param_controller #(.PARAM_COUNT(5)) ctrl2(.clk(clk),.rst_n(rst),.enable(enc2_enable),
        .tick_1ms(1'b0),.step_valid(step2),.step_up(up2),.step_ready(ready2),.press_event(press2),
        .external_volume_event(1'b0),.param_req_valid(req2),.param_req_id(param2),.param_req_ready(1'b1));
    always @(posedge clk) if(rst && req2) begin
        req2_count=req2_count+1;
        if(param2!=0) $fatal(1,"EC2 volume baseline changed wrong parameter");
    end
    always @(negedge clk) begin
        if(nxt!=nxtprev) next_count=next_count+1;
        if(prev!=prevprev) prev_count=prev_count+1;
        nxtprev=nxt;prevprev=prev;
    end
    task event_send; input [3:0] c; input [15:0] a,b;
        begin @(negedge clk);valid=1;code=c;arg=a;aux=b;
            if(c==4 && b[1]) enc2_count=a;
            @(negedge clk);valid=0;repeat(30) @(negedge clk); end
    endtask
    task turn; begin @(negedge clk);step=1;@(negedge clk);step=0;end endtask
    integer test_case;
    initial begin
        if(!$value$plusargs("case=%d",test_case)) test_case=1;
        repeat(3) @(negedge clk);rst=1;repeat(3) @(negedge clk);
        case(test_case)
        1: begin
            press=1;@(negedge clk);press=0;turn;repeat(3) @(negedge clk);
            if(selected!=1) $fatal(1,"selection setup");
            tick=1;repeat(4) @(negedge clk);tick=0;
            if(state!=0) $fatal(1,"timeout setup");
            turn;#1;
            if(!(state==2 && selected==0 && pid==0 && pvalid))
                $fatal(1,"reopened volume panel selects=%0d req=%0d",selected,pid);
            repeat(3) @(negedge clk);turn;#1;
            if(pid!=0) $fatal(1,"second volume step changes parameter %0d",pid);
        end
        2: begin
            event_send(4,16'd1,0);
            if(next_count!=1) $fatal(1,"encoder setup");
            event_send(6,16'hff00,16'hf609);
            if(!blank) $fatal(1,"blank setup");
            event_send(4,16'd2,0);
            if(blank || next_count!=1) $fatal(1,"wake must consume first step");
            event_send(4,16'd3,0);
            if(next_count!=2) $fatal(1,"wake step replayed later: next=%0d expected=2",next_count);
            // Reverse direction, then cross the 16-bit counter wrap at wake.
            event_send(4,16'd2,1);
            if(prev_count!=1) $fatal(1,"reverse after wake");
            event_send(6,16'hff00,16'hf609);
            event_send(4,16'hffff,1);
            event_send(4,16'd0,0);
            if(next_count!=3 || prev_count!=1) $fatal(1,"wrapped wake baseline");
        end
        3: begin
            event_send(6,16'hff00,16'hf609);
            if(!blank) $fatal(1,"blank setup");
            dip[4]=0;event_send(6,16'hff00,16'hba45);
            if(!blank) $fatal(1,"disabled IR woke display");
            event_send(1,0,0);
            if(blank || prev_count!=0) $fatal(1,"enabled key must only wake");
            // Disabled IR must also leave the automatic-idle timer untouched.
            dip[3]=1;tick=1;repeat(4) @(negedge clk);tick=0;
            if(!blank) $fatal(1,"automatic blank setup");
            event_send(6,16'hff00,16'hba45);
            if(!blank) $fatal(1,"disabled IR reset idle timer");
        end
        4: begin
            event_send(4,16'd1,16'd2);
            if(req2_count!=1) $fatal(1,"EC2 initial step");
            event_send(6,16'hff00,16'hf609);
            event_send(4,16'd2,16'd2);
            if(blank || req2_count!=1) $fatal(1,"EC2 wake must not change parameters");
            event_send(4,16'd3,16'd2);
            if(req2_count!=2) $fatal(1,"EC2 next step must change once, count=%0d",req2_count);
            enc2_allow=0;event_send(4,16'd8,16'd2);
            enc2_allow=1;repeat(4) @(negedge clk);
            if(req2_count!=2) $fatal(1,"EC2 disabled activity replayed");
            event_send(4,16'd9,16'd2);
            if(req2_count!=3) $fatal(1,"EC2 re-enable step must change once");
        end
        endcase
        $display("PASS final UI boundary case %0d",test_case);$finish;
    end
    initial begin #100000;$fatal(1,"watchdog");end
endmodule
