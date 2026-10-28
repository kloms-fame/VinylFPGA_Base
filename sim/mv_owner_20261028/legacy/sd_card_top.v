
module sd_card_top
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // SD card low speed mode frequency division parameter,spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0           // SD card high speed mode frequency division parameter,spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output           SD_nCS,                    //SD card chip select (SPI mode)
	output           SD_DCLK,                   //SD card clock
	output           SD_MOSI,                   //SD card controller data output
	input            SD_MISO,                   //SD card controller data input
	output           sd_init_done,              //SD card initialization is complete
	input            sd_sec_read,               //SD card sector read
	input[31:0]      sd_sec_read_addr,          //SD card sector read address
	output[7:0]      sd_sec_read_data,          //SD card sector read data
	output           sd_sec_read_data_valid,    //SD card sector read data valid
	output           sd_sec_read_end,           //SD card sector read end
	input            sd_sec_write,              //SD card sector write
	input[31:0]      sd_sec_write_addr,         //SD card sector write address
	input[7:0]       sd_sec_write_data,         //SD card sector write data
	output           sd_sec_write_data_req,     //SD card sector write data next clock is valid
	output           sd_sec_write_end,          //SD card sector write end

	// Bounded CMD18 owner for MV. Kept separate from the CMD17 audio/background
	// owner so the shared media loader and its 250 ms sector timeout are untouched.
	input            mv_burst_req,
	input[31:0]      mv_burst_lba,
	input[7:0]       mv_burst_len,
	input            mv_burst_pause,
	input            mv_burst_abort,
	output           mv_burst_valid,
	output[7:0]      mv_burst_data,
	output           mv_burst_sector_done,
	output           mv_burst_done,
	output[7:0]      mv_burst_error,
	output           mv_burst_active,
	output           mv_cmd17_idle
);
wire[15:0]           spi_clk_div;               //SPI module clock division parameter
wire                 cmd_req;                   //SD card command request
wire                 cmd_req_ack;               //SD card command request response
wire                 cmd_req_error;             //SD card command request error
wire[47:0]           cmd;                       //SD card command
wire[7:0]            cmd_r1;                    //SD card expect response
wire[15:0]           cmd_data_len;              //SD card command read data length
wire                 cmd_keep_cs;
wire                 cmd_wait_busy;
wire                 block_read_req;            //SD card sector data read request
wire                 block_read_valid;          //SD card sector data read data valid
wire[7:0]            block_read_data;           //SD card sector data read data
wire                 block_read_req_ack;        //SD card sector data read response
wire                 multi_read;
wire[7:0]            multi_sectors;
wire                 multi_pause;
wire                 multi_abort;
wire                 multi_sector_done;
wire                 multi_read_done;
wire                 block_write_req;
wire[7:0]            block_write_data;
wire                 block_write_data_rd;
wire                 block_write_req_ack;

wire                 nCS_ctrl;                  //SPI module chip select control
wire                 spi_wr_req;                //SPI module data sending request
wire                 spi_wr_ack;                //SPI module data request response
wire[7:0]            spi_data_in;               //SPI module send data
wire[7:0]            spi_data_out;              //SPI module data returned
wire[15:0]           clk_div;

// CMD17 owner (audio, cover, background, media probe)
wire                 cmd17_idle;
wire                 cmd17_req;
wire                 cmd17_ack;
wire                 cmd17_error;
wire[47:0]           cmd17_cmd;
wire[7:0]            cmd17_r1;
wire[15:0]           cmd17_len;
wire                 cmd17_block_req;
wire                 cmd17_block_ack;
wire                 cmd17_write_req;
wire                 cmd17_write_ack;

// CMD18 owner (MV)
wire                 mv_cmd_req;
wire                 mv_cmd_ack;
wire                 mv_cmd_error;
wire[47:0]           mv_cmd;
wire[7:0]            mv_cmd_r1;
wire[15:0]           mv_cmd_len;
wire                 mv_keep_cs;
wire                 mv_wait_busy;
wire                 mv_block_req;
wire                 mv_multi_read;
wire[7:0]            mv_multi_sectors;
wire                 mv_multi_pause;
wire                 mv_multi_abort;
wire                 mv_multi_sector_done;
wire                 mv_multi_read_done;

