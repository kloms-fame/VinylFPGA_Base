`timescale 1ns/1ps
// Use the production wrapper and actual TD model, without SIM RAM substitution.
module tb_vendor_stage;
    reg a_clk=0,b_clk=0;
    always #5 a_clk=~a_clk;
    always #4 b_clk=~b_clk;
    reg a_en=0,a_we=0,b_en=0,b_we=0;
    reg [9:0] a_addr=0,b_addr=0;
    reg [7:0] a_din=0,b_din=0;
    wire [7:0] a_dout,b_dout;
    audio_prefetch_stage dut (
        .a_clk(a_clk),.a_en(a_en),.a_we(a_we),.a_addr(a_addr),
        .a_din(a_din),.a_dout(a_dout),
        .b_clk(b_clk),.b_en(b_en),.b_we(b_we),.b_addr(b_addr),
        .b_din(b_din),.b_dout(b_dout)
    );
    integer n;
    reg [7:0] held;
    function [7:0] producer_byte;
        input integer index;
        begin producer_byte=(index*29)^8'ha7;end
    endfunction
    function [7:0] consumer_byte;
        input integer index;
        begin consumer_byte=(index*17)^8'h5c;end
    endfunction
    initial begin
        #100;
        for(n=0;n<512;n=n+1) begin
            @(negedge a_clk);a_en=1;a_we=1;a_addr=n;a_din=producer_byte(n);
        end
        @(negedge a_clk);a_en=0;a_we=0;
        for(n=0;n<512;n=n+1) begin
            @(negedge b_clk);b_en=1;b_we=0;b_addr=n;
            @(posedge b_clk);#1;
            if(b_dout!==producer_byte(n))
                $fatal(1,"B synchronous read[%0d]=%h expected %h",n,b_dout,producer_byte(n));
        end
        @(negedge b_clk);b_en=0;held=b_dout;b_addr=0;
        repeat(3) begin
            @(posedge b_clk);#1;
            if(b_dout!==held) $fatal(1,"B disabled CS changed output");
        end
        for(n=0;n<512;n=n+1) begin
            @(negedge b_clk);b_en=1;b_we=1;b_addr=512+n;b_din=consumer_byte(n);
        end
        @(negedge b_clk);b_en=0;b_we=0;
        for(n=0;n<512;n=n+1) begin
            @(negedge a_clk);a_en=1;a_we=0;a_addr=512+n;
            @(posedge a_clk);#1;
            if(a_dout!==consumer_byte(n))
                $fatal(1,"A synchronous read[%0d]=%h expected %h",n,a_dout,consumer_byte(n));
        end
        @(negedge a_clk);a_en=0;held=a_dout;a_addr=0;a_we=1;a_din=8'h00;
        repeat(3) begin
            @(posedge a_clk);#1;
            if(a_dout!==held) $fatal(1,"A disabled CS changed output");
        end
        @(negedge a_clk);a_en=1;a_we=0;a_addr=0;
        @(posedge a_clk);#1;
        if(a_dout!==producer_byte(0)) $fatal(1,"disabled A write modified producer data");
        $display("PASS actual EG_PHY_BRAM32K DP16K: dual-clock bidirectional 512-byte sectors, one-cycle NOREG read, active-high CS, disabled CS holds data");
        $finish;
    end
    initial begin #100000;$fatal(1,"vendor stage timeout");end
endmodule
