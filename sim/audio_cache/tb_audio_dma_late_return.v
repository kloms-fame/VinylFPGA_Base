`timescale 1ns/1ps
// An issued read can outlive the watchdog. Its late beats must not become
// graphics data or be mistaken for the next mailbox transaction.
module tb_audio_dma_late_return;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0, rt=0, wt=0, valid=0;
    wire ra, wa, lock, owner, rd, wr, se, sw;
    wire [7:0] re, we;
    wire [20:0] raddr,waddr;
    wire [31:0] wdata;
    wire [3:0] mask;
    wire [9:0] sa;
    wire [7:0] si;
    integer issued=0, late=0, writes=0;
    audio_sdram_dma #(.WATCHDOG_BITS(5)) dut(
        .mem_clk(clk),.rst_n(rst_n),.write_request_toggle(wt),.write_sector(10'd1),
        .write_ack_toggle(wa),.write_error(we),.read_request_toggle(rt),.read_sector(10'd0),
        .read_ack_toggle(ra),.read_error(re),.stage_en(se),.stage_we(sw),.stage_addr(sa),
        .stage_din(si),.stage_dout(8'h5a),.video_read_busy(1'b0),.video_write_busy(1'b0),
        .controller_busy(1'b0),.refresh_active(1'b0),.mem_read_valid(valid),
        .mem_read_data(32'hdecafbad),.access_lock(lock),.read_owner(owner),
        .mem_wr_en(wr),.mem_wr_addr(waddr),.mem_wr_data(wdata),.mem_wr_mask(mask),
        .mem_rd_en(rd),.mem_rd_addr(raddr));
    always @(posedge clk) if(rst_n) begin
        if(rd) issued=issued+1;
        if(wr) writes=writes+1;
        if(valid) begin
            late=late+1;
            if(!owner || !lock) $fatal(1,"late audio return exposed to graphics after watchdog");
            if(sw) $fatal(1,"failed read modified consumer staging");
        end
    end
    initial begin
        $dumpfile("late_return.vcd");$dumpvars(0,tb_audio_dma_late_return);
        repeat(4) @(negedge clk);rst_n=1;rt=1;
        wait(issued==32);
        wait(re!=0);
        // A new producer request must remain queued behind the old read.
        repeat(5) @(negedge clk);wt=1;
        repeat(12) @(negedge clk);
        if(writes!=0 || !lock || !owner)
            $fatal(1,"watchdog released outstanding read ownership");
        for(integer i=0;i<32;i=i+1) begin
            @(negedge clk);valid=1;
        end
        @(negedge clk);valid=0;
        wait(ra==rt);wait(wa==wt);
        if(re!=2 || we!=0 || issued!=32 || late!=32 || writes!=512)
            $fatal(1,"drain/recovery result re=%h we=%h reads=%0d late=%0d writes=%0d",re,we,issued,late,writes);
        if(lock || owner) $fatal(1,"ownership not released after proven drain");
        $display("PASS tb_audio_dma_late_return: late beats quarantined, next write waits, exact drain then recovery");
        $finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
