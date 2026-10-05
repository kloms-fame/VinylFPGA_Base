#!/usr/bin/env python3
"""S5 歌词资源生成器：把 .lrc 变成 FPGA 可用的字库 ROM + 歌词行表 ROM。

    python tools/gen_lrc_assets.py --lrc doc/资源/lyrics/demo.lrc --verify

产物（都是可综合的 Verilog ROM，综合时进入 BRAM）：
  * src/display/lrc_font_rom.v  —— 16x16 点阵字库，addr = 字形号*16 + 行号
  * src/display/lrc_lines_rom.v —— 每行：起始毫秒 + 若干字形号
  * src/include/lrc_geom.vh     —— 行数/每行字数/字号/位置/颜色等几何宏
  * doc/资源/lyrics/demo_preview.png（--verify：还原预览，人工核对字形）

设计取舍（对应报告 S5"字库容量必须先做 BRAM 预算"）：
  * 只收录**该歌词文件真正用到的字符**（外加空格），而不是整张字库，
    60 个字形的 16x16 点阵约 2KB，落 2~3 个 BRAM9K。
  * 字形统一 16x16、行表定长，渲染只需"行表查一次 + 字库查一次"，路径短。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]

GLYPH_W = 16
GLYPH_H = 16
CHARS_PER_LINE = 16
OSD_X = 96
OSD_Y = 340        # 落在画面中下部，避开底部波形条（Y 376..471）
SCALE = 1
COLOR = (0xFF, 0xE8, 0x60)      # 暖金色，与开机 Logo 一致
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]


class LrcError(RuntimeError):
    pass


def parse_lrc(path: Path) -> list:
    """解析 [mm:ss.xx] 行，返回 [(time_ms, text)]，按时间排序。"""
    tag = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")
    lines = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        stamps = list(tag.finditer(raw))
        if not stamps:
            continue
        text = tag.sub("", raw).strip()
        if not text:
            continue
        for m in stamps:
            mm, ss = int(m.group(1)), float(m.group(2))
            lines.append((int(round((mm * 60 + ss) * 1000)), text))
    if not lines:
        raise LrcError(f"{path} 中没有解析到任何 [mm:ss.xx] 歌词行")
    lines.sort(key=lambda x: x[0])
    if len(lines) > 15:
        raise LrcError(f"歌词行数 {len(lines)} 超过行表上限 15（S5 先支持有限行表）")
    for _, text in lines:
        if len(text) > CHARS_PER_LINE:
            raise LrcError(f"单行 {len(text)} 字超过每行上限 {CHARS_PER_LINE}: {text!r}")
    return lines


def build_charset(lines: list) -> list:
    chars = sorted({ch for _, text in lines for ch in text})
    if " " not in chars:
        chars.append(" ")
    chars = sorted(chars)
    if len(chars) > 240:
        raise LrcError(f"字形数 {len(chars)} 过多，BRAM 预算不允许")
    return chars


def find_font() -> Path:
    for cand in FONT_CANDIDATES:
        if Path(cand).exists():
            return Path(cand)
    raise LrcError("找不到可用的中文字体（msyh/simhei/simsun）")


def render_glyph(ch, is_ascii: bool) -> list:
    """渲染成 16x16 位图（每行 16bit，MSB 在左）。

    关键点：不能直接把字形画在 (0,0) —— 中文字号 16 的包围盒常略大于 16x16，
    会被裁掉笔画。这里按包围盒自适应缩小并居中，保证整字完整落在格子里。
    """
    font_path = str(find_font())
    size = 12 if is_ascii else GLYPH_H
    img = Image.new("1", (GLYPH_W, GLYPH_H), 0)
    for _ in range(8):
        f = ImageFont.truetype(font_path, size)
        probe = ImageDraw.Draw(Image.new("1", (GLYPH_W, GLYPH_H), 0))
        bbox = probe.textbbox((0, 0), ch, font=f)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        if w <= GLYPH_W and h <= GLYPH_H:
            break
        size -= 1
    img = Image.new("1", (GLYPH_W, GLYPH_H), 0)
    draw = ImageDraw.Draw(img)
    draw.text(((GLYPH_W - w) // 2 - bbox[0], (GLYPH_H - h) // 2 - bbox[1]),
              ch, font=f, fill=1)
    rows = []
    for y in range(GLYPH_H):
        bits = 0
        for x in range(GLYPH_W):
            if img.getpixel((x, y)):
                bits |= 1 << (GLYPH_W - 1 - x)
        rows.append(bits)
    return rows


def emit_font_rom(chars: list, glyphs: list) -> str:
    total = len(chars) * GLYPH_H
    addr_w = max(1, (total - 1).bit_length())
    lines = [
        "// 由 tools/gen_lrc_assets.py 自动生成，请勿手改。",
        "`ifndef EXP_LRC_FONT_ROM_V",
        "`define EXP_LRC_FONT_ROM_V",
        "module lrc_font_rom (",
        f"    input  wire [{addr_w - 1}:0] addr,",
        "    output reg  [15:0] dout",
        ");",
        "    always @* begin",
        "        case (addr)",
    ]
    for gi, rows in enumerate(glyphs):
        for r, bits in enumerate(rows):
            lines.append(f"            {addr_w}'d{gi * GLYPH_H + r}: dout = 16'h{bits:04X};")
    lines += ["            default: dout = 16'h0000;", "        endcase", "    end", "endmodule", "`endif", ""]
    return "\n".join(lines)


def emit_lines_rom(lines_data: list) -> str:
    out = [
        "// 由 tools/gen_lrc_assets.py 自动生成，请勿手改。",
        "`ifndef EXP_LRC_LINES_ROM_V",
        "`define EXP_LRC_LINES_ROM_V",
        "module lrc_lines_rom (",
        "    input  wire [3:0]  line,",
        "    input  wire [3:0]  col,",
        "    output reg  [31:0] time_ms,",
        "    output reg  [7:0]  glyph",
        ");",
        "    always @* begin",
        "        time_ms = 32'd0;",
        "        glyph   = 8'd0;",
        "        case (line)",
    ]
    for idx, (t_ms, glyph_idx, used) in enumerate(lines_data):
        out.append(f"            4'd{idx}: begin")
        out.append(f"                time_ms = 32'd{t_ms};")
        out.append(f"                case (col)")
        for c, g in enumerate(glyph_idx):
            out.append(f"                    4'd{c}: glyph = 8'd{g};")
        out.append(f"                    default: glyph = 8'd{used};")   # 空格
        out.append("                endcase")
        out.append("            end")
    out += ["            default: begin time_ms = 32'hFFFFFFFF; glyph = 8'd0; end",
            "        endcase", "    end", "endmodule", "`endif", ""]
    return "\n".join(out)


def emit_geom(chars: list, lines_data: list) -> str:
    return "\n".join([
        "// 由 tools/gen_lrc_assets.py 自动生成，请勿手改。",
        f"localparam integer LRC_LINE_COUNT     = {len(lines_data)};",
        f"localparam integer LRC_CHARS_PER_LINE = {CHARS_PER_LINE};",
        f"localparam integer LRC_GLYPH_W        = {GLYPH_W};",
        f"localparam integer LRC_GLYPH_H        = {GLYPH_H};",
        f"localparam integer LRC_OSD_X          = {OSD_X};",
        f"localparam integer LRC_OSD_Y          = {OSD_Y};",
        f"localparam integer LRC_SCALE          = {SCALE};",
        f"localparam integer LRC_CHARSET_SIZE   = {len(chars)};",
        f"localparam integer LRC_FONT_ADDR_W    = {max(1, (len(chars) * GLYPH_H - 1).bit_length())};",
        f"localparam [23:0]  LRC_COLOR          = 24'h{COLOR[0]:02X}{COLOR[1]:02X}{COLOR[2]:02X};",
        f"localparam [7:0]   LRC_SPACE_GLYPH    = 8'd{chars.index(' ')};",
        "",
    ])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="VinylFPGA S5 歌词资源生成器")
    ap.add_argument("--lrc", required=True)
    ap.add_argument("--verify", action="store_true", help="额外输出还原预览 PNG")
    ap.add_argument("--out-dir", default=str(ROOT))
    args = ap.parse_args(argv)

    lrc_path = Path(args.lrc)
    out = Path(args.out_dir)
    try:
        lines = parse_lrc(lrc_path)
        chars = build_charset(lines)
        glyphs = [render_glyph(ch, ord(ch) < 128) for ch in chars]
        char_index = {ch: i for i, ch in enumerate(chars)}
        space = char_index[" "]

        table = []
        for t_ms, text in lines:
            idx = [char_index[ch] for ch in text]
            table.append((t_ms, idx, space))

        (out / "src/display/lrc_font_rom.v").write_text(emit_font_rom(chars, glyphs), encoding="utf-8")
        (out / "src/display/lrc_lines_rom.v").write_text(emit_lines_rom(table), encoding="utf-8")
        (out / "src/include/lrc_geom.vh").write_text(emit_geom(chars, table), encoding="utf-8")

        print(f"LRC_OK 行数 {len(table)}，字形 {len(chars)}，"
              f"字库 {len(chars) * GLYPH_H * 2} 字节")
        for i, (t_ms, idx, _) in enumerate(table):
            print(f"  [{i}] {t_ms:>6} ms  " + "".join(chars[g] for g in idx))

        if args.verify:
            img = Image.new("RGB", (len(chars) * GLYPH_W, GLYPH_H), (0, 0, 0))
            px = img.load()
            for gi, rows in enumerate(glyphs):
                for y, bits in enumerate(rows):
                    for x in range(GLYPH_W):
                        if bits & (1 << (GLYPH_W - 1 - x)):
                            px[gi * GLYPH_W + x, y] = COLOR
            png = lrc_path.with_name(lrc_path.stem + "_preview.png")
            img.save(png)
            print(f"LRC_OK 预览 {png}")
        return 0
    except LrcError as exc:
        print(f"LRC_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
