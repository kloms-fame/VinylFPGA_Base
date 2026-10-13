"""Continue a frozen 3B implementation using separate placement seeds.

Only a known completed route with exit 2 (negative setup/hold slack) advances
to another seed. Tool errors, source changes and bitgen failures fail stop.
No physical SD write or FPGA download is performed.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime

from resource_opt_round import snapshot

ROOT = Path(__file__).resolve().parents[1]
ROUNDS = ROOT / "prj/resource_opt_verified_20261005"
FIRST = ROUNDS / "stage3b_background_20261013_r1"
RELEASE = ROUNDS / "stage3b_background_20261013_release"


def announce(message):
    print(f"{message} {datetime.now().astimezone().isoformat()}", flush=True)


def check_inputs():
    expected = json.loads((FIRST / "inputs.sha256.json").read_text())
    actual = {p.relative_to(ROOT).as_posix()
              for folder in ("src", "constraints")
              for p in (ROOT / folder).rglob("*") if p.is_file()}
    if actual != set(expected):
        raise RuntimeError("SOURCE_SET_CHANGED")
    for rel, digest in expected.items():
        if hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() != digest:
            raise RuntimeError("SOURCE_CHANGED " + rel)


def main():
    RELEASE.mkdir(exist_ok=True)
    if (RELEASE / "VinylFPGA_optimized.bit").exists():
        raise RuntimeError("RELEASE_EXISTS")
    check_inputs()
    shutil.copy2(FIRST / "inputs.sha256.json", RELEASE / "inputs.sha256.json")
    announce("START_SEED_RECOVERY")
    for round_number, seed in enumerate((7, 11, 3, 13), start=2):
        check_inputs()
        name = f"stage3b_background_20261013_r{round_number}"
        announce(f"BUILD_START round={name} seed={seed}")
        snapshot(name)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/build_verified_round.py"), name,
             "--seed", str(seed), "--gate", str(FIRST / "gate.db")], cwd=ROOT)
        if result.returncode == 2:
            announce(f"ROUTE_TIMING_RETRY round={name}")
            continue
        if result.returncode != 0:
            announce(f"BUILD_FAILED round={name} exit={result.returncode}")
            return 1
        announce(f"BUILD_COMPLETE round={name}")
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/release_verified_round.py"), name], cwd=ROOT)
        if result.returncode != 0:
            announce(f"BITGEN_FAILED round={name} exit={result.returncode}")
            return 1
        candidate = ROUNDS / name
        bit = candidate / "VinylFPGA_optimized.bit"
        digest = hashlib.sha256(bit.read_bytes()).hexdigest()
        for filename in ("VinylFPGA_optimized.bit", ".bitgen_param.f", "bitstream.sha256",
                         "final.qor", "final.area", "final.constraints", "release_bitgen.log"):
            shutil.copy2(candidate / filename, RELEASE / filename)
        if hashlib.sha256((RELEASE / bit.name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("DELIVERY_HASH_MISMATCH")
        manifest = {"source_round": name, "seed": seed, "sha256": digest,
                    "bytes": bit.stat().st_size, "source_gate": str(FIRST / "gate.db"),
                    "completed_at": datetime.now().astimezone().isoformat()}
        (RELEASE / "release_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        announce(f"BITGEN_COMPLETE round={name} sha256={digest}")
        return 0
    announce("BUILD_FAILED all placement seeds have timing violations")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        announce("PIPELINE_EXCEPTION " + str(exc))
        sys.exit(1)
