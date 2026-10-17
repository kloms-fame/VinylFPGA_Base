`timescale 1ns/1ps
// Arithmetic boundary check at the actual byte-53 decision point. Streamed
// scan/load tests separately verify the producer and header-byte alignment.
module tb_header_payload_bounds;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] length=0,ending=0;
    reg [5:0] position=48;
    integer i,checks=0;
    fat32_media_loader dut(.clk(clk),.rst(rst),.sd_init_done(1'b1));
    task check_pair;
        begin
            position=48;
            for(integer beat=49;beat<=53;beat=beat+1) begin
                @(negedge clk);position=beat;
            end
            @(negedge clk);
            if(dut.header_payload_ok !== (length>=ending))
                $fatal(1,"payload bounds length%h end%h",length,ending);
            checks=checks+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        force dut.load_state=dut.LD_HEADER;
        force dut.bmp_stream_valid=1'b1;
        force dut.header_byte_cnt=position;
        force dut.file_len=length;
        force dut.pixel_end=ending;
        length=0;ending=0;check_pair;
        length=54;ending=55;check_pair;
        length=55;ending=55;check_pair;
        length=32'hffff;ending=32'h10000;check_pair;
        length=32'h10000;ending=32'hffff;check_pair;
        length=32'hffffffff;ending=32'hffffffff;check_pair;
        length=0;ending=32'hffffffff;check_pair;
        for(i=0;i<10000;i=i+1) begin length=$random;ending=$random;check_pair;end
        $display("PASS tb_header_payload_bounds %0d vectors including byte-53 decision, high/low carry boundary and unsigned limits",checks);$finish;
    end
endmodule
