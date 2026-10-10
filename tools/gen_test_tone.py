#!/usr/bin/env python3
"""Generate a deterministic raw 48 kHz, signed 16-bit mono PCM demo tone."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path


def generate_pcm(
    sample_rate_hz: int = 48_000,
    frequency_hz: float = 1_000.0,
    duration_seconds: float = 5.0,
    peak_dbfs: float = -12.0,
) -> bytes:
    """Return headerless little-endian signed 16-bit mono PCM samples."""
    if sample_rate_hz <= 0:
        raise ValueError("sample_rate_hz must be positive")
    if not math.isfinite(frequency_hz) or frequency_hz <= 0 or frequency_hz >= sample_rate_hz / 2:
        raise ValueError("frequency_hz must be finite and strictly below Nyquist")
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        raise ValueError("duration_seconds must be finite and positive")
    if not math.isfinite(peak_dbfs) or peak_dbfs > 0 or peak_dbfs < -96:
        raise ValueError("peak_dbfs must be between -96 dBFS and 0 dBFS")

    frame_count = int(round(sample_rate_hz * duration_seconds))
    if frame_count <= 0:
        raise ValueError("duration_seconds is too short to produce a sample")
    amplitude = 32767.0 * (10.0 ** (peak_dbfs / 20.0))
    period_samples = sample_rate_hz / frequency_hz
    exact_period = round(period_samples)
    periodic_integer = math.isclose(period_samples, exact_period, rel_tol=0.0, abs_tol=1e-12)

    pcm = bytearray(frame_count * 2)
    for index in range(frame_count):
        phase_index = (index % exact_period) if periodic_integer else index
        phase = math.tau * frequency_hz * phase_index / sample_rate_hz
        sample = int(round(amplitude * math.sin(phase)))
        struct.pack_into("<h", pcm, index * 2, sample)
    return bytes(pcm)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="destination raw PCM path (must not exist)")
    parser.add_argument("--sample-rate", type=int, default=48_000)
    parser.add_argument("--frequency", type=float, default=1_000.0)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--peak-dbfs", type=float, default=-12.0)
    args = parser.parse_args(argv)

    if args.output.exists():
        parser.error(f"output already exists: {args.output}")
    pcm = generate_pcm(args.sample_rate, args.frequency, args.duration, args.peak_dbfs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(pcm)
    print(json.dumps({
        "path": str(args.output.resolve()),
        "format": "raw PCM, signed 16-bit little-endian, mono",
        "sample_rate_hz": args.sample_rate,
        "frequency_hz": args.frequency,
        "duration_seconds": args.duration,
        "peak_dbfs": args.peak_dbfs,
        "frames": len(pcm) // 2,
        "bytes": len(pcm),
        "sha256": hashlib.sha256(pcm).hexdigest(),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
