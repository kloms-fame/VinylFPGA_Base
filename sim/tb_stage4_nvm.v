`timescale 1ns/1ps
// Bit-level mode-0 NOR model: separate CS commands, WEL/WIP, erase,
// one-way programming, persistent contents across FPGA-only resets.
module nvm_test_flash(
    input wire clk, cs_n, sclk, mosi,
    input wire absent, wrong_id, deny_wren, protect,
    output reg miso = 1
);
    reg [7:0] mem [0:8191];
    reg [7:0] pending [0:255];
    reg [7:0] command=0, in_byte=0, out_byte=8'hff;
    reg [23:0] address=0;
    reg wel=0;
    integer bit_count=0, byte_count=0, pending_count=0;
    integer busy_cycles=0, erase_count=0, program_count=0;
    integer j;
    initial for(j=0;j<8192;j=j+1) mem[j]=8'hff;
    always @(posedge clk) if(busy_cycles>0) busy_cycles<=busy_cycles-1;
    always @(negedge cs_n) begin
        command=0;in_byte=0;out_byte=8'hff;address=0;
        bit_count=0;byte_count=0;pending_count=0;miso=1;
    end
    always @(posedge sclk) if(!cs_n && !absent) begin
        in_byte={in_byte[6:0],mosi};
        if(bit_count==7) begin
            bit_count=0;
            if(byte_count==0) begin
                command=in_byte;
                if(busy_cycles!=0 && in_byte!=8'h05 && in_byte!=8'hab)
                    $fatal(1,"host issued %h before WIP cleared",in_byte);
                case(in_byte)
                    8'h9f: out_byte=wrong_id ? 8'h00 : 8'hef;
                    8'h05: out_byte={5'd0,protect,wel,(busy_cycles!=0)};
                    8'h03,8'h02,8'h20,8'h06,8'hab: out_byte=8'hff;
                    default: $fatal(1,"unsupported SPI opcode %h",in_byte);
                endcase
            end else if((command==8'h03 || command==8'h02 || command==8'h20) && byte_count<=3) begin
                address={address[15:0],in_byte};
                if(byte_count==3) begin
                    if(address<24'h7fe000 || address>24'h7fffff)
                        $fatal(1,"Flash address escaped reserved window: %h",address);
                    if(command==8'h03) out_byte=mem[address[12:0]];
                end
            end else if(command==8'h03) begin
                address=address+1'b1;out_byte=mem[address[12:0]];
            end else if(command==8'h02) begin
                pending[pending_count]=in_byte;pending_count=pending_count+1;
                if(pending_count>16 || address[7:0]+pending_count>256)
                    $fatal(1,"page program exceeded record/page boundary");
            end else if(command==8'h9f) begin
                out_byte=byte_count==1 ? 8'h40 : byte_count==2 ? 8'h17 : 8'hff;
            end else if(command==8'h05)
                out_byte={5'd0,protect,wel,(busy_cycles!=0)};
            byte_count=byte_count+1;
        end else bit_count=bit_count+1;
    end
    always @(negedge sclk) if(!cs_n)
        miso=absent ? 1'b1 : out_byte[7-bit_count];
    always @(posedge cs_n) begin
        miso=1;
        if(!absent && busy_cycles==0) begin
            if(command==8'h06 && byte_count>=1 && !deny_wren) wel=1;
            if(command==8'h20 && byte_count==4 && wel && !protect) begin
                if(address[11:0]!=0) $fatal(1,"unaligned sector erase");
                for(j=0;j<4096;j=j+1) mem[{address[12],12'd0}+j]=8'hff;
                erase_count=erase_count+1;wel=0;busy_cycles<=120;
            end
            if(command==8'h02 && pending_count>0 && wel && !protect) begin
                for(j=0;j<pending_count;j=j+1)
                    mem[address[12:0]+j]=mem[address[12:0]+j]&pending[j];
                program_count=program_count+1;wel=0;busy_cycles<=60;
            end
        end
    end
endmodule

module tb_stage4_nvm;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0, defaults_req=0, manual_save=0, auto_enable=0;
    reg wr_valid=0, wr_up=0;
    reg [2:0] wr_id=0;
    reg absent=0, wrong_id=0, deny_wren=0, protect=0;
    reg [5:0] ms_div=0;
    wire tick_1ms=ms_div==39;
    always @(posedge clk) if(!rst_n || tick_1ms) ms_div<=0;else ms_div<=ms_div+1'b1;
    wire [7:0] volume;
    wire [2:0] bri,con,rot,wsl;
    wire [19:0] params={wsl,rot,con,bri,volume};
    localparam [19:0] DEFAULTS={3'd4,3'd2,3'd2,3'd3,8'd200};
    wire updated, restore_valid;
    wire [19:0] restore_data;
    wire [3:0] led;
    wire cs_n,sclk,mosi,miso,wp_n,hold_n;
    ui_param_csr csr(.clk(clk),.rst_n(rst_n),.defaults_req(defaults_req),
        .restore_valid(restore_valid),.restore_data(restore_data),
        .wr_valid(wr_valid),.wr_id(wr_id),.wr_up(wr_up),.volume(volume),
        .brightness_level(bri),.contrast_level(con),.rotation_level(rot),.ws_level(wsl),
        .param_update(updated));
    ui_param_persistence #(.AUTO_SAVE_MS(5),.SPI_HALF_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.current_params(params),
        .param_update(updated),.user_write(wr_valid),.defaults_req(defaults_req),
        .manual_save(manual_save),.auto_enable(auto_enable),
        .restore_valid(restore_valid),.restore_data(restore_data),.led_status(led),
        .flash_cs_n(cs_n),.flash_sclk(sclk),.flash_mosi(mosi),.flash_miso(miso),
        .flash_wp_n(wp_n),.flash_hold_n(hold_n));
    nvm_test_flash flash(.clk(clk),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso),
        .absent(absent),.wrong_id(wrong_id),.deny_wren(deny_wren),.protect(protect));
    task reboot;
        begin @(negedge clk);rst_n=0;repeat(8) @(negedge clk);rst_n=1;end
    endtask
    task ready;
        integer n;
        begin
            n=0;while(!dut.store_ready && n<200000) begin @(negedge clk);n=n+1;end
            if(!dut.store_ready) $fatal(1,"startup timeout state=%0d",dut.u_store.state);
            repeat(8) @(negedge clk);
        end
    endtask
    task write_param;
        input [2:0] id;input up;
        begin @(negedge clk);wr_id=id;wr_up=up;wr_valid=1;
            @(negedge clk);wr_valid=0;repeat(3) @(negedge clk);end
    endtask
    task press_save;
        begin @(negedge clk);manual_save=1;@(negedge clk);manual_save=0;end
    endtask
    task press_defaults;
        begin @(negedge clk);defaults_req=1;@(negedge clk);defaults_req=0;end
    endtask
    task finish_save;
        integer n;
        begin
            n=0;while(!led[2] && !led[3] && n<200000) begin @(negedge clk);n=n+1;end
            if(n==200000) $fatal(1,"save did not start");
            while(led[2] && n<400000) begin @(negedge clk);n=n+1;end
            if(n==400000 || led[3]) $fatal(1,"save failed code=%0d state=%0d",dut.store_fault_code,dut.u_store.state);
            repeat(8) @(negedge clk);
        end
    endtask
    function [15:0] crc_byte;
        input [15:0] c;input [7:0] d;
        integer k;reg [15:0] r;
        begin r=c^{d,8'd0};for(k=0;k<8;k=k+1) r=r[15] ? (r<<1)^16'h1021 : r<<1;crc_byte=r;end
    endfunction
    task seed_record;
        input integer slot;input [7:0] seq;input [19:0] p;
        integer k,b;reg [15:0] c;
        begin
            b=slot*4096;for(k=0;k<4096;k=k+1) flash.mem[b+k]=8'hff;
            flash.mem[b]=8'h56;flash.mem[b+1]=8'h50;flash.mem[b+2]=1;flash.mem[b+3]=0;
            flash.mem[b+4]=0;flash.mem[b+5]=seq;flash.mem[b+6]=p[7:0];
            flash.mem[b+7]={5'd0,p[10:8]};flash.mem[b+8]={5'd0,p[13:11]};
            flash.mem[b+9]={5'd0,p[16:14]};flash.mem[b+10]={5'd0,p[19:17]};flash.mem[b+11]=0;
            c=16'hffff;for(k=0;k<12;k=k+1)c=crc_byte(c,flash.mem[b+k]);
            flash.mem[b+12]=c[15:8];flash.mem[b+13]=c[7:0];flash.mem[b+14]=8'ha5;flash.mem[b+15]=8'h5a;
        end
    endtask
    reg [19:0] expected,a;
    integer n,writes_before,old_slot;
    initial begin
        reboot;ready;
        if(params!==DEFAULTS || led[3] || led[0]) $fatal(1,"blank Flash fallback");
        write_param(0,1);write_param(1,0);write_param(2,1);write_param(3,1);write_param(4,0);
        expected=params;press_save;finish_save;
        if(!led[1] || flash.program_count!=2 || !wp_n || !hold_n) $fatal(1,"manual save/commit");
        reboot;ready;if(params!==expected || !led[0] || !led[1]) $fatal(1,"atomic startup restore %h expected %h",params,expected);
        writes_before=flash.erase_count;press_save;repeat(600) @(negedge clk);
        if(flash.erase_count!=writes_before) $fatal(1,"duplicate save caused wear");
        auto_enable=1;write_param(4,0);expected=params;
        repeat(100) @(negedge clk);
        if(flash.erase_count!=writes_before) $fatal(1,"autosave fired before inactivity timeout");
        finish_save;auto_enable=0;reboot;ready;
        if(params!==expected) $fatal(1,"autosave restore");
        $display("PASS manual/auto/duplicate suppression/restore");

        write_param(0,0);press_save;wait(led[2]);write_param(0,0);expected=params;finish_save;
        if(led[1]) $fatal(1,"edit during save incorrectly marked durable");
        press_save;finish_save;reboot;ready;if(params!==expected) $fatal(1,"edit during save lost");
        $display("PASS immutable save snapshot and subsequent user edits");

        a=params;write_param(0,0);press_save;
        n=0;while(!(dut.u_store.state==10 && dut.u_store.read_mode==2) && n<100000) begin @(negedge clk);n=n+1;end
        if(n==100000) $fatal(1,"failed to locate payload verification phase");
        reboot;ready;if(params!==a) $fatal(1,"uncommitted write replaced last good slot");
        write_param(0,0);expected=params;press_save;finish_save;
        old_slot=dut.u_store.active_slot;
        flash.mem[old_slot*4096+6]=flash.mem[old_slot*4096+6]^8'h01;
        reboot;ready;if(params!==a) $fatal(1,"corrupt latest slot did not fall back");
        $display("PASS interrupted payload and CRC-corrupt newest slot fallback");

        seed_record(0,8'hff,DEFAULTS);seed_record(1,8'h00,{3'd1,3'd3,3'd4,3'd0,8'd91});
        expected={3'd1,3'd3,3'd4,3'd0,8'd91};reboot;ready;
        if(params!==expected) $fatal(1,"sequence wrap selection");
        press_defaults;repeat(3) @(negedge clk);
        if(params!==DEFAULTS) $fatal(1,"KEY2 runtime defaults");
        finish_save;old_slot=~dut.u_store.active_slot & 1;
        for(n=0;n<4096;n=n+1) if(flash.mem[old_slot*4096+n]!==8'hff) $fatal(1,"KEY2 old slot not erased");
        reboot;ready;if(params!==DEFAULTS || !led[0]) $fatal(1,"KEY2 durable defaults");
        $display("PASS sequence wrap and KEY2 committed defaults plus old-sector erase");

        seed_record(0,16'd8,expected);seed_record(1,16'd9,DEFAULTS);
        flash.mem[4096+7]=8'd9; // impossible brightness, with a fresh valid CRC
        begin: bad_range
            reg [15:0] cc;integer k;
            cc=16'hffff;for(k=0;k<12;k=k+1)cc=crc_byte(cc,flash.mem[4096+k]);
            flash.mem[4096+12]=cc[15:8];flash.mem[4096+13]=cc[7:0];
        end
        reboot;ready;if(params!==expected) $fatal(1,"range-invalid record restored");
        reboot;write_param(0,1);a=params;ready;
        if(params!==a || led[0]) $fatal(1,"late startup load overwrote user write");
        $display("PASS range validation and startup user-write priority");

        // KEY2 arriving during an ordinary save must queue a durable default
        // record after that immutable transaction, even with autosave disabled.
        reboot;ready;write_param(0,1);press_save;wait(led[2]);press_defaults;
        n=0;while((!led[1] || dut.defaults_pending || dut.inflight || led[2]) && !led[3] && n<200000)
            begin @(negedge clk);n=n+1;end
        if(n==200000 || led[3]) $fatal(1,"KEY2 during save queue");
        reboot;ready;if(params!==DEFAULTS) $fatal(1,"queued KEY2 not durable");
        $display("PASS KEY2 during save queues committed defaults");

        // Damage target payload before verification: no commit may be written.
        a=params;write_param(0,0);press_save;
        n=0;while(!(dut.u_store.state==9 && dut.u_store.read_mode==2) && n<100000)
            begin @(negedge clk);n=n+1;end
        if(n==100000) $fatal(1,"verify injection phase unavailable");
        old_slot=dut.u_store.target_slot;
        flash.mem[old_slot*4096+6]=flash.mem[old_slot*4096+6]^8'h01;
        n=0;while(!led[3] && n<100000) begin @(negedge clk);n=n+1;end
        if(!led[3] || dut.store_fault_code!=4 || flash.mem[old_slot*4096+14]!=8'hff)
            $fatal(1,"failed verification still committed");
        reboot;ready;if(params!==a) $fatal(1,"verify failure destroyed previous config");
        $display("PASS readback failure prevents commit and preserves previous record");

        flash.busy_cycles=2500;reboot;ready;
        if(params!==a || led[3]) $fatal(1,"startup did not wait for pre-existing WIP");
        seed_record(0,8'd40,expected);seed_record(1,8'd41,expected);
        flash.mem[2]=2; // newer, CRC-correct but unsupported format
        begin: bad_version
            reg [15:0] cc;integer k;
            cc=16'hffff;for(k=0;k<12;k=k+1)cc=crc_byte(cc,flash.mem[k]);
            flash.mem[12]=cc[15:8];flash.mem[13]=cc[7:0];
        end
        flash.mem[4096+14]=8'hff; // incomplete commit, otherwise valid
        reboot;ready;
        if(params!==DEFAULTS || led[0] || led[3]) $fatal(1,"invalid version/incomplete commit fallback");
        $display("PASS pre-existing WIP, unknown version and incomplete commit rejection");

        wrong_id=1;writes_before=flash.erase_count;reboot;ready;
        if(!led[3] || params!==DEFAULTS) $fatal(1,"wrong JEDEC ID fallback");
        press_save;repeat(500) @(negedge clk);if(flash.erase_count!=writes_before) $fatal(1,"write with wrong ID");
        wrong_id=0;deny_wren=1;reboot;ready;write_param(0,1);press_save;
        wait(led[2]);wait(!led[2]);repeat(8) @(negedge clk);
        if(!led[3] || dut.store_fault_code!=3 || flash.erase_count!=writes_before) $fatal(1,"WEL check failed");
        deny_wren=0;protect=1;reboot;ready;write_param(0,1);press_save;
        wait(led[2]);wait(!led[2]);repeat(8) @(negedge clk);
        if(!led[3] || dut.store_fault_code!=3 || flash.erase_count!=writes_before) $fatal(1,"protection check failed");
        protect=0;absent=1;reboot;ready;
        if(!led[3] || dut.store_fault_code!=2 || params!==DEFAULTS) $fatal(1,"no-Flash timeout fallback");
        $display("PASS wrong ID, WEL denial, missing Flash timeout; all writes confined to reserved sectors");
        $display("PASS STAGE4_NVM");$finish;
    end
    initial begin #100000000; $fatal(1,"global simulation watchdog");end
endmodule
