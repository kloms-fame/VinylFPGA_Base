`timescale 1ns/1ps
module tb_stage3b_raster_read;
    reg clk=0, rst=1, req=0, enable=1, mv=0, epoch=0;
    always #4 clk=~clk;
    reg [20:0] media_base=307200, bg_base=1459200;
    wire ack, finish, app_en, epoch_ack;
    wire [20:0] addr;
    reg wr_busy=0;
    integer count=0, run=0, px,py,expected,checks=0,gap=20;
    reg prev_en=0;
    reg [20:0] prev_addr=0;
    integer fifo_count=0,head=0,tail=0,consumed=0,cycles=0,cx,cy,consume_expected;
    reg [20:0] fifo [0:511];
    reg [20:0] return_addr [0:4];
    reg [4:0] return_valid=0;
    integer p;
    wire [9:0] used_words=fifo_count;
    // A bounded FIFO plus delayed virtual SDRAM responses. The video-side
    // consumer runs at one fifth of the memory clock and occasionally stalls.
    // Address identity is the virtual pixel data, giving an independent
    // end-to-end ordering check rather than only checking command addresses.
    always @(posedge clk) begin
        if(rst || ack) begin
            fifo_count=0;head=0;tail=0;consumed=0;cycles=0;return_valid=0;
        end else begin
            if(return_valid[4]) begin
                check(fifo_count<512,"read FIFO never overflows");
                fifo[tail]=return_addr[4];tail=(tail+1)%512;fifo_count=fifo_count+1;
            end
            if(run!=0 && fifo_count>0 && cycles%5==0 && cycles%12000<11000) begin
                cx=consumed%640;cy=consumed/640;
                if(cx>=16 && cx<336 && cy>=48 && cy<288)
                    consume_expected=(run==1)?307200+consumed:1228800+(cy-48)*320+cx-16;
                else consume_expected=((run==1)?1459200:1766400)+consumed;
                check(fifo[head]===consume_expected,"delayed FIFO pixel order");
                head=(head+1)%512;fifo_count=fifo_count-1;consumed=consumed+1;
            end
            for(p=4;p>0;p=p-1) return_addr[p]<=return_addr[p-1];
            return_addr[0]<=addr;return_valid<={return_valid[3:0],app_en};
            cycles=cycles+1;
        end
    end
    frame_fifo_read #(.COMPOSITE_READ(1),.BURST_SIZE(256)) dut (
        .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),
        .App_wr_busy(wr_busy),.App_rd_en(app_en),.App_rd_addr(addr),
        .read_req(req),.read_req_ack(ack),.read_finish(finish),
        .read_addr_0(21'd307200),.read_addr_1(21'd0),
        .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),
        .read_len(21'd307200),.wrusedw(used_words),
        .background_enable(enable),.background_media_mv(mv),
        .background_epoch(epoch),.background_epoch_ack(epoch_ack),
        .background_media_base(media_base),.background_base(bg_base));
    task check;
        input ok;
        input [511:0] msg;
        begin
            checks=checks+1;
            if(ok!==1'b1) begin $display("FAIL %0s count=%0d addr=%0d expected=%0d",msg,count,addr,expected); $finish_and_return(1); end
        end
    endtask
    always @(posedge clk) begin
        if(rst) begin prev_en=0;gap=20; end
        else begin
            if(app_en && run!=0) begin
                px=count%640; py=count/640;
                if(px>=16 && px<336 && py>=48 && py<288)
                    expected=(run==1) ? 307200+count : 1228800+(py-48)*320+px-16;
                else expected=((run==1)?1459200:1766400)+count;
                check(addr===expected,"complete raster address");
                check(count<307200,"no excess reads");
                if(prev_en) check(addr===prev_addr+1,"each burst contiguous");
                else check(gap>=10,"slot jumps occur after read drain");
                count=count+1;
            end
            if(app_en) gap=0; else gap=gap+1;
            prev_en=app_en; prev_addr=addr;
        end
    end
    task frame;
        input integer kind;
        begin
            @(negedge clk); count=0;run=kind;mv=(kind==2);
            media_base=(kind==2)?1228800:307200;
            bg_base=(kind==2)?1766400:1459200;epoch=(kind==2);req=1;
            wait(ack); @(negedge clk);req=0;wait(!ack);
            check(epoch_ack==epoch,"mem ACK captures invalidation epoch");
            // Changing upstream configuration must not alter this frame.
            @(negedge clk);media_base=999;bg_base=888;mv=~mv;
            repeat(30) @(negedge clk);wr_busy=1;
            repeat(30) @(negedge clk);wr_busy=0;
            wait(finish); @(negedge clk);
            check(count===307200,"full frame exact count");
            wait(consumed==307200);
            check(fifo_count==0 && return_valid==0,"all delayed words consumed exactly");
            run=0;repeat(20) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=0;
        frame(1);frame(2);
        $display("PASS stage3b raster read: %0d checks, 2 full frames, frozen config and contiguous bursts",checks);$finish;
    end
    initial begin #100000000;$display("FAIL timeout");$finish_and_return(1);end
endmodule
