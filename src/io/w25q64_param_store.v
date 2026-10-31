`ifndef W25Q64_PARAM_STORE_V
`define W25Q64_PARAM_STORE_V
// Dedicated U33 W25Q64, NOT the W25Q16 configuration flash.
// Only sectors 0x7FE000/0x7FF000 are writable. 16-byte format version 3:
// 56 50 03 flags 00 seq VOL BRI CON ROT WSL MIC crcHi crcLo A5 5A.
// Version 1 records carry no microphone level and load MIC=5X.
// Version 2 encoded MIC as 0/1/2/3 for 4X/5X/6X/7X; those values are mapped
// on load so they can never be mistaken for the new immediate-off 0X level.
// CRC16/CCITT-FALSE covers bytes 0..11. Commit bytes are programmed separately
// only after payload readback. Previous valid sector survives until commit.
module w25q64_param_store #(
    parameter integer SPI_HALF_CYCLES = 8,
    parameter [22:0] DEFAULT_PARAMS = {3'd5,3'd4,3'd2,3'd2,3'd3,8'd200},
    parameter integer POWER_WAIT_MS = 20,
    parameter integer WIP_TIMEOUT_MS = 2000
)(
    input wire clk, rst_n, tick_1ms,
    input wire save_req, save_defaults,
    input wire [22:0] save_params,
    output reg ready = 0, available = 0, busy = 1,
    output reg load_valid = 0,
    output wire [22:0] load_params,
    output reg save_done = 0, fault = 0,
    output reg [3:0] fault_code = 0,
    output wire flash_cs_n, flash_sclk, flash_mosi,
    input wire flash_miso,
    output wire flash_wp_n, flash_hold_n
);
    localparam POWER_WAIT=0, WAKE_ISSUE=1, WAKE_WAIT=2, WAKE_DELAY=3,
        POLL_ISSUE=4, POLL_WAIT=5, POLL_DELAY=6, ID_ISSUE=7, ID_WAIT=8,
        READ_ISSUE=9, READ_WAIT=10, READ_CHECK=11, IDLE=12,
        CRC_INIT=13, CRC_FEED=14, CRC_WAIT=15, WREN_ISSUE=16, WREN_WAIT=17,
        WEL_ISSUE=18, WEL_WAIT=19, WRITE_ISSUE=20, WRITE_WAIT=21,
        SUCCESS=22, FAIL=23, LOAD_PUBLISH=24;
    reg [4:0] state = POWER_WAIT;
    // Constant FSM destinations allow TD to extract/optimize the controller.
    // 0=startup ID, 1=next write, 2=readback, 3=completed default cleanup.
    reg [1:0] poll_stage = 0;
    reg [11:0] elapsed_ms = 0;
    reg jedec_good = 0;
    reg [7:0] status_byte = 0;
    reg read_slot = 0, target_slot = 0, active_slot = 0, active_valid = 0;
    // Startup read sequence storage becomes the immutable save sequence later.
    // Only two alternating slots exist, so an 8-bit wrapping serial is enough.
    reg [7:0] active_seq = 0, read_seq = 0;
    wire [7:0] write_seq = read_seq;
    reg [22:0] active_params = DEFAULT_PARAMS, read_params = DEFAULT_PARAMS;
    // ui_param_persistence holds its snapshot stable through save_done/fault.
    // Reuse that held bus rather than allocating another 23-bit snapshot here.
    wire [22:0] write_params = save_defaults ? DEFAULT_PARAMS : save_params;
    assign load_params = active_params;
    reg read_default = 0, write_default = 0, read_good = 0;
    reg read_v2 = 0, read_v3 = 0;
    // read_mode: 0/1 startup slots; 2 payload verify; 3 full committed verify.
    // write_op: 0 target erase; 1 payload program; 2 commit program; 3 old erase.
    reg [1:0] read_mode = 0, write_op = 0;
    reg [3:0] build_index = 0;
    reg [15:0] crc = 16'hffff;
    reg [7:0] crc_data = 0;
    reg [3:0] crc_bits = 0;
    wire txn_busy, txn_done, rx_valid;
    wire [4:0] data_index, rx_index;
    wire [7:0] rx_data;
    wire read_issue = state==READ_ISSUE;
    wire read_wait = state==READ_WAIT;
    wire txn_start = !txn_busy && (state==WAKE_ISSUE || state==POLL_ISSUE ||
        state==ID_ISSUE || read_issue || state==WREN_ISSUE ||
        state==WEL_ISSUE || state==WRITE_ISSUE);
    wire [7:0] txn_command = state==WAKE_ISSUE || state==WAKE_WAIT ? 8'hab :
        state==ID_ISSUE || state==ID_WAIT ? 8'h9f :
        state==POLL_ISSUE || state==POLL_WAIT || state==WEL_ISSUE || state==WEL_WAIT ? 8'h05 :
        read_issue || read_wait ? 8'h03 :
        state==WREN_ISSUE || state==WREN_WAIT ? 8'h06 :
        (write_op==0 || write_op==3) ? 8'h20 : 8'h02;
    wire txn_address_enable = read_issue || read_wait || state==WRITE_ISSUE || state==WRITE_WAIT;
    wire txn_slot = (read_issue || read_wait) ? read_slot :
                    (write_op==3 ? ~target_slot : target_slot);
    // Commit lands at slot base + 14; a constant select avoids a 24-bit adder.
    wire        commit_addr = (state==WRITE_ISSUE || state==WRITE_WAIT) &&
                              (write_op==2);
    wire [23:0] txn_address = commit_addr
        ? (txn_slot ? 24'h7ff00e : 24'h7fe00e)
        : (txn_slot ? 24'h7ff000 : 24'h7fe000);
    wire [4:0] txn_length = state==ID_ISSUE || state==ID_WAIT ? 5'd3 :
        state==POLL_ISSUE || state==POLL_WAIT || state==WEL_ISSUE || state==WEL_WAIT ? 5'd1 :
        read_issue || read_wait ? 5'd16 :
        state==WRITE_ISSUE || state==WRITE_WAIT ?
            (write_op==1 ? 5'd14 : write_op==2 ? 5'd2 : 5'd0) : 5'd0;
    wire [4:0] record_index = state==CRC_FEED || state==CRC_WAIT ? {1'b0,build_index} :
        read_wait ? rx_index : data_index + (write_op==2 ? 5'd14 : 5'd0);
    reg [7:0] record_byte;
    always @* begin
        case(record_index)
            0: record_byte=8'h56;
            1: record_byte=8'h50;
            2: record_byte=8'h03;
            3: record_byte={7'd0,write_default};
            4: record_byte=0;
            5: record_byte=write_seq;
            6: record_byte=write_params[7:0];
            7: record_byte={5'd0,write_params[10:8]};
            8: record_byte={5'd0,write_params[13:11]};
            9: record_byte={5'd0,write_params[16:14]};
            10: record_byte={5'd0,write_params[19:17]};
            11: record_byte={5'd0,write_params[22:20]};
            12: record_byte=crc[15:8];
            13: record_byte=crc[7:0];
            14: record_byte=8'ha5;
            default: record_byte=8'h5a;
        endcase
    end
    // Keep the computed save CRC through both readback transactions.
    wire crc_clear = state==CRC_INIT || (read_issue && read_mode<2 && !txn_busy);
    wire crc_feed = state==CRC_FEED || (read_wait && read_mode<2 && rx_valid && rx_index<12);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) crc<=16'hffff;
        else if(crc_clear) crc<=16'hffff;
        else if(crc_bits!=0)
            crc<={crc[14:0],1'b0} ^ ((crc[15]^crc_data[7]) ? 16'h1021 : 16'd0);
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) crc_data<=0;
        else if(crc_feed) crc_data<=state==CRC_FEED ? record_byte : rx_data;
        else if(crc_bits!=0) crc_data<={crc_data[6:0],1'b0};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) crc_bits<=0;
        else if(crc_clear) crc_bits<=0;
        else if(crc_feed) crc_bits<=8;
        else if(crc_bits!=0) crc_bits<=crc_bits-1'b1;
    end
    nvm_spi_transaction #(.HALF_CYCLES(SPI_HALF_CYCLES)) u_spi(
        .clk(clk),.rst_n(rst_n),.start(txn_start),.command(txn_command),
        .address_enable(txn_address_enable),.address(txn_address),.length(txn_length),
        .tx_data(record_byte),.data_index(data_index),.rx_index(rx_index),
        .rx_data(rx_data),.rx_valid(rx_valid),.busy(txn_busy),.done(txn_done),
        .cs_n(flash_cs_n),.sclk(flash_sclk),.mosi(flash_mosi),.miso(flash_miso));
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    wire [7:0] seq_delta=read_seq-active_seq;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=POWER_WAIT;poll_stage<=0;elapsed_ms<=0;jedec_good<=0;status_byte<=0;
            read_slot<=0;target_slot<=0;active_slot<=0;active_valid<=0;active_seq<=0;
            read_seq<=0;active_params<=DEFAULT_PARAMS;read_params<=DEFAULT_PARAMS;
            read_default<=0;write_default<=0;read_good<=0;read_v2<=0;read_v3<=0;
            read_mode<=0;write_op<=0;build_index<=0;
            ready<=0;available<=0;busy<=1;load_valid<=0;
            save_done<=0;fault<=0;fault_code<=0;
        end else begin
            load_valid<=0;save_done<=0;
            if(tick_1ms && elapsed_ms<4095) elapsed_ms<=elapsed_ms+1'b1;
            if(rx_valid && (state==POLL_WAIT || state==WEL_WAIT)) status_byte<=rx_data;
            if(rx_valid && state==ID_WAIT &&
               ((rx_index==0 && rx_data!=8'hef) ||
                (rx_index==1 && rx_data!=8'h40 && rx_data!=8'h60) ||
                (rx_index==2 && rx_data!=8'h17))) jedec_good<=0;
            if(rx_valid && read_wait) begin
                if(read_mode>=2) begin
                    if(rx_data!=record_byte) read_good<=0;
                end else case(rx_index)
                    0: if(rx_data!=8'h56) read_good<=0;
                    1: if(rx_data!=8'h50) read_good<=0;
                    2: begin
                        read_v2<=(rx_data==8'h02);
                        read_v3<=(rx_data==8'h03);
                        if(rx_data!=8'h01 && rx_data!=8'h02 && rx_data!=8'h03)
                            read_good<=0;
                    end
                    3: begin read_default<=rx_data[0];if(rx_data>1) read_good<=0;end
                    4: if(rx_data!=0) read_good<=0;
                    5: read_seq<=rx_data;
                    6: read_params[7:0]<=rx_data;
                    7: begin read_params[10:8]<=rx_data[2:0];if(rx_data>4) read_good<=0;end
                    8: begin read_params[13:11]<=rx_data[2:0];if(rx_data>4) read_good<=0;end
                    9: begin read_params[16:14]<=rx_data[2:0];if(rx_data>5) read_good<=0;end
                    10: begin read_params[19:17]<=rx_data[2:0];if(rx_data>4) read_good<=0;end
                    11: begin
                        if(read_v3) begin
                            read_params[22:20]<=rx_data[2:0];
                            if(((rx_data!=0) && (rx_data<4)) || (rx_data>7))
                                read_good<=0;
                        end else if(read_v2) begin
                            if(rx_data>3)
                                read_good<=0;
                            // Old 0/1/2/3 meant 4X/5X/6X/7X.
                            read_params[22:20]<=3'b100 | rx_data[1:0];
                        end else if(rx_data!=0) begin
                            read_good<=0;
                        end
                    end
                    12: if(rx_data!=crc[15:8]) read_good<=0;
                    13: if(rx_data!=crc[7:0]) read_good<=0;
                    14: if(rx_data!=8'ha5) read_good<=0;
                    15: if(rx_data!=8'h5a) read_good<=0;
                    default: read_good<=0;
                endcase
            end
            case(state)
                POWER_WAIT: if(elapsed_ms>=POWER_WAIT_MS) state<=WAKE_ISSUE;
                WAKE_ISSUE: if(!txn_busy) state<=WAKE_WAIT;
                WAKE_WAIT: if(txn_done) begin elapsed_ms<=0;state<=WAKE_DELAY;end
                WAKE_DELAY: if(elapsed_ms>=1) begin elapsed_ms<=0;poll_stage<=0;state<=POLL_ISSUE;end
                POLL_ISSUE: if(!txn_busy) state<=POLL_WAIT;
                POLL_WAIT: if(txn_done) begin
                    if(!status_byte[0]) begin
                        case(poll_stage)
                            0: state<=ID_ISSUE;
                            1: state<=WREN_ISSUE;
                            2: state<=READ_ISSUE;
                            default: state<=SUCCESS;
                        endcase
                    end
                    else if(elapsed_ms>=WIP_TIMEOUT_MS) begin fault_code<=2;state<=FAIL;end
                    else state<=POLL_DELAY;
                end
                POLL_DELAY: if(tick_1ms) state<=POLL_ISSUE;
                ID_ISSUE: if(!txn_busy) begin jedec_good<=1;state<=ID_WAIT;end
                ID_WAIT: if(txn_done) begin
                    if(jedec_good) begin
                        available<=1;read_mode<=0;read_slot<=0;state<=READ_ISSUE;
                    end else begin fault_code<=1;state<=FAIL;end
                end
                READ_ISSUE: if(!txn_busy) begin
                    read_good<=1;read_default<=0;state<=READ_WAIT;
                    if(read_mode<2) begin
                        read_seq<=0;
                        read_params<=DEFAULT_PARAMS;
                        read_v2<=0;
                        read_v3<=0;
                    end
                end
                READ_WAIT: if(txn_done) state<=READ_CHECK;
                READ_CHECK: if(read_mode<2) begin
                    if(read_good && (!active_valid || (!seq_delta[7] && seq_delta!=0))) begin
                        active_valid<=1;active_slot<=read_slot;active_seq<=read_seq;
                        active_params<=read_default ? DEFAULT_PARAMS : read_params;
                    end
                    if(read_mode==0) begin read_mode<=1;read_slot<=1;state<=READ_ISSUE;end
                    else state<=LOAD_PUBLISH;
                end else if(!read_good) begin fault_code<=4;state<=FAIL;end
                else begin
                    active_valid<=1;active_slot<=target_slot;active_seq<=write_seq;
                    if(write_default) begin write_op<=3;state<=WREN_ISSUE;end
                    else state<=SUCCESS;
                end
                LOAD_PUBLISH: begin
                    ready<=1;busy<=0;load_valid<=active_valid;state<=IDLE;
                end
                IDLE: if(save_req && available) begin
                    busy<=1;
                    write_default<=save_defaults;read_seq<=active_valid ? active_seq+1'b1 : 8'd0;
                    target_slot<=active_valid ? ~active_slot : 1'b0;state<=CRC_INIT;
                end
                CRC_INIT: begin build_index<=0;state<=CRC_FEED;end
                CRC_FEED: state<=CRC_WAIT;
                CRC_WAIT: if(crc_bits==0) begin
                    if(build_index==11) begin write_op<=0;state<=WREN_ISSUE;end
                    else begin build_index<=build_index+1'b1;state<=CRC_FEED;end
                end
                WREN_ISSUE: if(!txn_busy) state<=WREN_WAIT;
                WREN_WAIT: if(txn_done) state<=WEL_ISSUE;
                WEL_ISSUE: if(!txn_busy) state<=WEL_WAIT;
                WEL_WAIT: if(txn_done) begin
                    if(status_byte[1:0]==2'b10 && status_byte[4:2]==0) state<=WRITE_ISSUE;
                    else begin fault_code<=3;state<=FAIL;end
                end
                WRITE_ISSUE: if(!txn_busy) state<=WRITE_WAIT;
                WRITE_WAIT: if(txn_done) begin
                    elapsed_ms<=0;state<=POLL_ISSUE;
                    case(write_op)
                        0: begin write_op<=1;poll_stage<=1;end
                        1: begin write_op<=2;poll_stage<=1;end
                        2: begin read_slot<=target_slot;read_mode<=3;poll_stage<=2;end
                        default: poll_stage<=3;
                    endcase
                end
                SUCCESS: begin busy<=0;save_done<=1;state<=IDLE;end
                FAIL: begin available<=0;ready<=1;busy<=0;fault<=1;state<=IDLE;end
                default: begin fault_code<=5;state<=FAIL;end
            endcase
        end
    end
endmodule
`endif
