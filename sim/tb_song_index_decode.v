`timescale 1ns/1ps
// All entry/lane bytes change on every reload. Gaps and done on the final
// valid beat exercise decode/data alignment, rather than only zero high lanes.
module tb_song_index_decode;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,iv=0,id=0;
    reg [7:0] ib=0;
    wire done,valid;
    wire [7:0] err;
    wire [2:0] count;
    wire [63:0] c0,c1,c2,c3,a0,a1,a2,a3;
    reg [7:0] blob[0:319];
    reg [31:0] expected_c[0:3],expected_b[0:3],expected_a[0:3],expected_ab[0:3];
    reg [31:0] crc;
    integer round_no,i,j,k,t;
    song_index_db dut(.clk(clk),.rst_n(rst_n),.start(start),.in_valid(iv),.in_byte(ib),
        .in_done(id),.in_error(8'd0),.max_cluster(32'h7fffffff),.valid(valid),.done(done),.err(err),
        .song_count(count),.song_cover0(c0),.song_cover1(c1),.song_cover2(c2),.song_cover3(c3),
        .song_audio0(a0),.song_audio1(a1),.song_audio2(a2),.song_audio3(a3));
    task put_word;
        input integer pos;
        input [31:0] value;
        begin for(integer lane=0;lane<4;lane=lane+1) blob[pos+lane]=value>>(8*lane);end
    endtask
    initial begin
        #22;rst_n=1;
        for(round_no=0;round_no<8;round_no=round_no+1) begin
            for(i=0;i<320;i=i+1) blob[i]=0;
            blob[0]="V";blob[1]="I";blob[2]="N";blob[3]="Y";
            blob[4]="L";blob[5]="I";blob[6]="D";blob[7]="X";
            blob[8]=1;blob[10]=64;blob[12]=4;
            for(j=0;j<4;j=j+1) begin
                expected_c[j]=32'h12345602+round_no*65539+j*131079;
                expected_b[j]=32'h89abcdef+round_no*65793+j*263175;
                expected_a[j]=32'h23456703+round_no*66049+j*132103;
                expected_ab[j]=32'h76543210+round_no*131331+j*197379;
                blob[64+j*64]=3;
                put_word(68+j*64,expected_c[j]);put_word(72+j*64,expected_b[j]);
                put_word(80+j*64,expected_a[j]);put_word(84+j*64,expected_ab[j]);
            end
            crc=32'hffffffff;
            for(i=64;i<320;i=i+1) begin
                crc=crc^blob[i];
                for(k=0;k<8;k=k+1) crc=(crc>>1)^(crc[0]?32'hedb88320:0);
            end
            put_word(16,crc^32'hffffffff);
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            for(i=0;i<320;i=i+1) begin
                if((i+round_no)%7==0) begin @(negedge clk);iv=0;end
                @(negedge clk);iv=1;ib=blob[i];id=(i==319);
            end
            @(negedge clk);iv=0;id=0;t=0;
            while(!done && t<30) begin @(negedge clk);t=t+1;end
            if(!done || !valid || err!=0 || count!=4)
                $fatal(1,"round%0d completion valid%0d err%h count%0d",round_no,valid,err,count);
            if(c0!=={expected_b[0],expected_c[0]} || c1!=={expected_b[1],expected_c[1]} ||
               c2!=={expected_b[2],expected_c[2]} || c3!=={expected_b[3],expected_c[3]} ||
               a0!=={expected_ab[0],expected_a[0]} || a1!=={expected_ab[1],expected_a[1]} ||
               a2!=={expected_ab[2],expected_a[2]} || a3!=={expected_ab[3],expected_a[3]})
                $fatal(1,"round%0d entry/data/lane mismatch",round_no);
            @(negedge clk);
        end
        $display("PASS tb_song_index_decode 8 reloads all 64 field byte lanes, gaps, coincident valid/done");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
