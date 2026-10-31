`ifndef VINYL_MIC_SIGNAL_CONDITION_V
`define VINYL_MIC_SIGNAL_CONDITION_V
// Fixed-point DC removal followed by a three-sample averaging decimator.
// Input cadence is 144 kHz; output cadence is 48 kHz, same master clock.
module mic_signal_condition (
    input wire clk, input wire rst_n,
    input wire [11:0] sample_code, input wire sample_valid,
    output reg signed [15:0] mic_sample, output reg mic_valid
);
    wire signed [16:0] centered = $signed({1'b0,sample_code,4'b0}) - 17'sd32768;
    reg signed [26:0] dc_estimate;
    wire signed [26:0] target = $signed({{10{centered[16]}},centered}) <<< 10;
    wire signed [26:0] dc_next = dc_estimate + ((target - dc_estimate) >>> 10);
    wire signed [16:0] highpass = centered - (dc_estimate >>> 10);
    reg signed [18:0] sum;
    reg [1:0] phase;
    reg [11:0] timeout_count;
    wire signed [18:0] total = sum + {{2{highpass[16]}},highpass};
    wire signed [18:0] decimated = total >>> 2;
    wire signed [15:0] clipped = decimated > 19'sd32767 ? 16'sh7fff :
                                 decimated < -19'sd32768 ? 16'sh8000 : decimated[15:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_estimate <= 0;
            sum <= 0;
            phase <= 0;
            mic_sample <= 0;
            mic_valid <= 0;
            timeout_count <= 0;
        end else if (sample_valid) begin
            timeout_count <= 0;
            dc_estimate <= dc_next;
            if (phase == 2) begin
                mic_sample <= clipped;
                mic_valid <= 1;
                phase <= 0;
                sum <= 0;
            end else begin
                sum <= total;
                phase <= phase + 1'b1;
            end
        end else if (&timeout_count) begin
            mic_valid <= 0;
            mic_sample <= 0;
            dc_estimate <= 0;
            sum <= 0;
            phase <= 0;
        end else timeout_count <= timeout_count + 1'b1;
    end
endmodule
`endif
