`timescale 1ns/1ps
`include "sim/optimization/fat32_volume_scanner_reference.v"
module tb_resource_n1_directory_equiv;
    reg clk=0, rst_n=0, scan_start=0, sector_busy=0, sector_valid=0, sector_done=0;
    reg [7:0] sector_byte=0, sector_error=0;
    reg [8:0] sector_byte_index=0;
    reg [7:0] boot[0:511];
    reg [87:0] varied;
    reg [31:0] rng=32'h13579bdf;
    integer cycles=0, assertions=0, bytes=0, entries=0, substitutions=0, attributes=0;
    integer omitted=0, repeated=0, gaps=0, random_events=0, scans=0, requests=0;
    integer resets=0, spc_cases=0, busy_starts=0;
    integer n,p,v,j,k;
    always #5 clk=~clk;
    wire  d_scan_busy, r_scan_busy;
    wire  d_scan_done, r_scan_done;
    wire [7:0] d_fs_error, r_fs_error;
    wire [31:0] d_partition_lba, r_partition_lba;
    wire [7:0] d_sectors_per_cluster, r_sectors_per_cluster;
    wire [31:0] d_fat_start_lba, r_fat_start_lba;
    wire [31:0] d_data_start_lba, r_data_start_lba;
    wire [31:0] d_max_cluster, r_max_cluster;
    wire [3:0] d_resource_valid, r_resource_valid;
    wire [31:0] d_resource0_cluster, r_resource0_cluster;
    wire [31:0] d_resource1_cluster, r_resource1_cluster;
    wire [31:0] d_resource2_cluster, r_resource2_cluster;
    wire [31:0] d_resource3_cluster, r_resource3_cluster;
    wire [31:0] d_resource0_size, r_resource0_size;
    wire [31:0] d_resource1_size, r_resource1_size;
    wire [31:0] d_resource2_size, r_resource2_size;
    wire [31:0] d_resource3_size, r_resource3_size;
    wire  d_audio_valid, r_audio_valid;
    wire [31:0] d_audio_cluster, r_audio_cluster;
    wire [31:0] d_audio_size, r_audio_size;
    wire  d_index_valid, r_index_valid;
    wire [31:0] d_index_cluster, r_index_cluster;
    wire [31:0] d_index_size, r_index_size;
    wire  d_sector_req, r_sector_req;
    wire [31:0] d_sector_lba, r_sector_lba;
    fat32_volume_scanner dut (
        .clk(clk),
        .rst_n(rst_n),
        .scan_start(scan_start),
        .sector_busy(sector_busy),
        .sector_valid(sector_valid),
        .sector_byte(sector_byte),
        .sector_byte_index(sector_byte_index),
        .sector_done(sector_done),
        .sector_error(sector_error),
        .scan_busy(d_scan_busy),
        .scan_done(d_scan_done),
        .fs_error(d_fs_error),
        .partition_lba(d_partition_lba),
        .sectors_per_cluster(d_sectors_per_cluster),
        .fat_start_lba(d_fat_start_lba),
        .data_start_lba(d_data_start_lba),
        .max_cluster(d_max_cluster),
        .resource_valid(d_resource_valid),
        .resource0_cluster(d_resource0_cluster),
        .resource1_cluster(d_resource1_cluster),
        .resource2_cluster(d_resource2_cluster),
        .resource3_cluster(d_resource3_cluster),
        .resource0_size(d_resource0_size),
        .resource1_size(d_resource1_size),
        .resource2_size(d_resource2_size),
        .resource3_size(d_resource3_size),
        .audio_valid(d_audio_valid),
        .audio_cluster(d_audio_cluster),
        .audio_size(d_audio_size),
        .index_valid(d_index_valid),
        .index_cluster(d_index_cluster),
        .index_size(d_index_size),
        .sector_req(d_sector_req),
        .sector_lba(d_sector_lba)
    );

    fat32_volume_scanner_reference reference (
        .clk(clk),
        .rst_n(rst_n),
        .scan_start(scan_start),
        .sector_busy(sector_busy),
        .sector_valid(sector_valid),
        .sector_byte(sector_byte),
        .sector_byte_index(sector_byte_index),
        .sector_done(sector_done),
        .sector_error(sector_error),
        .scan_busy(r_scan_busy),
        .scan_done(r_scan_done),
        .fs_error(r_fs_error),
        .partition_lba(r_partition_lba),
        .sectors_per_cluster(r_sectors_per_cluster),
        .fat_start_lba(r_fat_start_lba),
        .data_start_lba(r_data_start_lba),
        .max_cluster(r_max_cluster),
        .resource_valid(r_resource_valid),
        .resource0_cluster(r_resource0_cluster),
        .resource1_cluster(r_resource1_cluster),
        .resource2_cluster(r_resource2_cluster),
        .resource3_cluster(r_resource3_cluster),
        .resource0_size(r_resource0_size),
        .resource1_size(r_resource1_size),
        .resource2_size(r_resource2_size),
        .resource3_size(r_resource3_size),
        .audio_valid(r_audio_valid),
        .audio_cluster(r_audio_cluster),
        .audio_size(r_audio_size),
        .index_valid(r_index_valid),
        .index_cluster(r_index_cluster),
        .index_size(r_index_size),
        .sector_req(r_sector_req),
        .sector_lba(r_sector_lba)
    );

    always @(posedge clk) begin
        #1;
        cycles = cycles + 1;
        if (d_scan_busy !== r_scan_busy) begin $display("FAIL: cycle=%0d output=scan_busy dut=%h ref=%h", cycles, d_scan_busy, r_scan_busy); $fatal(1); end
        if (d_scan_done !== r_scan_done) begin $display("FAIL: cycle=%0d output=scan_done dut=%h ref=%h", cycles, d_scan_done, r_scan_done); $fatal(1); end
        if (d_fs_error !== r_fs_error) begin $display("FAIL: cycle=%0d output=fs_error dut=%h ref=%h", cycles, d_fs_error, r_fs_error); $fatal(1); end
        if (d_partition_lba !== r_partition_lba) begin $display("FAIL: cycle=%0d output=partition_lba dut=%h ref=%h", cycles, d_partition_lba, r_partition_lba); $fatal(1); end
        if (d_sectors_per_cluster !== r_sectors_per_cluster) begin $display("FAIL: cycle=%0d output=sectors_per_cluster dut=%h ref=%h", cycles, d_sectors_per_cluster, r_sectors_per_cluster); $fatal(1); end
        if (d_fat_start_lba !== r_fat_start_lba) begin $display("FAIL: cycle=%0d output=fat_start_lba dut=%h ref=%h", cycles, d_fat_start_lba, r_fat_start_lba); $fatal(1); end
        if (d_data_start_lba !== r_data_start_lba) begin $display("FAIL: cycle=%0d output=data_start_lba dut=%h ref=%h", cycles, d_data_start_lba, r_data_start_lba); $fatal(1); end
        if (d_max_cluster !== r_max_cluster) begin $display("FAIL: cycle=%0d output=max_cluster dut=%h ref=%h", cycles, d_max_cluster, r_max_cluster); $fatal(1); end
        if (d_resource_valid !== r_resource_valid) begin $display("FAIL: cycle=%0d output=resource_valid dut=%h ref=%h", cycles, d_resource_valid, r_resource_valid); $fatal(1); end
        if (d_resource0_cluster !== r_resource0_cluster) begin $display("FAIL: cycle=%0d output=resource0_cluster dut=%h ref=%h", cycles, d_resource0_cluster, r_resource0_cluster); $fatal(1); end
        if (d_resource1_cluster !== r_resource1_cluster) begin $display("FAIL: cycle=%0d output=resource1_cluster dut=%h ref=%h", cycles, d_resource1_cluster, r_resource1_cluster); $fatal(1); end
        if (d_resource2_cluster !== r_resource2_cluster) begin $display("FAIL: cycle=%0d output=resource2_cluster dut=%h ref=%h", cycles, d_resource2_cluster, r_resource2_cluster); $fatal(1); end
        if (d_resource3_cluster !== r_resource3_cluster) begin $display("FAIL: cycle=%0d output=resource3_cluster dut=%h ref=%h", cycles, d_resource3_cluster, r_resource3_cluster); $fatal(1); end
        if (d_resource0_size !== r_resource0_size) begin $display("FAIL: cycle=%0d output=resource0_size dut=%h ref=%h", cycles, d_resource0_size, r_resource0_size); $fatal(1); end
        if (d_resource1_size !== r_resource1_size) begin $display("FAIL: cycle=%0d output=resource1_size dut=%h ref=%h", cycles, d_resource1_size, r_resource1_size); $fatal(1); end
        if (d_resource2_size !== r_resource2_size) begin $display("FAIL: cycle=%0d output=resource2_size dut=%h ref=%h", cycles, d_resource2_size, r_resource2_size); $fatal(1); end
        if (d_resource3_size !== r_resource3_size) begin $display("FAIL: cycle=%0d output=resource3_size dut=%h ref=%h", cycles, d_resource3_size, r_resource3_size); $fatal(1); end
        if (d_audio_valid !== r_audio_valid) begin $display("FAIL: cycle=%0d output=audio_valid dut=%h ref=%h", cycles, d_audio_valid, r_audio_valid); $fatal(1); end
        if (d_audio_cluster !== r_audio_cluster) begin $display("FAIL: cycle=%0d output=audio_cluster dut=%h ref=%h", cycles, d_audio_cluster, r_audio_cluster); $fatal(1); end
        if (d_audio_size !== r_audio_size) begin $display("FAIL: cycle=%0d output=audio_size dut=%h ref=%h", cycles, d_audio_size, r_audio_size); $fatal(1); end
        if (d_index_valid !== r_index_valid) begin $display("FAIL: cycle=%0d output=index_valid dut=%h ref=%h", cycles, d_index_valid, r_index_valid); $fatal(1); end
        if (d_index_cluster !== r_index_cluster) begin $display("FAIL: cycle=%0d output=index_cluster dut=%h ref=%h", cycles, d_index_cluster, r_index_cluster); $fatal(1); end
        if (d_index_size !== r_index_size) begin $display("FAIL: cycle=%0d output=index_size dut=%h ref=%h", cycles, d_index_size, r_index_size); $fatal(1); end
        if (d_sector_req !== r_sector_req) begin $display("FAIL: cycle=%0d output=sector_req dut=%h ref=%h", cycles, d_sector_req, r_sector_req); $fatal(1); end
        if (d_sector_lba !== r_sector_lba) begin $display("FAIL: cycle=%0d output=sector_lba dut=%h ref=%h", cycles, d_sector_lba, r_sector_lba); $fatal(1); end
    end

    task tick; begin @(posedge clk); #2; end endtask
    task check;
        input condition;
        input [511:0] label;
        begin
            assertions = assertions + 1;
            if (condition !== 1'b1) begin $display("FAIL: independent assertion %0s", label); $fatal(1); end
        end
    endtask
    task clear_bus;
        begin sector_valid=0; sector_done=0; sector_error=0; sector_busy=0; scan_start=0; end
    endtask
    task reset;
        begin
            @(negedge clk); clear_bus; rst_n=0;
            tick; tick;
            @(negedge clk); rst_n=1; tick;
            resets=resets+1;
        end
    endtask
    task send;
        input [8:0] position;
        input [7:0] value;
        begin
            @(negedge clk); sector_valid=1; sector_byte_index=position; sector_byte=value;
            tick; bytes=bytes+1;
        end
    endtask
    task gap;
        begin @(negedge clk); sector_valid=0; tick; gaps=gaps+1; end
    endtask
    task done;
        input [7:0] error;
        begin
            @(negedge clk); sector_valid=0; sector_done=1; sector_error=error; tick;
            @(negedge clk); sector_done=0; sector_error=0;
        end
    endtask
    task request;
        input [31:0] lba;
        integer watchdog;
        begin
            watchdog=0;
            while (!d_sector_req && watchdog<40) begin tick; watchdog=watchdog+1; end
            check(d_sector_req && d_sector_lba==lba,"public request LBA and latency bound");
            requests=requests+1;
        end
    endtask
    task prepare_boot;
        input [7:0] spc;
        integer k;
        begin
            for(k=0;k<512;k=k+1) boot[k]=0;
            boot[0]=8'heb; boot[12]=2; boot[13]=spc; boot[14]=32; boot[16]=2;
            boot[33]=4; boot[36]=1; boot[44]=2; boot[510]=8'h55; boot[511]=8'haa;
        end
    endtask
    task boot_stream;
        integer k;
        begin for(k=0;k<512;k=k+1) send(k,boot[k]); done(0); end
    endtask
    task start_scan;
        begin
            @(negedge clk); sector_valid=0; sector_busy=1; scan_start=1; tick;
            @(negedge clk); scan_start=0;
            tick; tick; check(!d_sector_req && d_scan_busy,"busy stalls initial request");
            @(negedge clk); sector_busy=0;
            request(0); scans=scans+1;
        end
    endtask
    task open_root;
        input mbr;
        input [7:0] spc;
        integer k;
        begin
            prepare_boot(spc); start_scan;
            if(mbr) begin
                for(k=0;k<512;k=k+1) begin
                    case(k)
                        450:send(k,8'h0c);
                        454:send(k,8'd100);
                        510:send(k,8'h55);
                        511:send(k,8'haa);
                        default:send(k,0);
                    endcase
                end
                done(0); request(100); boot_stream;
            end else boot_stream;
            request(mbr?134:34);
            check(d_partition_lba==(mbr?100:0),"partition");
            check(d_fat_start_lba==(mbr?132:32) && d_data_start_lba==(mbr?134:34),"boot layout");
            check(d_sectors_per_cluster==spc && d_max_cluster==(990/spc)+1,"spc and max cluster");
        end
    endtask
    task wait_finish;
        input [7:0] expected;
        integer k;
        begin
            k=0;
            while(!d_scan_done && k<8) begin tick; k=k+1; end
            if (!(d_scan_done && !d_scan_busy && d_fs_error==expected)) $display("DETAIL scans=%0d error=%h expected=%h done=%b busy=%b",scans,d_fs_error,expected,d_scan_done,d_scan_busy);
            check(d_scan_done && !d_scan_busy && d_fs_error==expected,"finish pulse and error");
            tick; check(!d_scan_done,"done is one cycle");
        end
    endtask
    task finish_scan;
        input [7:0] transport_error;
        input [7:0] expected;
        begin done(transport_error); wait_finish(expected); end
    endtask
    function [87:0] target;
        input integer n;
        begin
            case(n)
                0:target="PIC1    BMP"; 1:target="PIC2    BMP";
                2:target="PIC3    BMP"; 3:target="PIC4    BMP";
                4:target="AUDIO   PCM"; default:target="INDEX   BIN";
            endcase
        end
    endfunction
    task name_bytes;
        input [87:0] name;
        integer k;
        begin for(k=0;k<11;k=k+1) send(k,name[87-k*8 -:8]); end
    endtask
    task metadata;
        input [31:0] cluster;
        input [31:0] size;
        begin
            send(20,cluster[23:16]); send(21,cluster[31:24]);
            send(26,cluster[7:0]); send(27,cluster[15:8]);
            send(28,size[7:0]); send(29,size[15:8]); send(30,size[23:16]); send(31,size[31:24]);
        end
    endtask
    task entry;
        input [87:0] name;
        input [7:0] attribute;
        input [31:0] cluster;
        input [31:0] size;
        begin name_bytes(name); send(11,attribute); metadata(cluster,size); entries=entries+1; end
    endtask
    initial begin
        reset;
        open_root(0,1);
        // Independent examples use literal public metadata and validity values.
        for(n=0;n<6;n=n+1) entry(target(n),8'h20,32'h12340000+n,32'hfedc0000+n);
        check(d_resource_valid==15 && d_audio_valid && d_index_valid,"six known names valid");
        check(d_resource0_cluster==32'h12340000 && d_resource1_cluster==32'h12340001 &&
              d_resource2_cluster==32'h12340002 && d_resource3_cluster==32'h12340003,"PIC cluster mapping");
        check(d_resource0_size==32'hfedc0000 && d_resource1_size==32'hfedc0001 &&
              d_resource2_size==32'hfedc0002 && d_resource3_size==32'hfedc0003,"PIC sizes use current pos31");
        check(d_audio_cluster==32'h12340004 && d_audio_size==32'hfedc0004 &&
              d_index_cluster==32'h12340005 && d_index_size==32'hfedc0005,"audio and index metadata");
        // Batch entries in ROOT_WAIT: byte_index's upper bits are ignored there.
        // Deliberately non-storage-like streams are legal input-port sequences.
        for(n=0;n<6;n=n+1) begin
            for(p=0;p<11;p=p+1) begin
                for(v=0;v<256;v=v+1) begin
                    varied=target(n); varied[87-p*8 -:8]=v;
                    entry(varied,8'h20,32'h80000000+entries,32'ha5000000+entries);
                    substitutions=substitutions+1;
                end
            end
            for(v=0;v<256;v=v+1) begin
                entry(target(n),v,32'h90000000+entries,32'hff000000+entries);
                attributes=attributes+1;
            end
        end
        // Exact positive matches, with all byte and metadata endpoints exercised.
        entry(target(0),8'h20,0,0);
        check(d_resource0_cluster==0 && d_resource0_size==0,"zero metadata accepted");
        entry(target(0),8'h20,32'hffffffff,32'hffffffff);
        check(d_resource0_cluster==32'hffffffff && d_resource0_size==32'hffffffff,"duplicate last wins and full metadata");
        for(n=0;n<6;n=n+1) begin
            entry(target(n),8'h20,7,32'h01020304);
            send(11,0); metadata(8,32'hf1020304);
            // A failed repeated attr must preserve the preceding successful match.
            case(n)
                0:check(d_resource0_cluster==8 && d_resource0_size==32'hf1020304,"PIC1 sticky attr");
                1:check(d_resource1_cluster==8,"PIC2 sticky attr");
                2:check(d_resource2_cluster==8,"PIC3 sticky attr");
                3:check(d_resource3_cluster==8,"PIC4 sticky attr");
                4:check(d_audio_cluster==8,"audio sticky attr");
                5:check(d_index_cluster==8,"index sticky attr");
            endcase
            // Omit each nonzero name index: retained preceding byte must still match.
            for(p=1;p<11;p=p+1) begin
                varied=target(n); send(0,varied[87:80]);
                for(j=10;j>0;j=j-1) if(j!=p) begin send(j,varied[87-j*8 -:8]); gap; end
                send(11,8'h20); metadata(entries+1,32'h80000000+entries); entries=entries+1;
                omitted=omitted+1;
            end
            // Repeated positions, reordered names and repeated attr before/after name.
            varied=target(n); send(0,varied[87:80]); send(11,8'h20);
            for(j=10;j>0;j=j-1) begin send(j,0); send(j,varied[87-j*8 -:8]); end
            send(11,8'h20); send(3,0); send(11,8'h20); metadata(42,32'hc0ffee01);
            repeated=repeated+1;
        end
        // Without position zero, failed AUDIO recognition retains the prior PIC match.
        entry(target(0),8'h20,11,111);
        varied=target(4);
        for(j=1;j<11;j=j+1) send(j,varied[87-j*8 -:8]);
        send(11,8'h20); metadata(12,112);
        check(d_resource0_cluster==12,"failed name preserves match without position0");
        // First byte zero/deleted, long-file-name attr and all nonarchive attrs.
        varied=target(0); varied[87:80]=0; entry(varied,8'h20,13,113);
        varied[87:80]=8'he5; entry(varied,8'h20,14,114);
        entry(target(0),8'h0f,15,115);
        check(d_resource0_cluster==12,"empty deleted and LFN rejected");
        // Deterministic xorshift input schedule: random bytes, gaps, duplicate/omitted
        // metadata and arbitrary 9-bit positions; no hierarchical state forcing.
        for(j=0;j<30000;j=j+1) begin
            rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
            if(rng[2:0]==0) gap;
            else send(rng[8:0],rng[23:16]);
            if(j%257==0) begin
                @(negedge clk); scan_start=1; tick;
                @(negedge clk); scan_start=0; busy_starts=busy_starts+1;
            end
            random_events=random_events+1;
        end
        entry(target(5),8'h20,99,199); finish_scan(0,0);
        // Continuous scans, all accepted SPC values, both boot paths.
        for(n=0;n<8;n=n+1) begin
            open_root(n[0],1<<n); entry(target(5),8'h20,n+2,n+256); finish_scan(0,0);
            spc_cases=spc_cases+1;
        end
        open_root(1,4); entry(target(0),8'h20,123,456); finish_scan(8'h01,8'h10);
        open_root(0,2); finish_scan(0,8'h22); // early root done, no directory bytes
        // Transport errors at LBA0 and at the partition boot sector.
        prepare_boot(1); start_scan; done(8'hff); wait_finish(8'h10);
        start_scan;
        for(j=0;j<512;j=j+1) begin
            case(j)
                450:send(j,8'h0b); 454:send(j,100);
                510:send(j,8'h55); 511:send(j,8'haa); default:send(j,0);
            endcase
        end
        done(0); request(100); done(8'h80); wait_finish(8'h10);
        // Invalid boot signatures/BPB; early boot done uses existing buffer bytes.
        prepare_boot(1); boot[510]=0; start_scan; boot_stream; wait_finish(8'h20);
        prepare_boot(3); start_scan; boot_stream; wait_finish(8'h21);
        prepare_boot(1); start_scan; boot_stream; request(34); finish_scan(0,8'h22);
        start_scan; done(0); request(34); finish_scan(0,8'h22);
        // Async reset during a live scan and then clean recovery.
        open_root(0,1); name_bytes(target(0)); send(11,8'h20); reset;
        check(!d_scan_busy && !d_resource_valid && !d_audio_valid && !d_index_valid,"reset clears public validity");
        open_root(1,128); entry(target(5),8'h20,32'h80000000,32'habcdef12); finish_scan(0,0);
        // Held scan_start starts the next scan after one idle clock, by original contract.
        @(negedge clk); scan_start=1; tick; request(0); done(1);
        k=0; while(!d_scan_done && k<8) begin tick; k=k+1; end
        check(d_scan_done,"held start first scan done"); tick;
        check(d_scan_busy,"held start launches next scan");
        @(negedge clk); scan_start=0; request(0); done(1); wait_finish(8'h10);
        $display("COVERAGE seed=0x13579bdf final_rng=%h cycles=%0d bytes=%0d entries=%0d substitutions=%0d attributes=%0d omitted=%0d repeated=%0d gaps=%0d random_events=%0d scans=%0d requests=%0d resets=%0d spc_cases=%0d busy_starts=%0d assertions=%0d",rng,cycles,bytes,entries,substitutions,attributes,omitted,repeated,gaps,random_events,scans,requests,resets,spc_cases,busy_starts,assertions);
        $display("PASS: N1 directory equivalence all public outputs after NBA"); $finish;
    end
    initial begin #20000000; $display("FAIL: test timeout"); $fatal(1); end
endmodule
