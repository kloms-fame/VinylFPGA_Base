#!/usr/bin/env python3
"""离线背景打包：保留原 FAT32 卡，扩容生成可供 FPGA 直接读取的新镜像。

python tools/pack_backgrounds.py --source doc/资源/sd卡/card_S6.img \
    --output-dir doc/资源/sd卡/stage4

不访问物理磁盘。扩容时保留原簇号、FAT 链、目录项及文件内容；数据区
整体平移后只更新 INDEX.BIN 的绝对音频/MV LBA 和条目 CRC。
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import sys
import zlib

from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageStat
from vinyl_packer import Fat32Image, PackError, parse_index

WIDTH, HEIGHT = 640, 480
FRAME_BYTES = WIDTH * HEIGHT * 2
FRAME_SECTORS = FRAME_BYTES // 512
FRAME_COUNT = 6
BACKGROUND_BYTES = FRAME_BYTES * FRAME_COUNT
BACKGROUND_NAME = b"BG      BIN"
EXT_MAGIC = b"BGR1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rgb565_le(image: Image.Image, dither: bool = False) -> bytes:
    if image.size != (WIDTH, HEIGHT):
        raise PackError("背景尺寸必须为640x480")
    pixels = image.convert("RGB").tobytes()
    if dither:
        # 电脑端4x4有序抖动减少16bit渐变色带，硬件仍直接读取RGB565。
        bayer = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
        words = array("H")
        for position, (r, g, b) in enumerate(zip(pixels[0::3], pixels[1::3], pixels[2::3])):
            threshold = bayer[(position // WIDTH) & 3][position & 3]
            r = min(255, r + threshold // 2)
            g = min(255, g + threshold // 4)
            b = min(255, b + threshold // 2)
            words.append(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
    else:
        words = array("H", (((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                            for r, g, b in zip(pixels[0::3], pixels[1::3], pixels[2::3])))
    if sys.byteorder != "little":
        words.byteswap()
    return words.tobytes()


def decode_rgb565(data: bytes) -> Image.Image:
    if len(data) != FRAME_BYTES:
        raise PackError("背景帧字节数必须为614400")
    words = array("H")
    words.frombytes(data)
    if sys.byteorder != "little":
        words.byteswap()
    pixels = bytearray()
    for word in words:
        r, g, b = (word >> 11) & 31, (word >> 5) & 63, word & 31
        pixels.extend(((r << 3) | (r >> 2), (g << 2) | (g >> 4),
                       (b << 3) | (b >> 2)))
    return Image.frombytes("RGB", (WIDTH, HEIGHT), bytes(pixels))


def cover_background(cover_bytes: bytes) -> Image.Image:
    with Image.open(io.BytesIO(cover_bytes)) as cover:
        fitted = ImageOps.fit(cover.convert("RGB"), (80, 60),
                             method=Image.Resampling.LANCZOS)
    # 模糊全部在电脑端完成；低分辨率预模糊压掉封面文字/人像细节。
    blurred = fitted.filter(ImageFilter.GaussianBlur(7)).resize(
        (WIDTH, HEIGHT), Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(18))
    blurred = ImageEnhance.Color(blurred).enhance(0.65)
    mean = ImageStat.Stat(blurred.convert("L")).mean[0]
    if mean > 0:
        blurred = ImageEnhance.Brightness(blurred).enhance(112 / mean)
    # 留足文字对比，限制高亮封面产生的明亮大片区域。
    return blurred.point(lambda value: max(48, min(148, value)))


def art_background() -> Image.Image:
    pixels = bytearray()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            blue = math.exp(-(((x - 120) / 280) ** 2 + ((y - 100) / 230) ** 2))
            violet = math.exp(-(((x - 540) / 290) ** 2 + ((y - 370) / 260) ** 2))
            pixels.extend((round(80 + 9 * blue + 27 * violet),
                           round(83 + 23 * blue + 9 * violet),
                           round(95 + 30 * blue + 29 * violet)))
    return Image.frombytes("RGB", (WIDTH, HEIGHT), bytes(pixels))


def art_background_two() -> Image.Image:
    """低饱和暖金/青灰光晕，与原蓝紫艺术图形成区别。"""
    pixels = bytearray()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            gold = math.exp(-(((x - 170) / 300) ** 2 + ((y - 330) / 230) ** 2))
            teal = math.exp(-(((x - 540) / 250) ** 2 + ((y - 90) / 260) ** 2))
            pixels.extend((round(86 + 33 * gold + 6 * teal),
                           round(88 + 21 * gold + 21 * teal),
                           round(88 + 5 * gold + 24 * teal)))
    return Image.frombytes("RGB", (WIDTH, HEIGHT), bytes(pixels))


def patch_index(index: bytes, lba_delta: int, background_lba: int) -> bytes:
    info = parse_index(index)
    if not 0 < background_lba <= 0xFFFFFFFF - FRAME_COUNT * FRAME_SECTORS:
        raise PackError("背景LBA为零或越界")
    patched = bytearray(index)
    for number, song in enumerate(info["songs"]):
        entry = 64 + number * 64
        offsets = [28] if song["flags"] & 2 else []
        if song["mv_frames"]:
            offsets.append(56)
        for offset in offsets:
            original = struct.unpack_from("<I", index, entry + offset)[0]
            updated = original + lba_delta
            if not 0 < updated <= 0xFFFFFFFF:
                raise PackError("媒体LBA搬迁后越界")
            struct.pack_into("<I", patched, entry + offset, updated)
    patched[32:36] = EXT_MAGIC
    struct.pack_into("<III", patched, 36, background_lba, FRAME_BYTES, FRAME_COUNT)
    payload = patched[64:64 + info["count"] * 64]
    struct.pack_into("<I", patched, 16, zlib.crc32(payload) & 0xFFFFFFFF)
    parse_index(bytes(patched))
    return bytes(patched)


def background_metadata(index: bytes) -> dict | None:
    parse_index(index)
    if index[32:36] != EXT_MAGIC:
        return None
    lba, frame_bytes, count = struct.unpack_from("<III", index, 36)
    if (frame_bytes != FRAME_BYTES or count not in (5, FRAME_COUNT) or not lba or
            lba > 0xFFFFFFFF - count * FRAME_SECTORS):
        raise PackError("BGR1背景参数非法")
    return {"base_lba": lba, "frame_bytes": frame_bytes,
            "frame_sectors": FRAME_SECTORS, "frame_count": count}


def copy_span(source, output, source_offset: int, target_offset: int, size: int):
    source.seek(source_offset)
    output.seek(target_offset)
    while size:
        chunk = source.read(min(size, 1 << 20))
        if not chunk:
            raise PackError("原镜像数据被截断")
        output.write(chunk)
        size -= len(chunk)


def grow_fat32(source: Fat32Image, output: Path, size_mib: int) -> int:
    total_bytes = size_mib * (1 << 20)
    total_sectors = total_bytes // 512 - source.partition_lba
    if total_bytes <= source.image_bytes:
        raise PackError("新镜像必须大于原镜像")
    if total_sectors > 0xFFFFFFFF:
        raise PackError("新FAT32卷超过32位扇区限制")
    fat_size = source.fat_size
    while True:
        clusters = (total_sectors - source.reserved_sectors - source.num_fats * fat_size) // source.sectors_per_cluster
        required = (4 * (clusters + 2) + 511) // 512
        if required <= fat_size:
            break
        fat_size = required
    if clusters < 65525 or clusters >= 0x0FFFFFF5:
        raise PackError("扩容后的簇数量不符合FAT32")
    new_data_lba = source.partition_lba + source.reserved_sectors + source.num_fats * fat_size
    delta = new_data_lba - source.data_start_lba
    old_data_bytes = (source.total_sectors - source.reserved_sectors - source.fat_span) * 512
    with output.open("w+b") as target:
        target.truncate(total_bytes)
        copy_span(source.fh, target, 0, 0, source.fat_start_lba * 512)
        for copy in range(source.num_fats):
            copy_span(source.fh, target,
                      (source.fat_start_lba + copy * source.fat_size) * 512,
                      (source.fat_start_lba + copy * fat_size) * 512,
                      source.fat_size * 512)
        copy_span(source.fh, target, source.data_start_lba * 512,
                  new_data_lba * 512, old_data_bytes)
        boot = bytearray(source.read_sector(source.partition_lba))
        struct.pack_into("<H", boot, 19, 0)
        struct.pack_into("<II", boot, 32, total_sectors, fat_size)
        target.seek(source.partition_lba * 512)
        target.write(boot)
        backup_boot = struct.unpack_from("<H", boot, 50)[0]
        if 0 < backup_boot < source.reserved_sectors:
            target.seek((source.partition_lba + backup_boot) * 512)
            target.write(boot)
        fsinfo_sector = struct.unpack_from("<H", boot, 48)[0]
        if 0 < fsinfo_sector < source.reserved_sectors:
            fsinfo = bytearray(source.read_sector(source.partition_lba + fsinfo_sector))
            # 旧测试卡的FSInfo可能全零；新镜像写规范签名，空闲统计标为未知。
            struct.pack_into("<I", fsinfo, 0, 0x41615252)
            struct.pack_into("<I", fsinfo, 484, 0x61417272)
            struct.pack_into("<II", fsinfo, 488, 0xFFFFFFFF, 0xFFFFFFFF)
            struct.pack_into("<I", fsinfo, 508, 0xAA550000)
            target.seek((source.partition_lba + fsinfo_sector) * 512)
            target.write(fsinfo)
            if 0 < backup_boot and backup_boot + fsinfo_sector < source.reserved_sectors:
                target.seek((source.partition_lba + backup_boot + fsinfo_sector) * 512)
                target.write(fsinfo)
        if source.partition_lba:
            mbr = bytearray(source.read_sector(0))
            struct.pack_into("<I", mbr, 446 + 12, total_sectors)
            target.seek(0)
            target.write(mbr)
    return delta


def append_background(volume: Fat32Image, data: bytes) -> int:
    if len(data) != BACKGROUND_BYTES:
        raise PackError("BG.BIN必须包含五帧，共3072000字节")
    if any(entry.name.upper() == "BG.BIN" for entry in volume.root_entries()):
        raise PackError("原卡已有BG.BIN，拒绝覆盖")
    directory_lba, directory_offset = volume.free_root_slot()
    cluster_bytes = 512 * volume.sectors_per_cluster
    needed = (len(data) + cluster_bytes - 1) // cluster_bytes
    # 一次读FAT，避免数十万个逐扇区flush；寻找完整连续空闲区。
    volume.fh.seek(volume.fat_start_lba * 512)
    fat = bytearray(volume.fh.read(volume.fat_size * 512))
    consecutive = 0
    for cluster in range(2, volume.max_cluster):
        free = struct.unpack_from("<I", fat, cluster * 4)[0] & 0x0FFFFFFF == 0
        consecutive = consecutive + 1 if free else 0
        if consecutive == needed:
            first = cluster - needed + 1
            break
    else:
        raise PackError("新镜像没有足够连续簇")
    for cluster in range(first, first + needed):
        value = cluster + 1 if cluster + 1 < first + needed else 0x0FFFFFFF
        struct.pack_into("<I", fat, cluster * 4, value)
    for copy in range(volume.num_fats):
        volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
        volume.fh.write(fat)
    base_lba = volume.cluster_lba(first)
    volume.fh.seek(base_lba * 512)
    volume.fh.write(data)
    volume.fh.write(bytes(needed * cluster_bytes - len(data)))
    volume.fh.flush()
    volume.write_root_entry(directory_lba, directory_offset, BACKGROUND_NAME,
                            first, len(data))
    return base_lba


def pack(source_path: Path, output_dir: Path, size_mib: int = 128) -> dict:
    source_path = source_path.resolve()
    output_dir = output_dir.resolve()
    target = output_dir / "card_STAGE4.img"
    if target.resolve() == source_path:
        raise PackError("输出镜像不能覆盖原卡")
    if target.exists():
        raise PackError("输出镜像已存在，选择新的输出目录")
    original_hash = sha256_file(source_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    with Fat32Image(source_path) as source:
        original_entries = list(source.root_entries())
        index_entry = source.find_root_file("INDEX.BIN")
        if index_entry.size != 512:
            raise PackError("原INDEX.BIN必须正好512字节")
        original_index = source.read_file(index_entry.first_cluster, index_entry.size)
        info = parse_index(original_index)
        if info["count"] != 4:
            raise PackError("当前背景协议要求四首歌曲")
        original_files = {}
        for entry in original_entries:
            if entry.attr & 0x18:
                continue
            content = source.read_file(entry.first_cluster, entry.size) if entry.size else b""
            if len(content) != entry.size:
                raise PackError(f"{entry.name}原文件链截断")
            original_files[entry.name] = {"bytes": entry.size,
                                          "sha256": hashlib.sha256(content).hexdigest()}
        frames = []
        previews = []
        for number, song in enumerate(info["songs"]):
            cover = source.read_file(song["cover_cluster"], song["cover_bytes"])
            if zlib.crc32(cover) & 0xFFFFFFFF != song["cover_crc32"]:
                raise PackError(f"曲目{number + 1}封面CRC错误")
            if song["flags"] & 2:
                audio = source.read_file(song["audio_cluster"], song["audio_bytes"])
                if zlib.crc32(audio) & 0xFFFFFFFF != song["audio_crc32"]:
                    raise PackError(f"曲目{number + 1}音频CRC错误")
            frames.append(rgb565_le(cover_background(cover), dither=True))
            previews.append(f"song_{number + 1}_blur.png")
        frames.append(rgb565_le(art_background(), dither=True))
        previews.append("shared_art.png")
        frames.append(rgb565_le(art_background_two(), dither=True))
        previews.append("shared_art_2.png")
        delta = grow_fat32(source, target, size_mib)
    blob = b"".join(frames)
    with Fat32Image(target, writable=True) as volume:
        background_lba = append_background(volume, blob)
        updated_index = patch_index(original_index, delta, background_lba)
        relocated_index = volume.find_root_file("INDEX.BIN")
        index_sectors = (len(updated_index) + 511) // 512
        if index_sectors != 1:
            raise PackError("INDEX.BIN必须是单扇区")
        volume.write_sector(volume.cluster_lba(relocated_index.first_cluster), updated_index)
    with Fat32Image(target) as verify:
        for entry in verify.root_entries():
            if entry.name not in original_files or entry.name == "INDEX.BIN":
                continue
            restored = verify.read_file(entry.first_cluster, entry.size)
            if hashlib.sha256(restored).hexdigest() != original_files[entry.name]["sha256"]:
                raise PackError(f"{entry.name}搬迁回读不一致")
        background_entry = verify.find_root_file("BG.BIN")
        runs = verify.cluster_runs(background_entry.first_cluster)
        # 大簇可在文件尾带padding，但有效数据必须全部连续。
        if len(runs) != 1 or runs[0][0] != background_lba or runs[0][1] < FRAME_COUNT * FRAME_SECTORS:
            raise PackError("BG.BIN簇链不连续")
        verify.fh.seek(background_lba * 512)
        if verify.fh.read(BACKGROUND_BYTES) != blob:
            raise PackError("BG.BIN物理LBA回读不一致")
        on_card = verify.read_file(relocated_index.first_cluster, relocated_index.size)
        if on_card != updated_index:
            raise PackError("INDEX.BIN回读不一致")
        metadata = background_metadata(on_card)
        reparsed = parse_index(on_card)
        for song in reparsed["songs"]:
            if song["flags"] & 2:
                if song["audio_lba"] != verify.cluster_lba(song["audio_cluster"]):
                    raise PackError("搬迁音频起始LBA不一致")
                if len(verify.cluster_runs(song["audio_cluster"])) != 1:
                    raise PackError("音频不连续")
            if song["mv_frames"]:
                matches = [entry for entry in verify.root_entries()
                           if entry.first_cluster >= 2 and verify.cluster_lba(entry.first_cluster) == song["mv_lba"]]
                if len(matches) != 1 or matches[0].size != song["mv_frames"] * 153600 or len(verify.cluster_runs(matches[0].first_cluster)) != 1:
                    raise PackError("搬迁MV起始LBA/大小/连续性不一致")
        geometry = {key: getattr(verify, key) for key in
                    ("total_sectors", "fat_size", "data_start_lba", "sectors_per_cluster")}
    if sha256_file(source_path) != original_hash:
        raise PackError("原卡镜像hash发生变化")
    (output_dir / "BG.BIN").write_bytes(blob)
    (output_dir / "ART1.BIN").write_bytes(frames[4])
    (output_dir / "ART2.BIN").write_bytes(frames[5])
    (output_dir / "INDEX.BIN").write_bytes(updated_index)
    frame_report = []
    for number, (frame, preview) in enumerate(zip(frames, previews)):
        decode_rgb565(frame).save(output_dir / preview)
        frame_report.append({"number": number, "preview": preview,
                             "start_lba": background_lba + number * FRAME_SECTORS,
                             "sha256": hashlib.sha256(frame).hexdigest()})
    report = {"source": str(source_path), "source_sha256": original_hash,
              "image": str(target), "image_bytes": target.stat().st_size,
              "image_sha256": sha256_file(target), "geometry": geometry,
              "data_lba_delta": delta, "background": metadata,
              "background_sha256": hashlib.sha256(blob).hexdigest(),
              "index_entries_crc32": f"0x{reparsed['entries_crc32']:08X}",
              "songs": reparsed["songs"], "preserved_files": original_files,
              "frames": frame_report, "input_unchanged": True,
              "physical_background_readback": True}
    (output_dir / "background_pack_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--size-mib", type=int, default=128)
    args = parser.parse_args(argv)
    try:
        report = pack(args.source, args.output_dir, args.size_mib)
    except (PackError, OSError, ValueError) as error:
        print(f"PACK_BACKGROUND_FAILED: {error}", file=sys.stderr)
        return 1
    print(f"PACK_BACKGROUND_OK {report['image']} "
          f"base_lba={report['background']['base_lba']} frames={FRAME_COUNT} "
          f"crc={report['index_entries_crc32']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
