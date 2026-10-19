#!/usr/bin/env python3
"""Prepare real four-song SRT lyrics, LYR2 data, generated ROMs and an S3 SD image.

This tool only reads source media and image files. It never opens a physical
disk. The same normalized timed rows feed both the LYR2 file and synthesized
song-text ROM, keeping card and firmware content identical.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import re
import shutil
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack_backgrounds as bg  # noqa: E402
import prepare_s1_media as s1  # noqa: E402
import vinyl_packer as vp  # noqa: E402
import gen_lrc_assets as assets  # noqa: E402

LYR2_VERSION = 2
MAX_ROWS_PER_TRACK = 128
MAX_CHARS_PER_ROW = 16
LYRICS_NAME = "LYRICS.BIN"
COPY_CHUNK = 4 * 1024 * 1024
EXPECTED_S2_SHA256 = "5061694a17e27063cd157d90944792eabc17973b99abec1fce9c1ebd81084948"


class LyricError(RuntimeError):
    pass


@dataclass(frozen=True)
class Cue:
    start_ms: int
    end_ms: int
    text: str
    character_wrap: bool = False


def parse_timecode(value: str) -> int:
    match = re.fullmatch(r"(\d{2,}):(\d{2}):(\d{2}),(\d{1,3})", value.strip())
    if not match:
        raise LyricError(f"SRT 时间格式无效：{value!r}")
    hours, minutes, seconds = map(int, match.group(1, 2, 3))
    if minutes >= 60 or seconds >= 60:
        raise LyricError(f"SRT 时间字段越界：{value!r}")
    fraction = match.group(4).ljust(3, "0")
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + int(fraction)


def clean_subtitle_text(lines: list[str]) -> str:
    text = " ".join(line.strip() for line in lines if line.strip())
    text = text.replace(r"\N", " ").replace(r"\n", " ")
    text = re.sub(r"<[^>]*>", "", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    # Caption music markers are decoration, not separately timed lyrics. They
    # otherwise consume a row by themselves beside long unspaced CJK text.
    return text.strip(" \t♪♫")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(COPY_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_srt_text(text: str) -> list[Cue]:
    cues: list[Cue] = []
    for block in re.split(r"\r?\n\s*\r?\n", text.strip()):
        lines = block.splitlines()
        time_index = next((i for i, line in enumerate(lines) if "-->" in line), None)
        if time_index is None or time_index + 1 >= len(lines):
            continue
        start_raw, end_raw = (part.strip().split()[0]
                              for part in lines[time_index].split("-->", 1))
        start_ms, end_ms = parse_timecode(start_raw), parse_timecode(end_raw)
        lyric = clean_subtitle_text(lines[time_index + 1:])
        if not lyric:
            continue
        if end_ms <= start_ms:
            raise LyricError(f"SRT 字幕结束时间不晚于开始时间：{block[:100]!r}")
        cues.append(Cue(start_ms, end_ms, lyric))
    if not cues:
        raise LyricError("SRT 中没有可显示的有效字幕")
    cues.sort(key=lambda cue: (cue.start_ms, cue.end_ms))
    merged: list[Cue] = []
    for cue in cues:
        if merged and cue.start_ms == merged[-1].start_ms:
            prior = merged[-1]
            merged[-1] = Cue(prior.start_ms, max(prior.end_ms, cue.end_ms),
                             f"{prior.text} {cue.text}")
        else:
            merged.append(cue)
    return merged


def wrap_text(text: str, width: int = MAX_CHARS_PER_ROW,
              prefer_words: bool = True) -> list[str]:
    # Prefer word boundaries when space-delimited lyrics exceed the 16-glyph
    # line. CJK text without spaces still uses the exact hardware cell limit.
    rows: list[str] = []
    remaining = text
    while len(remaining) > width:
        split_at = remaining.rfind(" ", 0, width + 1) if prefer_words else -1
        if split_at <= 0:
            split_at = width
        rows.append(remaining[:split_at].rstrip())
        remaining = remaining[split_at:].lstrip()
    if remaining:
        rows.append(remaining)
    return rows


def make_display_rows(cues: list[Cue]) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    for index, cue in enumerate(cues):
        parts = wrap_text(cue.text, prefer_words=not cue.character_wrap)
        next_start = cues[index + 1].start_ms if index + 1 < len(cues) else cue.end_ms
        display_end = max(cue.start_ms + 1, min(cue.end_ms, next_start))
        duration = display_end - cue.start_ms
        if duration < len(parts):
            raise LyricError(f"字幕时段不足以容纳 {len(parts)} 行：{cue}")
        part_weights = [max(1, len(part)) for part in parts]
        total_weight = sum(part_weights)
        elapsed_weight = 0
        for part, part_weight in zip(parts, part_weights):
            row_time = cue.start_ms + (duration * elapsed_weight // total_weight)
            if result and row_time <= result[-1][0]:
                row_time = result[-1][0] + 1
            result.append((row_time, part))
            elapsed_weight += part_weight
    if len(result) > MAX_ROWS_PER_TRACK:
        raise LyricError(f"处理后共 {len(result)} 行，超过每曲 {MAX_ROWS_PER_TRACK} 行上限")
    if any(len(row) > MAX_CHARS_PER_ROW for _, row in result):
        raise LyricError("处理后存在超过16字形的歌词行")
    return result


def apply_manual_calibration(cues: list[Cue], song_number: int,
                             calibration: dict) -> list[Cue]:
    """Apply reviewed, one-based source-cue corrections without editing SRTs."""
    track = calibration.get("tracks", {}).get(str(song_number), {})
    offset_ms = int(track.get("timeline_offset_ms", 0))
    corrected = []
    for cue in cues:
        start_ms = max(0, cue.start_ms + offset_ms)
        end_ms = cue.end_ms + offset_ms
        if end_ms <= start_ms:
            raise LyricError(f"歌曲{song_number} 校准后字幕时段无效：{cue}")
        corrected.append(Cue(start_ms, end_ms, cue.text))
    replacements = {int(index): str(text)
                    for index, text in track.get("replace_text", {}).items()}
    merges = sorted(track.get("merge_cues", []), key=lambda item: int(item["first"]))
    merged_ranges: dict[int, tuple[int, str]] = {}
    consumed: set[int] = set()
    prior_end = 0
    for item in merges:
        first, last = int(item["first"]), int(item["last"])
        if first < 1 or last < first or last > len(corrected) or first <= prior_end:
            raise LyricError(f"歌曲{song_number} 人工合并字幕范围无效：{item}")
        if any(index in replacements for index in range(first, last + 1)):
            raise LyricError(f"歌曲{song_number} 合并字幕与文本修正重复：{item}")
        merged_ranges[first] = (last, str(item["text"]))
        consumed.update(range(first + 1, last + 1))
        prior_end = last
    unknown = [index for index in replacements if not 1 <= index <= len(corrected)]
    if unknown:
        raise LyricError(f"歌曲{song_number} 人工文本修正序号越界：{unknown}")
    character_wrap = {int(index) for index in track.get("character_wrap_cues", [])}
    if any(not 1 <= index <= len(corrected) for index in character_wrap):
        raise LyricError(f"歌曲{song_number} 强制字格换行序号越界")
    result: list[Cue] = []
    index = 1
    while index <= len(corrected):
        if index in consumed:
            index += 1
            continue
        if index in merged_ranges:
            last, text = merged_ranges[index]
            result.append(Cue(corrected[index - 1].start_ms,
                              corrected[last - 1].end_ms, text))
            index = last + 1
        else:
            cue = corrected[index - 1]
            result.append(Cue(cue.start_ms, cue.end_ms,
                              replacements.get(index, cue.text),
                              index in character_wrap))
            index += 1
    return result


def encode_lyr2(tracks: list[dict]) -> bytes:
    if not 1 <= len(tracks) <= 4:
        raise LyricError("LYR2 必须包含1至4首曲目")
    out = bytearray(b"LYR2" + struct.pack("<HH", LYR2_VERSION, len(tracks)))
    seen_ids: set[int] = set()
    for track in tracks:
        song_id = int(track["song_id"])
        title = track["title"].encode("utf-8")
        artist = track["artist"].encode("utf-8")
        rows = track["rows"]
        if song_id not in range(4) or song_id in seen_ids:
            raise LyricError(f"LYR2 song_id 重复或越界：{song_id}")
        if len(title) > 255 or len(artist) > 255 or len(rows) > MAX_ROWS_PER_TRACK:
            raise LyricError("LYR2 标题、歌手或歌词行数超过格式上限")
        if len(rows) == 0:
            raise LyricError(f"曲目{song_id + 1}没有歌词")
        seen_ids.add(song_id)
        out.extend(struct.pack("<BBBH", song_id, len(title), len(artist), len(rows)))
        out.extend(title)
        out.extend(artist)
        previous = -1
        for time_ms, lyric in rows:
            encoded = lyric.encode("utf-8")
            if (not isinstance(time_ms, int) or time_ms < 0 or time_ms <= previous or
                    time_ms > 0xFFFFFFFF or not lyric or len(lyric) > 16 or len(encoded) > 255):
                raise LyricError(f"曲目{song_id + 1}存在时间戳、文本长度或顺序错误")
            out.extend(struct.pack("<IH", time_ms, len(encoded)))
            out.extend(encoded)
            previous = time_ms
    out.extend(struct.pack("<I", zlib.crc32(out) & 0xFFFFFFFF))
    return bytes(out)


def decode_lyr2(blob: bytes) -> list[dict]:
    if len(blob) < 12 or blob[:4] != b"LYR2":
        raise LyricError("LYR2 magic 或长度错误")
    version, count = struct.unpack_from("<HH", blob, 4)
    if version != LYR2_VERSION or not 1 <= count <= 4:
        raise LyricError("LYR2 版本或曲目数量错误")
    stored_crc, = struct.unpack_from("<I", blob, len(blob) - 4)
    if (zlib.crc32(blob[:-4]) & 0xFFFFFFFF) != stored_crc:
        raise LyricError("LYR2 CRC32 校验失败")
    cursor, end = 8, len(blob) - 4
    tracks, seen = [], set()
    for _ in range(count):
        if cursor + 5 > end:
            raise LyricError("LYR2 曲目记录被截断")
        song_id, title_len, artist_len, row_count = struct.unpack_from("<BBBH", blob, cursor)
        cursor += 5
        if song_id not in range(4) or song_id in seen or not 1 <= row_count <= 128:
            raise LyricError("LYR2 song_id 或歌词行数错误")
        seen.add(song_id)
        if cursor + title_len + artist_len > end:
            raise LyricError("LYR2 标题/歌手被截断")
        title = blob[cursor:cursor + title_len].decode("utf-8")
        cursor += title_len
        artist = blob[cursor:cursor + artist_len].decode("utf-8")
        cursor += artist_len
        rows, previous = [], -1
        for _ in range(row_count):
            if cursor + 6 > end:
                raise LyricError("LYR2 歌词行头被截断")
            time_ms, text_len = struct.unpack_from("<IH", blob, cursor)
            cursor += 6
            if cursor + text_len > end:
                raise LyricError("LYR2 歌词文本被截断")
            text = blob[cursor:cursor + text_len].decode("utf-8")
            cursor += text_len
            if time_ms <= previous or not text or len(text) > 16:
                raise LyricError("LYR2 歌词时间或行内容非法")
            rows.append((time_ms, text))
            previous = time_ms
        tracks.append({"song_id": song_id, "title": title, "artist": artist, "rows": rows})
    if cursor != end:
        raise LyricError("LYR2 尾部存在未解析数据")
    return tracks


def build_tracks(project: Path, assets_dir: Path) -> tuple[list[dict], dict]:
    discovered = s1.discover_sources(project / s1.SOURCE_DIR)
    calibration_path = project / s1.SOURCE_DIR / "lyrics_manual_calibration.json"
    calibration = json.loads(calibration_path.read_text(encoding="utf-8")) if calibration_path.exists() else {}
    tracks = []
    for song in discovered:
        subtitles = sorted(song["folder"].glob("*.srt"))
        if len(subtitles) != 1:
            raise LyricError(f"歌曲{song['number']} 必须恰有1个SRT字幕文件")
        source_cues = parse_srt_text(subtitles[0].read_text(encoding="utf-8-sig"))
        cues = apply_manual_calibration(source_cues, song["number"], calibration)
        rows = make_display_rows(cues)
        track = {"song_id": song["number"] - 1, "title": song["title"],
                 "display_title": song["title"][:16],
                 "artist": song["artist"], "rows": rows,
                 "source_srt": str(subtitles[0]),
                 "source_srt_sha256": hashlib.sha256(subtitles[0].read_bytes()).hexdigest(),
                 "source_cue_count": len(source_cues), "cue_count": len(cues),
                 "timeline_offset_ms": int(calibration.get("tracks", {}).get(
                     str(song["number"]), {}).get("timeline_offset_ms", 0)),
                 "manual_calibration_sha256": (hashlib.sha256(calibration_path.read_bytes()).hexdigest()
                                                if calibration_path.exists() else None)}
        lrc_path = assets_dir / f"track{song['number']}.lrc"
        lrc_path.write_text("".join(f"[{ms // 60000:02d}:{(ms % 60000) / 1000:06.3f}]{line}\n"
                                      for ms, line in rows), encoding="utf-8", newline="\n")
        track["lrc"] = lrc_path.name
        tracks.append(track)
    return tracks, {song["number"]: song for song in discovered}


def add_lyr2_to_s2(s2_image: Path, output_image: Path, lyr2_path: Path) -> dict:
    shutil.copyfile(s2_image, output_image)
    blob = lyr2_path.read_bytes()
    decode_lyr2(blob)
    with vp.Fat32Image(output_image, writable=True) as volume:
        existing = next((entry for entry in volume.root_entries()
                         if entry.name.upper() == LYRICS_NAME), None)
        if existing:
            raise LyricError("S2 镜像已经包含 LYRICS.BIN；拒绝覆盖以避免留下孤立簇链")
        index_entry = volume.find_root_file("INDEX.BIN")
        index_blob = volume.read_file(index_entry.first_cluster, index_entry.size)
        parsed = vp.parse_index(index_blob)
        if parsed["count"] != 4 or parsed["version"] != 2:
            raise LyricError("输入镜像不是四曲 INDEX v2 的 S2 镜像")
        # Read complete FAT copies and require a clean starting point.
        volume.fh.seek(volume.fat_start_lba * 512)
        fat = bytearray(volume.fh.read(volume.fat_size * 512))
        if len(fat) != volume.fat_size * 512:
            raise LyricError("FAT1 读取不完整")
        for copy in range(1, volume.num_fats):
            volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
            if volume.fh.read(volume.fat_size * 512) != fat:
                raise LyricError(f"FAT{copy + 1} 与 FAT1 不一致")
        cluster_bytes = volume.sectors_per_cluster * 512
        cluster_count = math.ceil(len(blob) / cluster_bytes)
        first_cluster = next((cluster for cluster in range(volume.max_cluster - cluster_count,
                                                            1, -1)
                              if cluster >= 2 and all(
                                  struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF == 0
                                  for c in range(cluster, cluster + cluster_count))), None)
        if first_cluster is None:
            raise LyricError("FAT32 中没有可分配的连续簇用于 LYRICS.BIN")
        for index in range(cluster_count):
            value = first_cluster + index + 1 if index + 1 < cluster_count else 0x0FFFFFFF
            struct.pack_into("<I", fat, (first_cluster + index) * 4, value)
        lba = volume.cluster_lba(first_cluster)
        volume.fh.seek(lba * 512)
        volume.fh.write(blob)
        volume.fh.write(bytes(cluster_count * cluster_bytes - len(blob)))
        if index_entry.raw_index >= 16:
            raise LyricError("INDEX.BIN 不在根目录首扇区，拒绝改写FPGA扫描范围外的索引")
        directory_lba, directory_off = volume.free_root_slot()
        name83 = b"LYRICS  BIN"
        volume.write_root_entry(directory_lba, directory_off, name83, first_cluster, len(blob))
        mutable_index = bytearray(index_blob)
        for index in range(4):
            flags, = struct.unpack_from("<I", mutable_index, 64 + index * 64)
            struct.pack_into("<I", mutable_index, 64 + index * 64, flags | vp.FLAG_LRC)
        crc = zlib.crc32(mutable_index[64:64 + parsed["count"] * 64]) & 0xFFFFFFFF
        struct.pack_into("<I", mutable_index, 16, crc)
        volume.write_sector(volume.cluster_lba(index_entry.first_cluster), bytes(mutable_index))
        for copy in range(volume.num_fats):
            volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
            volume.fh.write(fat)
        volume.fh.flush()
        verify_index = vp.parse_index(volume.read_file(index_entry.first_cluster, index_entry.size))
        entry = volume.find_root_file(LYRICS_NAME)
        recovered = volume.read_file(entry.first_cluster, entry.size)
        if recovered != blob or decode_lyr2(recovered) is None:
            raise LyricError("LYRICS.BIN FAT 文件回读失败")
        runs = volume.cluster_runs(entry.first_cluster)
        if len(runs) != 1 or runs[0] != (lba, cluster_count * volume.sectors_per_cluster):
            raise LyricError("LYRICS.BIN FAT 簇链未保持连续")
        if any(not song["flags"] & vp.FLAG_LRC for song in verify_index["songs"]):
            raise LyricError("INDEX LRC 标志写后回读失败")
        return {"lba": lba, "first_cluster": first_cluster,
                "allocated_bytes": cluster_count * cluster_bytes,
                "sha256": hashlib.sha256(recovered).hexdigest(),
                "index_entries_crc32": f"0x{verify_index['entries_crc32']:08X}"}


def prepare(args) -> dict:
    project = args.project.resolve()
    output = args.output.resolve()
    if output.exists():
        raise LyricError(f"输出目录已存在，为避免覆盖请指定新目录：{output}")
    output.mkdir(parents=True)
    assets_dir = output / "assets"
    assets_dir.mkdir()
    tracks, discovered = build_tracks(project, assets_dir)
    lyr2_blob = encode_lyr2(tracks)
    lyr2_path = assets_dir / LYRICS_NAME
    lyr2_path.write_bytes(lyr2_blob)
    decoded_tracks = decode_lyr2(lyr2_blob)
    expected_tracks = [{"song_id": track["song_id"], "title": track["title"],
                        "artist": track["artist"], "rows": track["rows"]}
                       for track in tracks]
    if decoded_tracks != expected_tracks:
        raise LyricError("LYR2 编码结果未通过本地完整解码回读")

    manifest_path = assets_dir / "songs_manifest.json"
    manifest_path.write_text(json.dumps({"schema": "vinylfpga-song-text-v2",
                                        "glyph_banks": True,
                                        "tracks": [{"song_id": t["song_id"], "title": t["title"],
                                                    "display_title": t["display_title"],
                                                    "artist": t["artist"], "lrc": t["lrc"]}
                                                   for t in tracks]},
                                       ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    s2_image = args.s2_image.resolve(strict=True)
    input_hash = sha256_file(s2_image)
    if input_hash.lower() != args.expected_s2_sha256.lower():
        raise LyricError(f"输入不是 S2 验收镜像：SHA256 {input_hash}")
    image_path = output / "card_STAGE3.img"
    image_result = add_lyr2_to_s2(s2_image, image_path, lyr2_path)
    generated = assets.generate_song_text_assets(manifest_path, output / "generated")
    for relative in ("src/display/song_text_rom.v", "src/display/song_font_rom.v",
                     "src/include/song_text_geom.vh"):
        shutil.copyfile(output / "generated" / relative, project / relative)
    songs = []
    for track in tracks:
        source = discovered[track["song_id"] + 1]
        songs.append({"song_id": track["song_id"], "title": track["title"],
                      "artist": track["artist"], "srt": track["source_srt"],
                      "srt_sha256": track["source_srt_sha256"],
                      "source_cue_count": track["source_cue_count"],
                      "cue_count": track["cue_count"], "display_row_count": len(track["rows"]),
                      "timeline_offset_ms": track["timeline_offset_ms"],
                      "manual_calibration_sha256": track["manual_calibration_sha256"],
                      "first_lyric_ms": track["rows"][0][0],
                      "last_lyric_ms": track["rows"][-1][0],
                      "duration_seconds": source["source_duration_seconds"]})
    manifest = {"phase": "S3", "input_s2_image": str(s2_image),
                "input_s2_sha256": input_hash,
                "image": str(image_path), "image_bytes": image_path.stat().st_size,
                "image_sha256": sha256_file(image_path),
                "size_mib": image_path.stat().st_size // (1024 * 1024),
                "lyr2": {"name": LYRICS_NAME, "bytes": len(lyr2_blob),
                         "sha256": image_result["sha256"], "lba": image_result["lba"],
                         "index_entries_crc32": image_result["index_entries_crc32"],
                         "crc32": f"0x{struct.unpack_from('<I', lyr2_blob, len(lyr2_blob)-4)[0]:08X}"},
                "font": {"bank_count": 2,
                         "bank0_glyphs": len(generated["bank_chars"][0]),
                         "bank1_glyphs": len(generated["bank_chars"][1]),
                         "rom_depth": generated["font_depth"]},
                "songs": songs,
                "verified": {"lyr2_decode_crc": True, "rom_generated_from_same_rows": True,
                             "fat_chain_contiguous": True, "lyr2_full_readback_sha256": True,
                             "all_index_lrc_flags": True,
                             "manual_calibration_applied": any(
                                 t["manual_calibration_sha256"] for t in tracks)}}
    (output / "S3_lyrics_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--s2-image", type=Path, required=True)
    parser.add_argument("--expected-s2-sha256", default=EXPECTED_S2_SHA256)
    parser.add_argument("--output", type=Path, required=True,
                        help="仓库外的新目录；保留生成的 S3 镜像和歌词清单")
    args = parser.parse_args(argv)
    try:
        manifest = prepare(args)
        print(json.dumps({"result": "S3_LYRICS_OK", "image": manifest["image"],
                          "image_sha256": manifest["image_sha256"],
                          "lyr2_sha256": manifest["lyr2"]["sha256"],
                          "songs": manifest["songs"], "font": manifest["font"]},
                         ensure_ascii=False, indent=2))
        return 0
    except (LyricError, vp.PackError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"S3_LYRICS_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
