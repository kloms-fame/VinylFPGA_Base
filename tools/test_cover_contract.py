"""Keep the packer's accepted BMP offset aligned with the RTL parser."""
import struct
import unittest

from tools.vinyl_packer import PackError, _check_cover


def cover(offset):
    data = bytearray(offset + 12)
    data[:2] = b'BM'
    struct.pack_into('<I', data, 2, len(data))
    struct.pack_into('<I', data, 10, offset)
    struct.pack_into('<IiiHHI', data, 14, 40, 4, 1, 1, 24, 0)
    return bytes(data)


class CoverContractTest(unittest.TestCase):
    def test_standard_offset(self):
        _check_cover(cover(54), 'standard', 4, 1)

    def test_extended_offsets_are_rejected(self):
        for offset in (55, 66, 138, 500, 512, 513, 1024):
            with self.subTest(offset=offset), self.assertRaises(PackError):
                _check_cover(cover(offset), 'extended', 4, 1)


if __name__ == '__main__':
    unittest.main()
