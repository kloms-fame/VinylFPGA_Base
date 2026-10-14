#!/usr/bin/env python3
"""Prepare S1 independent song audio, real covers, backgrounds and FAT32 image.

The four PCM tracks are extracted from the AAC audio stream in each supplied
song MV. The resulting image is a 1536 MiB FAT32 superfloppy based on the
manually accepted 7029e60 image. No physical SD device is accessed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack_backgrounds as bg  # noqa: E402
import vinyl_packer as vp  # noqa: E402

SAMPLE_RATE = 48_000
CLUSTER_EOC = 0x0FFFFFFF
SONG_DIRS = [f"歌曲{i}" for i in range(1, 5)]
BACKGROUND_DIR = Path("doc/资源/sd卡/背景图")
SOURCE_DIR = Path("doc/资源/sd卡/歌曲素材")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=True, capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    return json.loads(result.stdout)


def discover_sources(root: Path) -> list[dict]:
    songs = []
    for number, dirname in enumerate(SONG_DIRS, 1):
        folder = root / dirname
        if not folder.is_dir():
            raise vp.PackError(f"缺少素材目录：{folder}")
        videos = sorted(folder.glob("*.mp4"))
        covers = sorted(p for p in folder.iterdir()
                        if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png"))
        infos = sorted(folder.glob("*.txt"))
        if len(videos) != 1 or len(covers) != 1:
            raise vp.PackError(
                f"{dirname} 必须恰有1个MP4和1张JPG/PNG（当前 {len(videos)} / {len(covers)}）")
        streams = run_json(["ffprobe", "-v", "error", "-show_entries",
                            "stream=codec_type,codec_name,sample_rate,channels",
                            "-show_entries", "format=duration", "-of", "json", str(videos[0])])
        audio = [s for s in streams.get("streams", []) if s.get("codec_type") == "audio"]
        if len(audio) != 1:
            raise vp.PackError(f"{videos[0].name} 必须恰有1条音轨（当前 {len(audio)}）")
        duration = float(streams["format"]["duration"])
        text = infos[0].read_text(encoding="utf-8-sig", errors="replace") if infos else ""
        title = re.search(r"(?:歌曲名称|歌曲|歌名)\s*[:：]?\s*(.+)", text)
        artist = re.search(r"(?:作者|歌手|作曲)\s*[:：]?\s*(.+)", text)
        songs.append({"number": number, "folder": folder, "video": videos[0],
                      "cover": covers[0], "title": title.group(1).strip() if title else videos[0].stem,
                      "artist": artist.group(1).strip() if artist else "",
                      "source_duration_seconds": duration,
                      "source_video_sha256": sha256_file(videos[0]),
                      "source_cover_sha256": sha256_file(covers[0]),
                      "source_audio": audio[0]})
    return songs


def convert_cover(source: Path, target: Path) -> dict:
    with Image.open(source) as original:
        dimensions = original.size
        source_rgb = original.convert("RGB")
        # Preserve every edge and all artwork text. A softly blurred full-frame
        # fill handles aspect ratios wider than the 4:3 hardware cover window.
        cover = ImageEnhance.Brightness(
            ImageOps.fit(source_rgb, (640, 480), method=Image.Resampling.LANCZOS)
        ).enhance(0.55).filter(ImageFilter.GaussianBlur(24))
        foreground = ImageOps.contain(source_rgb, (640, 480),
                                      method=Image.Resampling.LANCZOS)
        cover.paste(foreground, ((640 - foreground.width) // 2,
                                 (480 - foreground.height) // 2))
        cover.save(target, format="BMP", bits=24)
    data = target.read_bytes()
    vp._check_cover(data, target.name, 640, 480)
    return {"source": str(source), "source_dimensions": list(dimensions),
            "output": target.name, "bytes": len(data), "sha256": sha256(data)}


def extract_pcm(video: Path, target: Path) -> dict:
    subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(video), "-map", "0:a:0", "-vn", "-sn", "-dn",
                    "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le",
                    "-f", "s16le", str(target)], check=True)
    size = target.stat().st_size
    if not size or size & 1:
        raise vp.PackError(f"PCM字节数必须为非零偶数：{target} ({size})")
    return {"source_video": str(video), "output": target.name, "bytes": size,
            "samples": size // 2, "sample_rate_hz": SAMPLE_RATE,
            "channels": 1, "format": "signed 16-bit little-endian raw PCM",
            "duration_seconds": size / 2 / SAMPLE_RATE,
            "source_duration_seconds": None, "sha256": sha256_file(target)}


def read_fat(volume: vp.Fat32Image) -> bytearray:
    volume.fh.seek(volume.fat_start_lba * 512)
    data = bytearray(volume.fh.read(volume.fat_size * 512))
    if len(data) != volume.fat_size * 512:
        raise vp.PackError("FAT1读取不完整")
    for copy in range(1, volume.num_fats):
        volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
        other = volume.fh.read(volume.fat_size * 512)
        if other != data:
            raise vp.PackError(f"FAT{copy + 1}与FAT1不一致，拒绝修改镜像")
    return data


def fat_value(fat: bytearray, cluster: int) -> int:
    return struct.unpack_from("<I", fat, cluster * 4)[0] & 0x0FFFFFFF


def set_fat_value(fat: bytearray, cluster: int, value: int) -> None:
    struct.pack_into("<I", fat, cluster * 4, value & 0x0FFFFFFF)


def free_contiguous_file(volume: vp.Fat32Image, fat: bytearray,
                         entry: vp.DirEntry) -> None:
    if entry.size == 0:
        return
    runs = volume.cluster_runs(entry.first_cluster)
    if len(runs) != 1:
        raise vp.PackError(f"{entry.name} 原文件碎片化，S1不在原链上释放空间")
    clusters = (entry.size + volume.sectors_per_cluster * 512 - 1) // (volume.sectors_per_cluster * 512)
    expected_sectors = clusters * volume.sectors_per_cluster
    if runs[0][1] != expected_sectors:
        raise vp.PackError(f"{entry.name} FAT链长度与目录大小不一致")
    for cluster in range(entry.first_cluster, entry.first_cluster + clusters):
        set_fat_value(fat, cluster, 0)


def allocate_data_run(volume: vp.Fat32Image, fat: bytearray, first_candidate: int,
                      payload: bytes) -> tuple[int, int]:
    cluster_bytes = volume.sectors_per_cluster * 512
    count = (len(payload) + cluster_bytes - 1) // cluster_bytes
    if count < 1:
        raise vp.PackError("拒绝创建空媒体文件")
    end = first_candidate + count
    if end > volume.max_cluster:
        raise vp.PackError("1536 MiB镜像空间不足")
    for cluster in range(first_candidate, end):
        if fat_value(fat, cluster) != 0:
            raise vp.PackError(f"扩展区预期空闲但簇{cluster}已占用")
    for cluster in range(first_candidate, end - 1):
        set_fat_value(fat, cluster, cluster + 1)
    set_fat_value(fat, end - 1, CLUSTER_EOC)
    lba = volume.cluster_lba(first_candidate)
    volume.fh.seek(lba * 512)
    volume.fh.write(payload)
    padding = count * cluster_bytes - len(payload)
    if padding:
        volume.fh.write(bytes(padding))
    return first_candidate, count


def write_fats(volume: vp.Fat32Image, fat: bytearray) -> None:
    for copy in range(volume.num_fats):
        volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
        volume.fh.write(fat)


def write_chain_bytes(volume: vp.Fat32Image, entry: vp.DirEntry, data: bytes) -> None:
    cluster_bytes = volume.sectors_per_cluster * 512
    needed = (len(data) + cluster_bytes - 1) // cluster_bytes
    clusters = list(volume.iter_chain(entry.first_cluster, limit=needed + 1))
    if len(clusters) != needed:
        raise vp.PackError(f"{entry.name}簇链长度不适配新文件")
    runs = volume.cluster_runs(entry.first_cluster)
    if len(runs) != 1:
        raise vp.PackError(f"{entry.name}封面/背景文件必须连续")
    volume.fh.seek(volume.cluster_lba(entry.first_cluster) * 512)
    volume.fh.write(data)
    padding = needed * cluster_bytes - len(data)
    if padding:
        volume.fh.write(bytes(padding))


def pack_image(base: Path, output: Path, size_mib: int, songs: list[dict],
               converted: list[dict], backgrounds: list[Image.Image],
               art1_path: Path, art2_path: Path) -> dict:
    if output.exists():
        raise vp.PackError(f"输出已存在，为避免覆盖请使用新目录：{output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with vp.Fat32Image(base) as original:
        old_index_entry = original.find_root_file("INDEX.BIN")
        old_index = original.read_file(old_index_entry.first_cluster, old_index_entry.size)
        old_info = vp.parse_index(old_index)
        old_bg = bg.background_metadata(old_index)
        if old_bg is None or old_bg["frame_count"] != 6:
            raise vp.PackError("S0基线必须包含BGR1六帧背景区")
        source_max_cluster = original.max_cluster
        original_hash = sha256_file(base)
    with vp.Fat32Image(base) as original:
        delta = bg.grow_fat32(original, output, size_mib)

    pcm_paths = [item["pcm_path"] for item in converted]
    pcm_data = [p.read_bytes() for p in pcm_paths]
    cover_data = [item["cover_path"].read_bytes() for item in converted]
    bg_data = b"".join(bg.rgb565_le(image, dither=True) for image in backgrounds)
    if len(bg_data) != bg.BACKGROUND_BYTES:
        raise vp.PackError("背景帧总长度不符合六帧协议")

    with vp.Fat32Image(output, writable=True) as volume:
        fat = read_fat(volume)
        # Updating same-size 640x480 BMPs retains each known-good root entry and FAT chain.
        for number, data in enumerate(cover_data, 1):
            entry = volume.find_root_file(f"PIC{number}.BMP")
            if entry.size != len(data):
                raise vp.PackError(f"PIC{number}.BMP新旧长度不同，拒绝原地覆盖")
            write_chain_bytes(volume, entry, data)

        # Reuse AUDIO.PCM for track 1; allocate tracks 2-4 in the newly grown area.
        audio_entries: list[vp.DirEntry | None] = [None] * 4
        audio_entries[0] = volume.find_root_file("AUDIO.PCM")
        for number in range(2, 5):
            try:
                audio_entries[number - 1] = volume.find_root_file(f"AUDIO{number}.PCM")
            except vp.PackError:
                pass
        for entry in audio_entries:
            if entry is not None:
                free_contiguous_file(volume, fat, entry)
        next_cluster = source_max_cluster
        audio_records = []
        for i, data in enumerate(pcm_data):
            first, clusters = allocate_data_run(volume, fat, next_cluster, data)
            next_cluster = first + clusters
            audio_name = "AUDIO.PCM" if i == 0 else f"AUDIO{i + 1}.PCM"
            if i == 0:
                entry = volume.find_root_file(audio_name)
                stem, extension = audio_name.split(".")
                volume.write_root_entry(entry.lba, entry.slot_off,
                                         stem.upper().ljust(8).encode("ascii") + extension.upper().ljust(3).encode("ascii"),
                                         first, len(data))
            else:
                entry = next((e for e in volume.root_entries()
                              if e.name.upper() == audio_name.upper()), None)
                if entry is None:
                    directory_lba, directory_off = volume.free_root_slot()
                else:
                    directory_lba, directory_off = entry.lba, entry.slot_off
                stem, extension = audio_name.split(".")
                volume.write_root_entry(directory_lba, directory_off,
                                         stem.upper().ljust(8).encode("ascii") + extension.upper().ljust(3).encode("ascii"),
                                         first, len(data))
            audio_records.append({"name": audio_name, "first_cluster": first,
                                 "bytes": len(data), "sha256": sha256(data),
                                 "start_lba": volume.cluster_lba(first),
                                 "clusters": clusters})

        # Store actual covers in the existing six-frame BG.BIN slots:
        # four processed song covers followed by the user's ART1 and ART2.
        bge = volume.find_root_file("BG.BIN")
        if bge.size != len(bg_data):
            raise vp.PackError("基线BG.BIN大小与六帧协议不一致")
        write_chain_bytes(volume, bge, bg_data)

        index_songs = []
        for i, item in enumerate(converted):
            cover = volume.find_root_file(f"PIC{i + 1}.BMP")
            entry = vp.IndexSong(title=f"Track {i + 1}", cover_name=cover.name,
                                 audio_name=audio_records[i]["name"], flags=vp.FLAG_COVER | vp.FLAG_AUDIO,
                                 cover_cluster=cover.first_cluster, cover_bytes=cover.size,
                                 cover_crc32=zlib.crc32(cover_data[i]) & 0xFFFFFFFF,
                                 cover_sha256=sha256(cover_data[i]),
                                 audio_cluster=audio_records[i]["first_cluster"],
                                 audio_bytes=audio_records[i]["bytes"],
                                 audio_crc32=zlib.crc32(pcm_data[i]) & 0xFFFFFFFF,
                                 audio_sha256=audio_records[i]["sha256"],
                                 audio_lba=audio_records[i]["start_lba"])
            # Keep the accepted baseline's song-1 short MV descriptor for S1;
            # S2 will replace it with all four complete videos.
            if i == 0 and old_info["songs"][0]["mv_frames"]:
                old_mv = old_info["songs"][0]
                entry.flags |= vp.FLAG_MV
                entry.mv_lba = old_mv["mv_lba"] + delta
                entry.mv_frames = old_mv["mv_frames"]
                entry.mv_fps = old_mv["mv_fps"]
            index_songs.append(entry)
        index_blob = bg.patch_index(vp.build_index(index_songs), 0,
                                    old_bg["base_lba"] + delta)
        parsed = vp.parse_index(index_blob)
        index_entry = volume.find_root_file("INDEX.BIN")
        volume.write_sector(volume.cluster_lba(index_entry.first_cluster), index_blob)
        write_fats(volume, fat)
        volume.fh.flush()

        # Verify FAT, directory, index and complete bytes through fresh reads.
        verified_index = volume.read_file(index_entry.first_cluster, index_entry.size)
        verified_parsed = vp.parse_index(verified_index)
        if verified_index != index_blob:
            raise vp.PackError("INDEX.BIN写后回读不一致")
        if verified_parsed["count"] != 4 or any(s["audio_cluster"] < 2 for s in verified_parsed["songs"]):
            raise vp.PackError("四曲索引/音频簇校验失败")
        for i, record in enumerate(audio_records):
            chain = list(volume.iter_chain(record["first_cluster"], limit=record["clusters"] + 1))
            if len(chain) != record["clusters"] or any(b != a + 1 for a, b in zip(chain, chain[1:])):
                raise vp.PackError(f"{record['name']} FAT链不连续或长度错误")
            recovered = volume.read_file(record["first_cluster"], record["bytes"])
            if sha256(recovered) != record["sha256"]:
                raise vp.PackError(f"{record['name']} FAT回读SHA不匹配")
            if verified_parsed["songs"][i]["audio_cluster"] != record["first_cluster"]:
                raise vp.PackError(f"第{i + 1}曲音频索引簇不匹配")
        bgr = bg.background_metadata(verified_index)
        if bgr is None or bgr["base_lba"] != old_bg["base_lba"] + delta:
            raise vp.PackError("BGR1背景LBA搬迁校验失败")
        volume.fh.seek(bgr["base_lba"] * 512)
        if volume.fh.read(len(bg_data)) != bg_data:
            raise vp.PackError("背景帧物理LBA回读不一致")
        for i, expected in enumerate(cover_data, 1):
            ce = volume.find_root_file(f"PIC{i}.BMP")
            if sha256(volume.read_file(ce.first_cluster, ce.size)) != sha256(expected):
                raise vp.PackError(f"PIC{i}.BMP回读SHA不匹配")

        records = []
        for i, parsed_song in enumerate(verified_parsed["songs"]):
            records.append({"number": i + 1, "title": songs[i]["title"],
                            "artist": songs[i]["artist"], "audio": audio_records[i],
                            "cover": {"name": f"PIC{i + 1}.BMP", "bytes": len(cover_data[i]),
                                      "sha256": sha256(cover_data[i])},
                            "mv": ({"legacy_frames": parsed_song["mv_frames"],
                                    "lba": parsed_song["mv_lba"]}
                                   if parsed_song["mv_frames"] else None)})

    report = {"phase": "S1", "source_base": str(base), "source_base_sha256": original_hash,
              "image": str(output), "image_bytes": output.stat().st_size,
              "image_sha256": sha256_file(output), "size_mib": size_mib,
              "filesystem": "FAT32 superfloppy, 512 bytes/sector",
              "data_lba_delta_after_growth": delta,
              "index_version": parsed["version"], "index_entries_crc32": f"0x{parsed['entries_crc32']:08X}",
              "background": {"base_lba": bgr["base_lba"], "frame_bytes": bg.FRAME_BYTES,
                             "frame_count": bg.FRAME_COUNT,
                             "source_art1": str(art1_path),
                             "source_art1_sha256": sha256_file(art1_path),
                             "source_art2": str(art2_path),
                             "source_art2_sha256": sha256_file(art2_path),
                             "sha256": sha256(bg_data)},
              "songs": records,
              "verified": {"index_readback": True, "fat_audio_chains_contiguous": True,
                           "audio_full_sha256_readback": True, "covers_full_sha256_readback": True,
                           "background_lba_readback": True}}
    return report


def prepare(args) -> int:
    project = args.project.resolve()
    out = args.output.resolve()
    if out.exists():
        raise vp.PackError(f"输出目录已存在，请指定新的外部目录：{out}")
    out.mkdir(parents=True)
    assets = out / "assets"
    assets.mkdir()
    sources = discover_sources(project / SOURCE_DIR)
    converted = []
    for source in sources:
        number = source["number"]
        cover_path = assets / f"PIC{number}.BMP"
        cover_info = convert_cover(source["cover"], cover_path)
        audio_name = "AUDIO.PCM" if number == 1 else f"AUDIO{number}.PCM"
        pcm_path = assets / audio_name
        audio_info = extract_pcm(source["video"], pcm_path)
        audio_info["source_duration_seconds"] = source["source_duration_seconds"]
        converted.append({**source, "cover_path": cover_path, "cover_info": cover_info,
                          "pcm_path": pcm_path, "audio_info": audio_info})

    with Image.open(project / BACKGROUND_DIR / "背景图1.jpg") as im1:
        art1 = ImageOps.fit(im1.convert("RGB"), (640, 480), method=Image.Resampling.LANCZOS)
    with Image.open(project / BACKGROUND_DIR / "背景图2.jpg") as im2:
        art2 = ImageOps.fit(im2.convert("RGB"), (640, 480), method=Image.Resampling.LANCZOS)
    backgrounds = []
    for item in converted:
        backgrounds.append(bg.cover_background(item["cover_path"].read_bytes()))
    backgrounds.extend((art1, art2))
    for index, image in enumerate(backgrounds, 1):
        image.save(out / f"BG_PREVIEW_{index}.png")

    base = project / "doc/资源/sd卡/stage4/card_STAGE4.img"
    if not base.is_file():
        raise vp.PackError(f"缺少已验收S0镜像：{base}")
    image_path = out / "card_STAGE1.img"
    art1_path = project / BACKGROUND_DIR / "背景图1.jpg"
    art2_path = project / BACKGROUND_DIR / "背景图2.jpg"
    report = pack_image(base, image_path, args.size_mib, sources, converted, backgrounds,
                        art1_path, art2_path)
    report["songs"] = [{**record, "source_video": str(item["video"]),
                        "source_video_sha256": item["source_video_sha256"],
                        "source_cover": str(item["cover"]),
                        "source_cover_sha256": item["source_cover_sha256"],
                        "source_duration_seconds": item["source_duration_seconds"],
                        "audio_duration_seconds": item["audio_info"]["duration_seconds"],
                        "cover_conversion": item["cover_info"],
                        "audio_format": item["audio_info"]}
                       for record, item in zip(report["songs"], converted)]
    report_path = out / "S1_media_manifest.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": "S1_MEDIA_IMAGE_OK", "image": str(image_path),
                      "bytes": report["image_bytes"], "sha256": report["image_sha256"],
                      "songs": [{"number": r["number"], "audio_bytes": r["audio"]["bytes"],
                                 "duration": r["audio_duration_seconds"],
                                 "cover_sha256": r["cover"]["sha256"],
                                 "audio_sha256": r["audio"]["sha256"]} for r in report["songs"]],
                      "report": str(report_path)}, ensure_ascii=False, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True,
                        help="新的输出目录，建议放在仓库外的 VinylFPGA_backups")
    parser.add_argument("--size-mib", type=int, default=1536)
    args = parser.parse_args(argv)
    try:
        if args.size_mib < 1536:
            raise vp.PackError("S1镜像至少1536 MiB，为S2全长MV预留容量")
        return prepare(args)
    except (vp.PackError, OSError, ValueError, subprocess.CalledProcessError,
            json.JSONDecodeError) as error:
        print(f"S1_MEDIA_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
