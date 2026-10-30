"""使用 Tcl 解释器检查构建脚本的阶段停线和时序判定。"""
import os
from pathlib import Path
import shutil
import tempfile
import tkinter
import unittest


SCRIPT = Path(__file__).with_name('run_closeout_project.tcl').read_text(encoding='utf-8')


class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        self.cwd = Path.cwd()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(os.chdir, self.cwd)
        self.root = Path(self.temp.name)
        self.project = self.root/'VinylFPGA.al'
        params = ('place timing_driven_mode on', 'place crit_path_opt on',
                  'place post_place_opt high', 'place shifter_opt on',
                  'place split_data_from_clock on', 'place hfn_opt_effort high',
                  'route postrt_opt_extra_round 4')
        self.project.write_text('<MultiSeed><Property Enable="true" Random="false" '
                                'GenBit="true" EndStep="bitgen" Num="3" Init="7" Step="1">'
                                '</Property><Seeds select="9">7 8 9 </Seeds></MultiSeed>' +
                                ''.join('<param>set_param '+p+'</param>' for p in params))
        self.original_project = self.project.read_bytes()
        for directory, stages in [('syn_1', ['read_design', 'opt_rtl', 'opt_gate']),
                                  ('phy_1/seed_9', ['opt_place', 'opt_route', 'bitgen'])]:
            folder = self.root/'VinylFPGA_Runs'/directory
            folder.mkdir(parents=True)
            for stage in stages:
                (folder/f'.{stage}.end.f').touch()
        (self.root/'VinylFPGA_Runs/phy_1/.multiSeed.end.f').touch()
        (self.root/'VinylFPGA_Runs/syn_1/VinylFPGA_gate.db').write_bytes(b'gate')
        self.timing = self.root/'VinylFPGA_Runs/phy_1/seed_9/VinylFPGA_phy.ts'
        self.timing.write_text('SWNS: 0.117ns, STNS: 0.000ns\nHWNS: 0.022ns, HTNS: 0.000ns')
        self.qor = self.timing.with_name('route.qor')
        self.qor.write_text('Num of violated S-EP | 0\nNum of violated H-EP | 0')
        self.timing.with_name('VinylFPGA.bit').write_bytes(b'bitstream')
        self.timing.with_name('VinylFPGA_pr.db').write_bytes(b'database')
        self.timing.with_name('VinylFPGA_place.db').write_bytes(b'placed')
        best = self.root/'VinylFPGA_Runs/best_result'
        best.mkdir()
        (best/'readMe.txt').write_text('The implemented result of seed 9 from phy_1 is saved as best result.')
        (best/'VinylFPGA.bit').write_bytes(b'bitstream')
        (best/'VinylFPGA_pr.db').write_bytes(b'database')
        (best/'VinylFPGA_phy.ts').write_bytes(self.timing.read_bytes())
        self.tcl = tkinter.Tcl()
        self.tcl.setvar('env(VINYL_BUILD_DIR)', str(self.root))
        self.addCleanup(self.tcl.eval, 'unset env(VINYL_BUILD_DIR)')
        self.tcl.eval('set launched {}; proc launch_runs {args} {global launched; lappend launched [lindex $args 0]}')
        for command in ('import_device', 'open_project', 'reset_runs', 'wait_run',
                        'set_user_params', 'close_project', 'exit'):
            self.tcl.eval('proc '+command+' {args} {}')

    def test_pass(self):
        self.tcl.eval(SCRIPT)
        self.assertEqual(self.tcl.eval('set launched'), 'syn_1 phy_1')
        self.assertEqual(self.project.read_bytes(), self.original_project)

    def test_failed_synthesis_stops_physical_launch(self):
        (self.root/'VinylFPGA_Runs/syn_1/.opt_gate.error.f').touch()
        with self.assertRaisesRegex(tkinter.TclError, '构建阶段未完成'): self.tcl.eval(SCRIPT)
        self.assertEqual(self.tcl.eval('set launched'), 'syn_1')

    def test_failed_timing(self):
        self.timing.write_text('SWNS: -0.101ns, STNS: -0.101ns\nHWNS: 0.030ns, HTNS: 0.000ns')
        with self.assertRaisesRegex(tkinter.TclError, '最终时序未通过'): self.tcl.eval(SCRIPT)
        self.assertEqual(self.project.read_bytes(), self.original_project)

    def test_missing_bitgen_marker(self):
        (self.timing.parent/'.bitgen.end.f').unlink()
        with self.assertRaisesRegex(tkinter.TclError, '构建阶段未完成'): self.tcl.eval(SCRIPT)

    def test_seed_count_mismatch_rejected_before_launch(self):
        self.project.write_text(self.project.read_text().replace('Num="3"', 'Num="1"'))
        with self.assertRaisesRegex(tkinter.TclError, 'MultiSeed'): self.tcl.eval(SCRIPT)
        self.assertEqual(self.tcl.eval('set launched'), '')

    def test_route_endpoints_rejected(self):
        self.qor.write_text('Num of violated S-EP | 1\nNum of violated H-EP | 0')
        with self.assertRaisesRegex(tkinter.TclError, '端点违例'): self.tcl.eval(SCRIPT)

    def test_selected_bit_mismatch_rejected(self):
        (self.root/'VinylFPGA_Runs/best_result/VinylFPGA.bit').write_bytes(b'old')
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)

    def test_missing_gate_database_stops_physical_launch(self):
        (self.root/'VinylFPGA_Runs/syn_1/VinylFPGA_gate.db').unlink()
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)
        self.assertEqual(self.tcl.eval('set launched'), 'syn_1')

    def test_missing_routed_database_rejected(self):
        self.timing.with_name('VinylFPGA_pr.db').unlink()
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)

    def test_empty_matching_bitstreams_rejected(self):
        self.timing.with_name('VinylFPGA.bit').write_bytes(b'')
        (self.root/'VinylFPGA_Runs/best_result/VinylFPGA.bit').write_bytes(b'')
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)

    def test_new_seed_result_updates_gui_selection(self):
        self.project.write_text(self.project.read_text().replace(
            'Num="3" Init="7"', 'Num="3" Init="10"').replace(
            '<Seeds select="9">7 8 9 ', '<Seeds select="12">10 11 12 '))
        shutil.copytree(self.timing.parent, self.timing.parent.with_name('seed_10'))
        (self.root/'VinylFPGA_Runs/best_result/readMe.txt').write_text(
            'The implemented result of seed 10 from phy_1 is saved as best result.')
        self.tcl.eval(SCRIPT)
        self.assertIn('<Seeds select="10">10 11 12 ', self.project.read_text())


if __name__ == '__main__':
    unittest.main()