wire                 sel_mv = mv_burst_active;
wire                 sd_sec_read_eff = sd_sec_read && !mv_burst_req && !mv_burst_active;

// Handover visibility: the top level only drives mv_burst_req while the
// CMD17 owner is idle, so audio keeps reading until the card is actually free.
assign mv_cmd17_idle = cmd17_idle;

// The CMD17 owner must stop at its current sector as soon as MV asks for the
// card. It never starts a new CMD17 while a bounded CMD18 burst is pending.
sd_card_sec_read_write
#(
	.SPI_LOW_SPEED_DIV(SPI_LOW_SPEED_DIV),
	.SPI_HIGH_SPEED_DIV(SPI_HIGH_SPEED_DIV)
)
sd_card_sec_read_write_m0(
	.clk                            (clk                    ),
	.rst                            (rst                    ),
	.sd_init_done                   (sd_init_done           ),
	.sd_sec_read                    (sd_sec_read_eff        ),
	.sd_sec_read_addr               (sd_sec_read_addr       ),
	.sd_sec_read_data               (sd_sec_read_data       ),
	.sd_sec_read_data_valid         (sd_sec_read_data_valid ),
	.sd_sec_read_end                (sd_sec_read_end        ),
	.sd_sec_write                   (sd_sec_write           ),
	.sd_sec_write_addr              (sd_sec_write_addr      ),
	.sd_sec_write_data              (sd_sec_write_data      ),
	.sd_sec_write_data_req          (sd_sec_write_data_req  ),
	.sd_sec_write_end               (sd_sec_write_end       ),
	.idle                           (cmd17_idle             ),
	.spi_clk_div                    (spi_clk_div            ),
	.cmd_req                        (cmd17_req              ),
	.cmd_req_ack                    (cmd17_ack              ),
	.cmd_req_error                  (cmd17_error            ),
	.cmd                            (cmd17_cmd              ),
	.cmd_r1                         (cmd17_r1               ),
	.cmd_data_len                   (cmd17_len              ),
	.block_read_req                 (cmd17_block_req        ),
	.block_read_valid               (block_read_valid       ),
	.block_read_data                (block_read_data        ),
	.block_read_req_ack             (cmd17_block_ack        ),
	.block_write_req                (cmd17_write_req        ),
	.block_write_data               (block_write_data       ),
	.block_write_data_rd            (block_write_data_rd    ),
	.block_write_req_ack            (cmd17_write_ack        )
);

sd_cmd18_reader u_mv_cmd18_reader(
	.clk                            (clk                    ),
	.rst                            (rst                    ),
	.start                          (mv_burst_req && cmd17_idle),
	.lba                            (mv_burst_lba           ),
	.sectors                        (mv_burst_len           ),
	.pause                          (mv_burst_pause         ),
	.abort                          (mv_burst_abort         ),
	.cmd_req                        (mv_cmd_req             ),
	.cmd                            (mv_cmd                 ),
	.cmd_r1                         (mv_cmd_r1              ),
	.cmd_data_len                   (mv_cmd_len             ),
	.cmd_keep_cs                    (mv_keep_cs             ),
	.cmd_wait_busy                  (mv_wait_busy           ),
	.cmd_req_ack                    (mv_cmd_ack             ),
	.cmd_req_error                  (mv_cmd_error           ),
	.block_read_req                 (mv_block_req           ),
	.multi_read                     (mv_multi_read          ),
	.multi_sectors                  (mv_multi_sectors       ),
	.multi_pause                    (mv_multi_pause         ),
	.multi_abort                    (mv_multi_abort         ),
	.block_read_valid               (block_read_valid       ),
	.block_read_data                (block_read_data        ),
	.multi_sector_done              (mv_multi_sector_done   ),
	.multi_read_done                (mv_multi_read_done     ),
	.valid                          (mv_burst_valid         ),
	.data                           (mv_burst_data          ),
	.sector_done                    (mv_burst_sector_done   ),
	.active                         (mv_burst_active        ),
	.done                           (mv_burst_done          ),
	.error                          (mv_burst_error         )
);

