"""背景格式、旧索引兼容及独立FAT32夹具的真实扩容回读测试。"""
from __future__ import annotations

import hashlib
import io
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from PIL import Image
from vinyl_packer import Fat32Image, IndexSong, PackError, build_index, parse_index
from pack_backgrounds import (BACKGROUND_BYTES, FRAME_BYTES, FRAME_COUNT, FRAME_SECTORS,
                              append_background, background_metadata,
                              decode_rgb565, grow_fat32, pack, patch_index,
                              rgb565_le, sha256_file)


def synthetic_card(path: Path, mbr: bool = False):
    """仅测试用独立FAT32夹具；生产工具不依赖测试builder。"""
    partition = 2048 if mbr else 0
    total = 73728
    fat_size = 576
    boot = bytearray(512)
    boot[0:3] = b"\xeb\x58\x90"
    struct.pack_into("<H", boot, 11, 512)
    boot[13] = 1
    struct.pack_into("<H", boot, 14, 32)
    boot[16] = 2
    boot[21] = 0xF8
    struct.pack_into("<III", boot, 28, partition, total, fat_size)
    struct.pack_into("<IHH", boot, 44, 2, 1, 6)
    boot[510:512] = b"\x55\xaa"
    with path.open("wb") as stream:
        stream.truncate((partition + total) * 512)
        if mbr:
            record = bytearray(512)
            record[446 + 4] = 0x0C
            struct.pack_into("<II", record, 446 + 8, partition, total)
            record[510:512] = b"\x55\xaa"
            stream.write(record)
        stream.seek(partition * 512)
        stream.write(boot)
        stream.seek((partition + 6) * 512)
        stream.write(boot)
    colors = [(200, 40, 30), (30, 180, 60), (30, 60, 200), (170, 70, 180)]
    covers = []
    for color in colors:
        stream = io.BytesIO()
        Image.new("RGB", (640, 480), color).save(stream, format="BMP")
        covers.append(stream.getvalue())
    audio = bytes(range(256)) * 32
    mv = b"\x1f\x00" * (320 * 240)
    with Fat32Image(path, writable=True) as volume:
        fat = bytearray(fat_size * 512)
        struct.pack_into("<III", fat, 0, 0x0FFFFFF8, 0xFFFFFFFF, 0x0FFFFFFF)
        next_cluster = 3
        root_lba = volume.cluster_lba(2)
        root = bytearray(512)

        def add(number, name, content):
            nonlocal next_cluster
            first = next_cluster
            clusters = (len(content) + 511) // 512
            for cluster in range(first, first + clusters):
                struct.pack_into("<I", fat, cluster * 4,
                                 cluster + 1 if cluster + 1 < first + clusters else 0x0FFFFFFF)
            next_cluster += clusters
            volume.fh.seek(volume.cluster_lba(first) * 512)
            volume.fh.write(content)
            off = number * 32
            root[off:off + 11] = name
            root[off + 11] = 0x20
            root[off + 13] = 17  # 目录时间元数据也必须原样保留。
            struct.pack_into("<H", root, off + 20, first >> 16)
            struct.pack_into("<HI", root, off + 26, first & 0xFFFF, len(content))
            return first

        cover_clusters = [add(i, f"PIC{i+1}    BMP".encode(), cover)
                          for i, cover in enumerate(covers)]
        audio_cluster = add(4, b"AUDIO   PCM", audio)
        mv_cluster = add(5, b"TRACK1  MV ", mv)
        songs = [IndexSong(title=f"Song {i+1}", flags=11 if i == 0 else 3,
                           cover_cluster=cover_clusters[i], cover_bytes=len(covers[i]),
                           cover_crc32=zlib.crc32(covers[i]), audio_cluster=audio_cluster,
                           audio_bytes=len(audio), audio_crc32=zlib.crc32(audio),
                           audio_lba=volume.cluster_lba(audio_cluster),
                           mv_lba=volume.cluster_lba(mv_cluster) if i == 0 else 0,
                           mv_frames=1 if i == 0 else 0) for i in range(4)]
        index = bytearray(build_index(songs))
        index[24:32] = b"KEEPHEAD"
        index[48:64] = b"keep-reserved-16"
        index[400:416] = b"keep-index-tail!"
        add(6, b"INDEX   BIN", index)
        for copy in range(2):
            volume.fh.seek((volume.fat_start_lba + copy * fat_size) * 512)
            volume.fh.write(fat)
        volume.write_sector(root_lba, root)


