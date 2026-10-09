"""Collect and compare complete-route metrics for one isolated TD round."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
ROUNDS = ROOT / "prj/resource_opt_verified_20261005"


class MetricsError(ValueError):
    pass


def _number(patterns: list[str], *texts: str, field: str, required: bool = True) -> int | None:
    for text in texts:
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
            if match:
                return int(match.group(1).replace(",", ""))
    if required:
        raise MetricsError(f"missing required final report field: {field}")
    return None


def _timing(qor: str) -> tuple[dict[str, int], list[str]]:
    # TD native report_qor uses ps; MCP reports use SWNS/HWNS in ns.
    ps_names = {
        "setup_wns_ps": (r"Setup\s+WNS\s*\|\s*(-?[\d,]+)",),
        "setup_tns_ps": (r"Setup\s+TNS\s*\|\s*(-?[\d,]+)",),
        "setup_violations": (r"Num of violated S-EP\s*\|\s*(-?[\d,]+)",),
        "hold_wns_ps": (r"Hold\s+WNS\s*\|\s*(-?[\d,]+)",),
        "hold_tns_ps": (r"Hold\s+TNS\s*\|\s*(-?[\d,]+)",),
        "hold_violations": (r"Num of violated H-EP\s*\|\s*(-?[\d,]+)",),
    }
    metrics: dict[str, int] = {}
    units: list[str] = []
    for name, pats in ps_names.items():
        match = re.search(pats[0], qor, re.IGNORECASE)
        if match:
            metrics[name] = int(match.group(1).replace(",", ""))
            units.append("ps")

    ns_names = {
        "setup_wns_ps": r"SWNS\s*:\s*(-?[\d.]+)\s*ns",
        "setup_tns_ps": r"STNS\s*:\s*(-?[\d.]+)\s*ns",
        "hold_wns_ps": r"HWNS\s*:\s*(-?[\d.]+)\s*ns",
        "hold_tns_ps": r"HTNS\s*:\s*(-?[\d.]+)\s*ns",
    }
    for name, pattern in ns_names.items():
        if name in metrics:
            continue
        match = re.search(pattern, qor, re.IGNORECASE)
        if match:
            # Round away from zero so a small negative slack can never be hidden.
            value = float(match.group(1)) * 1000
            metrics[name] = int(value) if value >= 0 else int(value - 0.999999)
            units.append("ns")
    if "setup_violations" not in metrics:
        metrics["setup_violations"] = _number(
            [r"Num of violated S-EP\s*:\s*(-?[\d,]+)", r"Setup\s+NUM_FEPS\s+(-?[\d,]+)"],
            qor, field="setup violations")
    if "hold_violations" not in metrics:
        metrics["hold_violations"] = _number(
            [r"Num of violated H-EP\s*:\s*(-?[\d,]+)", r"Hold\s+NUM_FEPS\s+(-?[\d,]+)"],
            qor, field="hold violations")
    missing = [name for name in ps_names if name not in metrics]
    if missing:
        raise MetricsError("missing required final timing fields: " + ", ".join(missing))
    if len(set(units)) != 1:
        raise MetricsError("mixed or missing timing units in final report")
    metrics["unit_source"] = units[0]  # type: ignore[assignment]
    return metrics, units


def parse_reports(area_text: str, qor_text: str, metadata: dict[str, Any],
                  route_status: str = "") -> dict[str, Any]:
    area_patterns = {
        "lut": [r"^\s*#lut\s+([\d,]+)"],
        "reg": [r"^\s*#reg\s+([\d,]+)"],
        "ms": [r"^\s*#mslice\s+([\d,]+)"],
        "ls": [r"^\s*#lslice\s+([\d,]+)"],
        "plb": [r"^\s*#plb\s+([\d,]+)"],
        "bram9k": [r"^\s*#bram9k\s+([\d,]+)"],
        "bram32k": [r"^\s*#bram32k\s+([\d,]+)"],
        "dsp": [r"^\s*#dsp\s+([\d,]+)"],
    }
    resources = {key: _number(patterns, area_text, field=key)
                 for key, patterns in area_patterns.items()}
    slices = _number([r"#slices\s*\|\s*([\d,]+)", r"Slices\s*:\s*([\d,]+)"],
                     qor_text, field="slices")
    resources["slices"] = slices
    timing, units = _timing(qor_text)
    overflow = _number(
        [r"(?:Total\s+)?overflow\s*(?:\|\s*|:\s*)([\d,]+)",
         r"overflow\s*[=:]\s*([\d,]+)"], qor_text, route_status,
        field="final route overflow", required=False)
    required_metadata = ("tool_version", "strategy", "seed", "inputs_sha256", "constraints_sha256")
    missing = [key for key in required_metadata if metadata.get(key) in (None, "")]
    if missing:
        raise MetricsError("missing build metadata: " + ", ".join(missing))
    unknowns = [] if overflow is not None else ["route.overflow (not reported by final TD artifacts)"]
    timing_pass = (timing["setup_wns_ps"] >= 0 and timing["hold_wns_ps"] >= 0
                   and timing["setup_tns_ps"] == 0 and timing["hold_tns_ps"] == 0
                   and timing["setup_violations"] == 0 and timing["hold_violations"] == 0)
    known_failure = (not timing_pass) or (overflow is not None and overflow != 0)
    passed = False if known_failure else (None if overflow is None else True)
    return {
        "resources": resources,
        "timing": timing,
        "route": {"overflow": overflow,
                  "overflow_source": "reported" if overflow is not None else "not reported by TD final reports"},
        "metadata": {key: metadata[key] for key in required_metadata},
        "passed": passed,
        "unknowns": unknowns,
    }


def compare_metrics(parent: dict[str, Any], candidate: dict[str, Any]) -> None:
    for field in ("strategy", "seed", "tool_version", "constraints_sha256"):
        left = parent["metadata"].get(field)
        right = candidate["metadata"].get(field)
        if left != right:
            raise MetricsError(f"cannot compare rounds: {field} differs ({left!r} != {right!r})")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def freeze_manifest(round_dir: Path, bit_paths: list[Path] | None = None) -> Path:
    """Freeze source, project, tests, scripts, assets and locally available bit inputs."""
    import importlib.util

    test_script = ROOT / "tools/verify_s7_acceptance.py"
    spec = importlib.util.spec_from_file_location("s7_acceptance_inventory", test_script)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    included: set[Path] = {ROOT / "prj/VinylFPGA.al", test_script,
                           ROOT / "tools/collect_round_metrics.py",
                           ROOT / "tools/test_collect_round_metrics.py",
                           ROOT / "tools/resource_opt_round.py",
                           ROOT / "tools/build_verified_round.py",
                           ROOT / "tools/release_verified_round.py"}
    for folder, globs in ((ROOT / "src", ("**/*",)),
                          (ROOT / "constraints", ("**/*",)),
                          (ROOT / "sim", ("**/*.v", "**/*.vh", "**/*.mem", "**/*.hex")),
                          (ROOT / "tools", ("*.py", "*.tcl", "*.ps1")),
                          (ROOT / "doc/资源", ("**/*",)),
                          (ROOT / "tf_card_stage", ("**/*",))):
        if folder.exists():
            for pattern in globs:
                included.update(path for path in folder.glob(pattern) if path.is_file())
    file_records = {
        path.relative_to(ROOT).as_posix(): sha256(path)
        for path in sorted(included) if path.is_file() and ROOT in path.parents
    }
    snapshot_records = {
        path.relative_to(round_dir).as_posix(): sha256(path)
        for folder in (round_dir / "src", round_dir / "constraints")
        for path in folder.rglob("*") if path.is_file()
    }
    for name in ("VinylFPGA.al", "inputs.sha256.json"):
        path = round_dir / name
        if path.is_file():
            snapshot_records[name] = sha256(path)
    bits = []
    for bit_path in bit_paths or []:
        path = bit_path.resolve(strict=True)
        bits.append({"path": str(path), "sha256": sha256(path), "exists": True})
    payload: dict[str, Any] = {
        "schema": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "round": round_dir.name,
        "files": file_records,
        "round_snapshot_files": snapshot_records,
        "production_tests": list(module.PRODUCTION_TESTS),
        "top_level_tests_with_vendor_stubs": sorted(module.TOP_LEVEL_TESTS),
        "generated_pressure_test": "tb_s7_wav_wrap (48 sectors; derived from tb_wav_stream_player_flow)",
        "baseline_bit_files": bits,
        "board_binding": None,
        "notes": ["A local bit hash does not prove it is programmed on the current board.",
                  "No current board-to-bit or board-to-card binding is asserted."],
    }
    payload["manifest_sha256"] = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    output = round_dir / "build_manifest.json"
    if output.exists():
        raise MetricsError(f"refusing to replace frozen input manifest: {output}")
    output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return output


def _read_text(path: Path) -> str:
    for encoding in ("utf-8", "gbk", "cp1252"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    raise MetricsError(f"cannot decode report: {path}")


def _metadata(round_dir: Path, manifest_path: Path) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    snapshot_files = manifest.get("round_snapshot_files")
    if not isinstance(snapshot_files, dict):
        raise MetricsError("build manifest is missing round_snapshot_files")
    constraints_hashes = {name: digest for name, digest in snapshot_files.items()
                          if name.startswith("constraints/")}
    if not constraints_hashes:
        raise MetricsError("build manifest snapshot has no constraints")
    constraints_sha = hashlib.sha256(json.dumps(constraints_hashes, sort_keys=True).encode()).hexdigest()
    tcl = _read_text(round_dir / "native_build.tcl")
    param_path = round_dir / "gate.param"
    params = _read_text(param_path) if param_path.exists() else ""
    strategy_match = re.search(r"^\s*map_mode\s*\|\s*(\w+)", params, re.MULTILINE | re.IGNORECASE)
    if not strategy_match:
        strategy_match = re.search(r"set_param\s+gate\s+map_mode\s+(\w+)", tcl, re.IGNORECASE)
    if not strategy_match:
        raise MetricsError("gate strategy is not recorded in gate.param or native_build.tcl")
    seed_match = re.search(r"set_param\s+place\s+seed\s+(\d+)", tcl)
    if not seed_match:
        raise MetricsError("native_build.tcl is missing place seed")
    log = _read_text(round_dir / "native_build.log")
    version_match = re.search(r"Created by\s*:\s*(.+)", log)
    if not version_match:
        version_match = re.search(r"Tang Dynasty,?\s*(V[\d.]+)", log)
    if not version_match:
        raise MetricsError("native_build.log is missing Tang Dynasty version")
    return {
        "tool_version": version_match.group(1).strip(),
        "strategy": strategy_match.group(1).lower(),
        "seed": int(seed_match.group(1)),
        "inputs_sha256": manifest["manifest_sha256"],
        "constraints_sha256": constraints_sha,
    }


def _markdown(metrics: dict[str, Any]) -> str:
    state = "PASS" if metrics["passed"] is True else "FAIL" if metrics["passed"] is False else "UNVERIFIED"
    lines = ["# Routed-round metrics", "", f"Status: **{state}**", "",
             "## Resources", "", "| Metric | Count |", "|---|---:|"]
    lines += [f"| {key} | {value} |" for key, value in metrics["resources"].items()]
    lines += ["", "## Timing and routing", "", "| Metric | Value |", "|---|---:|"]
    lines += [f"| {key} | {value} |" for key, value in metrics["timing"].items()]
    lines += [f"| overflow | {metrics['route']['overflow']} |", "", "## Build identity", ""]
    lines += [f"- {key}: `{value}`" for key, value in metrics["metadata"].items()]
    if metrics["unknowns"]:
        lines += ["", "## Unreported fields", ""]
        lines += [f"- {item}" for item in metrics["unknowns"]]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("round", help="isolated round name in prj/resource_opt_verified_20261005")
    parser.add_argument("--parent", help="optional parent round; metrics.json must already exist")
    parser.add_argument("--report-dir", type=Path,
                        help="explicit report directory (for parser samples; does not use fixed round path)")
    parser.add_argument("--metadata-json", type=Path,
                        help="metadata JSON alongside parser samples; fixed rounds derive it from their manifest")
    parser.add_argument("--freeze-manifest", action="store_true",
                        help="write complete input manifest before the build; omit report collection")
    parser.add_argument("--bit", type=Path, action="append", default=[],
                        help="existing local bit file to bind into the input manifest (repeatable)")
    args = parser.parse_args(argv)
    round_dir = args.report_dir.resolve() if args.report_dir else (ROUNDS / args.round).resolve(strict=True)
    try:
        if args.freeze_manifest:
            manifest = freeze_manifest(round_dir, args.bit)
            print(f"Input manifest written: {manifest}")
            return 0
        if args.metadata_json:
            metadata = json.loads(args.metadata_json.read_text(encoding="utf-8"))
        else:
            metadata = _metadata(round_dir, round_dir / "build_manifest.json")
        area = _read_text(round_dir / "final_verbose.area") if (round_dir / "final_verbose.area").exists() else _read_text(round_dir / "final.area")
        qor = _read_text(round_dir / "final.qor")
        status = _read_text(round_dir / "route.status") if (round_dir / "route.status").exists() else ""
        metrics = parse_reports(area, qor, metadata, status)
        if args.parent:
            parent_file = ROUNDS / args.parent / "metrics.json"
            if not parent_file.is_file():
                raise MetricsError(f"parent metrics are missing: {parent_file}")
            compare_metrics(json.loads(parent_file.read_text(encoding="utf-8")), metrics)
        (round_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
        (round_dir / "metrics.md").write_text(_markdown(metrics), encoding="utf-8")
        print(f"Metrics written: {round_dir / 'metrics.json'}")
        return 2 if metrics["passed"] is False else 0
    except (OSError, KeyError, json.JSONDecodeError, MetricsError) as exc:
        print(f"metrics collection failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
