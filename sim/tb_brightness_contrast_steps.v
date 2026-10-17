`timescale 1ns/1ps

module tb_brightness_contrast_steps;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_de = 1'b0;
    reg [23:0] rgb_in = 24'h000000;
    reg [2:0] brightness_level = 3'd0;
    reg [2:0] contrast_level = 3'd0;
    wire out_de;
    wire [23:0] rgb_out;

    integer brightness_index;
    integer contrast_index;
    integer pixel_index;
    integer checks;
    integer errors;
    reg [7:0] green_value;
    reg [7:0] blue_value;
    reg expected_de;
    reg [23:0] expected_rgb;

    always #5 clk = ~clk;

    brightness_contrast_steps dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_de(in_de),
        .rgb_in(rgb_in),
        .brightness_level(brightness_level),
        .contrast_level(contrast_level),
        .out_de(out_de),
        .rgb_out(rgb_out)
    );

    function [7:0] reference_channel;
        input integer pixel;
        input integer brightness_sel;
        input integer contrast_sel;
        integer bright_value;
        integer signed delta;
        integer signed contrast_value;
        integer result_value;
        begin
            case (brightness_sel)
                0: bright_value = pixel >> 2;
                1: bright_value = pixel >> 1;
                2: bright_value = (pixel * 3) >> 2;
                3: bright_value = pixel;
                4: bright_value = (pixel * 5) >> 2;
                default: bright_value = pixel;
            endcase
            if (bright_value > 255)
                bright_value = 255;

            delta = bright_value - 128;
            case (contrast_sel)
                0: contrast_value = delta >>> 1;
                1: contrast_value = (delta * 3) >>> 2;
                2: contrast_value = delta;
                3: contrast_value = (delta * 5) >>> 2;
                4: contrast_value = (delta * 3) >>> 1;
                default: contrast_value = delta;
            endcase

            result_value = contrast_value + 128;
            if (result_value < 0)
                reference_channel = 0;
            else if (result_value > 255)
                reference_channel = 255;
            else
                reference_channel = result_value;
        end
    endfunction

    initial begin
        checks = 0;
        errors = 0;
        expected_de = 1'b0;
        expected_rgb = 24'h000000;
        repeat (2) @(posedge clk);
        #1;
        if (out_de !== 1'b0 || rgb_out !== 24'h000000) begin
            $display("FAIL: asynchronous reset did not clear outputs");
            errors = errors + 1;
        end
        rst_n = 1'b1;

        // Exhaust all input pixels and all 3-bit selectors, including defaults.
        // Multiplication by odd 73 and inversion make green and blue each span
        // every byte value for every selector pair as red does.
        for (brightness_index = 0; brightness_index < 8; brightness_index = brightness_index + 1) begin
            for (contrast_index = 0; contrast_index < 8; contrast_index = contrast_index + 1) begin
                for (pixel_index = 0; pixel_index < 256; pixel_index = pixel_index + 1) begin
                    @(negedge clk);
                    brightness_level = brightness_index[2:0];
                    contrast_level = contrast_index[2:0];
                    green_value = (pixel_index * 73 + 19) & 255;
                    blue_value = 255 - pixel_index;
                    rgb_in = {pixel_index[7:0], green_value, blue_value};
                    in_de = ((pixel_index + brightness_index * 3 + contrast_index) % 7) != 0;
                    expected_de = in_de;
                    expected_rgb = {
                        reference_channel(pixel_index, brightness_index, contrast_index),
                        reference_channel((pixel_index * 73 + 19) & 255, brightness_index, contrast_index),
                        reference_channel(255 - pixel_index, brightness_index, contrast_index)
                    };
                    @(posedge clk);
                    #1;
                    checks = checks + 1;
                    if (out_de !== expected_de || rgb_out !== expected_rgb) begin
                        if (errors < 12)
                            $display("FAIL b=%0d c=%0d p=%0d de=%b/%b rgb=%06x/%06x",
                                brightness_index, contrast_index, pixel_index,
                                out_de, expected_de, rgb_out, expected_rgb);
                        errors = errors + 1;
                    end
                end
            end
        end

        // Reassert reset while processing, then verify the first resumed pixel.
        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (out_de !== 1'b0 || rgb_out !== 24'h000000) begin
            $display("FAIL: mid-stream asynchronous reset did not clear outputs");
            errors = errors + 1;
        end
        @(negedge clk);
        rst_n = 1'b1;
        in_de = 1'b1;
        rgb_in = 24'h80FF00;
        brightness_level = 3'd4;
        contrast_level = 3'd3;
        expected_rgb = {
            reference_channel(8'h80, 4, 3),
            reference_channel(8'hFF, 4, 3),
            reference_channel(8'h00, 4, 3)
        };
        @(posedge clk);
        #1;
        checks = checks + 1;
        if (out_de !== 1'b1 || rgb_out !== expected_rgb) begin
            $display("FAIL: first pixel after reset de=%b rgb=%06x expected=%06x",
                out_de, rgb_out, expected_rgb);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_brightness_contrast_steps checks=%0d", checks);
        else
            $display("FAIL: tb_brightness_contrast_steps checks=%0d errors=%0d", checks, errors);
        $finish;
    end
endmodule
