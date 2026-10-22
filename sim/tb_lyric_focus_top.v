`timescale 1ns/1ps
// Real production top-level connectivity. Vendor clock/storage IP are stubs;
// inject accepted UI commands at the existing router boundary.
module tb_lyric_focus_top;
    reg clk=0, vclk=0, reset=0, frame_vs=1;
    always #10 clk=~clk;
    always #20 vclk=~vclk;
    reg valid=0;
    reg [3:0] code=0;
    reg [15:0] arg=0;
    reg playback=1, browse=0, paused=0;
    reg [1:0] song=0;
    top dut(.clk(clk),.rst_n(1'b0),.key2(1'b1),.key3(1'b1),.key4(1'b1),
        .sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),.needle_sense_n(1'b1),
        .sd_miso(1'b1),.flash_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
        .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
        .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
    task frame;
        begin
            @(negedge vclk);frame_vs=0;
            @(negedge vclk);frame_vs=1;
            @(negedge vclk);
        end
    endtask
    task key6;
        begin
            @(negedge clk);valid=1;code=1;arg=5;
            @(negedge clk);valid=0;
            repeat(8) @(negedge vclk);
        end
    endtask
    task require_focus;
        input expected;
        begin
            if(dut.u_playback_page.lyric_focus_frame !== expected ||
               dut.u_playback_page.u_lrc_five_osd.focus_only !== expected)
                $fatal(1,"FAIL actual top KEY6/page focus wiring expected=%b",expected);
        end
    endtask
    initial begin
        force dut.video_clk=vclk;
        force dut.sd_card_clk=clk;
        force dut.ext_mem_clk=clk;
        force dut.exp_rst_n=reset;
        force dut.video_rst_n=reset;
        force dut.media_video_rst_n=reset;
        force dut.sdcard_rst_n=reset;
        force dut.sd_media_rst_n=reset;
        force dut.mem_rst_n=reset;
        force dut.vs=frame_vs;
        force dut.ui_event_valid=valid;
        force dut.ui_event_code=code;
        force dut.ui_event_arg=arg;
        force dut.ui_event_aux=16'd0;
        force dut.playback_page_mode_frame=playback;
        force dut.browse_page_mode_frame=browse;
        force dut.paused_v2=paused;
        force dut.song_id_frame=song;
        repeat(4) @(negedge vclk);reset=1;
        repeat(6) @(negedge vclk);frame;require_focus(0);
        key6;require_focus(0);frame;require_focus(1);
        paused=1;frame;require_focus(1);
        key6;frame;require_focus(0);
        paused=0;key6;frame;require_focus(1);
        song=3;frame;require_focus(1);
        playback=0;browse=1;key6;frame;
        playback=1;browse=0;frame;require_focus(1);
        key6;frame;require_focus(0);
        $display("PASS lyric focus actual top wiring, pause, track, browse, frame commit");
        $finish;
    end
    initial begin #2000000;$fatal(1,"FAIL watchdog");end
endmodule
