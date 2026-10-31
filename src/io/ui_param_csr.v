`ifndef EXP_UI_PARAM_CSR_V
`define EXP_UI_PARAM_CSR_V
// 唯一可写参数所有者：VOL、BRI、CON、ROT、WSL、MIC 均在 50 MHz UI 域更新。
module ui_param_csr #(
    parameter [7:0] DEFAULT_VOLUME       = 8'd200,
    parameter [7:0] VOLUME_STEP          = 8'd16,
    parameter [2:0] DEFAULT_BRIGHTNESS   = 3'd3, // 1.00x
    parameter [2:0] DEFAULT_CONTRAST     = 3'd2, // 1.00x
    parameter [2:0] DEFAULT_ROTATION     = 3'd2, // 3 seconds, preserving D1 default
    parameter [2:0] DEFAULT_WS_LEVEL     = 3'd4, // 100% of existing safe colors
    parameter [2:0] DEFAULT_MIC_LEVEL    = 3'd5  // 5X
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       defaults_req,
    input  wire       restore_valid,
    input  wire [22:0] restore_data, // {MIC,WSL,ROT,CON,BRI,VOL}, atomic UI-domain load
    input  wire       wr_valid,
    input  wire [2:0] wr_id,       // 0=VOL, 1=BRI, 2=CON, 3=ROT, 4=WSL, 5=MIC
    input  wire       wr_up,
    output reg  [7:0] volume,
    output reg  [2:0] brightness_level,
    output reg  [2:0] contrast_level,
    output reg  [2:0] rotation_level,
    output reg  [2:0] ws_level,
    output reg  [2:0] mic_level,
    output reg        param_update
);
    localparam [2:0] PARAM_VOL = 3'd0;
    localparam [2:0] PARAM_BRI = 3'd1;
    localparam [2:0] PARAM_CON = 3'd2;
    localparam [2:0] PARAM_ROT = 3'd3;
    localparam [2:0] PARAM_WSL = 3'd4;
    localparam [2:0] PARAM_MIC = 3'd5;

    wire [8:0] volume_up_sum = {1'b0, volume} + {1'b0, VOLUME_STEP};
    wire [7:0] volume_up_next = (volume_up_sum > 9'd255) ? 8'd255 : volume_up_sum[7:0];
    wire [7:0] volume_dn_next = ({1'b0, volume} < {1'b0, VOLUME_STEP})
                              ? 8'd0 : volume - VOLUME_STEP;
    // MIC pages intentionally wrap: 0X -> 4X -> 5X -> 6X -> 7X -> 0X.
    wire [2:0] mic_up_next =
        (mic_level == 3'd0) ? 3'd4 :
        ((mic_level >= 3'd4) && (mic_level < 3'd7)) ? (mic_level + 3'd1) : 3'd0;
    wire [2:0] mic_dn_next =
        (mic_level == 3'd0) ? 3'd7 :
        ((mic_level > 3'd4) && (mic_level <= 3'd7)) ? (mic_level - 3'd1) : 3'd0;
    wire [2:0] restore_mic_level = restore_data[22:20];
    wire restore_mic_valid =
        (restore_mic_level == 3'd0) ||
        ((restore_mic_level >= 3'd4) && (restore_mic_level <= 3'd7));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            volume           <= DEFAULT_VOLUME;
            brightness_level <= DEFAULT_BRIGHTNESS;
            contrast_level   <= DEFAULT_CONTRAST;
            rotation_level   <= DEFAULT_ROTATION;
            ws_level         <= DEFAULT_WS_LEVEL;
            mic_level        <= DEFAULT_MIC_LEVEL;
            param_update     <= 1'b0;
        end else begin
            param_update <= 1'b0;
            if (defaults_req) begin
                volume           <= DEFAULT_VOLUME;
                brightness_level <= DEFAULT_BRIGHTNESS;
                contrast_level   <= DEFAULT_CONTRAST;
                rotation_level   <= DEFAULT_ROTATION;
                ws_level         <= DEFAULT_WS_LEVEL;
                mic_level        <= DEFAULT_MIC_LEVEL;
                param_update     <= 1'b1;
            end else if (wr_valid) begin
                case (wr_id)
                    PARAM_VOL: begin
                        if (wr_up && volume_up_next != volume) begin
                            volume       <= volume_up_next;
                            param_update <= 1'b1;
                        end else if (!wr_up && volume_dn_next != volume) begin
                            volume       <= volume_dn_next;
                            param_update <= 1'b1;
                        end
                    end
                    PARAM_BRI: begin
                        if (wr_up && brightness_level < 3'd4) begin
                            brightness_level <= brightness_level + 3'd1;
                            param_update <= 1'b1;
                        end else if (!wr_up && brightness_level > 3'd0) begin
                            brightness_level <= brightness_level - 3'd1;
                            param_update <= 1'b1;
                        end
                    end
                    PARAM_CON: begin
                        if (wr_up && contrast_level < 3'd4) begin
                            contrast_level <= contrast_level + 3'd1;
                            param_update <= 1'b1;
                        end else if (!wr_up && contrast_level > 3'd0) begin
                            contrast_level <= contrast_level - 3'd1;
                            param_update <= 1'b1;
                        end
                    end
                    PARAM_ROT: begin
                        if (wr_up && rotation_level < 3'd5) begin
                            rotation_level <= rotation_level + 3'd1;
                            param_update <= 1'b1;
                        end else if (!wr_up && rotation_level > 3'd0) begin
                            rotation_level <= rotation_level - 3'd1;
                            param_update <= 1'b1;
                        end
                    end
                    PARAM_WSL: begin
                        if (wr_up && ws_level < 3'd4) begin
                            ws_level <= ws_level + 3'd1;
                            param_update <= 1'b1;
                        end else if (!wr_up && ws_level > 3'd0) begin
                            ws_level <= ws_level - 3'd1;
                            param_update <= 1'b1;
                        end
                    end
                    PARAM_MIC: begin
                        if (wr_up) begin
                            mic_level    <= mic_up_next;
                            param_update <= 1'b1;
                        end else begin
                            mic_level    <= mic_dn_next;
                            param_update <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end else if (restore_valid && restore_data[10:8]<=3'd4 &&
                         restore_data[13:11]<=3'd4 && restore_data[16:14]<=3'd5 &&
                         restore_data[19:17]<=3'd4 && restore_mic_valid) begin
                volume           <= restore_data[7:0];
                brightness_level <= restore_data[10:8];
                contrast_level   <= restore_data[13:11];
                rotation_level   <= restore_data[16:14];
                ws_level         <= restore_data[19:17];
                mic_level        <= restore_mic_level;
                param_update     <= 1'b1;
            end
        end
    end
endmodule
`endif
