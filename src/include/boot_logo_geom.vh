// =============================================================================
// boot_logo_geom.vh —— S2 开机 Logo 几何参数（由 tools/gen_boot_logo.py 生成）
//
// 与 boot_logo_rom.v 必须成对更新；两者由同一条命令一起生成。
// 这里只用宏（`define），可安全地被多个模块 include。
// =============================================================================
`ifndef BOOT_LOGO_GEOM_VH
`define BOOT_LOGO_GEOM_VH

// 屏幕上的裁剪盒原点（0 基，左上角为 (0,0)）
`define BOOT_LOGO_X0   186
`define BOOT_LOGO_Y0   88
// ROM 存储尺寸与放大倍数
`define BOOT_LOGO_LW   134
`define BOOT_LOGO_LH   149
`define BOOT_LOGO_SCALE 2
`define BOOT_LOGO_SCALE_LOG2 1
// ROM 端口宽度（与 boot_logo_rom.v 的参数默认值一致）
`define BOOT_LOGO_PIXEL_BITS 4
`define BOOT_LOGO_ADDR_BITS  15
// 原图内容盒（仅用于文档/自检）
`define BOOT_LOGO_CROP_W 268
`define BOOT_LOGO_CROP_H 298

`endif
