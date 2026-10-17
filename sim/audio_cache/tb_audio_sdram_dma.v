`timescale 1ns/1ps
module tb_audio_sdram_dma;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0;
    reg wt=0,rt=0;
    reg [9:0] ws=0,rs=0;
    wire wa,ra;
    wire [7:0] we,re;
    wire se,sw;
    wire [9:0] sa;
    wire [7:0] si;
    reg [7:0] so=0;
    reg vr=0,vw=0,cb=0,ref_active=0,old_valid=0,drop_returns=0;
    wire lock,owner,mwe,mre;
    wire [20:0] mwa,mra;
    wire [31:0] mwd;
    wire [3:0] mask;
    reg [7:0] staging[0:1023];
    reg [31:0] memory[0:524287];
    reg [10:0] return_valid=0;
    reg [31:0] return_data[0:10];
    wire valid=old_valid || return_valid[10];
    wire [31:0] rddata=old_valid ? 32'hdeadbeef : return_data[10];
    integer i,j,cycle=0,write_words=0,read_words=0,stage_writes=0;
    integer chunk_words=0,chunk_count=0,unlock_cycles=0;
    reg prior_lock=0,prior_command=0,check_yields=1;
    reg [20:0] prior_address=0;
    audio_sdram_dma #(.BURST_WORDS(32),.DRAIN_CYCLES(16),
        .YIELD_CYCLES(16),.WATCHDOG_BITS(8)) dut(
        .mem_clk(clk),.rst_n(rst_n),.write_request_toggle(wt),.write_sector(ws),
        .write_ack_toggle(wa),.write_error(we),.read_request_toggle(rt),.read_sector(rs),
        .read_ack_toggle(ra),.read_error(re),.stage_en(se),.stage_we(sw),.stage_addr(sa),
        .stage_din(si),.stage_dout(so),.video_read_busy(vr),.video_write_busy(vw),
        .controller_busy(cb),.refresh_active(ref_active),.mem_read_valid(valid),
        .mem_read_data(rddata),.access_lock(lock),.read_owner(owner),.mem_wr_en(mwe),
        .mem_wr_addr(mwa),.mem_wr_data(mwd),.mem_wr_mask(mask),
        .mem_rd_en(mre),.mem_rd_addr(mra));

    always @(posedge clk) begin
        cycle=cycle+1;
        if(se) begin
            if(sw) begin staging[sa]<=si; stage_writes=stage_writes+1; end
            else so<=staging[sa];
        end
        if(!rst_n) return_valid<=0;
        else begin
            return_valid <= {return_valid[9:0],mre && !drop_returns};
            if(mre) return_data[0]<=memory[mra];
            for(j=1;j<11;j=j+1) return_data[j]<=return_data[j-1];
        end
        if(rst_n) begin
            if(mwe) begin
                if(mask!==4'b1110) $fatal(1,"write mask corrupts RGB");
                if(!lock) $fatal(1,"write without lock");
                if(mwa>=524288) $fatal(1,"ring address overflow");
                memory[mwa][7:0]<=mwd[7:0];
                write_words=write_words+1;
            end
            if(mre) begin
                if(!lock || !owner) $fatal(1,"read without ownership");
                if(mra>=524288) $fatal(1,"ring read address overflow");
                read_words=read_words+1;
            end
            if((mwe || mre) && (vr || vw || old_valid || ref_active))
                $fatal(1,"DMA overlapped old video/refresh");
            if(old_valid && (owner || sw)) $fatal(1,"old video return stolen");
            if(sw && (!owner || !valid || sa<512)) $fatal(1,"invalid staging write");
            if(lock && !prior_lock) begin
                if(check_yields && chunk_count%16!=0 && unlock_cycles<16) $fatal(1,"graphics yield too short");
                chunk_words=0;
            end
            if(!lock) unlock_cycles=unlock_cycles+1;
            else unlock_cycles=0;
            if(mwe || mre) begin
                chunk_words=chunk_words+1;
                if(chunk_words>32) $fatal(1,"chunk exceeds bound");
                if(prior_command && (mwe ? mwa : mra)!==prior_address+1)
                    $fatal(1,"noncontiguous word address");
                prior_address=mwe ? mwa : mra;
            end
            if(!lock && prior_lock && chunk_words!=0) chunk_count=chunk_count+1;
            prior_command=mwe || mre;
            prior_lock=lock;
        end
    end

    task await_write;
        integer limit;
        begin
            limit=0;
            while(wa!==wt && limit<10000) begin @(negedge clk); limit=limit+1; end
            if(wa!==wt) $fatal(1,"write acknowledgement missing");
            if(lock || mwe) $fatal(1,"write acknowledged before release");
            repeat(2) @(negedge clk);
        end
    endtask
    task await_read;
        integer limit;
        begin
            limit=0;
            while(ra!==rt && limit<10000) begin @(negedge clk); limit=limit+1; end
            if(ra!==rt) $fatal(1,"read acknowledgement missing");
            if(re==0 && (lock || owner)) $fatal(1,"successful read acknowledged before drain");
            if(re!=0 && dut.operation_issued && (!lock || !owner))
                $fatal(1,"failed outstanding read released quarantine");
            repeat(2) @(negedge clk);
        end
    endtask
    initial begin
        for(i=0;i<524288;i=i+1) memory[i]=32'h5522aa00;
        for(i=0;i<1024;i=i+1) staging[i]=i*13+7;
        repeat(4) @(negedge clk);
        rst_n=1;
        // Last sector: cover address 0x7ffff and all 512 staging words.
        vr=1; ws=1023; wt=1;
        repeat(12) @(negedge clk);
        if(!lock || mwe) $fatal(1,"lock must reserve before old video drain");
        vr=0; old_valid=1;
        repeat(4) @(negedge clk);
        old_valid=0;
        await_write;
        if(we!=0 || write_words!=512) $fatal(1,"sector write count/error");
        for(i=0;i<512;i=i+1) begin
            if(memory[1023*512+i][7:0]!==staging[i]) $fatal(1,"staging read pipeline misaligned %0d",i);
            if(memory[1023*512+i][31:8]!==24'h5522aa) $fatal(1,"RGB modified");
        end
        rs=1023; rt=1;
        await_read;
        if(re!=0 || read_words!=512 || stage_writes!=512) $fatal(1,"sector read count/error");
        for(i=0;i<512;i=i+1)
            if(staging[512+i]!==staging[i]) $fatal(1,"read return offset %0d",i);
        if(chunk_count!=32) $fatal(1,"expected 16 chunks per sector, got %0d",chunk_count);
        $display("PASS complete sector read/write, RGB preservation, last-sector boundary, old video drain, 32-word chunks and yields");

        // Both mailbox toggles arrive together: consumer read gets priority.
        ws=0; rs=1023; wt=0; rt=0;
        while(ra!==rt) begin
            @(negedge clk);
            if(mwe) $fatal(1,"producer preempted pending consumer");
        end
        await_write;
        if(we || re) $fatal(1,"priority operation failed");
        for(i=0;i<512;i=i+1)
            if(memory[i][7:0]!==staging[i]) $fatal(1,"sector zero wrapping failed");
        $display("PASS simultaneous mailbox consumer priority and sector-zero wrap");

        // Controller never becomes quiet: bounded error and lock release.
        check_yields=0; cb=1; wt=1;
        await_write;
        if(we==0) $fatal(1,"stuck controller did not report error");
        cb=0;
        // Lost SDRAM returns must never report a successful consumer sector.
        drop_returns=1; rt=1;
        await_read;
        if(re==0) $fatal(1,"missing read returns did not report error");
        if(!lock || !owner) $fatal(1,"lost returns must quarantine ownership");
        drop_returns=0;
        rt=0;
        repeat(40) @(negedge clk);
        if(mre || ra==rt) $fatal(1,"new read crossed an undrained failed transaction");
        // No return can drain this deliberately destroyed transaction. Reset
        // both mailbox endpoints together, as at a controller hardware reset.
        rst_n=0;rt=0;wt=0;
        repeat(4) @(negedge clk);
        rst_n=1;rt=1;
        await_read;
        if(re!=0) $fatal(1,"new valid request did not clear prior error");
        $display("PASS no-command timeout releases lock; lost returns quarantine until coordinated reset; next mailbox recovers");
        $display("PASS tb_audio_sdram_dma");
        $finish;
    end
    initial begin #1000000; $fatal(1,"global simulation timeout"); end
endmodule
