`timescale 1ns/1ps
// Tests the unmodified Anlogic encrypted controller against the Micron bus
// model. This is a functional byte-lane/command test, not Etron timing signoff.
module tb_vendor_mask_isolation;
    reg clk=0;
    always #4 clk=~clk;
    reg rst=1, wr_en=0, rd_en=0;
    reg [20:0] wr_addr=0, rd_addr=0;
    reg [31:0] wr_data=0;
    reg [3:0] client_mask=0;
    wire [3:0] held_mask;
    wire actual_wr_en,actual_rd_en,write_tail_busy;
    wire [20:0] actual_wr_addr,actual_rd_addr;
    wire [31:0] actual_wr_data;
    wire init_done, ref_active, busy, rd_valid;
    wire [31:0] rd_data, dq;
    wire sclk, ras_n, cas_n, we_n;
    wire [10:0] addr;
    wire [1:0] bank;
    wire [3:0] dqm;

    sdr_as_ram dut (
        .Sdr_clk(clk),.Sdr_clk_sft(~clk),.Rst(rst),
        .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_active),
        .Sdr_busy(busy),.App_ref_req(1'b0),
        .App_wr_en(actual_wr_en),.App_wr_addr(actual_wr_addr),
        .App_wr_dm(held_mask),.App_wr_din(actual_wr_data),
        .App_rd_en(actual_rd_en),.App_rd_addr(actual_rd_addr),
        .Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),
        .SDRAM_CLK(sclk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),
        .SDR_WE(we_n),.SDR_BA(bank),.SDR_ADDR(addr),
        .SDR_DM(dqm),.SDR_DQ(dq)
    );
    mt48lc2m32b2 memory (
        .Dq(dq),.Addr(addr),.Ba(bank),.Clk(sclk),.Cke(1'b1),
        .Cs_n(1'b0),.Ras_n(ras_n),.Cas_n(cas_n),.We_n(we_n),.Dqm(dqm)
    );

    // Exercise the actual production arbiter, including the live first-beat
    // mask and its registered protection of trailing physical write beats.
    audio_sdram_arbiter arbiter (
        .mem_clk(clk),.rst_n(!rst),.controller_busy(busy),
        .refresh_active(ref_active),.mem_read_valid(rd_valid),
        .audio_lock(client_mask==4'b1110),.audio_read_owner(1'b0),
        .graphics_wr_en(wr_en && client_mask!=4'b1110),
        .graphics_rd_en(rd_en),.graphics_wr_addr(wr_addr),
        .graphics_rd_addr(rd_addr),.graphics_wr_data(wr_data),.graphics_wr_mask(client_mask),
        .audio_wr_en(wr_en && client_mask==4'b1110),.audio_rd_en(1'b0),
        .audio_wr_addr(wr_addr),.audio_rd_addr(21'd0),
        .audio_wr_data(wr_data),.audio_wr_mask(client_mask),
        .graphics_stall(),.write_tail_busy(write_tail_busy),
        .graphics_read_valid(),.mem_wr_en(actual_wr_en),
        .mem_rd_en(actual_rd_en),.mem_wr_addr(actual_wr_addr),
        .mem_rd_addr(actual_rd_addr),.mem_wr_data(actual_wr_data),
        .mem_wr_mask(held_mask)
    );

    reg [31:0] expected[0:31];
    integer n, physical_reads=0, app_reads=0, app_mismatches=0;
    integer write_commands=0;
    reg checking_read=0;
    reg [3:0] expected_write_mask=0;
    reg mask_write_active=0;
    always @(posedge sclk) begin
        if(init_done && {ras_n,cas_n,we_n}==3'b100) begin
            write_commands=write_commands+1;
            if(dqm!==expected_write_mask)
                $fatal(1,"write command mask %b expected %b",dqm,expected_write_mask);
        end
        // Sample the physical bus in this model's valid output window.
        // App-side sampling is recorded separately, without hiding differences
        // between the Micron model and the actual Etron part/clock paths.
        #6;
        if(checking_read && dq!==32'hzzzzzzzz) begin
            if(physical_reads>=32)
                $fatal(1,"unexpected extra physical read word %h",dq);
            if(dq!==expected[physical_reads])
                $fatal(1,"physical read[%0d]=%h expected %h DQM=%b",
                       physical_reads,dq,expected[physical_reads],dqm);
            physical_reads=physical_reads+1;
        end
    end
    always @(posedge clk) begin
        if(checking_read && rd_valid) begin
            if(app_reads>=32 || rd_data!==expected[app_reads])
                app_mismatches=app_mismatches+1;
            app_reads=app_reads+1;
        end
    end

    task wait_drained;
        begin
            @(negedge clk);
            wait(!write_tail_busy && held_mask==0 && !busy && !ref_active && !rd_valid);
            repeat(4) @(negedge clk);
        end
    endtask
    task write_words;
        input [3:0] mask;
        input [31:0] data_base;
        begin
            wait_drained;
            client_mask=mask;
            expected_write_mask=mask;
            mask_write_active=1;
            for(n=0;n<32;n=n+1) begin
                @(negedge clk);
                wr_en=1;
                wr_addr=n;
                wr_data=data_base+n;
            end
            @(negedge clk);
            wr_en=0;
            // Deliberately change the inactive producer's mask immediately.
            // The registered hold must protect all physical trailing beats.
            client_mask=~mask;
            wait_drained;
            mask_write_active=0;
        end
    endtask
    task check_arrays;
        reg [31:0] value;
        integer physical_col, physical_bank;
        begin
            for(n=0;n<32;n=n+1) begin
                physical_bank=(n>>2)&3;
                physical_col=((n>>4)<<2)|(n&3);
                case(physical_bank)
                    0:value=memory.Bank0[physical_col];
                    1:value=memory.Bank1[physical_col];
                    2:value=memory.Bank2[physical_col];
                    3:value=memory.Bank3[physical_col];
                endcase
                if(value!==expected[n])
                    $fatal(1,"array[%0d]=%h expected %h",n,value,expected[n]);
            end
        end
    endtask
    initial begin
        #100;rst=0;
        wait(init_done);
        $display("Controller initialized at %t",$time);
        // Establish all lanes before testing either partial writer.
        write_words(4'b0000,32'h10203040);
        for(n=0;n<32;n=n+1) expected[n]=32'h10203040+n;
        check_arrays;
        write_words(4'b0001,32'ha1b2c300);
        for(n=0;n<32;n=n+1) expected[n]={24'ha1b2c3,expected[n][7:0]};
        check_arrays;
        $display("PASS graphics mask 0001 preserved every PCM byte");
        write_words(4'b1110,32'hffeedd80);
        for(n=0;n<32;n=n+1) expected[n]={expected[n][31:8],8'h80+n[7:0]};
        check_arrays;
        $display("PASS audio mask 1110 preserved every RGB byte");
        write_words(4'b0001,32'h31415900);
        for(n=0;n<32;n=n+1) expected[n]={24'h314159,expected[n][7:0]};
        check_arrays;
        $display("PASS graphics rewrite preserved cached PCM");
        // Independent RGB565 art lanes, with producer mask changing while
        // physical trailing beats are still queued inside the controller.
        write_words(4'b0011,32'hf81f0000);
        for(n=0;n<32;n=n+1) expected[n]={16'hf81f,expected[n][15:0]};
        check_arrays;
        write_words(4'b1100,32'h000007e0);
        for(n=0;n<32;n=n+1) expected[n]={expected[n][31:16],16'h07e0+n[15:0]};
        check_arrays;
        $display("PASS art1/art2 halfword masks preserved the other artwork");
        wait_drained;
        if(held_mask!==0) $fatal(1,"read admitted with nonzero mask");
        checking_read=1;
        for(n=0;n<32;n=n+1) begin
            @(negedge clk);rd_en=1;rd_addr=n;
        end
        @(negedge clk);rd_en=0;
        wait_drained;
        checking_read=0;
        if(physical_reads!=32) $fatal(1,"physical read length %0d",physical_reads);
        if(app_reads!=32) $fatal(1,"application read-valid length %0d",app_reads);
        $display("PASS encrypted controller: %0d physical masked WRITE commands; 32 full-lane physical READ words",write_commands);
        $display("OBSERVATION Micron timing model application sample mismatches=%0d/32; this test does not certify Etron sampling timing",app_mismatches);
        $finish;
    end
    initial begin #2000000;$fatal(1,"vendor mask test timeout");end
endmodule
