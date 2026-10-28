"""Run seek timeline and actual PCM restart integration regressions."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    'tb_seek_posjump': ['sim/fixF_20261028/tb_seek_posjump.v',
        'src/audio/timebase_48k.v', 'src/video/s6_video_layer.v',
        'src/video/mv_frame_scheduler.v'],
    'tb_seek_pcm_session': ['sim/fixF_20261028/tb_seek_pcm_session.v',
        'src/audio/seek_controller.v', 'src/audio/stream_session.v',
        'src/audio/wav_stream_player.v'],
}
with tempfile.TemporaryDirectory(prefix='vinyl_seek_') as tmp:
    for name, sources in CASES.items():
        exe = str(Path(tmp) / (name + '.vvp'))
        subprocess.run(['iverilog', '-g2012', '-Isrc', '-s', name, '-o', exe, *sources],
                       cwd=ROOT, check=True)
        result = subprocess.run(['vvp', exe], cwd=ROOT, text=True,
                                capture_output=True, check=True, timeout=120)
        print(result.stdout, end='')
        if 'PASS' not in result.stdout or 'FAIL' in result.stdout:
            raise SystemExit(f'{name}: missing pass or failure reported')
