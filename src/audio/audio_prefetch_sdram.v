`ifndef VINYL_AUDIO_PREFETCH_SDRAM_V
`define VINYL_AUDIO_PREFETCH_SDRAM_V
`timescale 1ns/1ps
// SD-clock sector cache. A committed ring entry always contains all 512 bytes.
// Session cancellation drains issued SD/DMA operations before reusing staging;
// request toggles and their sector payloads are never reset by a seek/stop.
module audio_prefetch_sdram #(
    parameter integer PREFILL_SECTORS=960,
    parameter integer HIGH_SECTORS=1008,
    parameter integer LOW_SECTORS=960
)(
    input sd_clk, sd_rst_n, mem_clk, mem_rst_n,
    input source_ready, enable,
    input [31:0] start_lba, total_sectors,
    input client_req,
    output client_busy, client_valid,
    output [7:0] client_byte,
    output [8:0] client_byte_index,
    output client_done,
    output [7:0] client_error,
    output raw_req,
    output reg [31:0] raw_lba=0,
    input raw_busy, raw_valid,
    input [7:0] raw_byte,
    input [8:0] raw_byte_index,
    input raw_done,
    input [7:0] raw_error,
    output reg playback_ready=0,
    output prefetch_low, prefetch_critical, session_busy,
    input video_read_busy,video_write_busy,controller_busy,refresh_active,
    input mem_read_valid,
    input [31:0] mem_read_data,
    output access_lock,read_owner,mem_wr_en,
    output [20:0] mem_wr_addr,
    output [31:0] mem_wr_data,
    output [3:0] mem_wr_mask,
    output mem_rd_en,
    output [20:0] mem_rd_addr
);
    localparam [2:0] P_IDLE=0,P_REQUEST=1,P_FILL=2,P_COMMIT=3;
    localparam [2:0] C_IDLE=0,C_LOAD=1,C_SEND=2,C_DONE=3,C_ERROR=4;
    reg [2:0] producer_state=P_IDLE,consumer_state=C_IDLE;
    reg session_active=0,prefill_ready=0,refilling=0;
    reg [31:0] producer_remaining=0,consumer_remaining=0;
    reg [10:0] write_pointer=0,read_pointer=0;
    reg [7:0] fault=0;
    reg [9:0] raw_count=0,send_count=0;
    reg raw_bad=0;
    reg write_toggle=0,read_toggle=0;
    reg [9:0] write_sector=0,read_sector=0;
    wire write_ack,read_ack;
    wire [7:0] write_error,read_error;
    reg write_ack0=0,write_ack1=0,read_ack0=0,read_ack1=0;
    reg send_pending=0;
    reg [8:0] send_index=0;
    wire [10:0] occupied=write_pointer-read_pointer;
    wire start_session=!session_active && producer_state==P_IDLE && consumer_state==C_IDLE &&
                       write_ack1==write_toggle && read_ack1==read_toggle &&
                       enable && source_ready && start_lba!=0 && total_sectors!=0;
    wire live=session_active && enable && source_ready;
    wire producer_start=live && fault==0 && producer_state==P_IDLE && source_ready &&
                        refilling && occupied<HIGH_SECTORS && producer_remaining!=0;
    wire raw_store=producer_state==P_FILL && raw_valid;
    wire raw_finish=producer_state==P_FILL && raw_done;
    wire raw_complete=(raw_count==10'd512 && !raw_valid) ||
                      (raw_count==10'd511 && raw_valid && raw_byte_index==9'd511);
    wire raw_failed=raw_finish && (raw_error!=0 || raw_bad || !raw_complete ||
                       (raw_valid && (raw_count>=512 || raw_byte_index!=raw_count[8:0])));
    wire publish_write=raw_finish && !raw_failed && live && fault==0;
    wire write_finished=producer_state==P_COMMIT && write_ack1==write_toggle;
    wire read_finished=consumer_state==C_LOAD && read_ack1==read_toggle;
    wire at_eof=consumer_remaining==0;
    wire accept_client=client_req && !client_busy;
    wire request_read=accept_client && fault==0 && !at_eof;
    wire write_committed=write_finished && write_error==0 && live && fault==0;
    wire read_committed=read_finished && read_error==0 && live && fault==0;
    wire a_read=consumer_state==C_SEND && send_count<512 && !raw_store && live && fault==0;
    wire a_en=raw_store || a_read;
    wire [9:0] a_addr=raw_store ? {1'b0,raw_byte_index} : {1'b1,send_count[8:0]};
    wire [7:0] a_dout;
    wire b_en,b_we;
    wire [9:0] b_addr;
    wire [7:0] b_din,b_dout;

    assign raw_req=producer_state==P_REQUEST && live && fault==0;
    // The initial prefill holds the requester, rather than pretending to have
    // granted a sector. Errors and unexpected EOF always get a bounded reply.
    assign client_busy=consumer_state!=C_IDLE || !live ||
                       (fault==0 && !at_eof && (!prefill_ready || occupied==0));
    assign client_valid=send_pending && live && fault==0;
    assign client_byte=a_dout;
    assign client_byte_index=send_index;
    assign client_done=live && (consumer_state==C_DONE || consumer_state==C_ERROR);
    assign client_error=consumer_state==C_ERROR ? (fault!=0 ? fault : 8'he4) : 8'd0;
    assign prefetch_low=live && fault==0 && producer_remaining!=0 && occupied<LOW_SECTORS;
    // Late diagnostic watermark only. SD admission must use prefetch_low and
    // audio-first arbitration to preserve the full slow-card service reserve;
    // two seconds cannot cover the previously observed 4.9-second slow window.
    assign prefetch_critical=live && fault==0 && producer_remaining!=0 && occupied<10'd384;
    assign session_busy=session_active || producer_state!=P_IDLE || consumer_state!=C_IDLE ||
                        write_ack1!=write_toggle || read_ack1!=read_toggle;

    audio_prefetch_stage staging(
        .a_clk(sd_clk),.a_en(a_en),.a_we(raw_store),.a_addr(a_addr),.a_din(raw_byte),.a_dout(a_dout),
        .b_clk(mem_clk),.b_en(b_en),.b_we(b_we),.b_addr(b_addr),.b_din(b_din),.b_dout(b_dout));
    audio_sdram_dma dma(
        .mem_clk(mem_clk),.rst_n(mem_rst_n),
        .write_request_toggle(write_toggle),.write_sector(write_sector),
        .write_ack_toggle(write_ack),.write_error(write_error),
        .read_request_toggle(read_toggle),.read_sector(read_sector),
        .read_ack_toggle(read_ack),.read_error(read_error),
        .stage_en(b_en),.stage_we(b_we),.stage_addr(b_addr),.stage_din(b_din),.stage_dout(b_dout),
        .video_read_busy(video_read_busy),.video_write_busy(video_write_busy),
        .controller_busy(controller_busy),.refresh_active(refresh_active),
        .mem_read_valid(mem_read_valid),.mem_read_data(mem_read_data),
        .access_lock(access_lock),.read_owner(read_owner),
        .mem_wr_en(mem_wr_en),.mem_wr_addr(mem_wr_addr),.mem_wr_data(mem_wr_data),
        .mem_wr_mask(mem_wr_mask),.mem_rd_en(mem_rd_en),.mem_rd_addr(mem_rd_addr));

    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) write_ack0<=0; else write_ack0<=write_ack;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) write_ack1<=0; else write_ack1<=write_ack0;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) read_ack0<=0; else read_ack0<=read_ack;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) read_ack1<=0; else read_ack1<=read_ack0;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) session_active<=0;
        else if(!enable || !source_ready) session_active<=0;
        else if(start_session) session_active<=1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) producer_remaining<=0;
        else if(start_session) producer_remaining<=total_sectors;
        else if(write_committed) producer_remaining<=producer_remaining-1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) consumer_remaining<=0;
        else if(start_session) consumer_remaining<=total_sectors;
        else if(consumer_state==C_DONE && live) consumer_remaining<=consumer_remaining-1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) write_pointer<=0;
        else if(start_session) write_pointer<=0;
        else if(write_committed) write_pointer<=write_pointer+1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) read_pointer<=0;
        else if(start_session) read_pointer<=0;
        else if(read_committed) read_pointer<=read_pointer+1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) prefill_ready<=0;
        else if(start_session || !live) prefill_ready<=0;
        else if(occupied>=PREFILL_SECTORS || producer_remaining==0) prefill_ready<=1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) playback_ready<=0;
        else if(start_session || !live) playback_ready<=0;
        else if(consumer_state==C_DONE && fault==0) playback_ready<=1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) refilling<=0;
        else if(start_session) refilling<=1;
        else if(!live || fault!=0 || occupied>=HIGH_SECTORS || producer_remaining==0) refilling<=0;
        else if(occupied<LOW_SECTORS) refilling<=1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) fault<=0;
        else if(start_session) fault<=0;
        else if(live && fault==0) begin
            if(raw_failed) fault<=raw_error!=0 ? raw_error : 8'he1;
            else if(write_finished && write_error!=0) fault<=8'he2;
            else if(read_finished && read_error!=0) fault<=8'he3;
        end
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) producer_state<=P_IDLE;
        else case(producer_state)
            P_IDLE: if(producer_start) producer_state<=P_REQUEST;
            P_REQUEST: if(!live || fault!=0) producer_state<=P_IDLE;
                       else if(!raw_busy) producer_state<=P_FILL;
            // source_ready drops only with the physical SD/media reset: unlike
            // ordinary enable cancellation, that reset destroys raw_done.
            P_FILL: if(!source_ready) producer_state<=P_IDLE;
                    else if(raw_done) producer_state<=publish_write ? P_COMMIT : P_IDLE;
            P_COMMIT: if(write_finished) producer_state<=P_IDLE;
            default: producer_state<=P_IDLE;
        endcase
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) raw_lba<=0;
        else if(start_session) raw_lba<=start_lba;
        else if(write_committed) raw_lba<=raw_lba+1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) raw_count<=0;
        else if(producer_state==P_REQUEST) raw_count<=0;
        else if(raw_store && raw_count<512) raw_count<=raw_count+1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) raw_bad<=0;
        else if(producer_state==P_REQUEST) raw_bad<=0;
        else if(raw_store && (raw_count>=512 || raw_byte_index!=raw_count[8:0])) raw_bad<=1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) write_toggle<=0;
        else if(publish_write) write_toggle<=!write_toggle;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) write_sector<=0;
        else if(publish_write) write_sector<=write_pointer[9:0];
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) consumer_state<=C_IDLE;
        else case(consumer_state)
            C_IDLE: if(accept_client) consumer_state<=request_read ? C_LOAD : C_ERROR;
            C_LOAD: if(read_finished) consumer_state<=!live ? C_IDLE :
                         ((read_error!=0 || fault!=0) ? C_ERROR : C_SEND);
            C_SEND: if(!live) consumer_state<=C_IDLE;
                    else if(fault!=0) consumer_state<=C_ERROR;
                    else if(client_valid && send_index==511) consumer_state<=C_DONE;
            C_DONE,C_ERROR: consumer_state<=C_IDLE;
            default: consumer_state<=C_IDLE;
        endcase
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) read_toggle<=0;
        else if(request_read) read_toggle<=!read_toggle;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) read_sector<=0;
        else if(request_read) read_sector<=read_pointer[9:0];
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) send_count<=0;
        else if(consumer_state!=C_SEND) send_count<=0;
        else if(a_read) send_count<=send_count+1'b1;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) send_pending<=0;
        else send_pending<=a_read;
    end
    always @(posedge sd_clk or negedge sd_rst_n) begin
        if(!sd_rst_n) send_index<=0;
        else if(a_read) send_index<=send_count[8:0];
    end
endmodule
`endif
