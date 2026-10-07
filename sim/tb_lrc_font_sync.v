`timescale 1ns/1ps
module tb_lrc_font_sync;
    reg clk=0;
    always #10 clk=~clk;
    reg [9:0] addr=0;
    wire [15:0] actual, expected;
    reg [15:0] held;
    reg [31:0] random_state=32'h534C4943;
    integer n, checks=0;
    lrc_font_rom dut(.clk(clk),.addr(addr),.dout(actual));
    lrc_font_rom_o0 reference(.addr(addr),.dout(expected));
    task check_addr;
        input [9:0] a;
        begin
            @(negedge clk);held=actual;addr=a;
            #1;
            if(actual!==held) $fatal(1,"ROM changed without clock");
            @(posedge clk);#1;
            if(actual!==expected) $fatal(1,"ROM address %d got %h expected %h",addr,actual,expected);
            if(addr>=960 && actual!==16'h0000) $fatal(1,"ROM padding not zero");
            checks=checks+1;
        end
    endtask
    initial begin
        for(n=0;n<1024;n=n+1) check_addr(n);
        for(n=0;n<4096;n=n+1) begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            check_addr(random_state[9:0]);
        end
        check_addr(0);check_addr(15);check_addr(16);check_addr(511);check_addr(512);
        check_addr(959);check_addr(960);check_addr(1023);check_addr(0);
        $display("PASS synchronous font ROM: %0d reads, 1024 addresses, random and boundary, exact glyphs and zero padding",checks);
        $finish;
    end
endmodule
