`timescale 1ns/1ps
// Transaction scoreboard for validation, fragmented chains and bounded errors.
module tb_fat32_streamer_boundaries;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0;
    reg [31:0] first=2,size=0,maximum=400;
    reg [7:0] spc=1,serror=0;
    wire busy,done,fvalid,req;
    wire [7:0] data,error;
    wire [31:0] offset,lba;
    reg reading=0;
    reg same_cycle_done=0;
    integer cursor=0,case_id=0,got=0,requests=0,data_requests=0;
    reg [31:0] served=0;
    wire svalid=reading && cursor<512;
    wire sdone=reading && cursor==(same_cycle_done ? 511 : 512);
    reg [27:0] fat[0:511];
    reg [31:0] expected_lba[0:15];
    reg [31:0] output_lba[0:15];
    integer expected_requests=0;
    wire [31:0] fat_word={4'd0,fat[((served-10)*128)+(cursor>>2)]};
    wire [7:0] sbyte=(served>=10 && served<14) ?
        (fat_word >> ((cursor%4)*8)) : ((served*7+cursor)&255);
    fat32_file_streamer #(.MAX_VISITED_CLUSTERS(4)) dut(
        .clk(clk),.rst_n(rst_n),.file_start(start),.first_cluster(first),.file_size(size),
        .sectors_per_cluster(spc),.fat_start_lba(32'd10),.data_start_lba(32'd100),
        .max_cluster(maximum),.file_busy(busy),.file_done(done),.file_valid(fvalid),
        .file_byte(data),.file_byte_offset(offset),.fs_error(error),.sector_req(req),
        .sector_lba(lba),.sector_busy(reading),.sector_valid(svalid),.sector_byte(sbyte),
        .sector_byte_index(cursor[8:0]),.sector_done(sdone),.sector_error(serror));
    always @(posedge clk) begin
        if(!rst_n) begin reading<=0;cursor<=0;end
        else if(req && !reading) begin
            if(requests>=expected_requests || lba!==expected_lba[requests])
                $fatal(1,"case%0d request%0d LBA%0d expected%0d",case_id,requests,lba,expected_lba[requests]);
            if(lba>=100) begin output_lba[data_requests]=lba;data_requests=data_requests+1;end
            requests=requests+1;served<=lba;cursor<=0;reading<=1;
        end else if(reading) begin
            if(sdone) reading<=0;else cursor<=cursor+1;
        end
        if(rst_n && fvalid) begin
            if(offset!==got || data!==((output_lba[got/512]*7+(got%512))&255))
                $fatal(1,"case%0d output byte%0d data%h offset%0d",case_id,got,data,offset);
            got=got+1;
        end
    end
    task reset_case;
        input integer n;
        begin
            @(negedge clk);rst_n=0;start=0;case_id=n;
            repeat(3) @(negedge clk);
            rst_n=1;got=0;requests=0;data_requests=0;size=512;first=2;spc=1;maximum=400;serror=0;
            expected_requests=0;same_cycle_done=0;
            for(integer j=0;j<512;j=j+1) fat[j]=28'hfffffff;
        end
    endtask
    task run_case;
        input [7:0] expected_error;
        input integer expected_bytes;
        integer limit;
        begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;limit=0;
            while(!done && limit<15000) begin @(negedge clk);limit=limit+1;end
            if(!done || error!==expected_error || got!=expected_bytes || requests!=expected_requests)
                $fatal(1,"case%0d done%0d err%h expected%h bytes%0d/%0d req%0d/%0d",case_id,done,error,expected_error,got,expected_bytes,requests,expected_requests);
            $display("PASS FAT case%0d error=%h bytes=%0d requests=%0d",case_id,error,got,requests);
        end
    endtask
    initial begin
        reset_case(1);size=0;run_case(0,0);
        reset_case(2);first=1;run_case(8'h24,0);
        reset_case(3);first=401;run_case(8'h24,0);
        reset_case(4);spc=0;run_case(8'h24,0);
        reset_case(5);expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(0,512);
        reset_case(6);size=1024;fat[2]=130;expected_requests=4;
        expected_lba[0]=100;expected_lba[1]=10;expected_lba[2]=228;expected_lba[3]=11;run_case(0,1024);
        reset_case(7);size=1024;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(8'h25,512);
        reset_case(8);size=1024;fat[2]=1;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(8'h24,512);
        reset_case(9);size=1024;fat[2]=2;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(8'h23,512);
        reset_case(10);size=2560;fat[2]=3;fat[3]=2;expected_requests=8;
        expected_lba[0]=100;expected_lba[1]=10;expected_lba[2]=101;expected_lba[3]=10;
        expected_lba[4]=100;expected_lba[5]=10;expected_lba[6]=101;expected_lba[7]=10;run_case(8'h26,2048);
        reset_case(11);serror=8'h01;expected_requests=1;expected_lba[0]=100;run_case(8'h10,512);
        reset_case(12);size=17;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(0,17);
        reset_case(13);spc=2;size=1024;expected_requests=3;
        expected_lba[0]=100;expected_lba[1]=101;expected_lba[2]=10;run_case(0,1024);
        reset_case(14);first=400;expected_requests=2;expected_lba[0]=498;expected_lba[1]=13;run_case(0,512);
        reset_case(15);size=1;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(0,1);
        reset_case(16);size=511;expected_requests=2;expected_lba[0]=100;expected_lba[1]=10;run_case(0,511);
        reset_case(17);size=513;spc=2;expected_requests=3;
        expected_lba[0]=100;expected_lba[1]=101;expected_lba[2]=10;run_case(0,513);
        reset_case(18);same_cycle_done=1;expected_requests=2;
        expected_lba[0]=100;expected_lba[1]=10;run_case(0,512);
        reset_case(19);size=17;same_cycle_done=1;expected_requests=2;
        expected_lba[0]=100;expected_lba[1]=10;run_case(0,17);
        $display("PASS tb_fat32_streamer_boundaries");$finish;
    end
    initial begin #3000000;$fatal(1,"global timeout");end
endmodule
