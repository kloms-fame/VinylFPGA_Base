`timescale 1ns / 1ps
// 校验 mic_gain_follow：满音量 5.0x、线性跟随、0 音量静音、超范围封顶、单调。
module tb_mic_gain_follow;
    reg  [7:0] vol;
    wire [7:0] gain;
    integer errors;
    integer i;
    integer exp;
    integer d;
    integer prev;

    mic_gain_follow dut (.volume(vol), .gain_q5(gain));

    task check_vol;
        input [7:0] v;
        input [7:0] expect;
        begin
            vol = v;
            #1;
            if (gain !== expect) begin
                $display("FAIL vol=%0d gain=%0d expect=%0d", v, gain, expect);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // 关键点：精确值
        check_vol(8'd0,   8'd0);
        check_vol(8'd1,   8'd1);
        check_vol(8'd5,   8'd4);
        check_vol(8'd50,  8'd40);
        check_vol(8'd100, 8'd80);
        check_vol(8'd150, 8'd120);
        check_vol(8'd200, 8'd160);
        // 超范围封顶
        check_vol(8'd201, 8'd160);
        check_vol(8'd255, 8'd160);

        // 全量程：与精确 round(v*4/5) 误差 <= 1，且单调不减
        prev = 0;
        for (i = 0; i < 201; i = i + 1) begin
            vol = i[7:0];
            #1;
            exp = (i * 4 + 2) / 5;
            d = gain - exp;
            if (d < 0) d = -d;
            if (d > 1) begin
                $display("FAIL sweep vol=%0d gain=%0d exact=%0d", i, gain, exp);
                errors = errors + 1;
            end
            if (gain < prev) begin
                $display("FAIL monotonic vol=%0d gain=%0d prev=%0d", i, gain, prev);
                errors = errors + 1;
            end
            prev = gain;
        end

        if (errors == 0) $display("PASS mic gain follow: linear 0..5x, 0 mutes, clamped, monotonic");
        else $display("FAIL mic gain follow: %0d error(s)", errors);
        $finish;
    end
endmodule
