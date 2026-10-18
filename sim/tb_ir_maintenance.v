`timescale 1ns/1ps
module tb_ir_maintenance;
    reg clk=0, rst_n=0, valid=0;
    reg [3:0] code=6;
    reg [15:0] arg=16'hff00, aux=0;
    reg [5:0] dip=6'b010001;
    wire cmd_valid, restart_req, manual_save_req, defaults_req, mute_toggle;
    wire [3:0] cmd_code;
    wire [15:0] cmd_arg;
    wire blank_active;
    always #10 clk=~clk;
    ui_command_router dut(
        .clk(clk),.rst_n(rst_n),.ev_valid(valid),.ev_code(code),
        .ev_arg(arg),.ev_aux(aux),.dip_level(dip),.tick_1ms(1'b0),
        .cmd_valid(cmd_valid),.cmd_code(cmd_code),.cmd_arg(cmd_arg),
        .restart_req(restart_req),.manual_save_req(manual_save_req),
        .defaults_req(defaults_req),.mute_toggle(mute_toggle),.blank_active(blank_active));
    task frame;
        input [15:0] upper;
        input [3:0] expected_pulses;
        input integer expected_key;
        begin
            @(negedge clk); aux=upper; valid=1;
            #1;
            if(expected_key>=0 && (!cmd_valid || cmd_code!=1 || cmd_arg!=expected_key))
                $fatal(1,"FAIL IR key %h -> %d",upper,cmd_arg);
            if(expected_key<0 && cmd_valid) $fatal(1,"FAIL maintenance leaked into keys");
            @(negedge clk);
            if({restart_req,manual_save_req,defaults_req,mute_toggle} !== expected_pulses)
                $fatal(1,"FAIL IR pulse %h",upper);
            valid=0;
            @(negedge clk);
            if({restart_req,manual_save_req,defaults_req,mute_toggle}!==4'b0)
                $fatal(1,"FAIL maintenance pulse repeated");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        frame(16'hf807,0,4); frame(16'hea15,0,3);
        frame(16'he916,4'b1000,-1);
        frame(16'he619,4'b0100,-1);
        frame(16'hf20d,4'b0010,-1);
        frame(16'hf30c,4'b0001,-1);
        dip[4]=0;
        frame(16'he916,0,-1);frame(16'he619,0,-1);frame(16'hf20d,0,-1);
        dip[4]=1;arg=16'hfe00;frame(16'he916,0,-1);arg=16'hff00;
        code=7;frame(16'he916,0,-1);code=6;
        frame(16'hf609,0,-1);
        if(!blank_active) $fatal(1,"FAIL blank action");
        frame(16'he916,4'b1000,-1);
        $display("PASS IR volume polarity, direct restart, save/default, mute, filtering and blank wake");
        $finish;
    end
endmodule
