`ifndef VINYL_MIC_ADC_CAPTURE_V
`define VINYL_MIC_ADC_CAPTURE_V
`timescale 1ns/1ps

// EG4S20 ADC_CH5 capture for the direct EXT3 microphone input.
// The 25 MHz video clock divides by two to produce the ADC hard-IP clock.
// Conversions are requested at about 192 kS/s; the conditioner decimates
// exactly 4:1 to 48 kHz. EOC is synchronized before its rising edge is used
// to capture the hard-IP result in the video-clock domain.
module mic_adc_capture (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [11:0] sample_code,
    output reg         sample_valid
);
    localparam integer ADC_STEPS_PER_SAMPLE = 192;
    localparam integer ADC_PHASE_MODULUS   = 12500;

    (* keep = "true" *) reg adc_clk;
    reg        adc_soc;
    reg [13:0] sample_phase;
    reg        soc_pending;
    reg        conversion_active;
    reg  [7:0] eoc_timeout;
    reg        eoc_meta;
    reg        eoc_sync_q;

    wire        adc_eoc;
    wire [11:0] adc_data;
    wire [13:0] phase_sum = sample_phase + ADC_STEPS_PER_SAMPLE;
    wire        sample_due = (phase_sum >= ADC_PHASE_MODULUS);
    // adc_clk is high here for the final video clock before it falls. The
    // resulting SOC is therefore stable across the following ADC rising edge.
    wire        start_conversion = soc_pending && adc_clk && !conversion_active;
    wire        eoc_rise = eoc_meta && !eoc_sync_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            adc_clk <= 1'b0;
        else
            adc_clk <= ~adc_clk;
    end

    // Update the fractional divider only on the rising half of adc_clk.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sample_phase <= 14'd0;
        else if (!adc_clk) begin
            if (sample_due)
                sample_phase <= phase_sum - ADC_PHASE_MODULUS;
            else
                sample_phase <= phase_sum;
        end
    end

    // adc_soc is sampled by the hard ADC on the next adc_clk rising edge.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            adc_soc <= 1'b0;
        else if (start_conversion)
            adc_soc <= 1'b1;
        else if (adc_soc && adc_clk)
            adc_soc <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            soc_pending <= 1'b0;
        else if (start_conversion)
            soc_pending <= 1'b0;
        else if (sample_due && !conversion_active)
            soc_pending <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conversion_active <= 1'b0;
            eoc_timeout       <= 8'd0;
        end else if (start_conversion) begin
            conversion_active <= 1'b1;
            eoc_timeout       <= 8'd0;
        end else if (eoc_rise) begin
            conversion_active <= 1'b0;
            eoc_timeout       <= 8'd0;
        end else if (conversion_active) begin
            if (&eoc_timeout) begin
                conversion_active <= 1'b0;
                eoc_timeout       <= 8'd0;
            end else begin
                eoc_timeout <= eoc_timeout + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eoc_meta   <= 1'b0;
            eoc_sync_q <= 1'b0;
        end else begin
            eoc_meta   <= adc_eoc;
            eoc_sync_q <= eoc_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_code  <= 12'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (eoc_rise) begin
                sample_code  <= adc_data;
                sample_valid <= 1'b1;
            end
        end
    end

    EG_PHY_ADC #(
        .CH5  ("ENABLE"),
        .VREF ("ENABLE")
    ) u_adc (
        .clk  (adc_clk),
        .pd   (!rst_n),
        .s    (3'd5),
        .soc  (adc_soc),
        .eoc  (adc_eoc),
        .dout (adc_data)
    );
endmodule
`endif
