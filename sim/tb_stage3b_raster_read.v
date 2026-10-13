`timescale 1ns/1ps
module tb_stage3b_raster_read;
    parameter BURST_WORDS=128;
    reg clk=0,rst=1,req=0,enable=1,mv=0,epoch=0;
    always #4 clk=~clk;
    reg [20:0] media_base=307200,bg_base=1459200;
    wire ack,finish,app_en,epoch_ack,keep;
    wire [20:0] addr;
    reg wr_busy=0,sdr_valid=0;
    reg [20:0] sdr_data=0;
    reg sdr_expected_keep=0;
    integer count=0,run=0,checks=0,gap=20;
    integer cmd_x=0,cmd_y=0,cmd_pair=0,expected=0;
    integer fifo_count=0,head=0,tail=0,consumed=0,cycles=0;
    integer cx,cy,consume_expected;
    reg [20:0] fifo [0:511];
    // Vary response time from two to seven clocks and insert valid bubbles.
    // Check returned source parity on valid beats, independent of latency.
    reg [20:0] pending_addr [0:1023];
    reg pending_keep [0:1023];
    integer pending_due [0:1023];
    integer pending_head=0,pending_tail=0,pending_count=0,last_due=0,due;
    integer burst_words=0,burst_id=0,burst_y=0,burst_region=0,region;
    reg prev_en=0;
    reg [20:0] prev_addr=0;
    wire [9:0] used_words=fifo_count;
    frame_fifo_read #(.COMPOSITE_READ(1),.BURST_SIZE(BURST_WORDS)) dut (
        .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(sdr_valid),
        .App_wr_busy(wr_busy),.App_rd_en(app_en),.App_rd_addr(addr),
        .read_req(req),.read_req_ack(ack),.read_finish(finish),
        .read_addr_0(21'd307200),.read_addr_1(21'd0),
        .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),
        .read_len(run==1?21'd384000:21'd307200),.wrusedw(used_words),
        .background_enable(enable),.background_media_mv(mv),
        .background_epoch(epoch),.background_epoch_ack(epoch_ack),
        .background_media_base(media_base),.background_base(bg_base),
        .read_data_keep(keep));
    task check;
        input ok;
        input [511:0] msg;
        begin
            checks=checks+1;
            if(ok!==1'b1) begin
                $display("FAIL %0s commands=%0d x=%0d y=%0d addr=%0d expected=%0d",msg,count,cmd_x,cmd_y,addr,expected);
                $finish_and_return(1);
            end
        end
    endtask
    // Drive response before the sampling edge, avoiding races with DUT NBA.
    always @(negedge clk) begin
        sdr_valid=0;
        if(!rst && !ack && pending_count>0 && pending_due[pending_head]<=cycles) begin
            sdr_valid=1;sdr_data=pending_addr[pending_head];
            sdr_expected_keep=pending_keep[pending_head];
            pending_head=(pending_head+1)%1024;pending_count=pending_count-1;
        end
    end
    always @(posedge clk) begin
        if(rst || ack) begin
            fifo_count=0;head=0;tail=0;consumed=0;cycles=0;
            pending_head=0;pending_tail=0;pending_count=0;last_due=0;
            prev_en=0;gap=20;burst_words=0;burst_id=0;
        end else begin
            if(sdr_valid) begin
                check(keep===sdr_expected_keep,"return-valid driven cover parity");
                if(keep) begin
                    check(fifo_count<512,"read FIFO never overflows");
                    fifo[tail]=sdr_data;tail=(tail+1)%512;fifo_count=fifo_count+1;
                end
            end
            if(run!=0 && fifo_count>0 && cycles%5==0 && cycles%12000<11000) begin
                cx=consumed%640;cy=consumed/640;
                if(cx>=16 && cx<336 && cy>=48 && cy<288)
                    consume_expected=run==1 ? 307200+2*(cy-48)*640+2*(cx-16)
                                           : 1228800+(cy-48)*320+cx-16;
                else consume_expected=(run==1?1459200:1766400)+consumed;
                check(fifo[head]===consume_expected,"delayed FIFO pixel order");
                head=(head+1)%512;fifo_count=fifo_count-1;consumed=consumed+1;
                check(consumed<=307200,"no excess output pixels");
            end
            if(app_en && run!=0) begin
                region=(cmd_y>=48 && cmd_y<288) ?
                       ((cmd_x<16)?0:((cmd_x<336)?1:2)) : 3;
                if(region==1)
                    expected=run==1 ? 307200+2*(cmd_y-48)*640+2*(cmd_x-16)+cmd_pair
                                   : 1228800+(cmd_y-48)*320+cmd_x-16;
                else expected=(run==1?1459200:1766400)+cmd_y*640+cmd_x;
                check(addr===expected,"complete raster address");
                check(count<(run==1?384000:307200),"no excess read commands");
                if(prev_en) begin
                    check(addr===prev_addr+1,"each burst contiguous");
                    check(addr[7:0]!=0,"burst never crosses physical 256-column row");
                    check(cmd_y==burst_y && region==burst_region,"burst never crosses screen/source boundary");
                end else begin
                    check(gap>=10,"source jumps follow response drain");
                    check(pending_count==0 && !sdr_valid,"prior burst fully returned");
                    burst_words=0;burst_y=cmd_y;burst_region=region;burst_id=burst_id+1;
                    if(run==1 && region==1) check(cmd_pair==0,"cover burst starts on even column");
                end
                burst_words=burst_words+1;
                check(burst_words<=BURST_WORDS,"maximum physical burst length");
                due=cycles+2+(burst_id%3)*2;
                if(burst_words>8) due=due+1;
                if(due<=last_due) due=last_due+1;
                last_due=due;
                check(pending_count<1024,"response queue bounded");
                pending_addr[pending_tail]=addr;
                pending_keep[pending_tail]=!(run==1 && region==1 && cmd_pair==1);
                pending_due[pending_tail]=due;
                pending_tail=(pending_tail+1)%1024;pending_count=pending_count+1;
                count=count+1;
                if(run==1 && region==1 && cmd_pair==0) cmd_pair=1;
                else begin
                    cmd_pair=0;
                    if(cmd_x==639) begin cmd_x=0;cmd_y=cmd_y+1;end
                    else cmd_x=cmd_x+1;
                end
            end
            if(!app_en && prev_en && run==1 && burst_region==1)
                check(burst_words%2==0,"cover burst ends on complete source pair");
            if(app_en) gap=0;else gap=gap+1;
            prev_en=app_en;prev_addr=addr;cycles=cycles+1;
        end
    end
    task frame;
        input integer kind;
        begin
            @(negedge clk);count=0;cmd_x=0;cmd_y=0;cmd_pair=0;run=kind;mv=kind==2;
            media_base=kind==2?1228800:307200;
            bg_base=kind==2?1766400:1459200;epoch=kind==2;req=1;
            wait(ack);@(negedge clk);req=0;wait(!ack);
            check(epoch_ack==epoch,"mem ACK freezes invalidation epoch");
            @(negedge clk);media_base=999;bg_base=888;mv=~mv;enable=0;epoch=~epoch;
            repeat(30) @(negedge clk);wr_busy=1;
            repeat(30) @(negedge clk);wr_busy=0;
            wait(finish);@(negedge clk);
            check(count==(kind==1?384000:307200),"exact full-frame read count");
            check(cmd_x==0 && cmd_y==480,"exact raster dimensions");
            wait(consumed==307200);@(negedge clk);
            check(fifo_count==0 && pending_count==0 && !sdr_valid,"all returned words consumed exactly");
            check(epoch_ack==(kind==2),"mid-frame epoch changes remain frozen");
            run=0;enable=1;repeat(20) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=0;
        frame(1);frame(2);
        $display("PASS stage4 raster read: burst=%0d checks=%0d cover384000/MV307200 commands, 307200 output each, variable valid latency and frozen frame",BURST_WORDS,checks);$finish;
    end
    initial begin #100000000;$display("FAIL timeout");$finish_and_return(1);end
endmodule
