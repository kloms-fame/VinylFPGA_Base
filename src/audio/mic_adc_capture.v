`ifndef VINYL_MIC_ADC_CAPTURE_V
`define VINYL_MIC_ADC_CAPTURE_V
`timescale 1ns/1ps

// EG4S20 ADC_CH5 capture. clk is the existing 25 MHz video clock.
// adc_clk is a divide-by-two clock and must be declared as a generated clock.
// The control and output registers run on clk. SOC changes at the falling
// edge of adc_clk; EOC/data are sampled half an ADC cycle after its rising
// edge. The relationship is synchronous, not an asynchronous CDC.
module mic_adc_capture (
    input wire clk,
    input wire rst_n,
    output reg [11:0] sample_code,
    output reg sample_valid
);
    (* keep = "true" *) reg adc_clk;
    reg adc_soc;
    reg [13:0] sample_phase;
    wire adc_eoc;
    wire [11:0] adc_data;
    // On ADC falling edges: average 144000 samples/sec from 12.5 MHz.
    wire [14:0] phase_sum = {1'b0, sample_phase} + 15'd144;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) adc_clk <= 1'b0;
        else adc_clk <= ~adc_clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_phase <= 14'd0;
        else if (adc_clk) begin
            if (phase_sum >= 15'd12500) sample_phase <= phase_sum - 15'd12500;
            else sample_phase <= phase_sum[13:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) adc_soc <= 1'b0;
        else if (adc_clk) adc_soc <= (phase_sum >= 15'd12500);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_code <= 12'd0;
        else if (adc_clk && adc_eoc) sample_code <= adc_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_valid <= 1'b0;
        else sample_valid <= adc_clk && adc_eoc;
    end

    EG_PHY_ADC #(.CH5("ENABLE"), .VREF("ENABLE")) u_adc (
        .clk(adc_clk), .pd(!rst_n), .s(3'd5), .soc(adc_soc),
        .eoc(adc_eoc), .dout(adc_data)
    );
endmodule
`endif
