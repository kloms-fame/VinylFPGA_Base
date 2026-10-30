"""The configuration entry point must not discard a verified MultiSeed search."""
import os
from pathlib import Path
import tempfile
import tkinter
import unittest

SCRIPT = Path(__file__).with_name('configure_optimized_project.tcl').read_text(encoding='utf-8')
PROJECT = Path(__file__).resolve().parents[1] / 'prj/VinylFPGA.al'


class ConfigureTests(unittest.TestCase):
    def test_preserves_multiseed_configuration(self):
        cwd = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'prj').mkdir()
            (root / 'tools').mkdir()
            project = root / 'prj/VinylFPGA.al'
            project.write_bytes(PROJECT.read_bytes())
            original = project.read_bytes()
            script = root / 'tools/configure_optimized_project.tcl'
            script.write_text(SCRIPT, encoding='utf-8')
            tcl = tkinter.Tcl()
            tcl.eval('set seed_changes {}; proc set_seed_param {args} {global seed_changes; lappend seed_changes $args}')
            for command in ('import_device', 'open_project', 'set_param',
                            'non_default_params', 'report_seed_param', 'close_project', 'exit'):
                tcl.eval('proc ' + command + ' {args} {}')
            try:
                tcl.call('source', str(script))
                self.assertEqual(tcl.eval('set seed_changes'), '',
                                 'Configuration silently resets the MultiSeed search')
                self.assertEqual(project.read_bytes(), original)
            finally:
                os.chdir(cwd)


if __name__ == '__main__':
    unittest.main()
