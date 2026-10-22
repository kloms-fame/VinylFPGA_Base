"""Verify KEY6 lyric focus, existing lyric boundaries and actual top wiring."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

from verify_finish_rtl import ROOT, top_compile_options

PAGE = ['src/display/playback_page.v', 'src/display/playback_background.v',
        'src/display/lrc_five_osd.v', 'src/display/song_font_rom.v']
CASES = {
    'tb_lyric_focus': ['src/io/ui_event_bridge.v', *PAGE],
    'tb_lyric_focus_top': ['src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'],
    'tb_lrc_window_boundaries': ['src/display/lrc_window_controller.v', 'src/display/lrc_five_osd.v'],
    'tb_ui_event_bridge_key_decode': ['src/io/ui_event_bridge.v'],
    'tb_ui_event_bridge_browse_integration': ['src/io/ui_event_bridge.v', 'src/io/browse_fsm.v'],
    'tb_ui_encoder_gap': ['src/io/ui_event_bridge.v'],
    'tb_playback_page_glyph_select': ['src/display/playback_page.v'],
    'tb_stage3a_page': ['src/io/ui_event_bridge.v', 'src/io/browse_fsm.v',
                         'src/display/ascii_font_rom.v', *PAGE],
}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    results=[]
    for top,sources in CASES.items():
        files=[*sources,'sim/'+top+'.v']
        input_paths={path for path in (ROOT/'src').rglob('*') if path.is_file()}
        input_paths.update(ROOT/f for f in files)
        inputs={path.relative_to(ROOT).as_posix():hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(input_paths)}
        options=top_compile_options() if top=='tb_lyric_focus_top' else []
        image=(a.output/(top+'.vvp')).resolve()
        compiled=subprocess.run(['iverilog','-g2005',*options,'-Isrc/include','-s',top,
                                 '-o',str(image),*files],cwd=ROOT,capture_output=True,text=True)
        log=compiled.stdout+compiled.stderr
        code=compiled.returncode
        if code==0:
            run=subprocess.run(['vvp',str(image)],cwd=ROOT,capture_output=True,text=True,timeout=120)
            code=run.returncode;log+=run.stdout+run.stderr
        stable=all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==v for f,v in inputs.items())
        passed=stable and code==0 and bool(re.search(r'\b(?:PASS|TEST_PASS)\b',log)) and not re.search(r'\b(?:FAIL|FATAL|ERROR)\b',log)
        (a.output/(top+'.log')).write_text(log,encoding='utf-8')
        results.append({'test':top,'passed':bool(passed),'exit':code,'inputs_unchanged':stable,'inputs_sha256':inputs})
        print(top,'PASS' if passed else 'FAIL',flush=True)
        if not passed:print(log[-2500:],flush=True)
    (a.output/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1

if __name__=='__main__':raise SystemExit(main())
