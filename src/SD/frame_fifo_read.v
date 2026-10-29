`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
    parameter COMPOSITE_READ        = 0,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128,
	// 第十二讲彩点修正：SDRAM 读突发节奏参数。
	// 依据《第八讲：四bank帧缓存架构》3.3/4.2 节，完赛工程 media_frame_reader 对
	// SDRAM 控制器采取“避让刷新 + 突发间隔 + 忙判据”的读调度：
	//   BURST_GAP_CYCLES = 12  ：两次读突发之间至少留 12 个空闲周期给自动刷新；
	//   controller_busy  : Sdr_busy      —— 控制器忙时不新起突发；
	//   refresh_active   : Sdr_init_ref_vld —— 刷新期间不新起突发。
	// 原官方 frame_fifo_read 收到这两个信号但从未使用，突发可以在刷新窗口内开跑，
	// 一旦读采样窗口被刷新命令挤掉，就会读出错误像素（表现为图片上的彩点）。
	// FIFO_LOW_WATERMARK 是安全兜底：FIFO 快空时不再等待空闲窗口，宁可照原样发突发，
	// 保证任何情况下都不会因为新增节流逻辑而欠载（worst case 退化为官方行为）。
	parameter BURST_GAP_CYCLES       = 12,
	parameter FIFO_LOW_WATERMARK     = 128
)               
(
	input                            rst,
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,
    output							 O_rd_busy,
	/*
    output reg                       rd_burst_req,               // to external memory controller,send out a burst read request  
	output reg[BURST_BITS - 1:0]     rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes 
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read request data valid    
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,
	
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output reg                       read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[9:0]                      wrusedw                     // from fifo write used words

    ,input wire background_enable, background_media_mv, background_epoch, background_art2
    ,input wire [20:0] background_media_base, background_base
    ,output wire background_epoch_ack
    ,output wire read_data_keep
    ,output wire read_data_art, read_data_art2

);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'
//read state machine code
localparam S_IDLE                    = 0;                        //idle state,waiting for frame read
localparam S_ACK                     = 1;                        //read request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst read
localparam S_READ_BURST              = 3;                        //begin a burst read
localparam S_READ_BURST_END          = 4;                        //a burst read complete
localparam S_END                     = 5;                        //a frame of data is read to complete

reg                                  read_req_d0;                //asynchronous read request, synchronize to 'mem_clk' clock domain,first beat
reg                                  read_req_d1;                //second
reg                                  read_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0]                 read_len_d0;                //asynchronous read_len(read data length), synchronize to 'mem_clk' clock domain first
reg[ADDR_BITS - 1:0]                 read_len_d1;                //second
reg[ADDR_BITS - 1:0]                 read_len_latch;             //lock read data length
reg[ADDR_BITS - 1:0]                 read_cnt;                   //read data counter
reg[3:0]                             state;                      //state machine
reg[1:0]                             read_addr_index_d0;         //synchronize to 'mem_clk' clock domain first
reg[1:0]                             read_addr_index_d1;         //synchronize to 'mem_clk' clock domain second
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg App_rd_en_r;
reg App_rd_en_d0;

// 两次读突发之间的空闲周期计数（App_rd_en 为低时累加，饱和在 BURST_GAP_CYCLES）
reg [4:0] rd_gap_cnt;
wire      rd_gap_ok = (rd_gap_cnt >= BURST_GAP_CYCLES);
// 控制器空闲（既不在刷新窗口，也不忙）时优先起突发
wire      ctrl_quiet = ~Sdr_init_ref_vld & ~Sdr_busy;
// FIFO 低水位兜底：即使控制器一直忙也必须发突发，避免显示端欠载
wire      fifo_low   = (wrusedw <= FIFO_LOW_WATERMARK);


wire rd_vld;
reg [3:0] rd_delay;

wire raster_enabled;
wire [20:0] raster_address;
wire [8:0] raster_span;
wire raster_span_ready, raster_cover;
wire raster_background;
reg frame_art = 1'b0, frame_art2 = 1'b0;
reg burst_art = 1'b0;
reg burst_cover = 1'b0;
reg returned_pair = 1'b0;
reg [BURST_BITS-1:0] burst_limit = BURST_SIZE;
background_raster_address u_background_raster_address (
    .clk(mem_clk),.rst_n(!rst),.latch(state == S_ACK),.advance(App_rd_en),
    .enable(COMPOSITE_READ && background_enable),.media_mv(background_media_mv),
    .epoch(background_epoch),.media_base(background_media_base),
    .background_base(background_base),.enabled(raster_enabled),
    .epoch_ack(background_epoch_ack),.address(raster_address),
    .contiguous_words(raster_span),.span_ready(raster_span_ready),
    .cover_words(raster_cover),.background_words(raster_background)
);
// Freeze the format with the same frame mailbox as the address. Bursts are
// split at every source boundary and fully drained before this tag changes.
assign read_data_art = burst_art;
assign read_data_art2 = frame_art2;
always @(posedge mem_clk or posedge rst) begin
    if (rst) frame_art <= 1'b0;
    else if (state == S_ACK) frame_art <= background_base == 21'd1766400;
end
always @(posedge mem_clk or posedge rst) begin
    if (rst) frame_art2 <= 1'b0;
    else if (state == S_ACK) frame_art2 <= background_art2;
end
always @(posedge mem_clk or posedge rst) begin
    if (rst) burst_art <= 1'b0;
    else if (state == S_CHECK_FIFO) burst_art <= raster_background && frame_art;
end
// Source boundaries and 128-word/256-column splits make every cover burst
// even. Hold its type until all returns drain; sample returned data, not the
// command-side cursor or an assumed fixed SDRAM latency.
assign read_data_keep = !burst_cover || !returned_pair;
always @(posedge mem_clk or posedge rst) begin
    if (rst) burst_cover <= 1'b0;
    else if (state == S_CHECK_FIFO) burst_cover <= raster_cover;
end
always @(posedge mem_clk or posedge rst) begin
    if (rst) returned_pair <= 1'b0;
    else if (state == S_CHECK_FIFO || fifo_aclr) returned_pair <= 1'b0;
    else if (Sdr_rd_en && burst_cover) returned_pair <= !returned_pair;
end
assign App_rd_addr = raster_enabled ? raster_address : App_rd_addr_r;
assign rd_vld = (state == S_READ_BURST && burst_cnt >= burst_limit);
always @(posedge mem_clk or posedge rst) begin
    if (rst) burst_limit <= BURST_SIZE;
    else if (state == S_CHECK_FIFO)
        burst_limit <= (raster_enabled && raster_span < BURST_SIZE)
                       ? raster_span : BURST_SIZE;
end

assign O_rd_busy = (state == S_READ_BURST);//读指令期间
//burst_cnt代表发送的读指令
//但rd_burst_finish需要在发送完十个时钟后拉高，此时数据全部读出
assign rd_burst_finish = (rd_vld && rd_delay == 4'd10);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             //read finish at state 'S_END'
assign App_rd_en = App_rd_en_d0;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d0 <= 0;
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d1 <= 0;
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
		rd_gap_cnt         <= 5'd0;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;     
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0; 
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;

		// 读突发节奏计数：突发进行中清零，空闲时累加并饱和
		if(App_rd_en)
			rd_gap_cnt <= 5'd0;
		else if(!rd_gap_ok)
			rd_gap_cnt <= rd_gap_cnt + 1'b1;
		
	end 
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst || App_rd_en)begin
        rd_delay <= 4'd0;
    end
    else if(rd_delay < 4'd10)begin
    	rd_delay <= rd_delay + 1'b1;
    end
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
	end
	else begin
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		//
		if(state == S_ACK)
			begin
				if(read_addr_index_d1 == 2'd0)
					App_rd_addr_r <= read_addr_0;
				else if(read_addr_index_d1 == 2'd1)
					App_rd_addr_r <= read_addr_1;
				else if(read_addr_index_d1 == 2'd2)
					App_rd_addr_r <= read_addr_2;
				else if(read_addr_index_d1 == 2'd3)
					App_rd_addr_r <= read_addr_3;
			end
		else if(App_rd_en)
			App_rd_addr_r <= App_rd_addr_r + 1'b1;
		else
			App_rd_addr_r <= App_rd_addr_r;
		//
		if(App_rd_en_r && burst_cnt + App_rd_en < burst_limit)
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];
		
		//rd_burst_addr <= ZERO[ADDR_BITS - 1:0];
		//rd_burst_req <= 1'b0;
		App_rd_en_r <= 1'b0;
		
		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		//rd_burst_len <= ZERO[BURST_BITS - 1:0];
		read_req_ack <= 1'b0;
	end
	else
		case(state)
			//idle state,waiting for read, read_req_d2 == '1' goto the 'S_ACK'
			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end
			//'S_ACK' state completes the read request response, the FIFO reset, the address latch, and the data length latch
			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					//read request response
					read_req_ack <= 1'b1;
					//FIFO reset
					fifo_aclr <= 1'b1;
					//select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
					/*
					if(read_addr_index_d1 == 2'd0)
						App_rd_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						App_rd_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						App_rd_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						App_rd_addr <= read_addr_3;
					*/
					//latch data length
					read_len_latch <= read_len_d1;
				end
				//read data counter reset, read_cnt <= 0;
				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the FIFO space is a burst read request, goto burst read state
				//第十二讲彩点修正：除了 FIFO 空间和写忙判据，还要满足
				//  (1) 与上一次读突发之间已间隔 BURST_GAP_CYCLES 个空闲周期；
				//  (2) 控制器处于空闲窗口（非刷新、非忙），或 FIFO 已到低水位。
				else if((!raster_enabled || raster_span_ready) &&
                        wrusedw < (FIFO_DEPTH - BURST_SIZE) && ~App_wr_busy &&
				        rd_gap_ok && (ctrl_quiet || fifo_low))
				begin
					state <= S_READ_BURST;
					//rd_burst_len <= BURST_SIZE[BURST_BITS - 1:0];
					//rd_burst_req <= 1'b1;
					App_rd_en_r <= 1'b1;
				end
			end
			
			S_READ_BURST:
			begin
				//burst finish  
				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;
					//read counter + burst length
					read_cnt <= read_cnt + burst_limit;
					//the next burst read address is generated
					//rd_burst_addr <= rd_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_READ_BURST_END:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the read counter value is less than the frame length, continue read,
				//otherwise the read is complete
				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
