`ifndef EXP_QUADRATURE_DECODER_V
`define EXP_QUADRATURE_DECODER_V
module quadrature_decoder #(
    // 50,000 cycles = 1 ms at the 50 MHz board clock. This rejects the
    // mechanical-contact chatter that previously created alternating +/- events.
    parameter integer STABLE_CYCLES = 50_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        a_async,
    input  wire        b_async,
    output reg         step_pulse,
    output reg         direction,
    output reg  [15:0] count
);
    wire        a_sync;
    wire        b_sync;
    wire [1:0]  raw_state;
    reg  [1:0]  candidate_state;
    reg  [1:0]  stable_state;
    reg  [31:0] stable_count;
    reg signed [3:0] quarter_steps;

    assign raw_state = {a_sync, b_sync};

    sync_bit u_sync_a (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (a_async),
        .sync_out (a_sync)
    );

    sync_bit u_sync_b (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (b_async),
        .sync_out (b_sync)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate_state <= 2'b11;
            stable_state    <= 2'b11;
            stable_count    <= 32'd0;
            quarter_steps   <= 4'sd0;
            step_pulse      <= 1'b0;
            direction       <= 1'b0;
            count           <= 16'd0;
        end else begin
            step_pulse <= 1'b0;

            // A raw A/B value must remain unchanged before it can alter the
            // sequence, rejecting short contact bounce and switch crosstalk.
            if (raw_state != candidate_state) begin
                candidate_state <= raw_state;
                stable_count    <= 32'd0;
            end else if (candidate_state != stable_state) begin
                if ((STABLE_CYCLES <= 1) || (stable_count >= STABLE_CYCLES - 1)) begin
                    stable_state <= candidate_state;
                    stable_count <= 32'd0;
                    case ({stable_state, candidate_state})
                        // Positive: 00->01->11->10->00.
                        4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00: begin
                            if (quarter_steps < 0)
                                quarter_steps <= quarter_steps + 1'b1;
                            else if (quarter_steps == 4'sd3) begin
                                quarter_steps <= 4'sd0;
                                step_pulse    <= 1'b1;
                                direction     <= 1'b0;
                                count         <= count + 1'b1;
                            end else
                                quarter_steps <= quarter_steps + 1'b1;
                        end

                        // Negative: 00->10->11->01->00.
                        4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00: begin
                            if (quarter_steps > 0)
                                quarter_steps <= quarter_steps - 1'b1;
                            else if (quarter_steps == -4'sd3) begin
                                quarter_steps <= 4'sd0;
                                step_pulse    <= 1'b1;
                                direction     <= 1'b1;
                                count         <= count - 1'b1;
                            end else
                                quarter_steps <= quarter_steps - 1'b1;
                        end

                        // A two-bit jump is not a legal quadrature transition.
                        default: quarter_steps <= 4'sd0;
                    endcase
                end else begin
                    stable_count <= stable_count + 1'b1;
                end
            end
        end
    end
endmodule
`endif
