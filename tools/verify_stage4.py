"""Batched Stage 4 regression; require positive evidence even from old benches."""
from pathlib import Path
import argparse
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iverilog', default='D:/iverilog/bin/iverilog.exe')
    parser.add_argument('--vvp', default='D:/iverilog/bin/vvp.exe')
    parser.add_argument('--output', type=Path, default=ROOT / 'sim/resource_opt_verified/stage4')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    page = ['src/display/playback_background.v', 'src/display/playback_page.v',
            'src/display/lrc_five_osd.v', 'src/display/song_font_rom.v',
            'src/display/ascii_font_rom.v', 'src/io/ui_event_bridge.v', 'src/io/browse_fsm.v']
    writer = ['src/video/media_write_pipeline.v', 'src/video/background_cache_loader.v',
              'src/video/background_sector_mux.v', 'src/video/mv_stream_player.v',
              'src/SD/frame_fifo_write.v', 'src/sync_2ff.v']
    raster = ['src/video/background_raster_address.v', 'src/SD/frame_fifo_read.v']
    cases = [
        ('tb_playback_background', [], ['src/display/playback_background.v']),
        ('tb_stage3a_page', [], page),
        ('tb_stage3b_page', [], ['sim/tb_stage3a_page.v'] + page),
        ('tb_background_frame_select', [], ['src/video/background_frame_select.v']),
        ('tb_background_cache_loader', [], ['src/video/background_cache_loader.v']),
        ('tb_background_cache_full_frame', [], ['src/video/background_cache_loader.v']),
        ('tb_background_sector_mux', [], ['src/video/background_sector_mux.v']),
        ('tb_background_index', [], ['src/SD/song_index_db.v']),
        ('tb_song_index_db', [], ['src/SD/song_index_db.v']),
        ('tb_stage3b_raster_read', [], raster),
        ('tb_stage3b_raster_read', ['-Ptb_stage3b_raster_read.BURST_WORDS=256'], raster),
        ('tb_stage4_cache_transaction', [], writer),
        ('tb_stage3b_shared_writer', [], writer),
        ('tb_stage3b_shared_writer', ['-Ptb_stage3b_shared_writer.SHORT_ART=1'], writer),
        ('tb_frame_fifo_read_pace', [], raster),
        ('tb_frame_fifo_read_gap', [], raster),
        ('tb_frame_fifo_write', [], ['src/SD/frame_fifo_write.v']),
        ('tb_mv_linear_write', [], ['src/SD/frame_fifo_write.v']),
        ('tb_closure_write_geometry', [], ['src/SD/frame_fifo_write.v']),
        ('tb_s6_video_layer', [], ['src/video/s6_video_layer.v', 'src/video/mv_frame_scheduler.v', 'src/io/ui_event_bridge.v']),
        ('tb_s6_cover_mv_only', [], ['src/video/s6_video_layer.v', 'src/video/mv_frame_scheduler.v']),
    ]
    results = []
    for number, (top, options, files) in enumerate(cases):
        name = f'{number:02d}_{top}'
        target = args.output / (name + '.vvp')
        command = [args.iverilog, '-g2005', '-Isrc/include', '-s', top, '-o', str(target)]
        compiled = subprocess.run(command + options + ['sim/' + top + '.v'] + files,
                                  cwd=ROOT, capture_output=True, text=True, errors='replace', timeout=90)
        log = compiled.stdout + compiled.stderr
        ok = compiled.returncode == 0
        if ok:
            ran = subprocess.run([args.vvp, str(target)], cwd=ROOT, capture_output=True,
                                 text=True, errors='replace', timeout=150)
            log += ran.stdout + ran.stderr
            ok = (ran.returncode == 0 and re.search(r'\b(?:PASS|TEST_PASS)\b', log) is not None
                  and re.search(r'\b(?:FAIL|FATAL)\b', log) is None)
        (args.output / (name + '.log')).write_text(log, encoding='utf-8')
        results.append({'name': name, 'passed': ok})
        print(name, 'PASS' if ok else 'FAIL', flush=True)
        if not ok:
            print(log[-3000:], flush=True)
    (args.output / 'regression_summary.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(case['passed'] for case in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
