`ifndef NVM_SPI_TRANSACTION_V
`define NVM_SPI_TRANSACTION_V
// Mode 0, MSB first. One opcode, optional 24-bit address, up to 16 data bytes.
// All command inputs remain stable until done. CS setup/hold/high each >= half period.
module nvm_spi_transaction #(
    parameter integer HALF_CYCLES = 8
)(
    input wire clk, rst_n, start,
    input wire [7:0] command,
    input wire address_enable,
    input wire [23:0] address,
    input wire [4:0] length,
    input wire [7:0] tx_data,
    output reg [4:0] data_index = 0,
    output reg [4:0] rx_index = 0,
    output wire [7:0] rx_data,
    output reg rx_valid = 0, busy = 0, done = 0,
    output reg cs_n = 1, sclk = 0,
    output wire mosi,
    input wire miso
);
    localparam IDLE=0, SETUP=1, SHIFT=2, NEXT_DATA=3, HOLD=4, GAP=5;
    localparam CW = (HALF_CYCLES < 2) ? 1 : $clog2(HALF_CYCLES);
    reg [2:0] state = IDLE, bit_index = 7;
    reg [CW-1:0] count = 0;
    reg [7:0] tx_shift = 0, rx_shift = 0;
    reg [1:0] header_index = 0;
    reg data_phase = 0;
    assign mosi = tx_shift[7];
    assign rx_data = rx_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE;bit_index<=7;count<=0;tx_shift<=0;rx_shift<=0;
            header_index<=0;data_phase<=0;data_index<=0;rx_index<=0;
            rx_valid<=0;busy<=0;done<=0;cs_n<=1;sclk<=0;
        end else begin
            done<=0;rx_valid<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1;cs_n<=0;sclk<=0;count<=0;bit_index<=7;
                    tx_shift<=command;header_index<=0;data_phase<=0;
                    data_index<=0;rx_shift<=0;state<=SETUP;
                end
                SETUP: if(count==HALF_CYCLES-1) begin count<=0;state<=SHIFT;end
                       else count<=count+1'b1;
                SHIFT: if(count==HALF_CYCLES-1) begin
                    count<=0;sclk<=~sclk;
                    if(!sclk) rx_shift<={rx_shift[6:0],miso};
                    else if(bit_index!=0) begin
                        bit_index<=bit_index-1'b1;tx_shift<={tx_shift[6:0],1'b0};
                    end else begin
                        bit_index<=7;
                        if(data_phase) begin
                            rx_valid<=1;rx_index<=data_index;
                            if(data_index+1'b1==length) state<=HOLD;
                            else begin data_index<=data_index+1'b1;state<=NEXT_DATA;end
                        end else if(address_enable && header_index!=3) begin
                            header_index<=header_index+1'b1;
                            case(header_index)
                                0: tx_shift<=address[23:16];
                                1: tx_shift<=address[15:8];
                                default: tx_shift<=address[7:0];
                            endcase
                        end else if(length==0) state<=HOLD;
                        else begin data_phase<=1;tx_shift<=tx_data;end
                    end
                end else count<=count+1'b1;
                NEXT_DATA: begin tx_shift<=tx_data;state<=SHIFT;end
                HOLD: if(count==HALF_CYCLES-1) begin cs_n<=1;count<=0;state<=GAP;end
                      else count<=count+1'b1;
                GAP: if(count==HALF_CYCLES-1) begin busy<=0;done<=1;count<=0;state<=IDLE;end
                     else count<=count+1'b1;
                default: begin cs_n<=1;sclk<=0;busy<=0;state<=IDLE;end
            endcase
        end
    end
endmodule
`endif
