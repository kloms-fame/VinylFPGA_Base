#!/usr/bin/env python3
"""Build S2 full-length 320x240 RGB565LE/10fps MV streams into an S1 image.

The script only reads an image file and local MP4 sources. It never opens a
physical disk or SD card. Every video is converted to a new contiguous FAT32
run, then indexed by INDEX v2 using the exact 300-sector/frame RTL contract.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack_backgrounds as bg  # noqa: E402
import prepare_s1_media as s1  # noqa: E402
import vinyl_packer as vp  # noqa: E402

FRAME_BYTES = 320 * 240 * 2
FRAME_SECTORS = FRAME_BYTES // 512
FPS = 10
EXPECTED_S1_SHA256 = "f407b008e1b9641950fd123c012aceaabe20cd70ae67dfe6d4422614ca8d96f0"
MV_NAMES = [f"TRACK{i}.MV" for i in range(1, 5)]
COPY_CHUNK = 4 * 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(COPY_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_index_with_mv(index_blob: bytes, records: list[dict], background_lba: int) -> bytes:
    """Set one validated contiguous RGB565 MV descriptor on each S1 song."""
    parsed = vp.parse_index(index_blob)
    if len(records) != parsed["count"] or len(records) != 4:
        raise vp.PackError("S2 必须为 INDEX 中四首歌各提供一条 MV 记录")
    if [int(record.get("number", -1)) for record in records] != [1, 2, 3, 4]:
        raise vp.PackError("MV 输入记录必须按曲号1..4排列")
    ordered = sorted(records, key=lambda record: int(record["lba"]))
    previous_end = 0
    for expected_number, record in enumerate(ordered, 1):
        try:
            number = int(record["number"])
            lba = int(record["lba"])
            frames = int(record["frames"])
            byte_count = int(record["bytes"])
            sectors = int(record["sectors"])
        except (KeyError, TypeError, ValueError) as error:
            raise vp.PackError("MV 记录缺少有效的 number/LBA/帧数/字节数/扇区数") from error
        if number != expected_number:
            raise vp.PackError("MV 记录必须按曲号1..4排列，且每曲唯一")
        if not (0 < frames <= 65535 and lba > 0):
            raise vp.PackError(f"曲目{number} MV帧数或起始LBA非法")
        if byte_count != frames * FRAME_BYTES or sectors != frames * FRAME_SECTORS:
            raise vp.PackError(f"曲目{number} MV长度必须等于完整RGB565帧数")
        if lba + sectors > 0xFFFFFFFF:
            raise vp.PackError(f"曲目{number} MV扇区地址溢出")
        if number > 1 and lba < previous_end:
            raise vp.PackError("四首 MV 的物理范围互相重叠")
        previous_end = lba + sectors

    songs = []
    for old, record in zip(parsed["songs"], records):
        song = vp.IndexSong(
            title=old["title"], cover_name=f"PIC{len(songs) + 1}.BMP",
            audio_name="AUDIO.PCM" if not songs else f"AUDIO{len(songs) + 1}.PCM",
            flags=old["flags"] | vp.FLAG_MV,
            cover_cluster=old["cover_cluster"], cover_bytes=old["cover_bytes"],
            cover_crc32=old["cover_crc32"], audio_cluster=old["audio_cluster"],
            audio_bytes=old["audio_bytes"], audio_crc32=old["audio_crc32"],
            audio_lba=old["audio_lba"], mv_lba=int(record["lba"]),
            mv_frames=int(record["frames"]), mv_fps=FPS,
            mv_sha256=str(record.get("sha256", "")))
        if (song.flags & (vp.FLAG_COVER | vp.FLAG_AUDIO)) != (vp.FLAG_COVER | vp.FLAG_AUDIO):
            raise vp.PackError(f"曲目{len(songs) + 1}缺少S1封面或独立音频")
        songs.append(song)

    result = bg.patch_index(vp.build_index(songs), 0, background_lba)
    check = vp.parse_index(result)
    if check["version"] != 2 or any(not item["flags"] & vp.FLAG_MV for item in check["songs"]):
        raise vp.PackError("S2 INDEX v2 回读检查未启用四首 MV")
    return result


def probe_video(video: Path) -> dict:
    streams = s1.run_json([
        "ffprobe", "-v", "error", "-show_entries",
        "stream=codec_type,codec_name,width,height,sample_aspect_ratio,avg_frame_rate,r_frame_rate,duration",
        "-show_entries", "format=duration", "-of", "json", str(video)])
    videos = [stream for stream in streams.get("streams", [])
              if stream.get("codec_type") == "video"]
    if len(videos) != 1:
        raise vp.PackError(f"{video.name} 必须恰有1条视频流（当前{len(videos)}）")
    stream = videos[0]
    if int(stream.get("width", 0)) <= 0 or int(stream.get("height", 0)) <= 0:
        raise vp.PackError(f"{video.name} 视频分辨率非法")
    return {"codec": stream.get("codec_name", "unknown"),
            "width": int(stream["width"]), "height": int(stream["height"]),
            "sample_aspect_ratio": stream.get("sample_aspect_ratio", "1:1"),
            "avg_frame_rate": stream.get("avg_frame_rate", "0/0"),
            "r_frame_rate": stream.get("r_frame_rate", "0/0"),
            "duration_seconds": float(stream.get("duration") or streams["format"]["duration"]),
            "container_duration_seconds": float(streams["format"]["duration"])}


def convert_video(source: dict, target: Path) -> dict:
    """Decode the complete video at 10fps, preserving aspect ratio with letterbox."""
    partial = target.with_name(target.name + ".partial")
    command = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source["video"]), "-map", "0:v:0", "-an", "-sn", "-dn",
        "-vf", ("fps=10,scale=320:240:force_original_aspect_ratio=decrease:flags=lanczos,"
                "pad=320:240:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=rgb565le"),
        "-fps_mode", "passthrough", "-pix_fmt", "rgb565le", "-f", "rawvideo", str(partial)]
    try:
        subprocess.run(command, check=True)
        size = partial.stat().st_size
        if size == 0 or size % FRAME_BYTES:
            raise vp.PackError(f"{source['video'].name} 输出不是完整的320x240 RGB565帧：{size}字节")
        frames = size // FRAME_BYTES
        if frames > 65535:
            raise vp.PackError(f"{source['video'].name} 超出INDEX v2帧数上限")
        partial.replace(target)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    return {"name": target.name, "path": str(target), "bytes": size,
            "frames": frames, "fps": FPS, "frame_bytes": FRAME_BYTES,
            "sectors": size // 512, "sectors_per_frame": FRAME_SECTORS,
            "duration_seconds": frames / FPS,
            "duration_delta_from_video_seconds": frames / FPS - source["video_probe"]["duration_seconds"],
            "sha256": sha256_file(target), "format": "RGB565LE 320x240 top-down row-major"}


def read_fat(volume: vp.Fat32Image) -> bytearray:
    volume.fh.seek(volume.fat_start_lba * 512)
    data = bytearray(volume.fh.read(volume.fat_size * 512))
    if len(data) != volume.fat_size * 512:
        raise vp.PackError("FAT1读取不完整")
    for copy in range(1, volume.num_fats):
        volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
        if volume.fh.read(volume.fat_size * 512) != data:
            raise vp.PackError(f"FAT{copy + 1}与FAT1不一致，拒绝继续")
    return data


def fat_value(fat: bytearray, cluster: int) -> int:
    return struct.unpack_from("<I", fat, cluster * 4)[0] & 0x0FFFFFFF


def set_fat_value(fat: bytearray, cluster: int, value: int) -> None:
    struct.pack_into("<I", fat, cluster * 4, value & 0x0FFFFFFF)


def free_old_mv(volume: vp.Fat32Image, fat: bytearray, entry: vp.DirEntry) -> None:
    if entry.size == 0 or entry.size % 512:
        raise vp.PackError(f"{entry.name} 旧MV目录长度非法")
    runs = volume.cluster_runs(entry.first_cluster)
    expected_clusters = math.ceil(entry.size / (volume.sectors_per_cluster * 512))
    chain = list(volume.iter_chain(entry.first_cluster, limit=expected_clusters + 1))
    if len(runs) != 1 or len(chain) != expected_clusters or any(
            right != left + 1 for left, right in zip(chain, chain[1:])):
        raise vp.PackError(f"{entry.name} 旧FAT簇链碎片化或长度不符")
    if runs[0][1] != expected_clusters * volume.sectors_per_cluster:
        raise vp.PackError(f"{entry.name} 旧MV簇链物理长度异常")
    for cluster in chain:
        set_fat_value(fat, cluster, 0)


def highest_allocated_cluster(fat: bytearray, volume: vp.Fat32Image) -> int:
    for cluster in range(volume.max_cluster - 1, 1, -1):
        if fat_value(fat, cluster):
            return cluster
    raise vp.PackError("FAT中找不到有效已分配簇")


def allocate_mv(volume: vp.Fat32Image, fat: bytearray, first_cluster: int,
                asset: dict) -> tuple[int, int, int]:
    cluster_bytes = volume.sectors_per_cluster * 512
    count = math.ceil(asset["bytes"] / cluster_bytes)
    end_cluster = first_cluster + count
    if first_cluster < 2 or end_cluster > volume.max_cluster:
        raise vp.PackError(f"1536 MiB S1镜像空间不足，无法分配{asset['name']}")
    for cluster in range(first_cluster, end_cluster):
        if fat_value(fat, cluster) != 0:
            raise vp.PackError(f"MV扩展区预期空闲，但簇{cluster}已占用")
    for cluster in range(first_cluster, end_cluster - 1):
        set_fat_value(fat, cluster, cluster + 1)
    set_fat_value(fat, end_cluster - 1, 0x0FFFFFFF)

    start_lba = volume.cluster_lba(first_cluster)
    volume.fh.seek(start_lba * 512)
    with Path(asset["path"]).open("rb") as source:
        shutil.copyfileobj(source, volume.fh, COPY_CHUNK)
    padding = count * cluster_bytes - asset["bytes"]
    if padding:
        volume.fh.write(bytes(padding))
    return first_cluster, count, start_lba


def set_root_mv_entry(volume: vp.Fat32Image, name: str, first_cluster: int, size: int) -> None:
    existing = next((entry for entry in volume.root_entries()
                     if entry.name.upper() == name.upper()), None)
    if existing is None:
        directory_lba, directory_off = volume.free_root_slot()
    else:
        if existing.raw_index >= 16:
            raise vp.PackError(f"{name} 不在FPGA扫描的根目录首扇区")
        directory_lba, directory_off = existing.lba, existing.slot_off
    stem, extension = name.split(".")
    name83 = stem.upper().ljust(8).encode("ascii") + extension.upper().ljust(3).encode("ascii")
    volume.write_root_entry(directory_lba, directory_off, name83, first_cluster, size)


def hash_image_range(volume: vp.Fat32Image, lba: int, size: int) -> str:
    digest = hashlib.sha256()
    volume.fh.seek(lba * 512)
    remaining = size
    while remaining:
        chunk = volume.fh.read(min(COPY_CHUNK, remaining))
        if not chunk:
            raise vp.PackError("MV物理LBA回读提前结束")
        digest.update(chunk)
        remaining -= len(chunk)
    return digest.hexdigest()


def patch_image(s1_image: Path, output_image: Path, converted: list[dict]) -> dict:
    source_hash = sha256_file(s1_image)
    shutil.copyfile(s1_image, output_image)
    records = []
    with vp.Fat32Image(output_image, writable=True) as volume:
        if volume.sectors_per_cluster < 1 or volume.image_bytes != output_image.stat().st_size:
            raise vp.PackError("S1 FAT32 BPB与镜像实际长度不一致")
        old_index_entry = volume.find_root_file("INDEX.BIN")
        old_index = volume.read_file(old_index_entry.first_cluster, old_index_entry.size)
        old_info = vp.parse_index(old_index)
        if old_info["count"] != 4:
            raise vp.PackError("S1 INDEX 必须正好包含四首歌曲")
        old_bg = bg.background_metadata(old_index)
        if old_bg is None or old_bg["frame_count"] != 6:
            raise vp.PackError("S1 INDEX 缺少有效BGR1六帧背景扩展")

        fat = read_fat(volume)
        for name in MV_NAMES:
            existing = next((entry for entry in volume.root_entries()
                             if entry.name.upper() == name), None)
            if existing is not None:
                free_old_mv(volume, fat, existing)

        next_cluster = highest_allocated_cluster(fat, volume) + 1
        for number, asset in enumerate(converted, 1):
            first, clusters, lba = allocate_mv(volume, fat, next_cluster, asset)
            asset.update({"first_cluster": first, "clusters": clusters,
                          "start_lba": lba})
            set_root_mv_entry(volume, asset["name"], first, asset["bytes"])
            records.append({"number": number, "lba": lba, "frames": asset["frames"],
                            "bytes": asset["bytes"], "sectors": asset["sectors"],
                            "sha256": asset["sha256"]})
            next_cluster = first + clusters

        index_blob = build_index_with_mv(old_index, records, old_bg["base_lba"])
        volume.write_sector(volume.cluster_lba(old_index_entry.first_cluster), index_blob)
        for copy in range(volume.num_fats):
            volume.fh.seek((volume.fat_start_lba + copy * volume.fat_size) * 512)
            volume.fh.write(fat)
        volume.fh.flush()

        readback_index = volume.read_file(old_index_entry.first_cluster, old_index_entry.size)
        parsed = vp.parse_index(readback_index)
        if readback_index != index_blob or parsed["version"] != 2:
            raise vp.PackError("INDEX v2 写后回读失败")
        if bg.background_metadata(readback_index)["base_lba"] != old_bg["base_lba"]:
            raise vp.PackError("S2 改写 INDEX 时背景LBA发生变化")
        for number, (asset, song) in enumerate(zip(converted, parsed["songs"]), 1):
            entry = volume.find_root_file(asset["name"])
            runs = volume.cluster_runs(entry.first_cluster)
            if entry.size != asset["bytes"] or len(runs) != 1 or runs[0] != (
                    song["mv_lba"], song["mv_frames"] * FRAME_SECTORS):
                raise vp.PackError(f"曲目{number} FAT链、目录长度或INDEX MV范围不匹配")
            if song["mv_frames"] != asset["frames"] or song["mv_lba"] != asset["start_lba"]:
                raise vp.PackError(f"曲目{number} INDEX MV元数据回读不匹配")
            if hash_image_range(volume, song["mv_lba"], asset["bytes"]) != asset["sha256"]:
                raise vp.PackError(f"曲目{number} MV物理扇区完整SHA256回读不匹配")
        if any(not song["flags"] & vp.FLAG_MV for song in parsed["songs"]):
            raise vp.PackError("四首曲目并未全部启用MV")
        return {"source_s1_sha256": source_hash, "index_version": parsed["version"],
                "index_entries_crc32": f"0x{parsed['entries_crc32']:08X}",
                "background_lba": old_bg["base_lba"], "songs": converted}


def prepare(args) -> dict:
    project = args.project.resolve()
    s1_image = args.s1_image.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        raise vp.PackError(f"输出目录已存在，为避免覆盖请使用新目录：{output}")
    actual_source_hash = sha256_file(s1_image)
    expected_source_hash = args.expected_s1_sha256.lower()
    if actual_source_hash != expected_source_hash:
        raise vp.PackError(f"输入不是已验收S1镜像：SHA256 {actual_source_hash}")

    sources = s1.discover_sources(project / s1.SOURCE_DIR)
    for source in sources:
        source["video_probe"] = probe_video(source["video"])
    estimated = sum(math.ceil(item["video_probe"]["duration_seconds"] * FPS) * FRAME_BYTES
                    for item in sources)
    output.parent.mkdir(parents=True, exist_ok=True)
    free_bytes = shutil.disk_usage(output.parent).free
    if free_bytes < s1_image.stat().st_size + estimated + 512 * 1024 * 1024:
        raise vp.PackError("输出盘空间不足以同时保存S2镜像、四条MV和安全余量")
    output.mkdir(parents=False)
    assets_dir = output / "assets"
    assets_dir.mkdir()

    converted = []
    for source in sources:
        number = source["number"]
        name = f"TRACK{number}.MV"
        asset = convert_video(source, assets_dir / name)
        converted.append({**asset, "number": number,
                          "source_video": str(source["video"]),
                          "source_video_sha256": source["source_video_sha256"],
                          "source_title": source["title"], "source_artist": source["artist"],
                          "video": source["video_probe"]})

    image_path = output / "card_STAGE2.img"
    image_result = patch_image(s1_image, image_path, converted)
    manifest = {"phase": "S2", "input_s1_image": str(s1_image),
                "input_s1_sha256": image_result["source_s1_sha256"],
                "image": str(image_path), "image_bytes": image_path.stat().st_size,
                "image_sha256": sha256_file(image_path), "size_mib": image_path.stat().st_size // (1024 * 1024),
                "filesystem": "FAT32 superfloppy, 512 bytes/sector",
                "mv_contract": {"width": 320, "height": 240, "fps": FPS,
                                "pixel_format": "RGB565LE", "frame_bytes": FRAME_BYTES,
                                "sectors_per_frame": FRAME_SECTORS,
                                "aspect_policy": "preserve full frame, letterbox to 320x240"},
                "index_version": image_result["index_version"],
                "index_entries_crc32": image_result["index_entries_crc32"],
                "background_lba": image_result["background_lba"],
                "songs": image_result["songs"],
                "verified": {"all_four_mv_flags": True, "full_frame_lengths": True,
                             "fat_chains_contiguous": True, "mv_ranges_nonoverlapping": True,
                             "index_readback": True, "full_mv_physical_sha256_readback": True}}
    report = output / "S2_mv_manifest.json"
    report.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--s1-image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="必须是新的仓库外目录，S2镜像和视频原始流均写入该目录")
    parser.add_argument("--expected-s1-sha256", default=EXPECTED_S1_SHA256)
    args = parser.parse_args(argv)
    if len(args.expected_s1_sha256) != 64 or any(c not in "0123456789abcdefABCDEF"
                                                    for c in args.expected_s1_sha256):
        parser.error("--expected-s1-sha256 必须是64位十六进制SHA256")
    try:
        manifest = prepare(args)
        print(json.dumps({"result": "S2_FULL_MV_IMAGE_OK", "image": manifest["image"],
                          "bytes": manifest["image_bytes"], "sha256": manifest["image_sha256"],
                          "songs": [{"number": song["number"], "frames": song["frames"],
                                     "duration_seconds": song["duration_seconds"],
                                     "start_lba": song["start_lba"], "bytes": song["bytes"],
                                     "sha256": song["sha256"]} for song in manifest["songs"]],
                          "report": str(Path(manifest["image"]).with_name("S2_mv_manifest.json"))},
                         ensure_ascii=False, indent=2))
        return 0
    except (vp.PackError, OSError, ValueError, subprocess.CalledProcessError,
            json.JSONDecodeError) as error:
        print(f"S2_MV_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
