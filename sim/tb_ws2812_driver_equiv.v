`timescale 1ns/1ps
module tb_ws2812_driver_equiv;
    parameter integer PIXELS=8;
    parameter integer REAL_TIMING=0;
    localparam integer LIMIT=REAL_TIMING ? 160000 : 40000;
    reg clk=0,rst_n=0,load=0;
    reg [PIXELS*24-1:0] payload=0, frozen=0;
    wire frame_pin,stream_pin,ref_pin,frame_busy,stream_busy,ref_busy;
    wire [4:0] pixel;
    wire [23:0] stream_color=frozen[pixel*24+:24];
    always #10 clk=~clk;
    ws2812_driver #(.PIXEL_COUNT(PIXELS),.BIT_CYCLES(REAL_TIMING ? 63 : 7),
        .T0H_CYCLES(REAL_TIMING ? 18 : 2),.T1H_CYCLES(REAL_TIMING ? 35 : 4),
        .RESET_CYCLES(REAL_TIMING ? 3000 : 5)) full_frame
        (.clk(clk),.rst_n(rst_n),.load(load),.grb_in(payload),.busy(frame_busy),.dout(frame_pin),
         .stream_grb(24'd0),.stream_pixel_index());
    ws2812_driver #(.PIXEL_COUNT(PIXELS),.BIT_CYCLES(REAL_TIMING ? 63 : 7),
        .T0H_CYCLES(REAL_TIMING ? 18 : 2),.T1H_CYCLES(REAL_TIMING ? 35 : 4),
        .RESET_CYCLES(REAL_TIMING ? 3000 : 5),.STREAMING(1)) stream
        (.clk(clk),.rst_n(rst_n),.load(load),.grb_in({PIXELS*24{1'b0}}),.busy(stream_busy),.dout(stream_pin),
         .stream_grb(stream_color),.stream_pixel_index(pixel));
    ws2812_driver_o4 #(.PIXEL_COUNT(PIXELS),.BIT_CYCLES(REAL_TIMING ? 63 : 7),
        .T0H_CYCLES(REAL_TIMING ? 18 : 2),.T1H_CYCLES(REAL_TIMING ? 35 : 4),
        .RESET_CYCLES(REAL_TIMING ? 3000 : 5)) golden
        (.clk(clk),.rst_n(rst_n),.load(load),.grb_in(payload),.busy(ref_busy),.dout(ref_pin));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) frozen<=0;
        else if(load && !stream_busy) frozen<=payload;
    end
    integer n,i,accepted=0,ignored=0,high_samples=0;
    reg [31:0] random_state=32'had21921a;
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(n=0;n<LIMIT;n=n+1) begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            load=(n%67==0 || n%500<20);
            for(i=0;i<PIXELS;i=i+1) payload[i*24+:24]=random_state[23:0]^(24'h438121*i);
            if(n==4000)rst_n=0;
            if(n==4003)rst_n=1;
            if(rst_n && load && !ref_busy) accepted=accepted+1;
            if(rst_n && load && ref_busy) ignored=ignored+1;
            @(posedge clk);#1;
            if(frame_pin!==ref_pin || stream_pin!==ref_pin || frame_busy!==ref_busy || stream_busy!==ref_busy) begin
                $display("FAIL WS_DRIVER pixels=%0d real=%0d cycle=%0d pins=%b%b%b busy=%b%b%b",PIXELS,REAL_TIMING,n,frame_pin,stream_pin,ref_pin,frame_busy,stream_busy,ref_busy);
                $fatal(1);
            end
            if(ref_pin)high_samples=high_samples+1;
        end
        if(accepted<3 || ignored<100 || high_samples<100)$fatal(1,"FAIL WS_DRIVER coverage");
        $display("PASS WS_DRIVER pixels=%0d real=%0d clocks=%0d accepted=%0d ignored=%0d",PIXELS,REAL_TIMING,LIMIT,accepted,ignored);
        $finish;
    end
endmodule
