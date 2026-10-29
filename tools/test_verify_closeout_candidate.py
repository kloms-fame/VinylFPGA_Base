"""校验交付损坏和失败时序确实被拒绝。"""
import json
from pathlib import Path
import tempfile
import unittest

from verify_closeout_candidate import sha, verify


class CloseoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('src', 'constraints', 'release'):
            (self.root/folder).mkdir()
        (self.root/'src/top.v').write_text('module top; endmodule')
        self.qor = self.root/'release/route.qor'
        self.qor.write_text('\n'.join(f'{name} | {value} |' for name, value in [
            ('Setup WNS', 148), ('Hold WNS', 30), ('Setup TNS', 0), ('Hold TNS', 0),
            ('Num of violated S-EP', 0), ('Num of violated H-EP', 0)]))
        (self.root/'release/test.bit').write_bytes(b'candidate')
        self.path = self.root/'manifest.json'
        self.data = {'inputs': {'src/top.v': sha(self.root/'src/top.v')},
                     'artifacts': {f'release/{name}': sha(self.root/'release'/name)
                                   for name in ('route.qor', 'test.bit')},
                     'qor': 'release/route.qor', 'bit': 'release/test.bit', 'board_acceptance': 'pending',
                     'open_items': ['实板待验收']}
        self.save()

    def save(self):
        self.path.write_text(json.dumps(self.data))

    def test_candidate(self):
        self.assertTrue(verify(self.root, self.path)['candidate_verified'])

    def test_source_changed(self):
        (self.root/'src/top.v').write_text('changed')
        with self.assertRaises(RuntimeError): verify(self.root, self.path)

    def test_added_source(self):
        (self.root/'src/other.v').write_text('other')
        with self.assertRaises(RuntimeError): verify(self.root, self.path)

    def test_bit_corrupted(self):
        (self.root/'release/test.bit').write_bytes(b'corrupted')
        with self.assertRaises(RuntimeError): verify(self.root, self.path)

    def test_failed_timing_even_with_updated_hash(self):
        self.qor.write_text(self.qor.read_text().replace('Setup WNS | 148', 'Setup WNS | -1'))
        self.data['artifacts']['release/route.qor'] = sha(self.qor)
        self.save()
        with self.assertRaises(RuntimeError): verify(self.root, self.path)

    def test_final_requires_board_acceptance(self):
        with self.assertRaises(RuntimeError): verify(self.root, self.path, True)


if __name__ == '__main__':
    unittest.main()
