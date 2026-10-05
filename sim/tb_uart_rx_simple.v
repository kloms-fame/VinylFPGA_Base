`timescale 1ns/1ps

module tb_uart_rx_simple;
    localparam integer CPB = 10;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg rx = 1'b1;
    wire [7:0] data;
    wire valid;
    integer i;

    uart_rx #(
        .CLKS_PER_BIT(CPB)
    ) dut (
        .clk(clk), .rst_n(rst_n), .rx(rx), .data(data), .valid(valid)
    );

    always #5 clk = ~clk;

    task send_bit;
        input value;
        begin
            rx = value;
            repeat (CPB) @(posedge clk);
        end
    endtask

    task send_byte;
        input [7:0] value;
        begin
            send_bit(1'b0);
            for (i = 0; i < 8; i = i + 1)
                send_bit(value[i]);
            send_bit(1'b1);
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(negedge clk);
        fork
            send_byte(8'hA5);
            begin
                wait (valid);
                if (data !== 8'hA5) begin
                    $display("TEST_FAIL uart_rx_simple");
                    $finish;
                end
            end
        join
        $display("TEST_PASS uart_rx_simple");
        $finish;
    end
endmodule
