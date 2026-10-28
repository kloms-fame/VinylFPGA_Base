`ifdef __ICARUS__
`timescale 1ns/1ps
`ifndef EXP_ASCII_FONT_ROM_V
`define EXP_ASCII_FONT_ROM_V
// Compact synchronous 8x8 ASCII font shared by the EC2 panel and playback UI.
module ascii_font_rom (
    input  wire       clk,
    input  wire [9:0] addr, // {ASCII[6:0], row[2:0]}
    output reg  [7:0] dout = 8'h00
);
    reg [7:0] row_mem [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            row_mem[i] = 8'h00;

        // Reserved control glyphs 4..15: four 8x8 tiles per 16x16 icon.
        // Each mode uses {bank[1:0], tile_y, tile_x} on the existing ROM port.
        // EOF pause: codes 4..7.
        row_mem[32] = 8'h00; row_mem[33] = 8'h00;
        row_mem[34] = 8'h00; row_mem[35] = 8'h0c;
        row_mem[36] = 8'h0c; row_mem[37] = 8'h0c;
        row_mem[38] = 8'h0c; row_mem[39] = 8'h0c;
        row_mem[40] = 8'h00; row_mem[41] = 8'h00;
        row_mem[42] = 8'h00; row_mem[43] = 8'h30;
        row_mem[44] = 8'h30; row_mem[45] = 8'h30;
        row_mem[46] = 8'h30; row_mem[47] = 8'h30;
        row_mem[48] = 8'h0c; row_mem[49] = 8'h0c;
        row_mem[50] = 8'h0c; row_mem[51] = 8'h0c;
        row_mem[52] = 8'h0c; row_mem[53] = 8'h00;
        row_mem[54] = 8'h00; row_mem[55] = 8'h00;
        row_mem[56] = 8'h30; row_mem[57] = 8'h30;
        row_mem[58] = 8'h30; row_mem[59] = 8'h30;
        row_mem[60] = 8'h30; row_mem[61] = 8'h00;
        row_mem[62] = 8'h00; row_mem[63] = 8'h00;
        // repeat-one: codes 8..11.
        row_mem[64] = 8'h00; row_mem[65] = 8'h00;
        row_mem[66] = 8'h1f; row_mem[67] = 8'h3f;
        row_mem[68] = 8'h30; row_mem[69] = 8'h31;
        row_mem[70] = 8'h33; row_mem[71] = 8'h31;
        row_mem[72] = 8'h00; row_mem[73] = 8'h30;
        row_mem[74] = 8'hf8; row_mem[75] = 8'hfc;
        row_mem[76] = 8'h38; row_mem[77] = 8'hb0;
        row_mem[78] = 8'h80; row_mem[79] = 8'h8c;
        row_mem[80] = 8'h31; row_mem[81] = 8'h01;
        row_mem[82] = 8'h0f; row_mem[83] = 8'h1c;
        row_mem[84] = 8'h3f; row_mem[85] = 8'h1f;
        row_mem[86] = 8'h0c; row_mem[87] = 8'h00;
        row_mem[88] = 8'h8c; row_mem[89] = 8'h8c;
        row_mem[90] = 8'hcc; row_mem[91] = 8'h0c;
        row_mem[92] = 8'hfc; row_mem[93] = 8'hf8;
        row_mem[94] = 8'h00; row_mem[95] = 8'h00;
        // repeat-list: codes 12..15.
        row_mem[96] = 8'h00; row_mem[97] = 8'h00;
        row_mem[98] = 8'h1f; row_mem[99] = 8'h3f;
        row_mem[100] = 8'h30; row_mem[101] = 8'h30;
        row_mem[102] = 8'h30; row_mem[103] = 8'h30;
        row_mem[104] = 8'h00; row_mem[105] = 8'h30;
        row_mem[106] = 8'hf8; row_mem[107] = 8'hfc;
        row_mem[108] = 8'h38; row_mem[109] = 8'h30;
        row_mem[110] = 8'h00; row_mem[111] = 8'h0c;
        row_mem[112] = 8'h30; row_mem[113] = 8'h00;
        row_mem[114] = 8'h0c; row_mem[115] = 8'h1c;
        row_mem[116] = 8'h3f; row_mem[117] = 8'h1f;
        row_mem[118] = 8'h0c; row_mem[119] = 8'h00;
        row_mem[120] = 8'h0c; row_mem[121] = 8'h0c;
        row_mem[122] = 8'h0c; row_mem[123] = 8'h0c;
        row_mem[124] = 8'hfc; row_mem[125] = 8'hf8;
        row_mem[126] = 8'h00; row_mem[127] = 8'h00;

        // Digits
        row_mem[384] = 8'h3c; row_mem[385] = 8'h66; row_mem[386] = 8'h6e; row_mem[387] = 8'h76;
        row_mem[388] = 8'h66; row_mem[389] = 8'h66; row_mem[390] = 8'h3c;
        row_mem[392] = 8'h18; row_mem[393] = 8'h38; row_mem[394] = 8'h18; row_mem[395] = 8'h18;
        row_mem[396] = 8'h18; row_mem[397] = 8'h18; row_mem[398] = 8'h7e;
        row_mem[400] = 8'h3c; row_mem[401] = 8'h66; row_mem[402] = 8'h06; row_mem[403] = 8'h0c;
        row_mem[404] = 8'h30; row_mem[405] = 8'h60; row_mem[406] = 8'h7e;
        row_mem[408] = 8'h3c; row_mem[409] = 8'h66; row_mem[410] = 8'h06; row_mem[411] = 8'h1c;
        row_mem[412] = 8'h06; row_mem[413] = 8'h66; row_mem[414] = 8'h3c;
        row_mem[416] = 8'h0c; row_mem[417] = 8'h1c; row_mem[418] = 8'h3c; row_mem[419] = 8'h6c;
        row_mem[420] = 8'h7e; row_mem[421] = 8'h0c; row_mem[422] = 8'h0c;
        row_mem[424] = 8'h7e; row_mem[425] = 8'h60; row_mem[426] = 8'h7c; row_mem[427] = 8'h06;
        row_mem[428] = 8'h06; row_mem[429] = 8'h66; row_mem[430] = 8'h3c;
        row_mem[432] = 8'h1c; row_mem[433] = 8'h30; row_mem[434] = 8'h60; row_mem[435] = 8'h7c;
        row_mem[436] = 8'h66; row_mem[437] = 8'h66; row_mem[438] = 8'h3c;
        row_mem[440] = 8'h7e; row_mem[441] = 8'h66; row_mem[442] = 8'h06; row_mem[443] = 8'h0c;
        row_mem[444] = 8'h18; row_mem[445] = 8'h18; row_mem[446] = 8'h18;
        row_mem[448] = 8'h3c; row_mem[449] = 8'h66; row_mem[450] = 8'h66; row_mem[451] = 8'h3c;
        row_mem[452] = 8'h66; row_mem[453] = 8'h66; row_mem[454] = 8'h3c;
        row_mem[456] = 8'h3c; row_mem[457] = 8'h66; row_mem[458] = 8'h66; row_mem[459] = 8'h3e;
        row_mem[460] = 8'h06; row_mem[461] = 8'h0c; row_mem[462] = 8'h38;

        // Time punctuation: '-' and ':'
        row_mem[360] = 8'h00; row_mem[361] = 8'h00; row_mem[362] = 8'h00; row_mem[363] = 8'h7e;
        row_mem[364] = 8'h7e; row_mem[365] = 8'h00; row_mem[366] = 8'h00; row_mem[367] = 8'h00;
        row_mem[464] = 8'h00; row_mem[465] = 8'h18; row_mem[466] = 8'h18; row_mem[467] = 8'h00;
        row_mem[468] = 8'h00; row_mem[469] = 8'h18; row_mem[470] = 8'h18; row_mem[471] = 8'h00;

        // Uppercase letters required for VOL/BRI/CON and SEL/ADJ.
        row_mem[520] = 8'h18; row_mem[521] = 8'h3c; row_mem[522] = 8'h66; row_mem[523] = 8'h66;
        row_mem[524] = 8'h7e; row_mem[525] = 8'h66; row_mem[526] = 8'h66; // A
        row_mem[528] = 8'h7c; row_mem[529] = 8'h66; row_mem[530] = 8'h66; row_mem[531] = 8'h7c;
        row_mem[532] = 8'h66; row_mem[533] = 8'h66; row_mem[534] = 8'h7c; // B
        row_mem[536] = 8'h3c; row_mem[537] = 8'h66; row_mem[538] = 8'h60; row_mem[539] = 8'h60;
        row_mem[540] = 8'h60; row_mem[541] = 8'h66; row_mem[542] = 8'h3c; // C
        row_mem[544] = 8'h78; row_mem[545] = 8'h6c; row_mem[546] = 8'h66; row_mem[547] = 8'h66;
        row_mem[548] = 8'h66; row_mem[549] = 8'h6c; row_mem[550] = 8'h78; // D
        row_mem[552] = 8'h7e; row_mem[553] = 8'h60; row_mem[554] = 8'h60; row_mem[555] = 8'h7c;
        row_mem[556] = 8'h60; row_mem[557] = 8'h60; row_mem[558] = 8'h7e; // E
        row_mem[560] = 8'h7e; row_mem[561] = 8'h60; row_mem[562] = 8'h60; row_mem[563] = 8'h7c;
        row_mem[564] = 8'h60; row_mem[565] = 8'h60; row_mem[566] = 8'h60; // F
        row_mem[584] = 8'h3c; row_mem[585] = 8'h18; row_mem[586] = 8'h18; row_mem[587] = 8'h18;
        row_mem[588] = 8'h18; row_mem[589] = 8'h18; row_mem[590] = 8'h3c; // I
        row_mem[592] = 8'h1e; row_mem[593] = 8'h0c; row_mem[594] = 8'h0c; row_mem[595] = 8'h0c;
        row_mem[596] = 8'h0c; row_mem[597] = 8'h6c; row_mem[598] = 8'h38; // J
        row_mem[600] = 8'h66; row_mem[601] = 8'h6c; row_mem[602] = 8'h78; row_mem[603] = 8'h70;
        row_mem[604] = 8'h78; row_mem[605] = 8'h6c; row_mem[606] = 8'h66; // K
        row_mem[608] = 8'h60; row_mem[609] = 8'h60; row_mem[610] = 8'h60; row_mem[611] = 8'h60;
        row_mem[612] = 8'h60; row_mem[613] = 8'h60; row_mem[614] = 8'h7e; // L
        row_mem[624] = 8'h66; row_mem[625] = 8'h76; row_mem[626] = 8'h7e; row_mem[627] = 8'h7e;
        row_mem[628] = 8'h6e; row_mem[629] = 8'h66; row_mem[630] = 8'h66; // N
        row_mem[632] = 8'h3c; row_mem[633] = 8'h66; row_mem[634] = 8'h66; row_mem[635] = 8'h66;
        row_mem[636] = 8'h66; row_mem[637] = 8'h66; row_mem[638] = 8'h3c; // O
        row_mem[656] = 8'h7c; row_mem[657] = 8'h66; row_mem[658] = 8'h66; row_mem[659] = 8'h7c;
        row_mem[660] = 8'h6c; row_mem[661] = 8'h66; row_mem[662] = 8'h66; // R
        row_mem[664] = 8'h3e; row_mem[665] = 8'h60; row_mem[666] = 8'h60; row_mem[667] = 8'h3c;
        row_mem[668] = 8'h06; row_mem[669] = 8'h06; row_mem[670] = 8'h7c; // S
        row_mem[688] = 8'h66; row_mem[689] = 8'h66; row_mem[690] = 8'h66; row_mem[691] = 8'h66;
        row_mem[692] = 8'h66; row_mem[693] = 8'h3c; row_mem[694] = 8'h18; // V
        row_mem[704] = 8'h66; row_mem[705] = 8'h66; row_mem[706] = 8'h3c; row_mem[707] = 8'h18;
        row_mem[708] = 8'h3c; row_mem[709] = 8'h66; row_mem[710] = 8'h66; // X
        row_mem[672] = 8'h7e; row_mem[673] = 8'h18; row_mem[674] = 8'h18; row_mem[675] = 8'h18;
        row_mem[676] = 8'h18; row_mem[677] = 8'h18; row_mem[678] = 8'h18; // T
        row_mem[696] = 8'h66; row_mem[697] = 8'h66; row_mem[698] = 8'h66; row_mem[699] = 8'h66;
        row_mem[700] = 8'h7e; row_mem[701] = 8'h7e; row_mem[702] = 8'h66; // W

        // Percentage sign for WSL values.
        row_mem[297] = 8'h62; row_mem[298] = 8'h64; row_mem[299] = 8'h08;
        row_mem[300] = 8'h10; row_mem[301] = 8'h26; row_mem[302] = 8'h46;

        // Ratio separator: '/'
        row_mem[376] = 8'h06; row_mem[377] = 8'h0c; row_mem[378] = 8'h18; row_mem[379] = 8'h30;
        row_mem[380] = 8'h60; row_mem[381] = 8'h40;
    end

    always @(posedge clk)
        dout <= row_mem[addr];
endmodule
`endif

`else
`timescale 1ns/1ps
`ifndef EXP_ASCII_FONT_ROM_V
`define EXP_ASCII_FONT_ROM_V
module ascii_font_rom(input wire clk,input wire [9:0] addr,output wire [7:0] dout);
wire [15:0] q;
EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
.INIT_02(256'h00300030003000300030000000000000000c000c000c000c000c000000000000),
.INIT_03(256'h00000000000000300030003000300030000000000000000c000c000c000c000c),
.INIT_04(256'h008c008000b0003800fc00f8003000000031003300310030003f001f00000000),
.INIT_05(256'h0000000000f800fc000c00cc008c008c0000000c001f003f001c000f00010031),
.INIT_06(256'h000c00000030003800fc00f8003000000030003000300030003f001f00000000),
.INIT_07(256'h0000000000f800fc000c000c000c000c0000000c001f003f001c000c00000030),
.INIT_12(256'h0000004600260010000800640062000000000000000000000000000000000000),
.INIT_16(256'h000000000000007e007e00000000000000000000000000000000000000000000),
.INIT_17(256'h000000000040006000300018000c000600000000000000000000000000000000),
.INIT_18(256'h0000007e0018001800180018003800180000003c006600660076006e0066003c),
.INIT_19(256'h0000003c00660006001c00060066003c0000007e00600030000c00060066003c),
.INIT_1A(256'h0000003c006600060006007c0060007e0000000c000c007e006c003c001c000c),
.INIT_1B(256'h0000001800180018000c00060066007e0000003c00660066007c00600030001c),
.INIT_1C(256'h00000038000c0006003e00660066003c0000003c00660066003c00660066003c),
.INIT_1D(256'h0000000000000000000000000000000000000018001800000000001800180000),
.INIT_20(256'h000000660066007e00660066003c001800000000000000000000000000000000),
.INIT_21(256'h0000003c00660060006000600066003c0000007c00660066007c00660066007c),
.INIT_22(256'h0000007e00600060007c00600060007e00000078006c006600660066006c0078),
.INIT_23(256'h000000000000000000000000000000000000006000600060007c00600060007e),
.INIT_24(256'h0000003c00180018001800180018003c00000000000000000000000000000000),
.INIT_25(256'h00000066006c007800700078006c006600000038006c000c000c000c000c001e),
.INIT_26(256'h000000000000000000000000000000000000007e006000600060006000600060),
.INIT_27(256'h0000003c00660066006600660066003c000000660066006e007e007e00760066),
.INIT_29(256'h0000007c00060006003c00600060003e000000660066006c007c00660066007c),
.INIT_2A(256'h000000000000000000000000000000000000001800180018001800180018007e),
.INIT_2B(256'h00000066007e007e006600660066006600000018003c00660066006600660066),
.INIT_2C(256'h00000000000000000000000000000000000000660066003c0018003c00660066)) ram(.clka(clk),.csa(1'b1),.wea(1'b0),.addra({1'b0,addr}),.dia(16'd0),.doa(q),.bytea(1'b0),.bytewea(1'b0),.rsta(1'b0),.ocea(1'b1),.clkb(clk),.csb(1'b0),.web(1'b0),.addrb(11'd0),.dib(16'd0),.dob(),.byteb(1'b0),.byteweb(1'b0),.rstb(1'b0),.oceb(1'b1));
reg read_started = 1'b0;
always @(posedge clk) read_started <= 1'b1;
assign dout = read_started ? q[7:0] : 8'd0;
endmodule

`endif
`endif
