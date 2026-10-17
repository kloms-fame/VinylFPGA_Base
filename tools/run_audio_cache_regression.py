"""Run audio SDRAM cache and affected media regressions with Icarus Verilog."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, help='New evidence directory; must not exist')
a = p.parse_args()
OUT = (a.out or ROOT / ('sim/audio_cache/regression_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))).resolve()
OUT.mkdir(parents=True, exist_ok=False)
CASES = {
    "tb_audio_sdram_dma": ["src/audio/audio_sdram_dma.v", "sim/audio_cache/tb_audio_sdram_dma.v"],
    "tb_audio_sdram_arbiter": ["src/audio/audio_sdram_arbiter.v", "sim/audio_cache/tb_audio_sdram_arbiter.v"],
    "tb_audio_prefetch_sdram": ["src/audio/audio_prefetch_stage.v", "src/audio/audio_sdram_dma.v",
                                  "src/audio/audio_prefetch_sdram.v", "sim/audio_cache/tb_audio_prefetch_sdram.v"],
    "tb_audio_prefetch_reserve": ["src/audio/audio_prefetch_stage.v", "src/audio/audio_sdram_dma.v",
                                  "src/audio/audio_prefetch_sdram.v", "sim/audio_cache/tb_audio_prefetch_reserve.v"],
    "tb_wav_startup_ready": ["src/audio/wav_stream_player.v", "sim/audio_cache/tb_wav_startup_ready.v"],
    "tb_wav_stream_player": ["src/audio/wav_stream_player.v", "sim/tb_wav_stream_player.v"],
    "tb_wav_underrun": ["src/audio/wav_stream_player.v", "sim/tb_wav_underrun.v"],
    "tb_s7_session": ["src/audio/stream_session.v", "sim/tb_s7_session.v"],
    "tb_background_sector_mux": ["src/video/background_sector_mux.v", "sim/tb_background_sector_mux.v"],
    "tb_media_write_pipeline": ["src/video/media_write_pipeline.v", "sim/tb_media_write_pipeline.v"],
    "tb_mv_linear_write": ["src/SD/frame_fifo_write.v", "sim/tb_mv_linear_write.v"],
    "tb_mv_frame_scheduler": ["src/video/mv_frame_scheduler.v", "sim/tb_mv_frame_scheduler.v"],
    "tb_frame_fifo_read_pace": ["src/SD/frame_fifo_read.v", "src/video/background_raster_address.v",
                                 "sim/tb_frame_fifo_read_pace.v"],
    "tb_audio_dma_late_return": ["src/audio/audio_sdram_dma.v", "sim/audio_cache/tb_audio_dma_late_return.v"],
    "tb_fat32_streamer_boundaries": ["src/SD/fat32_file_streamer.v", "sim/tb_fat32_streamer_boundaries.v"],
    "tb_wav_stream_player_flow": ["src/audio/wav_stream_player.v", "sim/tb_wav_stream_player_flow.v"],
    "tb_background_index": ["src/SD/song_index_db.v", "sim/tb_background_index.v"],
    "tb_song_index_db": ["src/SD/song_index_db.v", "sim/tb_song_index_db.v"],
    "tb_song_index_decode": ["src/SD/song_index_db.v", "sim/tb_song_index_decode.v"],
    "tb_background_cache_loader": ["src/video/background_cache_loader.v", "sim/tb_background_cache_loader.v"],
    "tb_background_cache_full_frame": ["src/video/background_cache_loader.v", "sim/tb_background_cache_full_frame.v"],
    "tb_background_capability": ["src/video/background_cache_loader.v", "sim/tb_background_capability.v"],
    "tb_x2_seek": ["src/audio/seek_controller.v", "sim/tb_x2_seek.v"],
    "tb_x2_seek_wav": ["src/audio/wav_stream_player.v", "src/audio/timebase_48k.v", "sim/tb_x2_seek_wav.v"],
}

LOADER_SOURCES = ['src/SD/fat32_volume_scanner.v','src/SD/fat32_file_streamer.v',
                  'src/SD/sd_sector_adapter.v','src/SD/song_index_db.v','src/SD/fat32_media_loader.v']
for loader_test in ['tb_fat32_media_loader','tb_fat32_index_loader','tb_closure_header_compare',
                    'tb_header_payload_bounds','tb_audio_metadata_valid']:
    CASES[loader_test] = [*LOADER_SOURCES, 'sim/'+loader_test+'.v']

results = []
for name, files in CASES.items():
    image, log = OUT / f"{name}.vvp", OUT / f"{name}.log"
    compile_flags = ["-DVINYL_AUDIO_CACHE_SIM"] if name in ["tb_audio_prefetch_sdram", "tb_audio_prefetch_reserve"] else []
    compile_result = subprocess.run(["iverilog", "-g2012", "-Isrc/include", *compile_flags, "-s", name, "-o", str(image), *files],
                                    cwd=ROOT, text=True, capture_output=True)
    transcript = compile_result.stdout + compile_result.stderr
    status = compile_result.returncode
    if status == 0:
        try:
            # The late-return bench exports a waveform. Keep it with this run.
            run = subprocess.run(["vvp", str(image)], cwd=OUT if name == 'tb_audio_dma_late_return' else ROOT,
                                 text=True, capture_output=True, timeout=600 if name == 'tb_audio_prefetch_reserve' else 180)
            transcript += run.stdout + run.stderr
            status = run.returncode
        except subprocess.TimeoutExpired as exc:
            transcript += str(exc.stdout or "") + str(exc.stderr or "") + "\nTIMEOUT\n"
            status = 124
    log.write_text(transcript, encoding="utf-8")
    passed = status == 0 and "PASS" in transcript and not any(word in transcript for word in ['FAIL', 'ERROR', 'FATAL'])
    results.append({"test": name, "pass": passed, "exit": status,
                    "inputs_sha256": {f: hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files}})
    print(f"{'PASS' if passed else 'FAIL'} {name} ({log})", flush=True)

(OUT / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
sys.exit(0 if all(item["pass"] for item in results) else 1)
