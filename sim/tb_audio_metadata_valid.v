`timescale 1ns/1ps
// Isolate the loader metadata mailbox. Invalid precomputed arithmetic must
// remain invisible; streamed index/fallback integration is tested separately.
module tb_audio_metadata_valid;
    reg clk=0,rst=1,event_q=0,index_path=1;
    reg [31:0] cluster_value=2,bytes_value=512;
    reg [7:0] spc_value=1;
    reg legacy_valid=1;
    wire file_valid;
    wire [31:0] lba,sectors,size;
    integer checks=0;
    wire index_event=event_q && index_path;
    wire legacy_event=event_q && !index_path;
    always #5 clk=~clk;
    fat32_media_loader dut(.clk(clk),.rst(rst),.sd_init_done(1'b1),
        .scan_start(1'b0),.load_start(1'b0),.song_sel(2'd0),
        .audio_file_valid(file_valid),.audio_start_lba(lba),
        .audio_total_sectors(sectors),.audio_size_bytes(size));
    task check;
        input index_mode;
        input [31:0] cl,by;
        input [7:0] spc;
        input present;
        reg cv,fv;
        reg [31:0] expected_lba;
        begin
            @(negedge clk);index_path=index_mode;cluster_value=cl;bytes_value=by;
            spc_value=spc;legacy_valid=present;event_q=1;
            @(negedge clk);event_q=0;
            repeat(3) @(negedge clk);
            cv=index_mode ? (cl>=2 && by!=0) : (present && cl>=2 && spc!=0);
            fv=cv && by!=0;
            expected_lba=cv ? 32'd30+((cl-32'd2) << (spc==2?1:0)) : 32'd0;
            if(file_valid!==fv || lba!==expected_lba || size!==(fv?by:0) || sectors!==(fv?((by+511)>>9):0))
                $fatal(1,"metadata path%0d cl%h by%0d spc%0d valid%0d lba%h expected%h size%0d sectors%0d",index_mode,cl,by,spc,file_valid,lba,expected_lba,size,sectors);
            checks=checks+1;
        end
    endtask
    initial begin
        force dut.idx_done=index_event;
        force dut.idx_valid=1'b1;
        force dut.idx_take=1'b0;
        force dut.song_sel_changed=1'b0;
        force dut.scanner_done=legacy_event;
        force dut.scanner_audio_valid=legacy_valid;
        force dut.idx_aud_cluster=cluster_value;
        force dut.idx_aud_bytes=bytes_value;
        force dut.scanner_audio_cluster=cluster_value;
        force dut.scanner_audio_size=bytes_value;
        force dut.scanner_spc=spc_value;
        force dut.scanner_data_start=32'd30;
        repeat(3) @(negedge clk);rst=0;
        check(1,2,512,1,1);check(1,3,1024,2,1);
        check(1,1,512,1,1);check(1,0,512,1,1);check(1,3,0,1,1);
        check(1,32'hffffffff,512,2,1);check(1,2,512,1,1);
        check(0,2,512,1,1);check(0,3,1024,2,1);
        check(0,1,512,1,1);check(0,0,512,1,1);check(0,3,0,1,1);
        check(0,3,512,0,1);check(0,3,512,1,0);check(0,2,512,1,1);
        $display("PASS tb_audio_metadata_valid %0d index/legacy transitions, invalid and empty masking, unsigned wrap and recovery",checks);$finish;
    end
endmodule
