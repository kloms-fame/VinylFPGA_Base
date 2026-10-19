import importlib.util
import sys
import struct
import unittest
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "prepare_s3_lyrics", Path(__file__).with_name("prepare_s3_lyrics.py"))
S3 = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = S3
SPEC.loader.exec_module(S3)

GEN_SPEC = importlib.util.spec_from_file_location(
    "gen_lrc_assets", Path(__file__).with_name("gen_lrc_assets.py"))
GEN = importlib.util.module_from_spec(GEN_SPEC)
sys.modules[GEN_SPEC.name] = GEN
GEN_SPEC.loader.exec_module(GEN)


class SrtConversionTests(unittest.TestCase):
    def test_parse_srt_cleans_markup_and_decodes_entities(self):
        cues = S3.parse_srt_text(
            "1\n00:00:01,250 --> 00:00:02,500\n<i>你&amp;我</i>\n\n"
            "2\n00:00:02,500 --> 00:00:03,000\n第二行\n")
        self.assertEqual([(c.start_ms, c.end_ms, c.text) for c in cues], [
            (1250, 2500, "你&我"), (2500, 3000, "第二行")])

    def test_split_long_cue_into_monotonic_bounded_display_rows(self):
        cues = [S3.Cue(0, 2000, "Never gonna tell a lie and hurt you")]
        rows = S3.make_display_rows(cues)
        self.assertEqual([row[1] for row in rows], [
            "Never gonna tell", "a lie and hurt", "you"])
        self.assertEqual([time for time, _ in rows], [0, 969, 1818])
        self.assertTrue(all(len(text) <= 16 for _, text in rows))
        self.assertEqual([time for time, _ in rows], sorted(set(time for time, _ in rows)))

    def test_music_annotations_do_not_become_standalone_lyric_rows(self):
        cue = S3.parse_srt_text("1\n00:00:01,000 --> 00:00:04,000\n♪ 一边走来的你让我如此蠢蠢欲动时 ♪\n")
        self.assertEqual(cue[0].text, "一边走来的你让我如此蠢蠢欲动时")
        self.assertFalse(any(text in {"♪", "♫"} for _, text in S3.make_display_rows(cue)))

    def test_rejects_timestamp_spill_outside_short_source_cue(self):
        with self.assertRaises(S3.LyricError):
            S3.make_display_rows([S3.Cue(0, 1, "Never gonna tell a lie and hurt you")])

    def test_manual_merge_and_offset_preserve_source_intervals(self):
        cues = [S3.Cue(0, 100, "a"), S3.Cue(100, 200, "b"), S3.Cue(200, 300, "c")]
        cal = {"tracks": {"1": {"timeline_offset_ms": 50, "replace_text": {"1": "x"},
                               "merge_cues": [{"first": 2, "last": 3, "text": "bc"}]}}}
        result = S3.apply_manual_calibration(cues, 1, cal)
        self.assertEqual([(c.start_ms, c.end_ms, c.text) for c in result],
                         [(50, 150, "x"), (150, 350, "bc")])

    def test_manual_merge_rejects_overlapping_source_ranges(self):
        cues = [S3.Cue(0, 100, "a"), S3.Cue(100, 200, "b"), S3.Cue(200, 300, "c")]
        cal = {"tracks": {"1": {"merge_cues": [
            {"first": 1, "last": 2, "text": "ab"}, {"first": 2, "last": 3, "text": "bc"}]}}}
        with self.assertRaises(S3.LyricError):
            S3.apply_manual_calibration(cues, 1, cal)

    def test_prepare_finishes_manifest_after_applying_calibration(self):
        # Exercise the orchestration through manifest completion without a GB
        # image or physical media; encoding, CRC and manifest code remain real.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rel in ("src/display", "src/include"):
                (root / rel).mkdir(parents=True)
            s2 = root / "s2.img"
            s2.write_bytes(b"S2")
            tracks = [{"song_id": i, "title": "T", "display_title": "T", "artist": "A",
                       "rows": [(100, "a")], "lrc": f"track{i+1}.lrc", "source_srt": "source.srt",
                       "source_srt_sha256": "digest", "source_cue_count": 1, "cue_count": 1,
                       "timeline_offset_ms": 0, "manual_calibration_sha256": "calibrated"}
                      for i in range(4)]
            def pack(_s2, target, lyr):
                target.write_bytes(b"S3")
                return {"sha256": S3.sha256_file(lyr), "lba": 1, "index_entries_crc32": "0x1"}
            def generate(_manifest, out):
                for rel in ("src/display/song_text_rom.v", "src/display/song_font_rom.v", "src/include/song_text_geom.vh"):
                    path = out / rel
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("generated", encoding="utf-8")
                return {"bank_chars": [["a"], ["b"]], "font_depth": 8192}
            args = SimpleNamespace(project=root, output=root / "out", s2_image=s2,
                                   expected_s2_sha256=S3.sha256_file(s2))
            with patch.object(S3, "build_tracks", return_value=(tracks, {i: {"source_duration_seconds": 1} for i in range(1, 5)})), \
                 patch.object(S3, "add_lyr2_to_s2", side_effect=pack), \
                 patch.object(S3.assets, "generate_song_text_assets", side_effect=generate):
                manifest = S3.prepare(args)
            self.assertTrue(manifest["verified"]["manual_calibration_applied"])
            self.assertTrue((root / "out/S3_lyrics_manifest.json").is_file())

    def test_lyr2_round_trip_and_crc_rejects_corruption(self):
        tracks = [{"song_id": 0, "title": "歌曲", "artist": "歌手",
                   "rows": [(1234, "歌词内容"), (9000, "第二句")] }]
        encoded = S3.encode_lyr2(tracks)
        decoded = S3.decode_lyr2(encoded)
        self.assertEqual(decoded, tracks)
        self.assertEqual(encoded[:4], b"LYR2")
        broken = bytearray(encoded)
        broken[12] ^= 1
        with self.assertRaises(S3.LyricError):
            S3.decode_lyr2(bytes(broken))

    def test_rejects_unsorted_or_duplicate_timestamp_rows(self):
        tracks = [{"song_id": 0, "title": "T", "artist": "A",
                   "rows": [(100, "a"), (100, "b")]}]
        with self.assertRaises(S3.LyricError):
            S3.encode_lyr2(tracks)

    def test_song_text_rom_splits_wide_records_into_bram_sized_words(self):
        char_index = {char: index for index, char in enumerate(" NO LYRICS A")}
        tracks = [{"char_index": char_index, "lines": [(0x12345, "A")],
                   "title": "A", "artist": "A"} for _ in range(4)]
        rom = GEN.emit_song_text_rom(tracks, list(char_index))
        self.assertIn("reg [31:0] glyph_mem_0 [0:3];", rom)
        self.assertIn("reg [22:0] time_length_mem [0:3];", rom)
        self.assertNotIn("reg [164:0] line_mem", rom)
        self.assertIn("time_length_mem[0] = 23'h2468A1;", rom)
        self.assertIn("line_glyph_word_0 <= glyph_mem_0[line_addr];", rom)
        self.assertIn("assign line_glyphs = line_valid ? {line_glyph_word_3, line_glyph_word_2, line_glyph_word_1, line_glyph_word_0} : 128'd0;", rom)


if __name__ == "__main__":
    unittest.main()
