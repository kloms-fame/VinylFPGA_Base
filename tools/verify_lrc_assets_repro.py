"""Check two clean generations against checked-in lyric assets and frozen glyphs."""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ("src/display/lrc_font_rom.v", "src/display/lrc_lines_rom.v", "src/include/lrc_geom.vh")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="vinyl_lrc_repro_") as tmp:
        snapshots = []
        for run in range(2):
            out = Path(tmp) / str(run)
            (out / "src/display").mkdir(parents=True)
            (out / "src/include").mkdir(parents=True)
            subprocess.run(
                [sys.executable, str(ROOT / "tools/gen_lrc_assets.py"),
                 "--lrc", str(ROOT / "doc/资源/lyrics/demo.lrc"), "--out-dir", str(out)],
                check=True, capture_output=True,
            )
            snapshots.append({name: (out / name).read_bytes() for name in ASSETS})
        assert snapshots[0] == snapshots[1], "clean generations differ"
        for name in ASSETS:
            assert snapshots[0][name] == (ROOT / name).read_bytes(), f"stale generated asset: {name}"
            print(f"PASS reproducible {name} sha256={hashlib.sha256(snapshots[0][name]).hexdigest()}")

    original = (ROOT / "sim/legacy/lrc_font_rom_o0.v").read_text(encoding="utf-8")
    generated = (ROOT / "src/display/lrc_font_rom.v").read_text(encoding="utf-8")
    golden = {int(a): int(v, 16) for a, v in re.findall(r"10'd(\d+): dout = 16'h([0-9A-F]+)", original)}
    rows = {int(a): int(v, 16) for a, v in re.findall(r"row_mem\[(\d+)\] = 16'h([0-9A-F]+)", generated)}
    assert len(golden) == 960 and len(rows) == 1024
    assert all(rows[a] == golden.get(a, 0) for a in range(1024)), "glyph/padding mismatch"
    print("PASS all 15360 original glyph bits preserved; 64 padding rows are zero")


if __name__ == "__main__":
    main()
