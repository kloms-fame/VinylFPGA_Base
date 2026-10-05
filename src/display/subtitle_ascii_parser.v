`timescale 1ns/1ps

// ASCII command parser used by tools/micu_subtitle_sender.py:
//
//   @C\n
//   @G,<2 hex slot>,<64 hex glyph rows>\n
//   @A,<2 hex slot>\n
//   @T\n
//
// @A writes a slot into the staging text bank. @T publishes the staging bank
// to the video domain as one complete line.
module subtitle_ascii_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_valid,
    input  wire [7:0] rx_data,

    output reg        glyph_we,
    output reg  [9:0] glyph_waddr,
    output reg  [15:0] glyph_wdata,

    output reg        text_we,
    output reg  [5:0] text_waddr,
    output reg  [4:0] text_wdata,

    output reg        commit_toggle,
    output reg        commit_bank,
    output reg  [5:0] commit_length
);
    localparam [3:0] ST_AT       = 4'd0;
    localparam [3:0] ST_CMD      = 4'd1;
    localparam [3:0] ST_G_SEP1   = 4'd2;
    localparam [3:0] ST_G_H1     = 4'd3;
    localparam [3:0] ST_G_H2     = 4'd4;
    localparam [3:0] ST_G_SEP2   = 4'd5;
    localparam [3:0] ST_G_HEX    = 4'd6;
    localparam [3:0] ST_G_LF     = 4'd7;
    localparam [3:0] ST_A_SEP    = 4'd8;
    localparam [3:0] ST_A_H1     = 4'd9;
    localparam [3:0] ST_A_H2     = 4'd10;
    localparam [3:0] ST_A_LF     = 4'd11;
    localparam [3:0] ST_C_LF     = 4'd12;
    localparam [3:0] ST_T_LF     = 4'd13;

    reg [3:0]  state;
    reg [3:0]  slot_hi;
    reg [4:0]  slot_value;
    reg [5:0]  staging_index;
    reg        write_bank;
    reg [3:0]  glyph_row;
    reg [1:0]  nibble_index;
    reg [15:0] glyph_shift;

    function [3:0] hex_nibble;
        input [7:0] value;
        begin
            if ((value >= "0") && (value <= "9"))
                hex_nibble = value - "0";
            else if ((value >= "A") && (value <= "F"))
                hex_nibble = value - "A" + 4'd10;
            else if ((value >= "a") && (value <= "f"))
                hex_nibble = value - "a" + 4'd10;
            else
                hex_nibble = 4'h0;
        end
    endfunction

    wire [3:0] rx_hex = hex_nibble(rx_data);
    wire       rx_is_hex =
        ((rx_data >= "0") && (rx_data <= "9")) ||
        ((rx_data >= "A") && (rx_data <= "F")) ||
        ((rx_data >= "a") && (rx_data <= "f"));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_AT;
            slot_hi       <= 4'd0;
            slot_value    <= 5'd0;
            staging_index <= 6'd0;
            write_bank    <= 1'b1;
            glyph_row     <= 4'd0;
            nibble_index  <= 2'd0;
            glyph_shift   <= 16'd0;
            glyph_we      <= 1'b0;
            glyph_waddr   <= 10'd0;
            glyph_wdata   <= 16'd0;
            text_we       <= 1'b0;
            text_waddr    <= 6'd0;
            text_wdata    <= 5'd0;
            commit_toggle <= 1'b0;
            commit_bank   <= 1'b0;
            commit_length <= 6'd0;
        end else begin
            glyph_we <= 1'b0;
            text_we  <= 1'b0;

            if (rx_valid) begin
                case (state)
                    ST_AT: begin
                        if (rx_data == "@")
                            state <= ST_CMD;
                    end

                    ST_CMD: begin
                        if (rx_data == "G") begin
                            glyph_row    <= 4'd0;
                            nibble_index <= 2'd0;
                            glyph_shift  <= 16'd0;
                            state        <= ST_G_SEP1;
                        end else if (rx_data == "A") begin
                            state <= ST_A_SEP;
                        end else if (rx_data == "C") begin
                            state <= ST_C_LF;
                        end else if (rx_data == "T") begin
                            state <= ST_T_LF;
                        end else begin
                            state <= ST_AT;
                        end
                    end

                    ST_G_SEP1: begin
                        if (rx_data == ",")
                            state <= ST_G_H1;
                        else if (rx_data == 8'h0a)
                            state <= ST_AT;
                        else if (rx_data != 8'h0d)
                            state <= ST_AT;
                    end

                    ST_G_H1: begin
                        if (rx_is_hex) begin
                            slot_hi <= rx_hex;
                            state   <= ST_G_H2;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_G_H2: begin
                        if (rx_is_hex) begin
                            slot_value <= {slot_hi[0], rx_hex};
                            state      <= ST_G_SEP2;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_G_SEP2: begin
                        if (rx_data == ",") begin
                            glyph_row    <= 4'd0;
                            nibble_index <= 2'd0;
                            glyph_shift  <= 16'd0;
                            state        <= ST_G_HEX;
                        end else if (rx_data == 8'h0a) begin
                            state <= ST_AT;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_G_HEX: begin
                        if (rx_is_hex) begin
                            glyph_shift <= {glyph_shift[11:0], rx_hex};
                            if (nibble_index == 2'd3) begin
                                glyph_we    <= 1'b1;
                                glyph_waddr <= {write_bank, slot_value, glyph_row};
                                glyph_wdata <= {glyph_shift[11:0], rx_hex};
                                nibble_index <= 2'd0;
                                if (glyph_row == 4'd15) begin
                                    glyph_row <= 4'd0;
                                    state     <= ST_G_LF;
                                end else begin
                                    glyph_row <= glyph_row + 4'd1;
                                end
                            end else begin
                                nibble_index <= nibble_index + 2'd1;
                            end
                        end else if (rx_data == 8'h0a) begin
                            state <= ST_AT;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_G_LF: begin
                        if (rx_data == 8'h0a)
                            state <= ST_AT;
                    end

                    ST_A_SEP: begin
                        if (rx_data == ",")
                            state <= ST_A_H1;
                        else if (rx_data == 8'h0a)
                            state <= ST_AT;
                        else if (rx_data != 8'h0d)
                            state <= ST_AT;
                    end

                    ST_A_H1: begin
                        if (rx_is_hex) begin
                            slot_hi <= rx_hex;
                            state   <= ST_A_H2;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_A_H2: begin
                        if (rx_is_hex) begin
                            slot_value <= {slot_hi[0], rx_hex};
                            state      <= ST_A_LF;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_A_LF: begin
                        if (rx_data == 8'h0a) begin
                            if (staging_index < 6'd32) begin
                                text_we    <= 1'b1;
                                text_waddr <= {write_bank, staging_index[4:0]};
                                text_wdata <= slot_value;
                                staging_index <= staging_index + 6'd1;
                            end
                            state <= ST_AT;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_C_LF: begin
                        if (rx_data == 8'h0a) begin
                            staging_index <= 6'd0;
                            state         <= ST_AT;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    ST_T_LF: begin
                        if (rx_data == 8'h0a) begin
                            commit_length <= staging_index;
                            commit_bank   <= write_bank;
                            commit_toggle <= ~commit_toggle;
                            write_bank    <= ~write_bank;
                            staging_index <= 6'd0;
                            state         <= ST_AT;
                        end else if (rx_data != 8'h0d) begin
                            state <= ST_AT;
                        end
                    end

                    default: begin
                        state <= ST_AT;
                    end
                endcase
            end
        end
    end
endmodule
