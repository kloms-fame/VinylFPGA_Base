#!/usr/bin/env python3
"""Build reproducible full-bleed cover and MV S3 resources.

The source card and source media are pinned by SHA256. This script writes only
to a new output directory; it never accesses a physical SD card.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

import PIL
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import prepare_s1_media as s1  # noqa: E402
import prepare_s2_mv as s2  # noqa: E402
import vinyl_packer as vp  # noqa: E402

SCRIPT_VERSION = "visual-assets-1.2.1"
EXPECTED_S3_SHA256 = "f1a17b8a4c303e0aaf7c631baed36fd0b682d2c2ec6ce212641fe654aaadb544"
DEFAULT_S3_CARD = Path(
    r"D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA_backups"
    r"\S3_lyrics_20261014_r5\card_STAGE3.img")
SOURCE_DIR = Path("doc/资源/sd卡/歌曲素材")
# Pin the exact media payloads used for this visual candidate. Song 1's cover
# differs from the older S1 package; this intentional source change is recorded
# rather than silently reusing the older artwork.
EXPECTED_MEDIA_SHA256 = [
    ("19c6cc084e9fa3353e44e19c6200776c8b481a4f35a5200bf98c362b1914290e",
     "7dc42c7d9e040406304698531be0b32936117c0d5e7aac94c6c28cdffeebddad"),
    ("45a86989d10bc5c914bf0eaf4e9c9750935497aa3de6373a1c83c3a6d6169697",
     "9d746cccef161fc73a314cf4fcb47dc330ae084260aeaf288c86175cb41709df"),
    ("8f4f6e0baf0d121d57e635ca3f1be920c347a9d462bf75ca74767fd3073b40be",
     "f13da00e373895dbd42c93ba48eeb536e597b46d6b5754bfac400f93afbb0b10"),
    ("bf9ef503ca15348aae3162fcb02c3587462aeae5aedb750a21ca7790613f6d99",
     "2d96322e4eec19f7a5099c4ad96d68307237ed71f0bddd060241918fb860f2f8"),
]
WIDTH, HEIGHT = 320, 240
FRAME_BYTES = WIDTH * HEIGHT * 2
FPS = 10
COPY_CHUNK = 4 * 1024 * 1024
SCALE_TO_FILL_FILTER = (
    "scale=320:240:force_original_aspect_ratio=increase:flags=lanczos,"
    "crop=320:240:(iw-ow)/2:(ih-oh)/2,setsar=1")
LETTERBOX_FILTER = (
    "fps=10,scale=320:240:force_original_aspect_ratio=decrease:flags=lanczos,"
    "pad=320:240:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=rgb24")
CENTER_CROP_PREVIEW_FILTER = (
    f"{SCALE_TO_FILL_FILTER},format=rgb24")
# These source mattes were visually reviewed and fixed in the user's 0d25421
# asset stage: Song 1 has vertical side bars; Song 4 has horizontal bars.
SOURCE_CROPS = {1: "crop=928:718:176:0", 4: "crop=1920:834:0:122"}
COVER_CENTERING = {
    1: (0.50, 0.50),
    2: (0.25, 0.50),
    3: (0.25, 0.50),
    4: (0.25, 0.50),
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(COPY_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_version(command: str) -> str:
    result = subprocess.run([command, "-version"], check=True, capture_output=True,
                            text=True, encoding="utf-8", errors="replace")
    return (result.stdout or result.stderr).splitlines()[0]


def cover_image(source: Path, policy: str,
                centering: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    with Image.open(source) as original:
        source_rgb = original.convert("RGB")
        if policy == "full_bleed":
            return ImageOps.fit(source_rgb, (640, 480),
                                method=Image.Resampling.LANCZOS,
                                centering=centering)
        if policy == "contain_blurred":
            canvas = ImageEnhance.Brightness(
                ImageOps.fit(source_rgb, (640, 480), method=Image.Resampling.LANCZOS)
            ).enhance(0.55).filter(ImageFilter.GaussianBlur(24))
            foreground = ImageOps.contain(source_rgb, (640, 480),
                                          method=Image.Resampling.LANCZOS)
            x_offset = (640 - foreground.width) // 2
            y_offset = (480 - foreground.height) // 2
            canvas.paste(foreground, (x_offset, y_offset))
            return canvas
        raise ValueError(f"未知封面处理方式：{policy}")


def save_cover(source: Path, target: Path,
               centering: tuple[float, float]) -> dict:
    with Image.open(source) as original:
        source_size = original.size
    image = cover_image(source, "full_bleed", centering)
    image.save(target, format="BMP", bits=24)
    data = target.read_bytes()
    vp._check_cover(data, target.name, 640, 480)
    return {"path": str(target), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "width": 640, "height": 480, "bits_per_pixel": 24,
            "source_dimensions": list(source_size),
            "policy": "full_bleed_content_biased_crop_4_3",
            "centering": list(centering)}


def video_filter(song_number: int, pixel_format: str) -> str:
    source_crop = SOURCE_CROPS.get(song_number)
    parts = ([source_crop] if source_crop else []) + [SCALE_TO_FILL_FILTER]
    if pixel_format == "rgb565le":
        parts.append(f"fps={FPS}")
    parts.append(f"format={pixel_format}")
    return ",".join(parts)


def extract_preview(video: Path, timestamp: float, filter_chain: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{timestamp:.3f}", "-i", str(video), "-map", "0:v:0",
        "-frames:v", "1", "-vf", filter_chain, str(target)], check=True,
        capture_output=True)
    with Image.open(target) as image:
        if image.size != (WIDTH, HEIGHT):
            raise vp.PackError(f"预览尺寸错误：{target} {image.size}")


def convert_center_cropped_video(source: dict, target: Path) -> dict:
    """Convert a complete MV using the visual-stage center-crop policy."""
    partial = target.with_name(target.name + ".partial")
    command = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source["video"]), "-map", "0:v:0", "-an", "-sn", "-dn",
        "-vf", video_filter(int(source["number"]), "rgb565le"),
        "-fps_mode", "passthrough", "-pix_fmt", "rgb565le",
        "-f", "rawvideo", str(partial),
    ]
    try:
        subprocess.run(command, check=True)
        size = partial.stat().st_size
        if size == 0 or size % FRAME_BYTES:
            raise vp.PackError(f"{source['video'].name}输出不是完整RGB565帧：{size}字节")
        frames = size // FRAME_BYTES
        if frames > 65535:
            raise vp.PackError(f"{source['video'].name}超出INDEX v2帧数上限")
        partial.replace(target)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    return {"name": target.name, "path": str(target), "bytes": size,
            "frames": frames, "fps": FPS, "frame_bytes": FRAME_BYTES,
            "sectors": size // 512, "sectors_per_frame": FRAME_BYTES // 512,
            "duration_seconds": frames / FPS,
            "duration_delta_from_video_seconds": frames / FPS -
            source["video_probe"]["duration_seconds"],
            "sha256": sha256_file(target),
            "source_crop": SOURCE_CROPS.get(int(source["number"]), "none"),
            "filter": video_filter(int(source["number"]), "rgb565le"),
            "format": "RGB565LE 320x240 top-down row-major"}


def build_cover_contact_sheet(sources: list[dict], full_bleed_dir: Path,
                              contain_dir: Path, output: Path) -> None:
    cell_w, cell_h, label_h = 640, 480, 30
    sheet = Image.new("RGB", (cell_w * 2, (cell_h + label_h) * 4), "white")
    draw = ImageDraw.Draw(sheet)
    for index, item in enumerate(sources):
        y = index * (cell_h + label_h)
        draw.text((8, y + 7), f"Song {index + 1} / full bleed crop", fill="black")
        draw.text((cell_w + 8, y + 7), f"Song {index + 1} / old contain + blur", fill="black")
        with Image.open(full_bleed_dir / f"PIC{index + 1}.BMP") as image:
            sheet.paste(image.convert("RGB"), (0, y + label_h))
        with Image.open(contain_dir / f"PIC{index + 1}.png") as image:
            sheet.paste(image.convert("RGB").resize(
                (cell_w, cell_h), Image.Resampling.LANCZOS),
                (cell_w, y + label_h))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG", optimize=True)


def build_mv_contact_sheet(sources: list[dict], preview_root: Path, output: Path) -> None:
    labels = ("10%", "50%", "90%")
    col_w, row_h, label_h = WIDTH, HEIGHT, 26
    sheet = Image.new("RGB", (col_w * 9, (row_h + label_h) * 4), "white")
    draw = ImageDraw.Draw(sheet)
    for song_index, _item in enumerate(sources, 1):
        y = (song_index - 1) * (row_h + label_h)
        for policy_index, policy in enumerate(("letterbox", "crop", "source_crop")):
            for sample_index, label in enumerate(labels):
                x = (policy_index * 3 + sample_index) * col_w
                draw.text((x + 7, y + 6),
                          f"Song {song_index} / {policy} / {label}", fill="black")
                frame = preview_root / policy / f"TRACK{song_index}_{label}.png"
                with Image.open(frame) as image:
                    sheet.paste(image.convert("RGB"), (x, y + label_h))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG", optimize=True)


def file_record(path: Path, role: str) -> dict:
    return {"role": role, "path": str(path), "bytes": path.stat().st_size,
            "sha256": sha256_file(path)}


def copy_asset_into_contiguous_file(volume: vp.Fat32Image, name: str, source: Path) -> dict:
    entry = volume.find_root_file(name)
    if source.stat().st_size != entry.size:
        raise vp.PackError(f"{name}目标字节数与卡内目录项不同，拒绝原地扩缩容")
    runs = volume.cluster_runs(entry.first_cluster)
    if len(runs) != 1:
        raise vp.PackError(f"{name}的FAT簇链不连续，拒绝修改")
    lba, allocated_sectors = runs[0]
    allocated_bytes = allocated_sectors * 512
    volume.fh.seek(lba * 512)
    with source.open("rb") as stream:
        shutil.copyfileobj(stream, volume.fh, COPY_CHUNK)
    padding = allocated_bytes - entry.size
    if padding < 0:
        raise vp.PackError(f"{name}文件分配长度小于目录文件长度")
    if padding:
        volume.fh.write(bytes(padding))
    return {"name": name, "lba": lba, "bytes": entry.size,
            "clusters_contiguous": True, "sha256": sha256_file(source)}


def hash_card_file(volume: vp.Fat32Image, entry: vp.DirEntry) -> str:
    runs = volume.cluster_runs(entry.first_cluster)
    if len(runs) != 1:
        raise vp.PackError(f"{entry.name}回读时发现FAT簇链不连续")
    digest = hashlib.sha256()
    volume.fh.seek(runs[0][0] * 512)
    remaining = entry.size
    while remaining:
        chunk = volume.fh.read(min(COPY_CHUNK, remaining))
        if not chunk:
            raise vp.PackError(f"{entry.name}物理数据回读提前结束")
        digest.update(chunk)
        remaining -= len(chunk)
    return digest.hexdigest()


def patch_s3_card(base_card: Path, output_card: Path, covers: list[Path],
                  movies: list[Path], expected_frames: list[int]) -> dict:
    if base_card.resolve() == output_card.resolve():
        raise vp.PackError("输出卡镜像不能覆盖输入S3基线")
    if sha256_file(base_card) != EXPECTED_S3_SHA256:
        raise vp.PackError("输入卡镜像SHA256不是固定的S3歌词基线")
    shutil.copyfile(base_card, output_card)
    changed = []
    with vp.Fat32Image(output_card, writable=True) as volume:
        index_entry = volume.find_root_file("INDEX.BIN")
        if index_entry.size != 512:
            raise vp.PackError("INDEX.BIN不是单扇区，拒绝更新")
        index_blob = bytearray(volume.read_file(index_entry.first_cluster, index_entry.size))
        parsed = vp.parse_index(bytes(index_blob))
        if parsed["count"] != 4 or parsed["version"] != 2:
            raise vp.PackError("输入基线不是四曲INDEX v2")
        if any(not song["flags"] & vp.FLAG_LRC for song in parsed["songs"]):
            raise vp.PackError("输入卡缺少四首LYR2标志")

        for i in range(4):
            cover_name, movie_name = f"PIC{i + 1}.BMP", f"TRACK{i + 1}.MV"
            cover_result = copy_asset_into_contiguous_file(volume, cover_name, covers[i])
            movie_result = copy_asset_into_contiguous_file(volume, movie_name, movies[i])
            if movie_result["bytes"] != expected_frames[i] * FRAME_BYTES:
                raise vp.PackError(f"{movie_name}长度与帧数不匹配")
            if parsed["songs"][i]["mv_frames"] != expected_frames[i]:
                raise vp.PackError(f"{movie_name}新旧帧数变化，拒绝沿用旧INDEX")
            cover_data = covers[i].read_bytes()
            struct_offset = 64 + i * 64
            struct_crc = zlib.crc32(cover_data) & 0xFFFFFFFF
            import struct
            struct.pack_into("<I", index_blob, struct_offset + 12, struct_crc)
            changed.append({"cover": cover_result, "cover_crc32": f"0x{struct_crc:08X}",
                            "mv": movie_result, "frames": expected_frames[i], "fps": FPS})

        entries_crc = zlib.crc32(index_blob[64:64 + parsed["count"] * 64]) & 0xFFFFFFFF
        struct.pack_into("<I", index_blob, 16, entries_crc)
        volume.write_sector(volume.cluster_lba(index_entry.first_cluster), bytes(index_blob))
        volume.fh.flush()

    readback = {"index_entries_crc32": f"0x{entries_crc:08X}", "songs": []}
    with vp.Fat32Image(output_card) as verify:
        index_entry = verify.find_root_file("INDEX.BIN")
        verified_index = vp.parse_index(verify.read_file(index_entry.first_cluster,
                                                         index_entry.size))
        for i, song in enumerate(verified_index["songs"]):
            cover_entry = verify.find_root_file(f"PIC{i + 1}.BMP")
            mv_entry = verify.find_root_file(f"TRACK{i + 1}.MV")
            if hash_card_file(verify, cover_entry) != changed[i]["cover"]["sha256"]:
                raise vp.PackError(f"PIC{i + 1}.BMP卡镜像回读SHA不匹配")
            if zlib.crc32(verify.read_file(cover_entry.first_cluster,
                                           cover_entry.size)) & 0xFFFFFFFF != \
                    song["cover_crc32"]:
                raise vp.PackError(f"PIC{i + 1}.BMP INDEX CRC不匹配")
            if hash_card_file(verify, mv_entry) != changed[i]["mv"]["sha256"]:
                raise vp.PackError(f"TRACK{i + 1}.MV卡镜像回读SHA不匹配")
            readback["songs"].append({"number": i + 1,
                                      "cover_sha256": changed[i]["cover"]["sha256"],
                                      "mv_sha256": changed[i]["mv"]["sha256"],
                                      "mv_lba": song["mv_lba"],
                                      "mv_frames": song["mv_frames"]})
    readback.update({"path": str(output_card), "bytes": output_card.stat().st_size,
                     "sha256": sha256_file(output_card), "verified": True})
    return readback


def build(args: argparse.Namespace) -> dict:
    project = args.project.resolve(strict=True)
    base_card = args.s3_card.resolve(strict=True)
    output_dir = args.output.resolve()
    if output_dir.exists():
        raise vp.PackError(f"输出目录已存在，为避免覆盖请另选新目录：{output_dir}")
    if sha256_file(base_card) != EXPECTED_S3_SHA256:
        raise vp.PackError("S3输入镜像SHA256不符合固定基线")

    sources = s1.discover_sources(project / SOURCE_DIR)
    if len(sources) != 4:
        raise vp.PackError("视觉阶段固定要求四首输入素材")
    for i, source in enumerate(sources):
        expected_cover, expected_video = EXPECTED_MEDIA_SHA256[i]
        if (source["source_cover_sha256"], source["source_video_sha256"]) != \
                (expected_cover, expected_video):
            raise vp.PackError(
                f"第{i + 1}曲输入素材哈希已变化；请先审阅并更新固定输入清单")
    for source in sources:
        source["video_probe"] = s2.probe_video(source["video"])

    output_dir.mkdir(parents=True)
    assets_dir = output_dir / "assets"
    contain_dir = output_dir / "preview" / "cover_contain_blurred"
    mv_preview_root = output_dir / "preview" / "mv"
    for directory in (assets_dir, contain_dir, mv_preview_root / "letterbox",
                      mv_preview_root / "crop", mv_preview_root / "source_crop"):
        directory.mkdir(parents=True, exist_ok=True)

    cover_records, preview_records = [], []
    for i, source in enumerate(sources, 1):
        full_bleed_path = assets_dir / f"PIC{i}.BMP"
        centering = COVER_CENTERING[i]
        cover_records.append(save_cover(source["cover"], full_bleed_path, centering))
        old_style = cover_image(source["cover"], "contain_blurred").resize(
            (WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        contain_preview = contain_dir / f"PIC{i}.png"
        old_style.save(contain_preview, format="PNG", optimize=True)
        preview_records.append(file_record(contain_preview,
                                           f"cover_preview_old_contain_blurred_song{i}"))
        full_preview = output_dir / "preview" / f"cover_full_bleed_{i}.png"
        cover_image(source["cover"], "full_bleed", centering).resize(
            (WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(
                full_preview, format="PNG", optimize=True)
        preview_records.append(file_record(full_preview,
                                           f"cover_preview_full_bleed_song{i}"))

        duration = source["video_probe"]["duration_seconds"]
        for percent in (10, 50, 90):
            timestamp = duration * percent / 100
            label = f"{percent}%"
            source_crop_filter = video_filter(i, "rgb24")
            for policy, filter_chain in (("letterbox", LETTERBOX_FILTER),
                                         ("crop", CENTER_CROP_PREVIEW_FILTER),
                                         ("source_crop", source_crop_filter)):
                preview = mv_preview_root / policy / f"TRACK{i}_{label}.png"
                extract_preview(source["video"], timestamp, filter_chain, preview)
                preview_records.append(file_record(preview, f"mv_preview_{policy}_song{i}_{label}"))

    cover_sheet = output_dir / "preview" / "cover_fill_compare.png"
    mv_sheet = output_dir / "preview" / "mv_crop_compare.png"
    build_cover_contact_sheet(sources, assets_dir, contain_dir, cover_sheet)
    build_mv_contact_sheet(sources, mv_preview_root, mv_sheet)
    preview_records.extend((file_record(cover_sheet, "cover_fill_contact_sheet"),
                            file_record(mv_sheet, "mv_crop_contact_sheet")))

    mv_records = []
    expected_frames = []
    if not args.preview_only:
        for i, source in enumerate(sources, 1):
            target = assets_dir / f"TRACK{i}.MV"
            converted = convert_center_cropped_video(source, target)
            if not 1 <= converted["frames"] <= 65535:
                raise vp.PackError(f"TRACK{i}.MV帧数超出INDEX v2范围")
            expected_frames.append(converted["frames"])
            mv_records.append({**converted, "source_video": str(source["video"]),
                               "source_video_sha256": source["source_video_sha256"],
                               "video_probe": source["video_probe"],
                               "filter": converted["filter"]})

    base_info = None
    with vp.Fat32Image(base_card) as volume:
        index_entry = volume.find_root_file("INDEX.BIN")
        parsed = vp.parse_index(volume.read_file(index_entry.first_cluster,
                                                 index_entry.size))
        base_info = [{"cover_bytes": volume.find_root_file(f"PIC{i + 1}.BMP").size,
                      "mv_bytes": volume.find_root_file(f"TRACK{i + 1}.MV").size,
                      "mv_frames": song["mv_frames"], "mv_lba": song["mv_lba"]}
                     for i, song in enumerate(parsed["songs"])]

    card_record = None
    if not args.preview_only:
        for i in range(4):
            if cover_records[i]["bytes"] != base_info[i]["cover_bytes"]:
                raise vp.PackError(f"PIC{i + 1}.BMP大小与S3基线不同")
            if mv_records[i]["bytes"] != base_info[i]["mv_bytes"]:
                raise vp.PackError(f"TRACK{i + 1}.MV大小与S3基线不同")
            if mv_records[i]["frames"] != base_info[i]["mv_frames"]:
                raise vp.PackError(f"TRACK{i + 1}.MV帧数与S3基线不同")
        output_card = output_dir / "card_VISUAL_S3.img"
        card_record = patch_s3_card(base_card, output_card,
                                   [assets_dir / f"PIC{i}.BMP" for i in range(1, 5)],
                                   [assets_dir / f"TRACK{i}.MV" for i in range(1, 5)],
                                   expected_frames)

    script_path = Path(__file__).resolve()
    manifest = {
        "schema": "vinylfpga-visual-assets-v1",
        "script_version": SCRIPT_VERSION,
        "script_sha256": sha256_file(script_path),
        "source_project": str(project),
        "source_directory": str(project / SOURCE_DIR),
        "base_s3_card": {"path": str(base_card), "bytes": base_card.stat().st_size,
                         "sha256": EXPECTED_S3_SHA256},
        "tools": {"python": sys.version.split()[0], "pillow": PIL.__version__,
                  "ffmpeg": command_version("ffmpeg"),
                  "ffprobe": command_version("ffprobe")},
        "policies": {
            "cover": {"canvas": [640, 480], "format": "24-bit BMP",
                      "policy": "full bleed 4:3 center crop using LANCZOS",
                      "per_song_centering": COVER_CENTERING,
                      "no_padding_or_blurred_bars": True},
            "mv": {"canvas": [WIDTH, HEIGHT], "fps": FPS,
                   "pixel_format": "RGB565LE", "frame_bytes": FRAME_BYTES,
                   "sectors_per_frame": 300,
                   "scale_and_crop_filter": SCALE_TO_FILL_FILTER,
                   "source_crops_from_0d25421": SOURCE_CROPS,
                   "policy": "remove known embedded mattes, then fill 4:3 with center crop; no padding"},
            "preview_samples": ["10%", "50%", "90%"]},
        "inputs": [{"song": i, "cover": {"path": str(source["cover"]),
                                            "bytes": source["cover"].stat().st_size,
                                            "sha256": source["source_cover_sha256"],
                                            "dimensions": list(Image.open(source["cover"]).size)},
                    "video": {"path": str(source["video"]),
                              "bytes": source["video"].stat().st_size,
                              "sha256": source["source_video_sha256"],
                              "probe": source["video_probe"]}}
                   for i, source in enumerate(sources, 1)],
        "outputs": {"cover_fill_compare": file_record(cover_sheet, "cover_contact_sheet"),
                    "mv_crop_compare": file_record(mv_sheet, "mv_contact_sheet"),
                    "cover_assets": cover_records,
                    "mv_assets": mv_records,
                    "preview_files": preview_records,
                    "card": card_record,
                    "base_card_layout": base_info},
        "checks": {"all_covers_640x480_24bit": True,
                   "preview_frames_320x240": True,
                   "mv_frame_lengths_match_index": card_record is not None,
                   "card_readback_sha_and_index_crc": card_record is not None}}
    manifest_path = output_dir / "visual_assets_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--s3-card", type=Path, default=DEFAULT_S3_CARD)
    parser.add_argument("--output", type=Path, required=True,
                        help="只能指定新的目录；输出资源/预览/清单，不访问物理SD卡")
    parser.add_argument("--preview-only", action="store_true",
                        help="只生成封面与MV对照预览，不解码全长MV、不写新卡镜像")
    args = parser.parse_args(argv)
    try:
        manifest = build(args)
        print(json.dumps({"result": "VISUAL_ASSETS_PREVIEW_OK" if args.preview_only
                          else "VISUAL_ASSETS_S3_IMAGE_OK",
                          "output": str(args.output.resolve()),
                          "script_version": SCRIPT_VERSION,
                          "script_sha256": manifest["script_sha256"],
                          "card": manifest["outputs"]["card"],
                          "previews": [manifest["outputs"]["cover_fill_compare"],
                                       manifest["outputs"]["mv_crop_compare"]]},
                         ensure_ascii=False, indent=2))
        return 0
    except (vp.PackError, OSError, ValueError, subprocess.CalledProcessError,
            json.JSONDecodeError) as error:
        print(f"VISUAL_ASSETS_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
