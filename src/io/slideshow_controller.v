`ifndef EXP_SLIDESHOW_CONTROLLER_V
`define EXP_SLIDESHOW_CONTROLLER_V
// Five-second picture rotation scheduler in the 100 MHz SD domain.
// It only requests a step; cover_navigation owns selection and transition I/O.
module slideshow_controller #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer PERIOD_MS = 5000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire busy,
    input  wire manual_action,
    output reg  auto_next
);
    localparam integer CYCLES_PER_MS = CLK_FREQ_HZ / 1000;
    localparam integer MS_COUNTER_WIDTH = (CYCLES_PER_MS <= 2) ? 1 : $clog2(CYCLES_PER_MS);
    localparam integer ELAPSED_WIDTH = (PERIOD_MS <= 2) ? 1 : $clog2(PERIOD_MS);
    localparam [2:0] IDLE              = 3'd0,
                     AUTO_WAIT_START   = 3'd1,
                     AUTO_WAIT_END     = 3'd2,
                     MANUAL_WAIT_START = 3'd3,
                     MANUAL_WAIT_END   = 3'd4;

    reg [MS_COUNTER_WIDTH-1:0] ms_counter;
    reg [ELAPSED_WIDTH-1:0] elapsed_ms;
    reg [2:0] state;
    reg pending;
    reg busy_q;

    wire ms_tick = (ms_counter == CYCLES_PER_MS - 1);
    wire period_due = ms_tick && (elapsed_ms == PERIOD_MS - 1);
    wire auto_issue = (state == IDLE) && !manual_action && !busy_q &&
                      (pending || period_due);

    // Register navigation busy before it participates in control decisions.
    // This keeps display-index decode off the 100 MHz FSM input path.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            busy_q <= 1'b0;
        else
            busy_q <= busy;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ms_counter <= {MS_COUNTER_WIDTH{1'b0}};
        else if (!enable)
            ms_counter <= {MS_COUNTER_WIDTH{1'b0}};
        else if (ms_tick)
            ms_counter <= {MS_COUNTER_WIDTH{1'b0}};
        else
            ms_counter <= ms_counter + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else if (!enable)
            state <= IDLE;
        else if (manual_action)
            state <= busy_q ? MANUAL_WAIT_END : MANUAL_WAIT_START;
        else begin
            case (state)
                IDLE: begin
                    if (auto_issue)
                        state <= AUTO_WAIT_START;
                end
                AUTO_WAIT_START: begin
                    if (busy_q)
                        state <= AUTO_WAIT_END;
                end
                AUTO_WAIT_END: begin
                    if (!busy_q)
                        state <= IDLE;
                end
                MANUAL_WAIT_START: begin
                    if (busy_q)
                        state <= MANUAL_WAIT_END;
                end
                MANUAL_WAIT_END: begin
                    if (!busy_q)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            elapsed_ms <= {ELAPSED_WIDTH{1'b0}};
        else if (!enable || manual_action)
            elapsed_ms <= {ELAPSED_WIDTH{1'b0}};
        else if (((state == AUTO_WAIT_END) || (state == MANUAL_WAIT_END)) && !busy_q)
            elapsed_ms <= {ELAPSED_WIDTH{1'b0}};
        else if (state == IDLE && pending && !busy_q)
            elapsed_ms <= {ELAPSED_WIDTH{1'b0}};
        else if (state == IDLE && !pending && ms_tick) begin
            if (elapsed_ms == PERIOD_MS - 1)
                elapsed_ms <= {ELAPSED_WIDTH{1'b0}};
            else
                elapsed_ms <= elapsed_ms + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pending <= 1'b0;
        else if (!enable || manual_action)
            pending <= 1'b0;
        else if (((state == AUTO_WAIT_END) || (state == MANUAL_WAIT_END)) && !busy_q)
            pending <= 1'b0;
        else if (state == IDLE && pending && !busy_q)
            pending <= 1'b0;
        else if (state == IDLE && !pending && period_due && busy_q)
            pending <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            auto_next <= 1'b0;
        else
            auto_next <= enable && auto_issue;
    end
endmodule
`endif
