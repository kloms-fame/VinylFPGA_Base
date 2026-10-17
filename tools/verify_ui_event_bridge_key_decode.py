#!/usr/bin/env python3
"""Compile and run the exhaustive UI event bridge key-index regression."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if not iverilog or not vvp:
        raise SystemExit("iverilog and vvp must be available on PATH")

    tests = (
        (
            "tb_ui_event_bridge_key_decode",
            [ROOT / "sim" / "tb_ui_event_bridge_key_decode.v"],
            "TEST_PASS ui_event_bridge key decode checks=",
        ),
        (
            "tb_ui_event_bridge_browse_integration",
            [
                ROOT / "src" / "io" / "browse_fsm.v",
                ROOT / "sim" / "tb_ui_event_bridge_browse_integration.v",
            ],
            "TEST_PASS ui_event_bridge to browse_fsm integration",
        ),
    )
    with tempfile.TemporaryDirectory(prefix="ui-key-decode-") as temporary:
        for top, sources, marker in tests:
            image = Path(temporary) / f"{top}.vvp"
            compile_result = subprocess.run(
                [
                    iverilog,
                    "-g2012",
                    "-I",
                    str(ROOT / "src" / "include"),
                    "-s",
                    top,
                    "-o",
                    str(image),
                    str(ROOT / "src" / "io" / "ui_event_bridge.v"),
                    *map(str, sources),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
            if compile_result.stdout:
                print(compile_result.stdout, end="")
            if compile_result.stderr:
                print(compile_result.stderr, end="")
            if compile_result.returncode:
                return compile_result.returncode

            run_result = subprocess.run(
                [vvp, str(image)], cwd=ROOT, text=True, capture_output=True
            )
            if run_result.stdout:
                print(run_result.stdout, end="")
            if run_result.stderr:
                print(run_result.stderr, end="")
            if run_result.returncode:
                return run_result.returncode
            if marker not in run_result.stdout:
                raise SystemExit(f"{top} exited without its PASS marker")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
