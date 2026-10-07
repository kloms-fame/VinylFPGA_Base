// Eight active-low digit selects, SEL0..SEL7. Blank one clock before each
// digit change so segment settling cannot light the previous digit (ghosting).
module seg_scan #(
 parameter SCAN_FREQ=200,
 parameter CLK_FREQ=50000000,
 parameter SCAN_COUNT=CLK_FREQ/(SCAN_FREQ*8)-1
)(
 input wire clk,rst_n,
 output reg [7:0] seg_sel,seg_data,
 input wire [7:0] seg_data_0,seg_data_1,seg_data_2,seg_data_3,
 input wire [7:0] seg_data_4,seg_data_5,seg_data_6,seg_data_7
);
 localparam TIMER_W=(SCAN_COUNT<2) ? 1 : $clog2(SCAN_COUNT+1);
 reg [TIMER_W-1:0] scan_timer;
 reg [2:0] scan_sel;
 reg [7:0] selected_data;
 always @* begin
  case(scan_sel)
   0:selected_data=seg_data_0;1:selected_data=seg_data_1;
   2:selected_data=seg_data_2;3:selected_data=seg_data_3;
   4:selected_data=seg_data_4;5:selected_data=seg_data_5;
   6:selected_data=seg_data_6;7:selected_data=seg_data_7;
   default:selected_data=8'hff;
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin scan_timer<=0;scan_sel<=0;seg_sel<=8'hff;seg_data<=8'hff;end
  else if(scan_timer==SCAN_COUNT) begin
   scan_timer<=0;scan_sel<=scan_sel+1'b1;seg_sel<=8'hff;
  end else begin
   scan_timer<=scan_timer+1'b1;
   if(scan_timer==0) begin seg_sel<=8'hff;seg_data<=selected_data;end
   else seg_sel<=~(8'b1<<scan_sel);
  end
 end
endmodule
