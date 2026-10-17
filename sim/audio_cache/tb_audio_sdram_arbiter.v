`timescale 1ns/1ps
// Unit-level routing and byte-mask lifetime contract. The actual encrypted
// SDRAM controller requires the separate vendor-controller simulation gate.
module tb_audio_sdram_arbiter;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0,controller_busy=0,refresh_active=0,read_valid=0;
    reg audio_lock=0,audio_owner=0,gw=0,gr=0,aw=0,ar=0;
    reg [20:0] gwa=21'd7,gra=21'd9,awa=21'd7,ara=21'd11;
    reg [31:0] gwd=32'h55667700,awd=32'h000000cc;
    wire stall,tail,gvalid,mw,mr;
    wire [20:0] mwa,mra;
    wire [31:0] mwd;
    wire [3:0] mask;
    reg [31:0] word7=32'h112233a5;
    integer checks=0,i;
    audio_sdram_arbiter #(.WRITE_DRAIN_CYCLES(16)) dut (
        .mem_clk(clk),.rst_n(rst_n),.controller_busy(controller_busy),
        .refresh_active(refresh_active),.mem_read_valid(read_valid),
        .audio_lock(audio_lock),.audio_read_owner(audio_owner),
        .graphics_wr_en(gw),.graphics_rd_en(gr),.graphics_wr_addr(gwa),
        .graphics_rd_addr(gra),.graphics_wr_data(gwd),
        .audio_wr_en(aw),.audio_rd_en(ar),.audio_wr_addr(awa),
        .audio_rd_addr(ara),.audio_wr_data(awd),.audio_wr_mask(4'b1110),
        .graphics_stall(stall),.write_tail_busy(tail),.graphics_read_valid(gvalid),
        .mem_wr_en(mw),.mem_rd_en(mr),.mem_wr_addr(mwa),.mem_rd_addr(mra),
        .mem_wr_data(mwd),.mem_wr_mask(mask));
    always @(posedge clk) begin
        if (rst_n && mw && mwa==7) begin
            if (!mask[0]) word7[7:0]<=mwd[7:0];
            if (!mask[1]) word7[15:8]<=mwd[15:8];
            if (!mask[2]) word7[23:16]<=mwd[23:16];
            if (!mask[3]) word7[31:24]<=mwd[31:24];
        end
        if (rst_n && mr && mask!==4'b0000)
            $fatal(1,"A read was issued while a write mask was still held");
        if (rst_n && gvalid !== (read_valid && !audio_owner))
            $fatal(1,"Read owner routing differs from contract");
    end
    task check;
        input condition;
        input [511:0] message;
        begin
            checks=checks+1;
            if (condition!==1'b1) $fatal(1,"%0s",message);
        end
    endtask
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task settle_write_tail;
        begin
            for(i=0;i<15;i=i+1) begin
                tick;
                check(tail,"Mask cleared before 16 fully quiet clocks");
            end
            tick;
            check(!tail && mask==0,"Write tail did not clear at quiet boundary");
        end
    endtask
    initial begin
        repeat(3) tick;
        @(negedge clk); rst_n=1;
        tick;
        check(mask==0 && !tail && !stall,"Reset state is not quiet");
        // A lock acquired during an old graphics burst must not steal it.
        @(negedge clk); gr=1; audio_lock=1; read_valid=1;
        #1; check(mr && mra==gra && gvalid && stall,
                  "Lock acquisition stole an existing graphics read");
        tick;
        @(negedge clk); gr=0; read_valid=0; gw=1;
        #1; check(mw && mwa==gwa && mwd==gwd && mask==1,
                  "Existing graphics write was not passed with byte zero protected");
        tick;
        check(word7==32'h556677a5,"Graphics write overwrote cached PCM byte");
        @(negedge clk); gw=0; controller_busy=1;
        repeat(20) begin tick; check(mask==1 && tail,"Busy write mask lost"); end
        @(negedge clk); controller_busy=0; refresh_active=1;
        repeat(3) begin tick; check(mask==1 && tail,"Refresh erased write tail"); end
        @(negedge clk); refresh_active=0;
        repeat(5) tick;
        @(negedge clk); read_valid=1;
        tick;
        check(gvalid && mask==1,"Old graphics return was misclassified as audio");
        @(negedge clk); read_valid=0;
        settle_write_tail;
        check(stall,"Clearing write tail also released audio lock");
        // PCM writes touch byte zero only; mask remains through queued writes.
        @(negedge clk); aw=1;
        #1; check(mw && mwa==awa && mask==14 && mwd==awd,
                  "Audio byte write mux/mask incorrect");
        tick;
        check(word7==32'h556677cc,"PCM write overwrote RGB bytes");
        @(negedge clk); aw=0; controller_busy=1;
        repeat(8) begin tick; check(mask==14 && tail,"PCM mask not held through busy"); end
        @(negedge clk); controller_busy=0;
        settle_write_tail;
        @(negedge clk); ar=1; audio_owner=1;
        #1; check(mr && mra==ara && mask==0,"Audio read address or DQM incorrect");
        tick;
        @(negedge clk); ar=0; read_valid=1;
        tick;
        check(!gvalid,"Audio read return reached graphics FIFO");
        @(negedge clk); read_valid=0;
        repeat(3) tick;
        @(negedge clk); audio_owner=0; audio_lock=0;
        #1; check(!stall,"Graphics did not regain access after audio yield");
        @(negedge clk); gw=1; gwd=32'h77889900;
        tick;
        check(word7==32'h778899cc,"Later graphics write erased the prefetched byte");
        @(negedge clk); gw=0;
        settle_write_tail;
        $display("PASS tb_audio_sdram_arbiter checks=%0d RGB/PCM isolation, old graphics drain, mask hold/clear, ownership, yield",checks);
        $finish;
    end
    initial begin #20000; $fatal(1,"Timeout"); end
endmodule
