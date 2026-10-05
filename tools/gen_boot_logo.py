# -*- coding: utf-8 -*-
"""S2 开机 Logo：从 640x480 原图生成片上调色板 ROM 与几何参数。

输入：doc/资源/开机logo透明背景.png（优先，带 alpha 通道）
      doc/资源/VinylFPGA_640x480.jpg（回退，若上面的 PNG 不存在）
输出：src/boot/boot_logo_rom.v       片上调色板 ROM（自动生成）
      src/include/boot_logo_geom.vh  几何宏（供 boot_layer.v 参数默认值引用）
      doc/资源/s2_boot_logo_preview.png（可选，--verify 时输出还原预览）

做法（利用原图 92% 是纯黑底这一事实，把分辨率花在真正有内容的地方）：
  1. 求非黑内容包围盒并加 margin，得到裁剪盒 (x0,y0,w,h)；
  2. 裁剪盒按 SCALE 倍欠采样成 LOGO_W x LOGO_H 的索引图（SCALE=2）；
  3. 自适应调色板量化成 N 色，索引直接做成 ROM；
  4. 显示时按 SCALE 倍放大并贴到原屏幕位置，盒外保持纯黑，
     视觉上等价于“整帧 SCALE 倍缩小”，但省掉了 92% 的黑底存储。

用法：
    python tools/gen_boot_logo.py --verify
    python tools/gen_boot_logo.py --margin 8 --scale 2 --colors 16
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_CANDIDATES = (
    ROOT / "doc/资源/开机logo透明背景.png",
    ROOT / "doc/资源/VinylFPGA_640x480.jpg",
)
OUT_ROM = ROOT / "src/boot/boot_logo_rom.v"
OUT_GEOM = ROOT / "src/include/boot_logo_geom.vh"
OUT_PREVIEW = ROOT / "doc/资源/s2_boot_logo_preview.png"

SCREEN_W = 640
SCREEN_H = 480
BLACK_THRESHOLD = 24


def pick_source(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    for candidate in SRC_CANDIDATES:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("找不到开机图源：" + ", ".join(str(p) for p in SRC_CANDIDATES))


def load_source(path: Path) -> tuple[Image.Image, np.ndarray | None]:
    """返回 (合成到黑底上的 RGB 图, alpha 掩码或 None)。"""
    raw = Image.open(path)
    alpha = None
    if raw.mode in ("RGBA", "LA") or "transparency" in raw.info:
        rgba = raw.convert("RGBA")
        alpha = np.asarray(rgba)[:, :, 3].copy()
        canvas = Image.new("RGB", rgba.size, (0, 0, 0))
        canvas.paste(rgba, mask=rgba.split()[3])
        im = canvas
    else:
        im = raw.convert("RGB")
    if im.size != (SCREEN_W, SCREEN_H):
        im = im.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
        if alpha is not None:
            alpha = np.asarray(
                Image.fromarray(alpha).resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
            )
    return im, alpha


def content_box(im: Image.Image, alpha: np.ndarray | None, margin: int) -> tuple[int, int, int, int]:
    """内容包围盒 + margin，裁剪到画面内并对齐到偶数（便于 2 的幂次缩放）。

    有 alpha 时以 alpha 为准（透明背景 Logo 的边界最准），否则退回亮度阈值。
    """
    if alpha is not None:
        mask = alpha > BLACK_THRESHOLD
    else:
        mask = np.asarray(im, dtype=np.int16).mean(axis=2) > BLACK_THRESHOLD
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        raise ValueError("源图内容为空")
    x0 = max(0, (int(xs.min()) - margin) & ~1)
    y0 = max(0, (int(ys.min()) - margin) & ~1)
    x1 = min(SCREEN_W, int(xs.max()) + 1 + margin + 1) & ~1
    y1 = min(SCREEN_H, int(ys.max()) + 1 + margin + 1) & ~1
    return x0, y0, x1 - x0, y1 - y0


class Scheme:
    """一次生成的完整参数与数据。"""

    def __init__(
        self,
        im: Image.Image,
        alpha: np.ndarray | None,
        margin: int,
        scale: int,
        colors: int,
        source: Path,
    ) -> None:
        x0, y0, w, h = content_box(im, alpha, margin)
        assert scale & (scale - 1) == 0, "scale 必须是 2 的幂"
        assert w % scale == 0 and h % scale == 0
        self.im = im
        self.source = source
        self.x0, self.y0, self.w, self.h = x0, y0, w, h
        self.scale = scale
        self.colors = colors
        self.lw, self.lh = w // scale, h // scale
        crop = im.crop((x0, y0, x0 + w, y0 + h)).resize((self.lw, self.lh), Image.LANCZOS)
        self.pal_img = crop.quantize(colors=colors, method=Image.MEDIANCUT)
        self.idx = np.asarray(self.pal_img, dtype=np.uint8)
        self.pixel_bits = max(1, (colors - 1).bit_length())
        self.pixels = self.lw * self.lh
        self.addr_bits = max(1, (self.pixels - 1).bit_length())
        self.rom_words = self.pixels if self.pixel_bits > 4 else self.pixels // 2
        self.blocks = math.ceil(self.rom_words / 1024)

    def reconstruct(self) -> Image.Image:
        """按 RTL 的显示方式还原整屏（盒外纯黑），用于画质核对。"""
        up = self.pal_img.convert("RGB").resize(
            (self.w, self.h), Image.NEAREST
        )
        screen = Image.new("RGB", (SCREEN_W, SCREEN_H), (0, 0, 0))
        screen.paste(up, (self.x0, self.y0))
        return screen

    def psnr(self) -> float:
        a = np.asarray(self.reconstruct(), dtype=np.float64)
        b = np.asarray(self.im, dtype=np.float64)
        mse = float(np.mean((a - b) ** 2))
        return 99.0 if mse <= 1e-9 else 10.0 * math.log10(255.0 * 255.0 / mse)

    def describe(self) -> str:
        return (
            "crop x[{0},{1}] y[{2},{3}] {4}x{5} -> store {6}x{7} ({8} px), "
            "colors={9} ({10} bit), ROM ~{11} x BRAM9K".format(
                self.x0, self.x0 + self.w - 1, self.y0, self.y0 + self.h - 1,
                self.w, self.h, self.lw, self.lh, self.pixels,
                self.colors, self.pixel_bits, self.blocks)
        )


def ascii_map(img: Image.Image, cols: int = 96, rows: int = 48) -> str:
    lum = np.asarray(img.convert("L").resize((cols, rows), Image.BOX), dtype=np.float64)
    chars = " .:-=+*#%@"
    return "\n".join("".join(chars[min(9, int(v) // 26)] for v in row) for row in lum)


def emit_rom(s: Scheme) -> str:
    pal = (s.pal_img.getpalette() or [])[:]
    pal += [0] * (256 * 3 - len(pal))
    pb = s.pixel_bits
    lines = [
        "// =============================================================================",
        "// boot_logo_rom.v —— S2 开机 Logo 片上调色板 ROM（由 tools/gen_boot_logo.py 生成）",
        "//",
        "// 源图    ：{0} (640x480)".format(
            s.source.relative_to(ROOT).as_posix() if ROOT in s.source.parents else s.source.name),
        "// 裁剪盒  ：x[{0},{1}] y[{2},{3}]，{4}x{5}".format(
            s.x0, s.x0 + s.w - 1, s.y0, s.y0 + s.h - 1, s.w, s.h),
        "// 存储    ：{0}x{1}，屏幕按 {2}x 还原".format(s.lw, s.lh, s.scale),
        "// 调色板  ：{0} 色，索引 {1} bit".format(s.colors, pb),
        "// 规模    ：{0} 像素，约 {1} x BRAM9K".format(s.pixels, s.blocks),
        "//",
        "// 时钟域与主链路一致：只使用 video_clk；ROM 内容由 initial 初始化，",
        "// 供 TD 推断块 RAM。pix_index 以像素为单位（0 .. LOGO_W*LOGO_H-1），",
        "// 4bit 索引时内部按 2 像素/字打包以减半 BRAM 占用。",
        "// =============================================================================",
        "`ifndef BOOT_LOGO_ROM_V",
        "`define BOOT_LOGO_ROM_V",
        "",
        "module boot_logo_rom #(",
        "    parameter integer LOGO_W     = {0},".format(s.lw),
        "    parameter integer LOGO_H     = {0},".format(s.lh),
        "    parameter integer PIXEL_BITS = {0},".format(pb),
        "    parameter integer ADDR_BITS  = {0}".format(s.addr_bits),
        ")(",
        "    input  wire                 clk,",
        "    input  wire [ADDR_BITS-1:0] pix_index,",
        "    output reg  [23:0]          rgb",
        ");",
        "",
    ]
    if pb > 4:
        lines += [
            "    // 每字 1 像素",
            "    reg [PIXEL_BITS-1:0] idx_mem [0:LOGO_W*LOGO_H-1];",
            "    initial begin",
        ]
        for i in range(0, s.pixels, 16):
            chunk = s.idx.reshape(-1)[i : i + 16]
            lines.append("        " + " ".join(
                "idx_mem[{0}] = {1}'d{2};".format(i + j, pb, int(v))
                for j, v in enumerate(chunk)))
        lines += [
            "    end",
            "",
            "    reg [PIXEL_BITS-1:0] idx_q;",
            "    always @(posedge clk) begin",
            "        idx_q <= idx_mem[pix_index];",
            "    end",
            "",
        ]
    else:
        words = s.idx.reshape(-1)
        assert words.size % 2 == 0
        packed = (words[0::2].astype(np.uint16) & 0xF) | ((words[1::2].astype(np.uint16) & 0xF) << 4)
        lines += [
            "    // 每字 2 像素（低半字 = 偶数像素）",
            "    localparam integer WORDS = LOGO_W*LOGO_H/2;",
            "    reg [2*PIXEL_BITS-1:0] word_mem [0:WORDS-1];",
            "    initial begin",
        ]
        for i in range(0, packed.size, 16):
            chunk = packed[i : i + 16]
            lines.append("        " + " ".join(
                "word_mem[{0}] = {1}'h{2:02X};".format(i + j, 2 * pb, int(v))
                for j, v in enumerate(chunk)))
        lines += [
            "    end",
            "",
            "    reg [2*PIXEL_BITS-1:0] word_q;",
            "    reg                    sel_q;",
            "    always @(posedge clk) begin",
            "        word_q <= word_mem[pix_index[ADDR_BITS-1:1]];",
            "        sel_q  <= pix_index[0];",
            "    end",
            "",
            "    wire [PIXEL_BITS-1:0] idx_q = sel_q ? word_q[2*PIXEL_BITS-1:PIXEL_BITS]",
            "                                          : word_q[PIXEL_BITS-1:0];",
            "",
        ]
    lines += [
        "    // 调色板查表（纯组合，规模小）",
        "    always @(*) begin",
        "        case (idx_q)",
    ]
    for i in range(s.colors):
        r, g, b = pal[3 * i : 3 * i + 3]
        lines.append("            {0}'d{1:>3} : rgb = 24'h{2:02X}{3:02X}{4:02X};".format(
            pb, i, r, g, b))
    lines += [
        "            default : rgb = 24'h000000;",
        "        endcase",
        "    end",
        "",
        "endmodule",
        "`endif",
        "",
    ]
    return "\n".join(lines)


def emit_geom(s: Scheme) -> str:
    return "\n".join([
        "// =============================================================================",
        "// boot_logo_geom.vh —— S2 开机 Logo 几何参数（由 tools/gen_boot_logo.py 生成）",
        "//",
        "// 与 boot_logo_rom.v 必须成对更新；两者由同一条命令一起生成。",
        "// 这里只用宏（`define），可安全地被多个模块 include。",
        "// =============================================================================",
        "`ifndef BOOT_LOGO_GEOM_VH",
        "`define BOOT_LOGO_GEOM_VH",
        "",
        "// 屏幕上的裁剪盒原点（0 基，左上角为 (0,0)）",
        "`define BOOT_LOGO_X0   {0}".format(s.x0),
        "`define BOOT_LOGO_Y0   {0}".format(s.y0),
        "// ROM 存储尺寸与放大倍数",
        "`define BOOT_LOGO_LW   {0}".format(s.lw),
        "`define BOOT_LOGO_LH   {0}".format(s.lh),
        "`define BOOT_LOGO_SCALE {0}".format(s.scale),
        "`define BOOT_LOGO_SCALE_LOG2 {0}".format(s.scale.bit_length() - 1),
        "// ROM 端口宽度（与 boot_logo_rom.v 的参数默认值一致）",
        "`define BOOT_LOGO_PIXEL_BITS {0}".format(s.pixel_bits),
        "`define BOOT_LOGO_ADDR_BITS  {0}".format(s.addr_bits),
        "// 原图内容盒（仅用于文档/自检）",
        "`define BOOT_LOGO_CROP_W {0}".format(s.w),
        "`define BOOT_LOGO_CROP_H {0}".format(s.h),
        "",
        "`endif",
        "",
    ])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--margin", type=int, default=8, help="内容包围盒外扩像素")
    ap.add_argument("--scale", type=int, default=2, help="欠采样/还原倍数（2 的幂）")
    ap.add_argument("--colors", type=int, default=16, help="调色板颜色数（2 的幂，<=16 打包）")
    ap.add_argument("--source", type=Path, default=None, help="指定图源（默认自动挑选）")
    ap.add_argument("--verify", action="store_true", help="输出还原预览 PNG 并打印画质")
    args = ap.parse_args()

    src = pick_source(args.source)
    im, alpha = load_source(src)
    s = Scheme(im, alpha, args.margin, args.scale, args.colors, src)
    print("方案：" + s.describe())
    print("图源：{0}".format(src.relative_to(ROOT)))
    print("整屏还原 PSNR：{0:.2f} dB".format(s.psnr()))

    OUT_ROM.parent.mkdir(parents=True, exist_ok=True)
    OUT_ROM.write_text(emit_rom(s), encoding="utf-8")
    OUT_GEOM.write_text(emit_geom(s), encoding="utf-8")
    print("wrote {0}".format(OUT_ROM.relative_to(ROOT)))
    print("wrote {0}".format(OUT_GEOM.relative_to(ROOT)))

    if args.verify:
        rec = s.reconstruct()
        rec.save(OUT_PREVIEW)
        print("wrote {0}".format(OUT_PREVIEW.relative_to(ROOT)))
        print("")
        print("== 还原预览（96x48 灰度） ==")
        print(ascii_map(rec))


if __name__ == "__main__":
    main()
