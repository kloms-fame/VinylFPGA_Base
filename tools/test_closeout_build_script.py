"""使用 Tcl 解释器检查构建脚本的阶段停线和时序判定。"""
import os
from pathlib import Path
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
        (self.root/'VinylFPGA.al').write_text('Num="1" Init="7" <Seeds select="7">7 </Seeds>')
        for directory, stages in [('syn_1', ['read_design', 'opt_rtl', 'opt_gate']),
                                  ('phy_1/seed_7', ['opt_place', 'opt_route', 'bitgen'])]:
            folder = self.root/'VinylFPGA_Runs'/directory
            folder.mkdir(parents=True)
            for stage in stages:
                (folder/f'.{stage}.end.f').touch()
        self.timing = self.root/'VinylFPGA_Runs/phy_1/seed_7/VinylFPGA_phy.ts'
        self.timing.write_text('SWNS: 0.148ns, STNS: 0.000ns\nHWNS: 0.030ns, HTNS: 0.000ns')
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

    def test_failed_synthesis_stops_physical_launch(self):
        (self.root/'VinylFPGA_Runs/syn_1/.opt_gate.error.f').touch()
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)
        self.assertEqual(self.tcl.eval('set launched'), 'syn_1')

    def test_failed_timing(self):
        self.timing.write_text('SWNS: -0.101ns, STNS: -0.101ns\nHWNS: 0.030ns, HTNS: 0.000ns')
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)

    def test_missing_bitgen_marker(self):
        (self.root/'VinylFPGA_Runs/phy_1/seed_7/.bitgen.end.f').unlink()
        with self.assertRaises(tkinter.TclError): self.tcl.eval(SCRIPT)


if __name__ == '__main__':
    unittest.main()
