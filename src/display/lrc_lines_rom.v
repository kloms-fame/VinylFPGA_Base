// 由 tools/gen_lrc_assets.py 自动生成，请勿手改。
`ifndef EXP_LRC_LINES_ROM_V
`define EXP_LRC_LINES_ROM_V
module lrc_lines_rom (
    input  wire [3:0]  line,
    input  wire [3:0]  col,
    output reg  [31:0] time_ms,
    output reg  [7:0]  glyph
);
    always @* begin
        time_ms = 32'd0;
        glyph   = 8'd0;
        case (line)
            4'd0: begin
                time_ms = 32'd0;
                case (col)
                    4'd0: glyph = 8'd13;
                    4'd1: glyph = 8'd15;
                    4'd2: glyph = 8'd17;
                    4'd3: glyph = 8'd18;
                    4'd4: glyph = 8'd16;
                    4'd5: glyph = 8'd9;
                    4'd6: glyph = 8'd12;
                    4'd7: glyph = 8'd10;
                    4'd8: glyph = 8'd6;
                    4'd9: glyph = 8'd0;
                    4'd10: glyph = 8'd42;
                    4'd11: glyph = 8'd45;
                    4'd12: glyph = 8'd40;
                    4'd13: glyph = 8'd51;
                    default: glyph = 8'd0;
                endcase
            end
            4'd1: begin
                time_ms = 32'd3000;
                case (col)
                    4'd0: glyph = 8'd33;
                    4'd1: glyph = 8'd59;
                    4'd2: glyph = 8'd48;
                    4'd3: glyph = 8'd35;
                    4'd4: glyph = 8'd19;
                    4'd5: glyph = 8'd55;
                    4'd6: glyph = 8'd43;
                    default: glyph = 8'd0;
                endcase
            end
            4'd2: begin
                time_ms = 32'd6500;
                case (col)
                    4'd0: glyph = 8'd50;
                    4'd1: glyph = 8'd29;
                    4'd2: glyph = 8'd58;
                    4'd3: glyph = 8'd32;
                    4'd4: glyph = 8'd32;
                    4'd5: glyph = 8'd56;
                    4'd6: glyph = 8'd39;
                    default: glyph = 8'd0;
                endcase
            end
            4'd3: begin
                time_ms = 32'd10000;
                case (col)
                    4'd0: glyph = 8'd8;
                    4'd1: glyph = 8'd7;
                    4'd2: glyph = 8'd2;
                    4'd3: glyph = 8'd0;
                    4'd4: glyph = 8'd36;
                    4'd5: glyph = 8'd55;
                    4'd6: glyph = 8'd26;
                    4'd7: glyph = 8'd21;
                    4'd8: glyph = 8'd24;
                    4'd9: glyph = 8'd40;
                    default: glyph = 8'd0;
                endcase
            end
            4'd4: begin
                time_ms = 32'd13500;
                case (col)
                    4'd0: glyph = 8'd34;
                    4'd1: glyph = 8'd20;
                    4'd2: glyph = 8'd38;
                    4'd3: glyph = 8'd22;
                    4'd4: glyph = 8'd23;
                    4'd5: glyph = 8'd34;
                    4'd6: glyph = 8'd46;
                    4'd7: glyph = 8'd47;
                    default: glyph = 8'd0;
                endcase
            end
            4'd5: begin
                time_ms = 32'd17000;
                case (col)
                    4'd0: glyph = 8'd11;
                    4'd1: glyph = 8'd8;
                    4'd2: glyph = 8'd14;
                    4'd3: glyph = 8'd1;
                    4'd4: glyph = 8'd3;
                    4'd5: glyph = 8'd0;
                    4'd6: glyph = 8'd52;
                    4'd7: glyph = 8'd30;
                    4'd8: glyph = 8'd58;
                    4'd9: glyph = 8'd57;
                    default: glyph = 8'd0;
                endcase
            end
            4'd6: begin
                time_ms = 32'd20500;
                case (col)
                    4'd0: glyph = 8'd11;
                    4'd1: glyph = 8'd8;
                    4'd2: glyph = 8'd14;
                    4'd3: glyph = 8'd1;
                    4'd4: glyph = 8'd4;
                    4'd5: glyph = 8'd0;
                    4'd6: glyph = 8'd52;
                    4'd7: glyph = 8'd31;
                    4'd8: glyph = 8'd58;
                    4'd9: glyph = 8'd57;
                    default: glyph = 8'd0;
                endcase
            end
            4'd7: begin
                time_ms = 32'd24000;
                case (col)
                    4'd0: glyph = 8'd11;
                    4'd1: glyph = 8'd8;
                    4'd2: glyph = 8'd14;
                    4'd3: glyph = 8'd1;
                    4'd4: glyph = 8'd5;
                    4'd5: glyph = 8'd0;
                    4'd6: glyph = 8'd27;
                    4'd7: glyph = 8'd25;
                    4'd8: glyph = 8'd41;
                    4'd9: glyph = 8'd49;
                    default: glyph = 8'd0;
                endcase
            end
            4'd8: begin
                time_ms = 32'd27500;
                case (col)
                    4'd0: glyph = 8'd40;
                    4'd1: glyph = 8'd51;
                    4'd2: glyph = 8'd54;
                    4'd3: glyph = 8'd44;
                    4'd4: glyph = 8'd37;
                    4'd5: glyph = 8'd28;
                    4'd6: glyph = 8'd53;
                    default: glyph = 8'd0;
                endcase
            end
            default: begin time_ms = 32'hFFFFFFFF; glyph = 8'd0; end
        endcase
    end
endmodule
`endif
