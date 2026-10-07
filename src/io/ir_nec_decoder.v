`ifndef EXP_IR_NEC_DECODER_V
`define EXP_IR_NEC_DECODER_V
module ir_nec_decoder #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ir_async,
    output reg         event_valid,
    output reg  [31:0] code,
    output reg  [7:0]  command,
    output reg         repeat_event
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_LOW  = 2'd1;
    localparam [1:0] ST_HIGH = 2'd2;

    localparam integer MIN_LEADER = (CLK_FREQ_HZ * 7) / 1000;
    localparam integer MAX_LEADER = (CLK_FREQ_HZ * 11) / 1000;
    localparam integer MIN_SPACE  = (CLK_FREQ_HZ * 3) / 1000;
    localparam integer MAX_SPACE  = (CLK_FREQ_HZ * 6) / 1000;
    localparam integer MIN_REPEAT = (CLK_FREQ_HZ * 15) / 10000;
    localparam integer MAX_REPEAT = (CLK_FREQ_HZ * 30) / 10000;
    localparam integer MIN_BIT    = (CLK_FREQ_HZ * 3) / 10000;
    localparam integer MAX_BIT    = (CLK_FREQ_HZ * 10) / 10000;
    localparam integer MIN_ONE    = (CLK_FREQ_HZ * 10) / 10000;
    localparam integer MAX_ONE    = (CLK_FREQ_HZ * 22) / 10000;

    // Include the saturated endpoint itself, also when it is a power of two.
    // Unsigned input preserves the original 32-bit counter/parameter comparison.
    function integer counter_width;
        input [31:0] maximum;
        reg [31:0] remaining;
        begin
            remaining = maximum;
            counter_width = 0;
            while (remaining != 0) begin
                counter_width = counter_width + 1;
                remaining = remaining >> 1;
            end
            if (counter_width == 0) counter_width = 1;
        end
    endfunction
    localparam integer LOW_COUNT_WIDTH = counter_width(MAX_LEADER);
    localparam integer HIGH_COUNT_WIDTH = counter_width(MAX_SPACE);

    wire        ir_sync;
    wire        ir_fall;
    wire        ir_rise;
    reg         ir_d;
    reg  [1:0]  state;
    reg  [LOW_COUNT_WIDTH-1:0] low_cnt;
    reg  [HIGH_COUNT_WIDTH-1:0] high_cnt;
    reg  [LOW_COUNT_WIDTH-1:0] low_width;
    reg  [5:0]  bit_count;
    reg  [31:0] shift_reg;
    reg         frame_active;
    reg  [31:0] last_code;
    reg  [7:0]  last_command;
    reg         last_valid;
    reg         event_next;
    reg         repeat_next;
    wire [31:0] next_zero;
    wire [31:0] next_one;
    wire [7:0]  next_command_zero;
    wire [7:0]  next_command_one;

    assign ir_fall = ir_d && !ir_sync;
    assign ir_rise = !ir_d && ir_sync;
    assign next_zero = {1'b0, shift_reg[31:1]};
    assign next_one  = {1'b1, shift_reg[31:1]};
    assign next_command_zero = next_zero[15:8];
    assign next_command_one  = next_one[15:8];

    sync_bit u_sync_ir (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (ir_async),
        .sync_out (ir_sync)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ir_d <= 1'b1;
        else
            ir_d <= ir_sync;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            low_cnt      <= 32'd0;
            high_cnt     <= 32'd0;
            low_width    <= 32'd0;
            bit_count    <= 6'd0;
            shift_reg    <= 32'd0;
            frame_active <= 1'b0;
            last_code    <= 32'd0;
            last_command <= 8'd0;
            last_valid   <= 1'b0;
            event_next   <= 1'b0;
            repeat_next  <= 1'b0;
            event_valid  <= 1'b0;
            code         <= 32'd0;
            command      <= 8'd0;
            repeat_event <= 1'b0;
        end else begin
            event_valid  <= event_next;
            event_next   <= 1'b0;
            repeat_event <= repeat_next;
            repeat_next  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    low_cnt  <= 32'd0;
                    high_cnt <= 32'd0;
                    if (ir_fall) begin
                        low_cnt <= 32'd0;
                        state   <= ST_LOW;
                    end
                end

                ST_LOW: begin
                    if (ir_rise) begin
                        low_width <= low_cnt;
                        high_cnt  <= 32'd0;
                        state     <= ST_HIGH;
                    end else if (low_cnt < MAX_LEADER) begin
                        low_cnt <= low_cnt + 1'b1;
                    end else begin
                        frame_active <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                ST_HIGH: begin
                    if (ir_fall) begin
                        if ((low_width >= MIN_LEADER) && (low_width <= MAX_LEADER) &&
                            (high_cnt >= MIN_SPACE) && (high_cnt <= MAX_SPACE)) begin
                            bit_count    <= 6'd0;
                            shift_reg    <= 32'd0;
                            frame_active <= 1'b1;
                        end else if ((low_width >= MIN_LEADER) && (low_width <= MAX_LEADER) &&
                                     (high_cnt >= MIN_REPEAT) && (high_cnt <= MAX_REPEAT)) begin
                            if (last_valid) begin
                                event_next   <= 1'b1;
                                repeat_next  <= 1'b1;
                                code         <= last_code;
                                command      <= last_command;
                            end
                        end else if (frame_active &&
                                     (low_width >= MIN_BIT) && (low_width <= MAX_BIT)) begin
                            if ((high_cnt >= MIN_BIT) && (high_cnt <= MAX_BIT)) begin
                                if (bit_count == 6'd31) begin
                                    event_next   <= 1'b1;
                                    code         <= next_zero;
                                    command      <= next_command_zero;
                                    last_code    <= next_zero;
                                    last_command <= next_command_zero;
                                    last_valid   <= 1'b1;
                                    frame_active <= 1'b0;
                                    bit_count    <= 6'd0;
                                end else begin
                                    shift_reg <= next_zero;
                                    bit_count <= bit_count + 1'b1;
                                end
                            end else if ((high_cnt >= MIN_ONE) && (high_cnt <= MAX_ONE)) begin
                                if (bit_count == 6'd31) begin
                                    event_next   <= 1'b1;
                                    code         <= next_one;
                                    command      <= next_command_one;
                                    last_code    <= next_one;
                                    last_command <= next_command_one;
                                    last_valid   <= 1'b1;
                                    frame_active <= 1'b0;
                                    bit_count    <= 6'd0;
                                end else begin
                                    shift_reg <= next_one;
                                    bit_count <= bit_count + 1'b1;
                                end
                            end else begin
                                frame_active <= 1'b0;
                            end
                        end else begin
                            frame_active <= 1'b0;
                        end

                        low_cnt <= 32'd0;
                        state   <= ST_LOW;
                    end else if (high_cnt < MAX_SPACE) begin
                        high_cnt <= high_cnt + 1'b1;
                    end else begin
                        frame_active <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                default: begin
                    frame_active <= 1'b0;
                    state        <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
`endif
