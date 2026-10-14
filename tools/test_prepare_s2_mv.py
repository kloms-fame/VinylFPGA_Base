"""S2 INDEX v2 contract tests for four contiguous full-MV entries."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import pack_backgrounds as bg
import vinyl_packer as vp
from prepare_s2_mv import build_index_with_mv


def base_index() -> bytes:
    songs = [vp.IndexSong(title=f"Track {n}", flags=vp.FLAG_COVER | vp.FLAG_AUDIO,
                          cover_cluster=10 + n, cover_bytes=921654,
                          cover_crc32=n, audio_cluster=100 + n,
                          audio_bytes=2048, audio_crc32=n + 10,
                          audio_lba=200 + n) for n in range(4)]
    return bg.patch_index(vp.build_index(songs), 0, 180000)


class S2IndexTests(unittest.TestCase):
    def setUp(self) -> None:
        self.records = [
            {"number": n + 1, "lba": 500000 + n * 100000, "frames": 100 + n,
             "bytes": (100 + n) * 153600, "sectors": (100 + n) * 300}
            for n in range(4)
        ]

    def test_sets_four_mv_descriptors_and_preserves_other_s1_fields(self) -> None:
        result = build_index_with_mv(base_index(), self.records, 180000)
        parsed = vp.parse_index(result)
        self.assertEqual(parsed["version"], 2)
        self.assertEqual(parsed["entries_crc32"], __import__("zlib").crc32(result[64:320]) & 0xFFFFFFFF)
        self.assertEqual([song["mv_lba"] for song in parsed["songs"]],
                         [record["lba"] for record in self.records])
        self.assertEqual([song["mv_frames"] for song in parsed["songs"]],
                         [record["frames"] for record in self.records])
        self.assertTrue(all(song["flags"] & vp.FLAG_MV for song in parsed["songs"]))
        self.assertTrue(all(song["flags"] & (vp.FLAG_COVER | vp.FLAG_AUDIO) ==
                            (vp.FLAG_COVER | vp.FLAG_AUDIO) for song in parsed["songs"]))
        self.assertEqual(bg.background_metadata(result)["base_lba"], 180000)

    def test_rejects_non_frame_aligned_or_empty_video(self) -> None:
        bad = [dict(record) for record in self.records]
        bad[2]["frames"] = 0
        with self.assertRaises(vp.PackError):
            build_index_with_mv(base_index(), bad, 180000)

        bad = [dict(record) for record in self.records]
        bad[1]["bytes"] -= 1
        with self.assertRaises(vp.PackError):
            build_index_with_mv(base_index(), bad, 180000)

    def test_rejects_overlapping_physical_ranges(self) -> None:
        bad = [dict(record) for record in self.records]
        bad[1]["lba"] = bad[0]["lba"] + bad[0]["sectors"] - 1
        with self.assertRaises(vp.PackError):
            build_index_with_mv(base_index(), bad, 180000)

    def test_rejects_records_out_of_song_order(self) -> None:
        with self.assertRaises(vp.PackError):
            build_index_with_mv(base_index(), list(reversed(self.records)), 180000)


if __name__ == "__main__":
    unittest.main()
