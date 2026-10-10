`timescale 1ns/1ps
`ifndef EXP_ASCII_FONT_ROM_V
`define EXP_ASCII_FONT_ROM_V
// Compact synchronous 8x8 ASCII font used by the EC2 panel and future time text.
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
        row_mem[584] = 8'h3c; row_mem[585] = 8'h18; row_mem[586] = 8'h18; row_mem[587] = 8'h18;
        row_mem[588] = 8'h18; row_mem[589] = 8'h18; row_mem[590] = 8'h3c; // I
        row_mem[592] = 8'h1e; row_mem[593] = 8'h0c; row_mem[594] = 8'h0c; row_mem[595] = 8'h0c;
        row_mem[596] = 8'h0c; row_mem[597] = 8'h6c; row_mem[598] = 8'h38; // J
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

        // Ratio separator: '/'
        row_mem[376] = 8'h06; row_mem[377] = 8'h0c; row_mem[378] = 8'h18; row_mem[379] = 8'h30;
        row_mem[380] = 8'h60; row_mem[381] = 8'h40;
    end

    always @(posedge clk)
        dout <= row_mem[addr];
endmodule
`endif
