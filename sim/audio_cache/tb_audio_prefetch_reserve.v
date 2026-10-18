`timescale 1ns/1ps
module tb_audio_prefetch_reserve;
    reg sd_clk=0,mem_clk=0;
    always #5 sd_clk=~sd_clk;
    always #4 mem_clk=~mem_clk;
    reg sd_rst_n=0,mem_rst_n=0,enable=0,source_ready=1;
    reg [31:0] start_lba=100,total_sectors=1100;
    reg client_req=0;
    wire client_busy,client_valid,client_done;
    wire [7:0] client_byte,client_error;
    wire [8:0] client_byte_index;
    wire raw_req;
    wire [31:0] raw_lba;
    reg raw_active=0,raw_valid=0,raw_done=0,hold_source=0;
    reg [7:0] raw_byte=0,raw_error=0;
    reg [8:0] raw_index=0;
    reg [31:0] issuing_lba=0;
    integer raw_cursor=0,raw_tick=0,raw_issued=0;
    reg short_source=0,error_source=0;
    wire raw_busy=raw_active || hold_source;
    wire ready,low,critical,busy,lock,owner,mwe,mre;
    wire [20:0] mwa,mra;
    wire [31:0] mwd;
    wire [3:0] mask;
    reg [31:0] memory[0:524287];
    reg [11:0] return_valid=0;
    reg [31:0] return_data[0:11];
    integer i,j;
    integer expected_lba=100,expected_index=0,received_sectors=0,done_count=0;
    integer initial_done=0;
    reg checking=1,expect_error=0;
    reg [7:0] expected_error=0;
    audio_prefetch_sdram #(.PREFILL_SECTORS(960),.HIGH_SECTORS(1008),.LOW_SECTORS(960)) dut(
        .sd_clk(sd_clk),.sd_rst_n(sd_rst_n),.mem_clk(mem_clk),.mem_rst_n(mem_rst_n),
        .source_ready(source_ready),.enable(enable),.start_lba(start_lba),.total_sectors(total_sectors),
        .client_req(client_req),.client_busy(client_busy),.client_valid(client_valid),
        .client_byte(client_byte),.client_byte_index(client_byte_index),.client_done(client_done),
        .client_error(client_error),.raw_req(raw_req),.raw_lba(raw_lba),.raw_busy(raw_busy),
        .raw_valid(raw_valid),.raw_byte(raw_byte),.raw_byte_index(raw_index),
        .raw_done(raw_done),.raw_error(raw_error),.playback_ready(ready),.prefetch_low(low),
        .prefetch_critical(critical),
        .session_busy(busy),.video_read_busy(1'b0),.video_write_busy(1'b0),
        .controller_busy(1'b0),.refresh_active(1'b0),.mem_read_valid(return_valid[11]),
        .mem_read_data(return_data[11]),.access_lock(lock),.read_owner(owner),
        .mem_wr_en(mwe),.mem_wr_addr(mwa),.mem_wr_data(mwd),.mem_wr_mask(mask),
        .mem_rd_en(mre),.mem_rd_addr(mra));

    // Registered SD responses, with inter-byte gaps and a complete transaction
    // that continues to completion even if the playback session is cancelled.
    always @(posedge sd_clk) begin
        raw_tick=raw_tick+1;
        raw_valid<=0;
        raw_done<=0;
        if(!source_ready) begin
            raw_active<=0;
        end else if(raw_req && !raw_busy) begin
            raw_active<=1;
            issuing_lba<=raw_lba;
            raw_cursor=0;
            raw_issued=raw_issued+1;
            raw_error<=0;
        end else if(raw_active && raw_tick%3==0) begin
            if(raw_cursor==(short_source ? 511 : 512)) begin
                raw_done<=1;
                raw_error<=error_source ? 8'h35 : 0;
                raw_active<=0;
            end else begin
                raw_valid<=1;
                raw_index<=raw_cursor;
                raw_byte<=issuing_lba*7+raw_cursor*13;
                raw_cursor=raw_cursor+1;
            end
        end
    end
    always @(posedge mem_clk) begin
        return_valid<={return_valid[10:0],mre};
        if(mre) return_data[0]<=memory[mra];
        for(j=1;j<12;j=j+1) return_data[j]<=return_data[j-1];
        if(mwe) begin
            if(mask!==4'b1110) $fatal(1,"PCM write mask incorrect");
            memory[mwa][7:0]<=mwd[7:0];
        end
    end
    always @(posedge sd_clk) begin
        if(checking && enable && sd_rst_n) begin
            if(client_req && !client_busy) expected_index=0;
            if(client_valid) begin
                if(client_byte_index!==expected_index[8:0]) $fatal(1,"client byte index %0d expected %0d",client_byte_index,expected_index);
                if(client_byte!==((expected_lba*7+expected_index*13)&255))
                    $fatal(1,"client byte %0d LBA %0d got %0h",expected_index,expected_lba,client_byte);
                if(expect_error) $fatal(1,"invalid sector became visible");
                expected_index=expected_index+1;
            end
            if(client_done) begin
                if(expect_error) begin
                    if(client_error!==expected_error) $fatal(1,"wrong client error %0h",client_error);
                    if(low) $fatal(1,"fault still reserves SD priority");
                end else begin
                    if(client_error!=0 || expected_index!=512) $fatal(1,"successful sector incomplete %0d error%0h",expected_index,client_error);
                    expected_lba=expected_lba+1;
                    received_sectors=received_sectors+1;
                end
                done_count=done_count+1;
                initial_done=1;
            end
            if(ready && !initial_done) $fatal(1,"playback released before first client sector");
            if(dut.occupied>1008) $fatal(1,"ring exceeded high watermark");
        end
    end
    task request_sector;
        integer t,old_done;
        begin
            old_done=done_count;
            @(negedge sd_clk); client_req=1;
            t=0;
            while(client_busy && t<5000000) begin @(negedge sd_clk); t=t+1; end
            if(client_busy) $fatal(1,"client request stuck");
            @(negedge sd_clk); client_req=0;
            t=0;
            while(done_count==old_done && t<5000000) begin @(negedge sd_clk); t=t+1; end
            if(done_count==old_done) $fatal(1,"client completion stuck");
            repeat(2) @(negedge sd_clk);
        end
    endtask
    task new_session;
        input integer base,count;
        begin
            @(negedge sd_clk); enable=0; client_req=0;
            repeat(3) @(negedge sd_clk);
            expected_lba=base; expected_index=0; initial_done=0;
            start_lba=base; total_sectors=count; enable=1;
        end
    endtask
    // Transaction-level service-reserve test. 919 sectors represent
    // 919*512/96000 = 4.901333 seconds of mono PCM. Clocks/transactions are
    // simulated normally; no claim of a real-time five-second hardware run.
    initial begin
        for(i=0;i<524288;i=i+1) memory[i]=32'h12345600;
        repeat(5) @(negedge sd_clk);
        sd_rst_n=1;mem_rst_n=1;enable=1;
        request_sector;
        if(!ready || dut.occupied<950) $fatal(1,"production prefill not established");
        if(critical) $fatal(1,"healthy prefill unnecessarily excludes MV service");
        hold_source=1;
        wait(!raw_active);
        repeat(4000) @(negedge sd_clk);
        begin : reserve_window
            integer raw_before;
            raw_before=raw_issued;
            for(i=0;i<919;i=i+1) request_sector;
            if(raw_issued!=raw_before || !ready || dut.occupied==0)
                $fatal(1,"zero-input reserve exhausted or SD request escaped hold");
            if(!critical) $fatal(1,"depleted PCM reserve did not restore urgent SD priority");
            $display("PASS production 960/1008 prefill: 919 ordered sectors = 4.901333 seconds at 96000 B/s with zero new SD reads; remaining=%0d",dut.occupied);
        end
        hold_source=0;
        for(i=0;i<180;i=i+1) request_sector;
        if(received_sectors!=1100 || dut.occupied!=0 || dut.read_pointer!=1100 || dut.write_pointer!=1100)
            $fatal(1,"refill/physical-wrap/EOF accounting");
        if(critical) $fatal(1,"EOF reserves SD priority after source is fully cached");
        for(i=0;i<524288;i=i+1)
            if(memory[i][31:8]!==24'h123456) $fatal(1,"RGB plane modified");
        $display("PASS tb_audio_prefetch_reserve: service resumes, physical slot rollover, 1100 sectors exact and RGB preserved");
        $finish;
    end
    initial begin #120000000;$fatal(1,"global timeout");end
endmodule
