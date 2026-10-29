`timescale 1ns/1ps
module tb_background_capability;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,cap=0,request2=0,raw_active=0,fin=0,mv=1;
    reg [31:0] base=1000;
    wire [5:0] info;
    wire inv,wr,active,sr,ss,pv;
    wire [31:0] lba,pixel;
    wire [20:0] address;
    integer cursor=0,drain=0,pixels=0,issued=0;
    reg [31:0] expected_lba=0;
    wire valid=raw_active && ss && cursor<512;
    wire done=raw_active && ss && cursor==512;
    background_cache_loader #(.FRAME_SECTORS(1)) dut(
        .clk(clk),.rst_n(rst_n),.enable(enable),.base_lba(base),.song_id(2'd0),
        .art2_supported(cap),.art_request_async(1'b1),.art2_request_async(request2),
        .mv_writer_active(mv),.invalidate_ack_async(inv),.write_ack(wr),
        .write_finish_toggle(fin),.ready_info(info),.invalidate_toggle(inv),
        .writer_active(active),.write_req(wr),.write_hold(),.write_cancel(),
        .write_address(address),.pixel_valid(pv),.pixel_data(pixel),
        .sector_req(sr),.sector_start(ss),.sector_lba(lba),.sector_busy(raw_active),
        .sector_grant(raw_active),.sector_valid(valid),.sector_byte(8'h5a),
        .sector_byte_index(cursor[8:0]),.sector_done(done),.sector_error(8'd0));
    // Hold MV until the capability/request synchronizers settle; normal
    // arbitration must then select the right artwork generation.
    always @(posedge clk) begin
        if(!rst_n) begin raw_active<=0;cursor<=0;drain<=0;fin<=0;end
        else begin
            if(sr && !raw_active) begin
                if(lba!==expected_lba) $fatal(1,"cap=%0d request2=%0d LBA%h expected%h",cap,request2,lba,expected_lba);
                raw_active<=1;cursor<=0;issued=issued+1;
            end else if(valid) cursor<=cursor+1;
            else if(done) raw_active<=0;
            if(dut.state==7 || dut.state==9) begin
                if(drain==8) begin fin<=!fin;drain<=0;end else drain<=drain+1;
            end else drain<=0;
            if(pv) pixels=pixels+1;
        end
    end
    task check_start;
        input capability,want2;
        input [31:0] start_base;
        integer cycles;
        begin
            mv=1;
            @(negedge clk);rst_n=0;enable=0;
            repeat(4) @(negedge clk);
            cap=capability;request2=want2;base=start_base;pixels=0;issued=0;
            expected_lba=start_base+((capability && want2)?6000:4800);
            rst_n=1;enable=1;
            repeat(12) @(negedge clk);
            mv=0;
            cycles=0;
            while(!(capability && want2 ? info[4] : info[3]) && cycles<3000) begin @(negedge clk);cycles=cycles+1;end
            if(!(capability && want2 ? info[4] : info[3]) || pixels!=256 || issued!=1)
                $fatal(1,"art tag/count cap%0d want%0d info%b pixels%0d requests%0d",capability,want2,info,pixels,issued);
        end
    endtask
    initial begin
        check_start(0,1,1000);
        check_start(1,1,2000);
        check_start(1,0,3000);
        check_start(0,0,4000);
        $display("PASS tb_background_capability art1/art2 capability, request, reset/reload and exact one-sector publication");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
