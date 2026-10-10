`ifndef EXP_SLIDESHOW_CONTROLLER_V
`define EXP_SLIDESHOW_CONTROLLER_V
// Picture rotation scheduler in the 100 MHz SD domain.
// It only requests a step; cover_navigation owns selection and transition I/O.
module slideshow_controller #(
    parameter integer CLK_FREQ_HZ = 100_000_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       busy,
    input  wire       manual_action,
    input  wire [2:0] period_level, // 0=OFF, 1=2s, 2=3s, 3=5s, 4=10s, 5=20s
    output reg        auto_next
);
    localparam integer SEC_COUNTER_WIDTH = (CLK_FREQ_HZ <= 2) ? 1 : $clog2(CLK_FREQ_HZ);
    localparam [2:0] DEFAULT_PERIOD_LEVEL = 3'd2;
    localparam [2:0] IDLE              = 3'd0,
                     AUTO_WAIT_START   = 3'd1,
                     AUTO_WAIT_END     = 3'd2,
                     MANUAL_WAIT_START = 3'd3,
                     MANUAL_WAIT_END   = 3'd4;

    reg [SEC_COUNTER_WIDTH-1:0] second_counter;
    reg [4:0] elapsed_seconds;
    reg [2:0] period_level_q;
    reg [2:0] state;
    reg pending;
    reg busy_q;
    reg [4:0] period_seconds;

    always @* begin
        case (period_level)
            3'd1: period_seconds = 5'd2;
            3'd2: period_seconds = 5'd3;
            3'd3: period_seconds = 5'd5;
            3'd4: period_seconds = 5'd10;
            3'd5: period_seconds = 5'd20;
            default: period_seconds = 5'd0;
        endcase
    end

    wire period_active = enable && (period_level != 3'd0);
    wire period_changed = (period_level != period_level_q);
    wire second_tick = (second_counter == CLK_FREQ_HZ - 1);
    wire period_due = period_active && !period_changed && second_tick &&
                      (elapsed_seconds == period_seconds - 5'd1);
    wire auto_issue = (state == IDLE) && !manual_action && !busy_q &&
                      !period_changed && (pending || period_due);

    // Register navigation busy before it participates in control decisions.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            busy_q <= 1'b0;
        else
            busy_q <= busy;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            period_level_q <= DEFAULT_PERIOD_LEVEL;
        else
            period_level_q <= period_level;
    end

    // A local one-second clock enable avoids transferring the 50 MHz UI tick
    // and keeps elapsed rotation time in a compact five-bit seconds counter.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            second_counter <= {SEC_COUNTER_WIDTH{1'b0}};
        else if (!period_active || period_changed || second_tick)
            second_counter <= {SEC_COUNTER_WIDTH{1'b0}};
        else
            second_counter <= second_counter + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else if (!period_active)
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
            elapsed_seconds <= 5'd0;
        else if (!period_active || manual_action || period_changed)
            elapsed_seconds <= 5'd0;
        else if (((state == AUTO_WAIT_END) || (state == MANUAL_WAIT_END)) && !busy_q)
            elapsed_seconds <= 5'd0;
        else if (state == IDLE && pending && !busy_q)
            elapsed_seconds <= 5'd0;
        else if (state == IDLE && !pending && second_tick) begin
            if (elapsed_seconds == period_seconds - 5'd1)
                elapsed_seconds <= 5'd0;
            else
                elapsed_seconds <= elapsed_seconds + 5'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pending <= 1'b0;
        else if (!period_active || manual_action || period_changed)
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
            auto_next <= period_active && auto_issue;
    end
endmodule
`endif
