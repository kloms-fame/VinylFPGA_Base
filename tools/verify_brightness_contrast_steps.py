#!/usr/bin/env python3
"""Exhaustively verify brightness_contrast_steps arithmetic and pixel alignment."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import sys


ROOT = Path(__file__).resolve().parents[1]
IVERILOG = shutil.which("iverilog") or r"D:\iverilog\bin\iverilog.exe"
VVP = shutil.which("vvp") or r"D:\iverilog\bin\vvp.exe"


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="vinyl_brightness_steps_") as temp_dir:
        image = Path(temp_dir) / "tb_brightness_contrast_steps.vvp"
        compile_cmd = [
            IVERILOG,
            "-g2005",
            "-s",
            "tb_brightness_contrast_steps",
            "-o",
            str(image),
            str(ROOT / "sim" / "tb_brightness_contrast_steps.v"),
            str(ROOT / "src" / "display" / "brightness_contrast_steps.v"),
        ]
        compiled = subprocess.run(compile_cmd, cwd=ROOT, text=True, capture_output=True)
        if compiled.stdout:
            print(compiled.stdout, end="")
        if compiled.stderr:
            print(compiled.stderr, end="", file=sys.stderr)
        if compiled.returncode != 0:
            return compiled.returncode

        simulated = subprocess.run([VVP, str(image)], cwd=ROOT, text=True, capture_output=True)
        if simulated.stdout:
            print(simulated.stdout, end="")
        if simulated.stderr:
            print(simulated.stderr, end="", file=sys.stderr)
        if simulated.returncode != 0:
            return simulated.returncode
        if "PASS: tb_brightness_contrast_steps checks=16385" not in simulated.stdout:
            print("ERROR: simulation did not emit the expected pass marker", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
