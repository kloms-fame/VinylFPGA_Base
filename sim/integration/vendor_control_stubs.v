// Explicit simulation-only hard-IP boundary stubs. Outputs intentionally undriven.
// Top control benches force clocks/storage/video boundaries; these do not model hardware.
`include "global_def.v"

module sys_pll (
  refclk,
  reset,
  clk0_out,
  clk1_out,
  clk2_out,
  locked
);

  input refclk;
  input reset;
  output clk0_out;
  output clk1_out;
  output clk2_out;
  output locked;

endmodule

module video_pll (
  refclk,
  reset,
  clk0_out,
  clk1_out,
  locked
);

  input refclk;
  input reset;
  output clk0_out;
  output clk1_out;
  output locked;

endmodule

module wfifo_32_32_512 #(parameter DATA_WIDTH_W = 32,
        parameter DATA_WIDTH_R = 32,
        parameter ADDR_WIDTH_W = 9,
        parameter ADDR_WIDTH_R = 9,
        parameter AL_FULL_NUM = 509,
        parameter AL_EMPTY_NUM = 2,
        parameter SHOW_AHEAD_EN = 1'b1,
        parameter OUTREG_EN = "NOREG") (
    //SHOWAHEAD mode enable
    //OUTREG, NOREG
    //independent clock mode,fixed as asynchronous reset
    input rst,  //asynchronous port,active hight
    input clkw,  //write clock
    input clkr,  //read clock
    input we,  //write enable,active hight
    input [(DATA_WIDTH_W - 1):0] di,  //write data
    input re,  //read enable,active hight
    output [(DATA_WIDTH_R - 1):0] dout,  //read data
    output reg valid,  //read data valid flag
    output full_flag,  //fifo full flag
    output empty_flag,  //fifo empty flag
    output afull,  //fifo almost full flag
    output aempty,  //fifo almost empty flag
    output [(ADDR_WIDTH_W - 1):0] wrusedw,  //stored data number in fifo
    output [(ADDR_WIDTH_R - 1):0] rdusedw //available data number for read
        )  /* fehdl keep_hierarchy="true" */ ;
endmodule

module rfifo_32_32_512 #(parameter DATA_WIDTH_W = 32,
        parameter DATA_WIDTH_R = 32,
        parameter ADDR_WIDTH_W = 9,
        parameter ADDR_WIDTH_R = 9,
        parameter AL_FULL_NUM = 509,
        parameter AL_EMPTY_NUM = 2,
        parameter SHOW_AHEAD_EN = 1'b0,
        parameter OUTREG_EN = "NOREG") (
    //SHOWAHEAD mode enable
    //OUTREG, NOREG
    //independent clock mode,fixed as asynchronous reset
    input rst,  //asynchronous port,active hight
    input clkw,  //write clock
    input clkr,  //read clock
    input we,  //write enable,active hight
    input [(DATA_WIDTH_W - 1):0] di,  //write data
    input re,  //read enable,active hight
    output [(DATA_WIDTH_R - 1):0] dout,  //read data
    output reg valid,  //read data valid flag
    output full_flag,  //fifo full flag
    output empty_flag,  //fifo empty flag
    output afull,  //fifo almost full flag
    output aempty,  //fifo almost empty flag
    output [(ADDR_WIDTH_W - 1):0] wrusedw,  //stored data number in fifo
    output [(ADDR_WIDTH_R - 1):0] rdusedw //available data number for read
        )  /* fehdl keep_hierarchy="true" */ ;
endmodule

module hdmi_phy_wrapper#(
    parameter DEVICE = "EG"
    )(
    input wire      I_pixel_clk,
    input wire      I_serial_clk,
    input wire      I_rst,

    input wire[9:0] I_tmds_channel_0,
    input wire[9:0] I_tmds_channel_1,
    input wire[9:0] I_tmds_channel_2,
    input wire[9:0] I_tmds_channel_clk,

    output wire     O_tmds_ch0_p,
    output wire     O_tmds_ch1_p,
    output wire     O_tmds_ch2_p,
    output wire     O_tmds_clk_p
);
endmodule

module hdmi_1_4b_transmitter_core_wrapper#(
    parameter DEVICE            = "EG", //"EF2","EF3","EF4","SF1","SF2","EG","PH1A","PH1P","DR1","PH2A"

    parameter HTOTAL            = 2200,
    parameter HSA               = 44,
    parameter HFP               = 88,
    parameter HBP               = 148,
    parameter HACTIVE           = 1920,
    parameter VTOTAL            = 1125,
    parameter VSA               = 5,
    parameter VFP               = 4,
    parameter VBP               = 36,
    parameter VACTIVE           = 1080,

    parameter VIDEO_TPG         = "Enable",
    parameter VIDEO_FORMAT      = "RGB",
    parameter VIDEO_VIC         = 16,

    parameter AUDIO_SAMPLE_RATE = "48K",

    parameter IIC_SCL_DIV       = 125
)(
    input wire       I_pixel_clk,
    input wire       I_rst,

    /*
        edid read interface
    */
    input wire       I_edid_read_trig,
    output wire      O_edid_read_valid,
    output wire[7:0] O_edid_read_data,

    /*
        video interface
    */
    input wire       I_axis_s_user,
    input wire       I_axis_s_valid,
    input wire       I_axis_s_last,
    input wire[23:0] I_axis_s_data,
    output wire      O_axis_s_ready,

    /*
        audio interface
    */
    input wire       I_audio_valid,
    input wire[23:0] I_audio_left_data,
    input wire[23:0] I_audio_right_data,

    /*
        audio regenaration interface
    */
    input wire       I_acr_valid,
    input wire[19:0] I_acr_cts,
    input wire[19:0] I_acr_n,

    /*
        status signal
    */
    output wire      O_video_locked,

    /*
        DDC channel interface
    */
    output wire      O_ddc_scl,
    inout wire       IO_ddc_sda,

    /*
        tmds data interface
    */
    output wire[9:0] O_ch0_tmds_data,
    output wire[9:0] O_ch1_tmds_data,
    output wire[9:0] O_ch2_tmds_data,
    output wire[9:0] O_clk_tmds_data
);
endmodule

module sdr_as_ram  #( parameter self_refresh_open=1)
	(
	    input   		Sdr_clk,
		input			Sdr_clk_sft,
        input   		Rst,

		output			Sdr_init_done,
		output			Sdr_init_ref_vld,
		output	    	Sdr_busy,

		input			App_ref_req,

        input						App_wr_en,
        input  [`ADDR_WIDTH-1:0]	App_wr_addr,  	////row[10:0],bank[1:0],col[7:0]
		input	[`DM_WIDTH-1:0]		App_wr_dm,
		input	[`DATA_WIDTH-1:0]	App_wr_din,

		input						App_rd_en,
		input	[`ADDR_WIDTH-1:0]	App_rd_addr,
		output						Sdr_rd_en,	//synthesis keep
		output	[`DATA_WIDTH-1:0]	Sdr_rd_dout,//synthesis keep


		output							SDRAM_CLK,
		output  						SDR_RAS,
		output							SDR_CAS,
		output							SDR_WE,
		output		[`BA_WIDTH-1:0]		SDR_BA,
		output		[`ROW_WIDTH-1:0]	SDR_ADDR,
		output		[`DM_WIDTH-1:0]		SDR_DM,
		inout		[`DATA_WIDTH-1:0]	SDR_DQ

	);
endmodule

module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,cs_n,dm0,dm1,dm2,dm3,cke,
 input[10:0]addr,input[1:0]ba,inout[31:0]dq); endmodule

// ADC hard-macro stub for the microphone capture path. EOC is tied low and the
// data bus is tied to mid-scale, so the capture FSM stays idle instead of
// propagating X into the audio mixer. This is not a converter model.
module EG_PHY_ADC #(
  parameter CH5  = "DISABLE",
  parameter VREF = "DISABLE"
)(
  input  wire       clk,
  input  wire       pd,
  input  wire [2:0] s,
  input  wire       soc,
  output wire       eoc,
  output wire [11:0] dout
);
  assign eoc  = 1'b0;
  assign dout = 12'h800;
endmodule
