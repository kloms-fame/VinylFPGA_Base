`timescale 1ns/1ps

module tb_ui_event_bridge_key_decode;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ev_valid = 1'b0;
    reg [3:0] ev_code = 4'd0;
    reg [15:0] ev_arg = 16'd0;
    reg [15:0] ev_aux = 16'd0;

    wire prev_tgl, next_tgl, confirm_tgl, mode_tgl;
    wire home_tgl, effect_tgl, end_mode_tgl;
    wire enc_cw_tgl, enc_ccw_tgl, key_up_tgl, visual_tgl, key_down_tgl;
    wire ws_mode_tgl, seek_fwd5_tgl, seek_bwd5_tgl, replay_tgl;
    wire seek_fwd2_tgl, seek_bwd2_tgl;

    wire [17:0] observed = {
        seek_bwd2_tgl, seek_fwd2_tgl, replay_tgl, seek_bwd5_tgl,
        seek_fwd5_tgl, ws_mode_tgl, key_down_tgl, visual_tgl,
        key_up_tgl, enc_ccw_tgl, enc_cw_tgl, end_mode_tgl,
        effect_tgl, home_tgl, mode_tgl, confirm_tgl, next_tgl, prev_tgl
    };

    reg [17:0] expected = 18'd0;
    integer checks = 0;
    integer idx;

    always #5 clk = ~clk;

    ui_event_bridge dut (.*);

    task send_and_check;
        input [3:0] code;
        input [15:0] arg;
        input [17:0] toggle_mask;
        input [8*40-1:0] label;
        begin
            @(negedge clk);
            ev_valid = 1'b1;
            ev_code = code;
            ev_arg = arg;
            ev_aux = 16'd0;
            @(posedge clk);
            #1;
            expected = expected ^ toggle_mask;
            checks = checks + 1;
            if (observed !== expected)
                $fatal(1, "FAIL %0s code=%0d arg=%04x got=%05x expected=%05x",
                       label, code, arg, observed, expected);
            @(negedge clk);
            ev_valid = 1'b0;
            ev_code = 4'd0;
            ev_arg = 16'd0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // KEY indices 0..14, including deliberately unmapped index 5.
        send_and_check(4'd1, 16'd0,  18'h00101, "KEY index 0");
        send_and_check(4'd1, 16'd1,  18'h00004, "KEY index 1");
        send_and_check(4'd1, 16'd2,  18'h00082, "KEY index 2");
        send_and_check(4'd1, 16'd3,  18'h00201, "KEY index 3");
        send_and_check(4'd1, 16'd4,  18'h00802, "KEY index 4");
        send_and_check(4'd1, 16'd5,  18'h00000, "KEY index 5 unmapped");
        send_and_check(4'd1, 16'd6,  18'h00008, "KEY index 6");
        send_and_check(4'd1, 16'd7,  18'h00400, "KEY index 7");
        send_and_check(4'd1, 16'd8,  18'h00020, "KEY index 8");
        send_and_check(4'd1, 16'd9,  18'h01000, "KEY index 9");
        send_and_check(4'd1, 16'd10, 18'h00010, "KEY index 10");
        send_and_check(4'd1, 16'd11, 18'h00040, "KEY index 11");
        send_and_check(4'd1, 16'd12, 18'h02000, "KEY index 12");
        send_and_check(4'd1, 16'd13, 18'h04000, "KEY index 13");
        send_and_check(4'd1, 16'd14, 18'h08000, "KEY index 14");
        send_and_check(4'd1, 16'd15, 18'h00000, "KEY index 15 unmapped");

        // A low-nibble alias must never be accepted when any upper bit is set.
        for (idx = 0; idx <= 14; idx = idx + 1) begin
            send_and_check(4'd1, 16'h0010 | idx[15:0], 18'd0, "high nibble alias 001x");
            send_and_check(4'd1, 16'h1000 | idx[15:0], 18'd0, "high nibble alias 1xxx");
            send_and_check(4'd1, 16'hF000 | idx[15:0], 18'd0, "high nibble alias Fxxx");
        end
        send_and_check(4'd1, 16'hFFFF, 18'd0, "all bits set");

        // Same arguments on non-key events must not toggle any key output.
        for (idx = 0; idx <= 14; idx = idx + 1)
            send_and_check(4'd6, idx[15:0], 18'd0, "IR frame arg is not a key");
        for (idx = 0; idx <= 14; idx = idx + 1)
            send_and_check(4'd2, idx[15:0], 18'd0, "KEY_UP is not KEY_DOWN");

        $display("TEST_PASS ui_event_bridge key decode checks=%0d", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL watchdog");
    end
endmodule
