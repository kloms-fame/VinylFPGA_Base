`ifndef EXP_SEG_BUSINESS_MUX_V
`define EXP_SEG_BUSINESS_MUX_V
// Eight digits, left to right: MM-SS blank NN. The sample position is a
// same-clock snapshot of consumed audio (PLAY) or selected track length (BROWSE).
// Conversion uses one shared subtractor; no wide combinational division.
module seg_business_mux (
 input wire clk,rst_n,display_enable,
 input wire [31:0] sample_position,
 input wire [1:0] song_index,
 output wire [7:0] seg_data_0,seg_data_1,seg_data_2,seg_data_3,
 output wire [7:0] seg_data_4,seg_data_5,seg_data_6,seg_data_7
);
 reg [31:0] remaining;
 reg [32:0] difference;
 reg [1:0] unit_sel;
 reg [1:0] state;
 reg [3:0] mh,ml,sh,sl;
 reg [15:0] time_bcd;
 reg [1:0] song_latched, song_display;
 wire [31:0] unit_samples = unit_sel==0 ? 32'd2880000 :
                            unit_sel==1 ? 32'd480000 : 32'd48000;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   remaining<=0;difference<=0;unit_sel<=0;state<=0;
   mh<=0;ml<=0;sh<=0;sl<=0;time_bcd<=0;song_latched<=0;song_display<=0;
  end else case(state)
   0: begin
    remaining <= sample_position >= 32'd287952000 ? 32'd287952000 : sample_position;
    mh<=0;ml<=0;sh<=0;sl<=0;unit_sel<=0;song_latched<=song_index;state<=1;
   end
   1: begin difference<={1'b0,remaining}-{1'b0,unit_samples};state<=2;end
   2: begin
    if(!difference[32]) begin
     remaining<=difference[31:0];state<=1;
     case(unit_sel)
      0: if(ml==9) begin ml<=0;mh<=mh+1'b1;end else ml<=ml+1'b1;
      1: sh<=sh+1'b1;
      2: sl<=sl+1'b1;
     endcase
    end else if(unit_sel==2) begin
     time_bcd<={mh,ml,sh,sl};song_display<=song_latched;state<=0;
    end else begin unit_sel<=unit_sel+1'b1;state<=1;end
   end
   default: state<=0;
  endcase
 end
 wire [6:0] dmh,dml,dsh,dsl,dsong;
 seg_decoder mh_dec(.bin_data(time_bcd[15:12]),.seg_data(dmh));
 seg_decoder ml_dec(.bin_data(time_bcd[11:8]),.seg_data(dml));
 seg_decoder sh_dec(.bin_data(time_bcd[7:4]),.seg_data(dsh));
 seg_decoder sl_dec(.bin_data(time_bcd[3:0]),.seg_data(dsl));
 seg_decoder song_dec(.bin_data({2'b0,song_display}+4'd1),.seg_data(dsong));
 assign seg_data_0=display_enable ? {1'b1,dmh} : 8'hff;
 assign seg_data_1=display_enable ? {1'b1,dml} : 8'hff;
 assign seg_data_2=display_enable ? 8'hbf : 8'hff;
 assign seg_data_3=display_enable ? {1'b1,dsh} : 8'hff;
 assign seg_data_4=display_enable ? {1'b1,dsl} : 8'hff;
 assign seg_data_5=8'hff;
 assign seg_data_6=display_enable ? 8'hc0 : 8'hff;
 assign seg_data_7=display_enable ? {1'b1,dsong} : 8'hff;
endmodule
`endif
