"""Focused tests for final-round TD resource and timing report collection."""
from __future__ import annotations

import unittest
import hashlib
import json
import tempfile
from pathlib import Path

from collect_round_metrics import MetricsError, _metadata, compare_metrics, parse_reports


NATIVE_AREA = """Utilization Statistics
#mslice 3758 out of 4900
#lslice 3783 out of 4900
#plb 2360 out of 2450
#lut 13734 out of 19600
#reg 9400 out of 19600
#bram9k 42
#bram32k 0 out of 16
#dsp 15 out of 29
"""
NATIVE_QOR = """|     Setup WNS             |          121                |
|     Setup TNS             |            0                |
|     Num of violated S-EP  |            0                |
|     Hold WNS              |           24                |
|     Hold TNS              |            0                |
|     Num of violated H-EP  |            0                |
|     #slices               |         7541                |
|     Overflow              |            0                |
"""
AUTO_AREA = """Utilization Statistics
#mslice 4219 out of 4900
#lslice 4228 out of 4900
#plb 2404 out of 2450
#lut 15068 out of 19600
#reg 9414 out of 19600
#bram9k 42
#bram32k 0 out of 16
#dsp 15 out of 29
"""
AUTO_QOR = """Timing Status
SWNS: 0.075ns, STNS: 0.000ns
HWNS: 0.003ns, HTNS: 0.000ns
Num of violated S-EP: 0
Num of violated H-EP: 0
Slices: 8447
Overflow: 0
"""
META = {
    "tool_version": "Tang Dynasty v6.2.168116",
    "strategy": "area_prior",
    "seed": 5,
    "inputs_sha256": "a" * 64,
    "constraints_sha256": "b" * 64,
}
MANIFEST_FIELDS = (
    "schema", "created_utc", "round", "files", "round_snapshot_files", "production_tests",
    "top_level_tests_with_vendor_stubs", "generated_pressure_test", "baseline_bit_files",
    "board_binding", "notes",
)


def make_manifest(snapshot_constraints):
    payload = {
        "schema": 1,
        "created_utc": "2026-10-09T00:00:00+00:00",
        "round": "test_round",
        "files": {"tools/collect_round_metrics.py": "a" * 64},
        "round_snapshot_files": snapshot_constraints,
        "production_tests": ["tb_example"],
        "top_level_tests_with_vendor_stubs": [],
        "generated_pressure_test": "tb_s7_wav_wrap",
        "baseline_bit_files": [],
        "board_binding": None,
        "notes": [],
    }
    payload["manifest_sha256"] = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return payload


def write_metadata_fixture(round_dir, manifest):
    (round_dir / "build_manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (round_dir / "native_build.tcl").write_text(
        "set_param gate map_mode area_prior\nset_param place seed 5\n", encoding="utf-8")
    (round_dir / "native_build.log").write_text(
        "Created by          : Tang Dynasty v6.2.168116\n", encoding="utf-8")


