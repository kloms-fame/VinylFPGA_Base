"""Exercise result validation with real temporary TD-style artifacts."""
import os
from pathlib import Path
import tempfile
import time
import unittest
import subprocess
import sys

from verify_gui_runs import verify


class GuiResultTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'VinylFPGA.al'
        self.runs = self.root / 'VinylFPGA_Runs'

    def fixture(self, seed):
        self.project.write_text(
            '<Runs><Run Name="syn_1"><Strategy><GateProperty>'
            '<map_mode>area_prior</map_mode><pack_effort>high</pack_effort>'
            '</GateProperty></Strategy></Run>'
            '<Run Name="phy_1"><Strategy><PlaceProperty>'
            '<opt_timing>high</opt_timing></PlaceProperty><RouteProperty>'
            '<effort>routability</effort></RouteProperty></Strategy></Run></Runs>'
            '<MultiSeed><Property Enable="true" GenBit="true" '
            f'EndStep="bitgen" Random="false" Num="1" Init="{seed}" '
            f'Jobs="1" Save="1" Step="1"/><Seeds select="{seed}">{seed} '
            '</Seeds></MultiSeed>', encoding='utf-8')
        phy = self.runs / 'phy_1'
        run = phy / f'seed_{seed}'
        run.mkdir(parents=True)
        for name in ('.multiSeed.begin.f', '.multiSeed.end.f'):
            (phy / name).write_bytes(b'')
        os.utime(phy / '.multiSeed.begin.f', (time.time() - 10,) * 2)
        for name in ('.opt_route.end.f', '.bitgen.end.f', '.bitgen_param.f'):
            (run / name).write_bytes(b'')
        for name, data in {
            'VinylFPGA_pr.db': b'database', 'VinylFPGA.bit': b'bitstream',
            'VinylFPGA_phy.ts': b'SWNS: 0.100ns, STNS: 0.000ns\nHWNS: 0.010ns, HTNS: 0.000ns',
            'route.qor': b'route complete',
        }.items():
            (run / name).write_bytes(data)
            (phy / name).write_bytes(data)
        (run / 'run.log').write_text('start command "fix_hold"\n', encoding='gbk')
        return phy, run

    def check(self):
        return verify(run_root=self.runs, project_file=self.project)

    def test_seed_five(self):
        self.fixture(5)
        self.assertIn('seed_5', self.check()['bit'])

    def test_seed_three(self):
        self.fixture(3)
        self.assertIn('seed_3', self.check()['bit'])

    def test_strategy_cli_does_not_require_old_run_outputs(self):
        self.fixture(3)
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('verify_gui_runs.py')),
                                 '--project-file', str(self.project), '--strategy-only'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PROJECT_STRATEGY_VERIFIED', result.stdout)

    def test_strategy_cli_rejects_missing_area_mapping(self):
        self.fixture(3)
        self.project.write_text(self.project.read_text(encoding='utf-8').replace(
            '<map_mode>area_prior</map_mode>', ''), encoding='utf-8')
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('verify_gui_runs.py')),
                                 '--project-file', str(self.project), '--strategy-only'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PROJECT_STRATEGY_VERIFIED', result.stdout)

    def test_missing_strategy_rejected(self):
        self.fixture(3)
        original = self.project.read_text(encoding='utf-8')
        for tag, value in (('map_mode', 'area_prior'), ('pack_effort', 'high'),
                           ('opt_timing', 'high'), ('effort', 'routability')):
            with self.subTest(tag=tag):
                self.project.write_text(
                    original.replace(f'<{tag}>{value}</{tag}>', ''), encoding='utf-8')
                with self.assertRaisesRegex(RuntimeError, 'Project strategy'):
                    self.check()

    def test_changed_strategy_rejected(self):
        self.fixture(3)
        self.project.write_text(self.project.read_text(encoding='utf-8').replace(
            '<effort>routability</effort>', '<effort>medium</effort>'), encoding='utf-8')
        with self.assertRaisesRegex(RuntimeError, 'Project strategy'):
            self.check()

    def test_seed_six(self):
        self.fixture(6)
        self.assertIn('seed_6', self.check()['bit'])

    def test_failed_route_rejected(self):
        _, run = self.fixture(6)
        (run / '.opt_route.error.f').write_bytes(b'')
        with self.assertRaisesRegex(RuntimeError, 'error marker'):
            self.check()

    def test_negative_setup_rejected(self):
        _, run = self.fixture(6)
        (run / 'VinylFPGA_phy.ts').write_text(
            'SWNS: -0.001ns, STNS: -0.001ns\nHWNS: 0.010ns, HTNS: 0.000ns', encoding='gbk')
        with self.assertRaisesRegex(RuntimeError, 'timing does not pass'):
            self.check()

    def test_stale_bit_rejected(self):
        _, run = self.fixture(6)
        os.utime(run / 'VinylFPGA.bit', (time.time() - 100,) * 2)
        with self.assertRaisesRegex(RuntimeError, 'predate'):
            self.check()

    def test_selected_copy_mismatch_rejected(self):
        phy, _ = self.fixture(6)
        (phy / 'VinylFPGA.bit').write_bytes(b'old bitstream')
        with self.assertRaisesRegex(RuntimeError, 'selected-result mismatch'):
            self.check()


if __name__ == '__main__':
    unittest.main()
