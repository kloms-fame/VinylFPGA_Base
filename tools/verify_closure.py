"""One batched closure regression, including a cycle-exact loader comparison."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

import verify_s7_acceptance as legacy

ROOT = Path(__file__).resolve().parents[1]
STAGE_MARKERS = (
    "PASS playback_background:", "PASS stage3a page: 3850", "PASS stage3a page: 4985",
    "PASS background_frame_select:", "TEST_PASS background_cache_loader",
    "TEST_PASS background_cache_full_frame", "TEST_PASS background_sector_mux",
    "TEST_PASS background_index", "TEST_PASS song_index_db_s4",
    "PASS stage3b raster read:", "PASS stage3b shared writer:",
    "PASS: tb_frame_fifo_read_pace all checks passed", "PASS: frame_fifo_write registered-level burst",
    "STAGE3B_VERIFICATION_PASS",
)


def stage_passed(text, exit_code):
    # Old Verilog benches sometimes use $finish after printing FAIL and still
    # exit zero. Demand all expected evidence, not only the shell exit code.
    return (exit_code == 0 and not re.search(r"\b(?:FAIL|FATAL)\b", text)
            and all(marker in text for marker in STAGE_MARKERS)
            and re.search(r"(?m)^OK\s*$", text) is not None)


def loader_equivalence(output, baseline):
    loader = (baseline / "src/SD/fat32_media_loader.v").read_text(encoding="utf-8")
    old_loader = re.sub(r"\bfat32_media_loader\b", "fat32_media_loader_before", loader)
    old_loader = re.sub(r"\bfat32_file_streamer\b", "fat32_file_streamer_before", old_loader)
    old_loader = re.sub(r"\bsong_index_db\b", "song_index_db_before", old_loader)
    old_streamer = (baseline / "src/SD/fat32_file_streamer.v").read_text(encoding="utf-8")
    old_streamer = re.sub(r"\bfat32_file_streamer\b", "fat32_file_streamer_before", old_streamer)
    loader_path = output / "fat32_media_loader_before.v"
    streamer_path = output / "fat32_file_streamer_before.v"
    loader_path.write_text(old_loader, encoding="utf-8")
    streamer_path.write_text(old_streamer, encoding="utf-8")
    index_path = output / "song_index_db_before.v"
    old_index = (baseline / "src/SD/song_index_db.v").read_text(encoding="utf-8")
    old_index = old_index.replace("EXP_SONG_INDEX_DB_V", "EXP_SONG_INDEX_DB_BEFORE_V")
    index_path.write_text(re.sub(r"\bsong_index_db\b", "song_index_db_before", old_index), encoding="utf-8")
    bench = (ROOT / "sim/tb_fat32_index_loader.v").read_text(encoding="utf-8")
    bench = bench.replace("module tb_fat32_index_loader;", "module tb_closure_loader_equiv;")
    instance = re.search(r"fat32_media_loader dut\s*\(.*?\n\s*\);", bench, re.S)
    clone = instance.group().replace("fat32_media_loader dut", "fat32_media_loader_before before")
    header = loader.split(");", 1)[0]
    declarations, pairs = [], []
    for width, port in re.findall(r"\boutput\s+(?:(?:wire|reg)\s+)?(\[[^\]]+\])?\s*(\w+)", header):
        match = re.search(r"\." + port + r"\s*\(\s*(\w+)\s*\)", clone)
        if not match:
            continue
        signal = match.group(1)
        declarations.append(f"wire {width or ''} before_{signal};")
        clone = re.sub(r"(\." + port + r"\s*\(\s*)" + signal + r"(\s*\))",
                       r"\g<1>before_" + signal + r"\g<2>", clone)
        pairs.append((signal, "before_" + signal))
    checks = "\n".join(
        f'if ({new} !== {old}) $fatal(1,"cycle mismatch {new}");' for new, old in pairs)
    instrumentation = "\n".join(declarations) + "\n" + clone + "\n" + (
        "always @(negedge clk) if(!rst) begin\n" + checks + "\nend\n")
    bench = bench[:instance.end()] + "\n" + instrumentation + bench[instance.end():]
    path = output / "tb_closure_loader_equiv.v"
    path.write_text(bench, encoding="utf-8")
    target = output / "loader_equivalence.vvp"
    cmd = ["iverilog", "-g2005", "-I.", "-Isrc", "-Isrc/include", "-Isrc/SD"]
    for directory in ("src", "src/SD", "src/video", "src/io", "src/display"):
        cmd += ["-y", directory]
    cmd += ["-s", "tb_closure_loader_equiv", "-o", str(target), str(path), str(loader_path), str(streamer_path), str(index_path)]
    compiled = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, errors="replace", timeout=90)
    log = compiled.stdout + compiled.stderr
    ok = compiled.returncode == 0
    if ok:
        result = subprocess.run(["vvp", str(target)], cwd=ROOT, capture_output=True,
                                text=True, errors="replace", timeout=150)
        log += result.stdout + result.stderr
        ok = result.returncode == 0 and "TEST_PASS" in log and "FAIL" not in log
    (output / "loader_equivalence.log").write_text(log, encoding="utf-8")
    print("LOADER_CYCLE_EQUIVALENCE " + ("PASS" if ok else "FAIL"), flush=True)
    if not ok:
        print(log[-6000:], flush=True)
    return ok


def resource_equivalence(output, baseline):
    """Reproduce the byte-mux comparison and parameterized writer checks."""
    old = (baseline / "src/display/lrc_five_osd.v").read_text(encoding="utf-8")
    old_path = output / "lrc_five_osd_before.v"
    old = old.replace("EXP_LRC_FIVE_OSD_V", "EXP_LRC_FIVE_OSD_BEFORE_V")
    old_path.write_text(re.sub(r"\blrc_five_osd\b", "lrc_five_osd_before", old), encoding="utf-8")
    cases = [("lyric_equivalence", "tb_closure_lyric_equiv", [],
              [ROOT / "sim/tb_closure_lyric_equiv.v", old_path], "PASS lyric combinational equivalence")]
    window = (baseline / "src/display/lrc_window_controller.v").read_text(encoding="utf-8")
    window = window.replace("EXP_LRC_WINDOW_CONTROLLER_V", "EXP_LRC_WINDOW_CONTROLLER_BEFORE_V")
    window_path = output / "lrc_window_controller_before.v"
    window_path.write_text(re.sub(r"\blrc_window_controller\b", "lrc_window_controller_before", window), encoding="utf-8")
    cases.append(("window_equivalence", "tb_closure_window_equiv", [],
                  [ROOT / "sim/tb_closure_window_equiv.v", window_path], "PASS lyric window cycle equivalence"))
    for width, burst in ((1, 1), (8, 8), (640, 128)):
        cases.append((f"write_geometry_{width}", "tb_closure_write_geometry",
                      [f"-Ptb_closure_write_geometry.WIDTH={width}",
                       f"-Ptb_closure_write_geometry.BURST={burst}"],
                      [ROOT / "sim/tb_closure_write_geometry.v"], "PASS write geometry"))
    results = {}
    for name, top, parameters, sources, marker in cases:
        target = output / f"{name}.vvp"
        cmd = ["iverilog", "-g2005", "-I.", "-Isrc/include"]
        for directory in ("src/SD", "src/display"):
            cmd += ["-y", directory]
        cmd += parameters + ["-s", top, "-o", str(target)] + [str(p) for p in sources]
        compiled = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, errors="replace", timeout=90)
        log = compiled.stdout + compiled.stderr
        ok = compiled.returncode == 0
        if ok:
            result = subprocess.run(["vvp", str(target)], cwd=ROOT, capture_output=True,
                                    text=True, errors="replace", timeout=150)
            log += result.stdout + result.stderr
            ok = result.returncode == 0 and marker in log and not re.search(r"\b(?:FAIL|FATAL)\b", log)
        (output / f"{name}.log").write_text(log, encoding="utf-8")
        results[name] = ok
        print(name + ": " + ("PASS" if ok else "FAIL"), flush=True)
        if not ok:
            print(log[-6000:], flush=True)
    return results


def index_equivalence(output, baseline):
    old = (baseline / "src/SD/song_index_db.v").read_text(encoding="utf-8")
    old = old.replace("EXP_SONG_INDEX_DB_V", "EXP_SONG_INDEX_DB_BEFORE_V")
    old_path = output / "song_index_db_before.v"
    old_path.write_text(re.sub(r"\bsong_index_db\b", "song_index_db_before", old), encoding="utf-8")
    bench = (ROOT / "sim/tb_song_index_db.v").read_text(encoding="utf-8")
    bench = bench.replace("module tb_song_index_db;", "module tb_closure_index_equiv;")
    instance = re.search(r"song_index_db\s*#\(.*?\)\s*dut\s*\(.*?\n\s*\);", bench, re.S)
    clone = instance.group().replace("song_index_db", "song_index_db_before").replace(" dut (", " before (")
    widths = {"busy":1,"done":1,"valid":1,"err":8,"song_count":3,"song_flags":16}
    for kind in ("cover", "audio", "mv"):
        widths.update({f"song_{kind}{i}":64 for i in range(4)})
    widths["background_base_lba"] = 32
    declarations, checks = [], []
    for port, width in widths.items():
        match = re.search(r"\." + port + r"\s*\(\s*(\w+)\s*\)", clone)
        if not match:
            continue
        signal = match.group(1)
        declarations.append(f"wire [{width-1}:0] before_{signal};")
        clone = re.sub(r"(\." + port + r"\s*\(\s*)" + signal + r"(\s*\))",
                       r"\g<1>before_" + signal + r"\g<2>", clone)
        checks.append(f'if ({signal} !== before_{signal}) $fatal(1,"index cycle mismatch {signal}");')
    instrumentation = "\n".join(declarations) + "\n" + clone + "\nalways @(negedge clk) if(rst_n) begin\n" + "\n".join(checks) + "\nend\n"
    bench = bench[:instance.end()] + "\n" + instrumentation + bench[instance.end():]
    path = output / "tb_closure_index_equiv.v"
    path.write_text(old_path.read_text(encoding="utf-8") + "\n" + bench, encoding="utf-8")
    return legacy.run("tb_closure_index_equiv", output, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline", type=Path, default=ROOT / "prj/resource_opt_verified_20261005/closure_before_20261013")
    parser.add_argument("--focused", action="store_true", help="R2 changed paths only; retains the separate R1 full-suite evidence")
    parser.add_argument("--index-focused", action="store_true", help="Index pipeline and integrated loader differential checks only")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    # Preserve the full current stage suite; do not delete failed legacy tests
    # to manufacture a clean result. This is an explicitly scoped new suite.
    results = {}
    if not (args.focused or args.index_focused):
        stage = subprocess.run(["pwsh", "-NoProfile", "-File", str(ROOT / "tools/verify_stage3b.ps1")],
                           cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        stage_log = stage.stdout + stage.stderr
        (args.output / "stage3b_full.log").write_text(stage_log, encoding="utf-8")
        results["stage3b_full"] = stage_passed(stage_log, stage.returncode)
        print("STAGE3B_BATCH " + ("PASS" if results["stage3b_full"] else "FAIL"), flush=True)
        if not results["stage3b_full"]:
            print(stage_log[-6000:], flush=True)
    names = ("tb_media_write_pipeline", "tb_closure_writer_padding", "tb_fat32_index_loader",
             "tb_fat32_file_streamer", "tb_fat32_volume_scanner", "tb_wav_stream_player",
             "tb_wav_stream_player_flow", "tb_mv_audio_shared", "tb_x2_seek", "tb_cdc_bundle_latest", "tb_closure_header_compare")
    if args.focused:
        names = ("tb_stage3a_page", "tb_stage3b_page", "tb_stage3b_shared_writer", "tb_closure_writer_padding")
    if args.index_focused:
        names = ("tb_song_index_db", "tb_background_index", "tb_fat32_index_loader", "tb_fat32_file_streamer", "tb_closure_header_compare")
    for name in names:
        results[name] = legacy.run(name, args.output)
    if not args.focused:
        results["loader_cycle_equivalence"] = loader_equivalence(args.output, args.baseline)
    results["index_cycle_equivalence"] = index_equivalence(args.output, args.baseline)
    if not args.index_focused:
        results.update(resource_equivalence(args.output, args.baseline))
    (args.output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    passed = all(results.values())
    print("CLOSURE_VERIFICATION_" + ("PASS" if passed else "FAIL"), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
