#!/usr/bin/env python3
"""Clone a known VinylFPGA FAT32 card image and replace only its demo AUDIO.PCM."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
from pathlib import Path

import vinyl_packer as vp


def replace_audio_in_image(image_path: Path, pcm_path: Path) -> None:
    """Replace the root AUDIO.PCM payload and truncate its private FAT chain."""
    pcm = pcm_path.read_bytes()
    if not pcm or len(pcm) & 1:
        raise ValueError("PCM must contain a non-empty even number of bytes")

    with vp.Fat32Image(image_path, writable=True) as image:
        entry = image.find_root_file("AUDIO.PCM")
        if entry.first_cluster < 2:
            raise vp.PackError("AUDIO.PCM has no valid first cluster")

        cluster_bytes = image.bytes_per_sector * image.sectors_per_cluster
        cluster_count = math.ceil(len(pcm) / cluster_bytes)
        chain = list(image.iter_chain(entry.first_cluster))
        if len(chain) < cluster_count:
            raise vp.PackError(
                f"AUDIO.PCM allocation has {len(chain)} clusters; {cluster_count} required")
        used = chain[:cluster_count]
        if any(b != a + 1 for a, b in zip(used, used[1:])):
            raise vp.PackError("test audio allocation is not physically contiguous")

        offset = 0
        for cluster in used:
            first_lba = image.cluster_lba(cluster)
            for sector_offset in range(image.sectors_per_cluster):
                if offset >= len(pcm):
                    break
                block = pcm[offset:offset + image.bytes_per_sector]
                image.write_sector(first_lba + sector_offset,
                                   block.ljust(image.bytes_per_sector, b"\x00"))
                offset += len(block)

        # The original demo track is much larger. Stop the FAT chain at the new
        # final cluster so the packer and player see only the five-second sample.
        image.fat_set(used[-1], 0x0FFFFFFF)
        root_sector = bytearray(image.read_sector(entry.lba))
        struct.pack_into("<I", root_sector, entry.slot_off + 28, len(pcm))
        image.write_sector(entry.lba, bytes(root_sector))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def create_demo_image(source_image: Path, pcm_path: Path, output_image: Path,
                      report_path: Path) -> dict:
    source_image = source_image.resolve()
    pcm_path = pcm_path.resolve()
    output_image = output_image.resolve()
    report_path = report_path.resolve()
    if not source_image.is_file() or not pcm_path.is_file():
        raise FileNotFoundError("source image and PCM file must both exist")
    if output_image in (source_image, pcm_path) or output_image.exists():
        raise FileExistsError(f"output image must be a new path: {output_image}")
    if report_path.exists():
        raise FileExistsError(f"report already exists: {report_path}")

    output_image.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_image, output_image)
    replace_audio_in_image(output_image, pcm_path)

    pack_report = report_path.with_suffix(".pack.json")
    pack_result = vp.main(["pack", "--image", str(output_image), "--demo",
                           "--report", str(pack_report)])
    if pack_result != 0:
        raise RuntimeError(f"vinyl_packer pack failed with status {pack_result}")
    verify_result = vp.main(["verify", "--image", str(output_image)])
    if verify_result != 0:
        raise RuntimeError(f"vinyl_packer verify failed with status {verify_result}")

    result = {
        "source_image": str(source_image),
        "source_image_sha256": sha256(source_image),
        "output_image": str(output_image),
        "output_image_sha256": sha256(output_image),
        "audio_path_in_card": "AUDIO.PCM (Track 1 only)",
        "audio_bytes": pcm_path.stat().st_size,
        "audio_sha256": sha256(pcm_path),
        "pack_report": str(pack_report),
        "index_verified": True,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-image", required=True, type=Path)
    parser.add_argument("--pcm", required=True, type=Path)
    parser.add_argument("--output-image", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args(argv)
    result = create_demo_image(args.source_image, args.pcm, args.output_image, args.report)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
