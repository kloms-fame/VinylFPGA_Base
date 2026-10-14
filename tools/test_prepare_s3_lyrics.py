import importlib.util
import sys
import struct
import unittest
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
            "Never gonna tell", " a lie and hurt ", "you"])
        self.assertTrue(all(len(text) <= 16 for _, text in rows))
        self.assertEqual([time for time, _ in rows], sorted(set(time for time, _ in rows)))

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