class CollectRoundMetricsTests(unittest.TestCase):
    def test_parses_native_ps_final_reports_and_all_requested_resources(self):
        metrics = parse_reports(NATIVE_AREA, NATIVE_QOR, META)
        self.assertEqual(metrics["resources"], {
            "lut": 13734, "reg": 9400, "slices": 7541, "ms": 3758,
            "ls": 3783, "plb": 2360, "bram9k": 42, "bram32k": 0,
            "dsp": 15,
        })
        self.assertEqual(metrics["timing"]["setup_wns_ps"], 121)
        self.assertEqual(metrics["timing"]["hold_wns_ps"], 24)
        self.assertTrue(metrics["passed"])

    def test_parses_auto_ns_final_reports_and_converts_to_ps(self):
        metadata = dict(META, strategy="auto")
        metrics = parse_reports(AUTO_AREA, AUTO_QOR, metadata)
        self.assertEqual(metrics["timing"]["setup_wns_ps"], 75)
        self.assertEqual(metrics["timing"]["hold_wns_ps"], 3)
        self.assertEqual(metrics["resources"]["slices"], 8447)

    def test_rejects_missing_required_fields(self):
        with self.assertRaisesRegex(MetricsError, "bram32k"):
            parse_reports(NATIVE_AREA.replace("#bram32k 0 out of 16", ""), NATIVE_QOR, META)

    def test_negative_setup_or_hold_slack_fails_round(self):
        metrics = parse_reports(NATIVE_AREA, NATIVE_QOR.replace("121", "-1", 1), META)
        self.assertFalse(metrics["passed"])
        self.assertLess(metrics["timing"]["setup_wns_ps"], 0)

    def test_unreported_overflow_is_unknown_not_zero_or_a_false_pass(self):
        metrics = parse_reports(NATIVE_AREA, NATIVE_QOR.replace("|     Overflow              |            0                |", ""), META)
        self.assertIsNone(metrics["route"]["overflow"])
        self.assertIsNone(metrics["passed"])
        self.assertTrue(metrics["unknowns"])

    def test_rejects_comparison_when_strategy_or_constraints_differ(self):
        baseline = parse_reports(NATIVE_AREA, NATIVE_QOR, META)
        different_strategy = parse_reports(AUTO_AREA, AUTO_QOR, dict(META, strategy="auto"))
        with self.assertRaisesRegex(MetricsError, "strategy"):
            compare_metrics(baseline, different_strategy)
        different_constraints = parse_reports(NATIVE_AREA, NATIVE_QOR,
                                              dict(META, constraints_sha256="c" * 64))
        with self.assertRaisesRegex(MetricsError, "constraints"):
            compare_metrics(baseline, different_constraints)

    def test_rejects_comparison_when_tool_version_differs(self):
        baseline = parse_reports(NATIVE_AREA, NATIVE_QOR, META)
        different_tool = parse_reports(NATIVE_AREA, NATIVE_QOR,
                                       dict(META, tool_version="Tang Dynasty v6.2.168117"))
        with self.assertRaisesRegex(MetricsError, "tool_version"):
            compare_metrics(baseline, different_tool)

    def test_constraint_identity_comes_from_round_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            round_dir = Path(temp)
            snapshot_constraints = {"constraints/timing.sdc": "b" * 64,
                                    "constraints/pin.adc": "c" * 64}
            manifest = make_manifest(snapshot_constraints)
            write_metadata_fixture(round_dir, manifest)
            metadata = _metadata(round_dir, round_dir / "build_manifest.json")
        expected = hashlib.sha256(json.dumps(snapshot_constraints, sort_keys=True).encode()).hexdigest()
        self.assertEqual(metadata["constraints_sha256"], expected)

    def test_rejects_manifest_modified_without_recomputing_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            round_dir = Path(temp)
            manifest = make_manifest({"constraints/timing.sdc": "b" * 64})
            manifest["round_snapshot_files"]["constraints/timing.sdc"] = "c" * 64
            write_metadata_fixture(round_dir, manifest)
            with self.assertRaisesRegex(MetricsError, "manifest_sha256 mismatch"):
                _metadata(round_dir, round_dir / "build_manifest.json")

    def test_rejects_manifest_missing_required_schema_field(self):
        with tempfile.TemporaryDirectory() as temp:
            round_dir = Path(temp)
            manifest = make_manifest({"constraints/timing.sdc": "b" * 64})
            del manifest["top_level_tests_with_vendor_stubs"]
            manifest.pop("manifest_sha256")
            manifest["manifest_sha256"] = hashlib.sha256(
                json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
            write_metadata_fixture(round_dir, manifest)
            with self.assertRaisesRegex(MetricsError, "top_level_tests_with_vendor_stubs"):
                _metadata(round_dir, round_dir / "build_manifest.json")


if __name__ == "__main__":
    unittest.main()
