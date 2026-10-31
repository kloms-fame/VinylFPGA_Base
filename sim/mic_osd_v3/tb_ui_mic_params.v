`timescale 1ns/1ps
// 参数页轮转与 MIC 档位（0X/4X/5X/6X/7X）自检。
// 运行：iverilog -g2005 -o tb_ui.vvp sim/mic_osd_v3/tb_ui_mic_params.v \
//          src/io/ec2_param_controller.v src/io/ui_param_csr.v
//       vvp tb_ui.vvp   ->   期望最后一行 "TB_PASS"
module tb_ui_mic;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg enable = 1;
    reg tick_1ms = 0;
    reg step_valid = 0, step_up = 1;
    reg press_event = 0;
    wire step_ready;
    wire req_valid, req_up, req_ready;
    wire [2:0] req_id, selected;
    wire [1:0] ui_state;
    wire ui_update;
    wire [7:0] volume;
    wire [2:0] bri, con, rot, wsl, mic;
    wire param_update;

    ec2_param_controller #(.PARAM_COUNT(6)) u_ctrl(
        .clk(clk), .rst_n(rst_n), .enable(enable), .tick_1ms(tick_1ms),
        .step_valid(step_valid), .step_up(step_up), .step_ready(step_ready),
        .press_event(press_event), .external_volume_event(1'b0),
        .param_req_valid(req_valid), .param_req_id(req_id), .param_req_up(req_up),
        .param_req_ready(req_ready), .selected_param(selected), .ui_state(ui_state),
        .ui_update(ui_update));
    assign req_ready = 1'b1; // CSR always accepts in this TB

    ui_param_csr u_csr(
        .clk(clk), .rst_n(rst_n), .defaults_req(1'b0),
        .restore_valid(1'b0), .restore_data(23'd0),
        .wr_valid(req_valid), .wr_id(req_id), .wr_up(req_up),
        .volume(volume), .brightness_level(bri), .contrast_level(con),
        .rotation_level(rot), .ws_level(wsl), .mic_level(mic),
        .param_update(param_update));

    integer errors = 0;
    task do_step(input up); begin
        step_up = up; step_valid = 1; @(posedge clk); #1 step_valid = 0; @(posedge clk); #1;
    end endtask
    task do_press; begin
        press_event = 1; @(posedge clk); #1 press_event = 0; @(posedge clk); #1;
    end endtask

    integer i;
    reg [2:0] expect_sel [0:5];
    initial begin
        expect_sel[0]=0; expect_sel[1]=1; expect_sel[2]=2; expect_sel[3]=3; expect_sel[4]=4; expect_sel[5]=5;
        rst_n = 0; repeat (5) @(posedge clk); #1 rst_n = 1; repeat (3) @(posedge clk); #1;
        if (volume !== 8'd200 || mic !== 3'd5) begin
            $display("FAIL defaults vol=%0d mic=%0d", volume, mic); errors = errors + 1;
        end
        // enter SELECT
        do_press();
        $display("state after press=%0d sel=%0d", ui_state, selected);
        for (i = 0; i < 6; i = i + 1) begin
            if (selected !== expect_sel[i]) begin
                $display("FAIL page %0d got %0d", i, selected); errors = errors + 1;
            end
            do_step(1'b1);
        end
        if (selected !== 3'd0) begin $display("FAIL wrap got %0d", selected); errors = errors + 1; end
        // select MIC page: step down once from 0 -> 5
        do_step(1'b0);
        if (selected !== 3'd5) begin $display("FAIL down wrap got %0d", selected); errors = errors + 1; end
        // enter ADJUST on MIC page and cycle levels 5 6 7 0 4 5
        do_press();
        $display("state=%0d sel=%0d mic=%0d", ui_state, selected, mic);
        do_step(1'b1); $display("mic after +1 = %0d (expect 6)", mic);
        if (mic !== 3'd6) errors = errors + 1;
        do_step(1'b1); if (mic !== 3'd7) begin $display("FAIL mic7 got %0d", mic); errors = errors + 1; end
        do_step(1'b1); if (mic !== 3'd0) begin $display("FAIL mic0 got %0d", mic); errors = errors + 1; end
        do_step(1'b1); if (mic !== 3'd4) begin $display("FAIL mic4 got %0d", mic); errors = errors + 1; end
        do_step(1'b1); if (mic !== 3'd5) begin $display("FAIL mic5 got %0d", mic); errors = errors + 1; end
        do_step(1'b0); if (mic !== 3'd4) begin $display("FAIL mic4dn got %0d", mic); errors = errors + 1; end
        do_step(1'b0); if (mic !== 3'd0) begin $display("FAIL mic0dn got %0d", mic); errors = errors + 1; end
        do_step(1'b0); if (mic !== 3'd7) begin $display("FAIL mic7dn got %0d", mic); errors = errors + 1; end
        if (volume !== 8'd200) begin $display("FAIL volume changed %0d", volume); errors = errors + 1; end
        if (errors == 0) $display("TB_PASS all checks");
        else $display("TB_FAIL errors=%0d", errors);
        $finish;
    end
endmodule