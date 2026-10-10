`timescale 1ns/1ps
// Bundled-data CDC for a slowly changing multi-bit value.
// The source holds src_data_latched stable while req is asserted. The
// destination captures the whole bundle only after the synchronized request,
// then acknowledges it. Source changes while busy are coalesced to the latest
// value and sent after the current transfer completes.
module cdc_bundle_latest #(
    parameter WIDTH = 8
)(
    input wire src_clk,
    input wire src_rst_n,
    input wire [WIDTH-1:0] src_data,
    input wire src_update,
    input wire dst_clk,
    input wire dst_rst_n,
    output reg [WIDTH-1:0] dst_data
);
    reg [WIDTH-1:0] src_data_latched;
    reg req;
    wire ack_sync;
    wire req_sync;
    wire dst_alive_sync;
    reg dst_alive;
    reg dst_alive_seen;
    reg force_publish;
    reg update_pending;
    reg ack;

    sync_2ff u_req_sync(
        .clk(dst_clk),.rst_n(dst_rst_n),.async_in(req),.sync_out(req_sync));
    sync_2ff u_ack_sync(
        .clk(src_clk),.rst_n(src_rst_n),.async_in(ack),.sync_out(ack_sync));
    sync_2ff u_dst_alive_sync(
        .clk(src_clk),.rst_n(src_rst_n),.async_in(dst_alive),.sync_out(dst_alive_sync));

    // A target reset clears the captured data. Announce target readiness back
    // to the source so a target-only reset also causes the current bundle to
    // be republished after both synchronizer chains settle.
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_alive <= 1'b0;
            ack <= 1'b0;
            dst_data <= {WIDTH{1'b0}};
        end else begin
            dst_alive <= 1'b1;
            if (req_sync && !ack) begin
                dst_data <= src_data_latched;
                ack <= 1'b1;
            end else if (!req_sync) begin
                ack <= 1'b0;
            end
        end
    end

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_data_latched <= {WIDTH{1'b0}};
            req <= 1'b0;
            dst_alive_seen <= 1'b0;
            force_publish <= 1'b0;
            update_pending <= 1'b0;
        end else begin
            if (src_update)
                update_pending <= 1'b1;
            if (!dst_alive_sync) begin
                dst_alive_seen <= 1'b0;
            end else if (!dst_alive_seen) begin
                dst_alive_seen <= 1'b1;
                force_publish <= 1'b1;
            end

            if (req && ack_sync) begin
                req <= 1'b0;
            end else if (!req && !ack_sync && dst_alive_sync &&
                         (force_publish || update_pending || src_update)) begin
                src_data_latched <= src_data;
                req <= 1'b1;
                force_publish <= 1'b0;
                update_pending <= 1'b0;
            end
        end
    end
endmodule
