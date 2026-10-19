"""Regenerate the actual four-song lyrics and verify ROM/LYR2 reproducibility."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

import prepare_s3_lyrics as prep
import gen_lrc_assets as generator

ROOT = Path(__file__).resolve().parents[1]
ROM_FILES = ('src/display/song_text_rom.v', 'src/display/song_font_rom.v',
             'src/include/song_text_geom.vh')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--update-rom', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    asset_dir = output / 'assets'
    asset_dir.mkdir()
    tracks, media = prep.build_tracks(ROOT, asset_dir)
    expected = [{k: t[k] for k in ('song_id', 'title', 'artist', 'rows')} for t in tracks]
    binary = prep.encode_lyr2(tracks)
    if prep.decode_lyr2(binary) != expected:
        raise RuntimeError('LYR2 complete decode differs from calibrated source')
    (asset_dir / prep.LYRICS_NAME).write_bytes(binary)
    manifest = {'glyph_banks': True, 'tracks': [
        {k: t[k] for k in ('song_id', 'title', 'display_title', 'artist', 'lrc')} for t in tracks]}
    manifest_path = asset_dir / 'songs_manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    generated = generator.generate_song_text_assets(manifest_path, output / 'generated')
    generator.generate_song_text_assets(manifest_path, output / 'repeat')
    for rel in ROM_FILES:
        first = (output / 'generated' / rel).read_text(encoding='utf-8')
        if first != (output / 'repeat' / rel).read_text(encoding='utf-8'):
            raise RuntimeError('Non-reproducible generation: ' + rel)
        if args.update_rom:
            shutil.copyfile(output / 'generated' / rel, ROOT / rel)
        if first != (ROOT / rel).read_text(encoding='utf-8'):
            raise RuntimeError('Checked-in ROM is stale: ' + rel)
    rom = (output / 'generated/src/display/song_text_rom.v').read_text(encoding='utf-8')
    chunks = [{int(a): int(v, 16) for a, v in re.findall(
        rf"glyph_mem_{part}\[(\d+)\] = 32'h([0-9A-F]+)", rom)} for part in range(4)]
    times = {int(a): int(v, 16) for a, v in re.findall(
        r"time_length_mem\[(\d+)\] = 23'h([0-9A-F]+)", rom)}
    flat_index = 0
    details = []
    for track in tracks:
        duration_ms = int(media[track['song_id'] + 1]['source_duration_seconds'] * 1000)
        previous = -1
        chars = generated['bank_chars'][track['song_id'] // 2]
        for stamp, text in track['rows']:
            if not previous < stamp < min(1 << 18, duration_ms + 1):
                raise RuntimeError('Lyric timestamp outside hardware/media bounds')
            if not text.strip(' ♪♫') or not 1 <= len(text) <= 16:
                raise RuntimeError('Empty/decorative/oversized lyric row')
            word = times[flat_index]
            packed = sum(chunks[p][flat_index] << (p * 32) for p in range(4))
            decoded = ''.join(chars[(packed >> (8 * i)) & 255] for i in range(len(text)))
            if decoded != text or word >> 5 != stamp or word & 31 != len(text):
                raise RuntimeError('ROM glyph/timestamp round trip mismatch')
            previous = stamp
            flat_index += 1
        details.append({'song_id': track['song_id'], 'source_cues': track['source_cue_count'],
                        'calibrated_cues': track['cue_count'], 'rows': len(track['rows']),
                        'offset_ms': track['timeline_offset_ms'], 'last_row_ms': previous,
                        'duration_ms': duration_ms, 'source_srt': track['source_srt'],
                        'source_srt_sha256': track['source_srt_sha256']})
    inputs = [*ROM_FILES, 'tools/prepare_s3_lyrics.py', 'tools/gen_lrc_assets.py',
              'tools/verify_calibrated_lyrics.py',
              'doc/资源/sd卡/歌曲素材/lyrics_manual_calibration.json']
    summary = {'passed': True, 'rows': flat_index, 'tracks': details,
               'font_glyphs': list(map(len, generated['bank_chars'])),
               'font_depth': generated['font_depth'],
               'lyr2_sha256': hashlib.sha256(binary).hexdigest(),
               'inputs_sha256': {p: prep.sha256_file(ROOT / p) for p in inputs},
               'checks': ['LYR2 full CRC decode', 'two clean generations match',
                          'checked-in ROM matches', 'all ROM glyph IDs and timestamps round-trip',
                          '128 rows / 16 glyphs / 18-bit timestamps / media duration bounds'],
               'listening_alignment_verified': False}
    (output / 'results.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS calibrated lyrics:', ', '.join(str(t['rows']) for t in details), 'rows;', flat_index, 'total')
    print('PASS LYR2 CRC / ROM glyphs / timestamps / fonts / repeatability; font depth', generated['font_depth'])
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