class BackgroundFormatTests(unittest.TestCase):
    def test_rgb565_little_endian_golden_and_decode(self):
        image = Image.new("RGB", (640, 480), (255, 0, 0))
        image.putpixel((1, 0), (0, 255, 0))
        image.putpixel((2, 0), (0, 0, 255))
        binary = rgb565_le(image)
        self.assertEqual(len(binary), FRAME_BYTES)
        self.assertEqual(binary[:6], bytes.fromhex("00f8e0071f00"))
        restored = decode_rgb565(binary)
        self.assertEqual([restored.getpixel((i, 0)) for i in range(3)],
                         [(255, 0, 0), (0, 255, 0), (0, 0, 255)])

    def test_reject_wrong_frame_dimensions_and_size(self):
        with self.assertRaises(PackError):
            rgb565_le(Image.new("RGB", (320, 240)))
        with self.assertRaises(PackError):
            decode_rgb565(bytes(FRAME_BYTES - 1))

    def test_dither_is_deterministic_and_only_changes_one_quantum(self):
        image = Image.new("RGB", (640, 480), (101, 101, 101))
        first = rgb565_le(image, dither=True)
        self.assertEqual(first, rgb565_le(image, dither=True))
        restored = decode_rgb565(first)
        colors = {restored.getpixel((x, y)) for x in range(4) for y in range(4)}
        self.assertGreater(len(colors), 1)
        for color in colors:
            self.assertTrue(all(abs(channel - 101) <= 9 for channel in color))

    def test_old_v1_and_v2_index_remain_parseable(self):
        for version in (1, 2):
            original = bytearray(build_index([IndexSong() for _ in range(4)]))
            struct.pack_into("<H", original, 8, version)
            self.assertIsNone(background_metadata(original))
            patched = patch_index(original, 0, 10000)
            self.assertEqual(parse_index(patched), parse_index(original))
            self.assertEqual(background_metadata(patched)["frame_count"], FRAME_COUNT)
            self.assertEqual(patched[64:], original[64:])

    def test_bad_index_crc_rejected_before_extension(self):
        original = bytearray(build_index([IndexSong() for _ in range(4)]))
        original[64] ^= 1
        with self.assertRaises(PackError):
            patch_index(original, 0, 10000)

    def test_background_lba_and_header_rejection(self):
        original = build_index([IndexSong() for _ in range(4)])
        for lba in (0, -1, 0xFFFFFFFF - FRAME_COUNT * FRAME_SECTORS + 1):
            with self.assertRaises(PackError):
                patch_index(original, 0, lba)
        legal = patch_index(original, 0, 10000)
        for offset, value in ((36, 0), (40, 614399), (44, 4), (36, 0xFFFFFFFF)):
            corrupted = bytearray(legal)
            struct.pack_into("<I", corrupted, offset, value)
            with self.assertRaises(PackError):
                background_metadata(corrupted)

    def test_legacy_five_frame_background_extension_remains_parseable(self):
        original = build_index([IndexSong() for _ in range(4)])
        legacy = bytearray(patch_index(original, 0, 10000))
        struct.pack_into("<I", legacy, 44, 5)
        metadata = background_metadata(legacy)
        self.assertEqual(metadata["frame_count"], 5)
        self.assertEqual(metadata["base_lba"], 10000)
        self.assertEqual(metadata["frame_bytes"], FRAME_BYTES)
        self.assertEqual(parse_index(legacy), parse_index(original))
        # 旧格式的溢出边界按5帧计算，不得因生产输出扩为6帧而误拒绝。
        struct.pack_into("<I", legacy, 36, 0xFFFFFFFF - 5 * FRAME_SECTORS)
        self.assertEqual(background_metadata(legacy)["frame_count"], 5)
        struct.pack_into("<I", legacy, 36, 0xFFFFFFFF - 5 * FRAME_SECTORS + 1)
        with self.assertRaises(PackError):
            background_metadata(legacy)

    def test_new_six_frame_extension_and_crc_remain_valid(self):
        original = build_index([IndexSong() for _ in range(4)])
        patched = patch_index(original, 0, 10000)
        self.assertEqual(FRAME_COUNT, 6)
        self.assertEqual(background_metadata(patched)["frame_count"], FRAME_COUNT)
        info = parse_index(patched)
        payload = patched[64:64 + info["count"] * 64]
        self.assertEqual(info["entries_crc32"], zlib.crc32(payload) & 0xFFFFFFFF)
        self.assertEqual(patched[64:], original[64:])


class BackgroundImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temp.name)
        cls.source = cls.directory / "old.img"
        synthetic_card(cls.source)
        cls.source_hash = sha256_file(cls.source)
        cls.report = pack(cls.source, cls.directory / "packed", 48)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_original_input_preserved(self):
        self.assertEqual(self.source_hash, sha256_file(self.source))
        self.assertTrue(self.report["input_unchanged"])

    def test_all_original_files_metadata_and_indices_preserved(self):
        with Fat32Image(self.source) as original, Fat32Image(Path(self.report["image"])) as new:
            old_index = original.find_root_file("INDEX.BIN")
            new_index = new.find_root_file("INDEX.BIN")
            old_bytes = original.read_file(old_index.first_cluster, old_index.size)
            new_bytes = new.read_file(new_index.first_cluster, new_index.size)
            self.assertEqual(new_bytes[24:32], old_bytes[24:32])
            self.assertEqual(new_bytes[48:64], old_bytes[48:64])
            self.assertEqual(new_bytes[320:], old_bytes[320:])
            self.assertEqual(original.read_sector(original.cluster_lba(2))[:7*32],
                             new.read_sector(new.cluster_lba(2))[:7*32])
            old_songs = parse_index(old_bytes)["songs"]
            new_songs = parse_index(new_bytes)["songs"]
            delta = self.report["data_lba_delta"]
            for old_song, new_song in zip(old_songs, new_songs):
                for key in ("title", "flags", "cover_cluster", "cover_crc32", "audio_cluster", "audio_crc32", "audio_bytes", "mv_frames"):
                    self.assertEqual(old_song[key], new_song[key])
                self.assertEqual(new_song["audio_lba"], old_song["audio_lba"] + delta)
                self.assertEqual(new_song["mv_lba"], old_song["mv_lba"] + delta if old_song["mv_lba"] else 0)

    def test_all_frames_contiguous_physical_readback_hashes(self):
        with Fat32Image(Path(self.report["image"])) as volume:
            entry = volume.find_root_file("BG.BIN")
            self.assertEqual(entry.size, BACKGROUND_BYTES)
            base = self.report["background"]["base_lba"]
            self.assertEqual(volume.cluster_runs(entry.first_cluster),
                             [(base, FRAME_COUNT * FRAME_SECTORS)])
            self.assertEqual(len(self.report["frames"]), FRAME_COUNT)
            for number, frame in enumerate(self.report["frames"]):
                volume.fh.seek((base + number * FRAME_SECTORS) * 512)
                data = volume.fh.read(FRAME_BYTES)
                self.assertEqual(hashlib.sha256(data).hexdigest(), frame["sha256"])
                self.assertEqual(frame["start_lba"], base + number * FRAME_SECTORS)
            self.assertEqual(len(set(frame["sha256"] for frame in self.report["frames"])), FRAME_COUNT)

    def test_art1_and_art2_exports_match_on_card_frames_and_previews(self):
        output = Path(self.report["image"]).parent
        blob = (output / "BG.BIN").read_bytes()
        self.assertEqual(len(blob), BACKGROUND_BYTES)
        for number, name, preview in ((4, "ART1.BIN", "shared_art.png"),
                                     (5, "ART2.BIN", "shared_art_2.png")):
            exported = (output / name).read_bytes()
            self.assertEqual(len(exported), FRAME_BYTES)
            self.assertEqual(exported, blob[number * FRAME_BYTES:(number + 1) * FRAME_BYTES])
            self.assertEqual(hashlib.sha256(exported).hexdigest(),
                             self.report["frames"][number]["sha256"])
            with Image.open(output / preview) as restored:
                self.assertEqual(restored.size, (640, 480))
                self.assertEqual(restored.convert("RGB").tobytes(),
                                 decode_rgb565(exported).tobytes())
        self.assertNotEqual((output / "ART1.BIN").read_bytes(),
                            (output / "ART2.BIN").read_bytes())

    def test_refuse_overwrite_or_undersize_or_wrong_blob(self):
        with self.assertRaises(PackError):
            pack(self.source, self.directory / "packed", 48)
        with Fat32Image(self.source) as volume:
            with self.assertRaises(PackError):
                grow_fat32(volume, self.directory / "too-small.img", 32)
        with Fat32Image(Path(self.report["image"]), writable=True) as volume:
            with self.assertRaises(PackError):
                append_background(volume, bytes(BACKGROUND_BYTES - 1))
            with self.assertRaises(PackError):
                append_background(volume, bytes(BACKGROUND_BYTES))

    def test_mbr_growth_rewrites_partition_and_backup_bpb(self):
        source_path = self.directory / "mbr.img"
        target = self.directory / "mbr-grown.img"
        synthetic_card(source_path, mbr=True)
        with Fat32Image(source_path) as source:
            delta = grow_fat32(source, target, 48)
        with Fat32Image(target) as volume:
            self.assertGreater(delta, 0)
            self.assertEqual(volume.partition_lba, 2048)
            self.assertEqual(struct.unpack_from("<I", volume.read_sector(0), 446 + 12)[0], volume.total_sectors)
            self.assertEqual(volume.read_sector(2048), volume.read_sector(2054))
            fsinfo = volume.read_sector(2049)
            self.assertEqual(struct.unpack_from("<I", fsinfo, 0)[0], 0x41615252)
            self.assertEqual(struct.unpack_from("<I", fsinfo, 484)[0], 0x61417272)
            self.assertEqual(struct.unpack_from("<I", fsinfo, 508)[0], 0xAA550000)
            self.assertEqual(fsinfo, volume.read_sector(2055))
            self.assertGreaterEqual((volume.total_sectors - 32 - volume.fat_span), 65525)


if __name__ == "__main__":
    unittest.main()