// One command/read engine, two mutually exclusive owners.
assign cmd_req       = sel_mv ? mv_cmd_req : cmd17_req;
assign cmd           = sel_mv ? mv_cmd : cmd17_cmd;
assign cmd_r1        = sel_mv ? mv_cmd_r1 : cmd17_r1;
assign cmd_data_len  = sel_mv ? mv_cmd_len : cmd17_len;
assign cmd_keep_cs   = sel_mv ? mv_keep_cs : 1'b0;
assign cmd_wait_busy = sel_mv ? mv_wait_busy : 1'b0;
assign block_read_req= sel_mv ? mv_block_req : cmd17_block_req;
assign multi_read    = sel_mv ? mv_multi_read : 1'b0;
assign multi_sectors = sel_mv ? mv_multi_sectors : 8'd0;
assign multi_pause   = sel_mv ? mv_multi_pause : 1'b0;
assign multi_abort   = sel_mv ? mv_multi_abort : 1'b0;
assign block_write_req = cmd17_write_req;

assign cmd17_ack       = cmd_req_ack && !sel_mv;
assign mv_cmd_ack      = cmd_req_ack && sel_mv;
assign cmd17_error     = cmd_req_error && !sel_mv;
assign mv_cmd_error    = cmd_req_error && sel_mv;
assign cmd17_block_ack = block_read_req_ack && !sel_mv;
assign mv_multi_sector_done = multi_sector_done && sel_mv;
assign mv_multi_read_done   = multi_read_done && sel_mv;
assign cmd17_write_ack = block_write_req_ack;

sd_card_cmd sd_card_cmd_m0(
	.sys_clk                        (clk                    ),
	.rst                            (rst                    ),
	.spi_clk_div                    (spi_clk_div            ),
	.cmd_req                        (cmd_req                ),
	.cmd_req_ack                    (cmd_req_ack            ),
	.cmd_req_error                  (cmd_req_error          ),
	.cmd                            (cmd                    ),
	.cmd_r1                         (cmd_r1                 ),
	.cmd_data_len                   (cmd_data_len           ),
	.cmd_keep_cs                    (cmd_keep_cs            ),
	.cmd_wait_busy                  (cmd_wait_busy          ),
	.multi_read                     (multi_read             ),
	.multi_sectors                  (multi_sectors          ),
	.multi_pause                    (multi_pause            ),
	.multi_abort                    (multi_abort            ),
	.multi_sector_done              (multi_sector_done      ),
	.multi_read_done                (multi_read_done        ),
	.block_read_req                 (block_read_req         ),
	.block_read_req_ack             (block_read_req_ack     ),
	.block_read_data                (block_read_data        ),
	.block_read_valid               (block_read_valid       ),
	.block_write_req                (block_write_req        ),
	.block_write_data               (block_write_data       ),
	.block_write_data_rd            (block_write_data_rd    ),
	.block_write_req_ack            (block_write_req_ack    ),
	.nCS_ctrl                       (nCS_ctrl               ),
	.clk_div                        (clk_div                ),
	.spi_wr_req                     (spi_wr_req             ),
	.spi_wr_ack                     (spi_wr_ack             ),
	.spi_data_in                    (spi_data_in            ),
	.spi_data_out                   (spi_data_out           )
);

spi_master spi_master_m0(
	.sys_clk                        (clk                    ),
	.rst                            (rst                    ),
	.nCS                            (SD_nCS                 ),
	.DCLK                           (SD_DCLK                ),
	.MOSI                           (SD_MOSI                ),
	.MISO                           (SD_MISO                ),
	.clk_div                        (clk_div                ),
	.CPOL                           (1'b1                   ),
	.CPHA                           (1'b1                   ),
	.nCS_ctrl                       (nCS_ctrl               ),
	.wr_req                         (spi_wr_req             ),
	.wr_ack                         (spi_wr_ack             ),
	.data_in                        (spi_data_in            ),
	.data_out                       (spi_data_out           )
);
endmodule
