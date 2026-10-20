"""Reproduce final-review boundary defects and verify their fixes."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

from verify_finish_rtl import ROOT, top_compile_options

CASES = {
    'axis_lines': ('tb_final_axis_lines', ['src/video_rgb_to_axis_640x480.v'], []),
    'ec2_reopen': ('tb_final_ui_boundaries', ['src/io/ec2_param_controller.v', 'src/io/ui_command_router.v', 'src/io/ui_event_bridge.v'], ['+case=1']),
    'encoder_wake': ('tb_final_ui_boundaries', ['src/io/ec2_param_controller.v', 'src/io/ui_command_router.v', 'src/io/ui_event_bridge.v'], ['+case=2']),
    'ir_disabled': ('tb_final_ui_boundaries', ['src/io/ec2_param_controller.v', 'src/io/ui_command_router.v', 'src/io/ui_event_bridge.v'], ['+case=3']),
    'ec2_wake': ('tb_final_ui_boundaries', ['src/io/ec2_param_controller.v', 'src/io/ui_command_router.v', 'src/io/ui_event_bridge.v'], ['+case=4']),
    'fat_multicluster': ('tb_fat32_streamer_boundaries', ['src/SD/fat32_file_streamer.v'], []),
    'browse_text': ('tb_final_browse_text', ['src/display/playback_page.v', 'src/display/playback_background.v', 'src/display/lrc_five_osd.v', 'src/display/song_text_rom.v', 'src/display/song_font_rom.v'], []),
    'wave_fullscale': ('tb_final_wave_fullscale', ['src/display/promax_audio_waveform.v'], []),
    'audio_prefill': ('tb_final_audio_prefill_cadence', ['src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'], []),
    'bmp_offset': ('tb_final_bmp_offset', ['src/SD/fat32_volume_scanner.v', 'src/SD/fat32_file_streamer.v', 'src/SD/sd_sector_adapter.v', 'src/SD/song_index_db.v', 'src/SD/fat32_media_loader.v'], []),
}


def modelsim_case(folder, name, top, files, options, vsim):
    folder.mkdir()
    args = ['-sv'] if name == 'fat_multicluster' else []
    if name == 'audio_prefill':
        args += ['+define+VINYL_AUDIO_CACHE_SIM', '+libext+.v']
        directories = [ROOT / 'src', ROOT / 'sim',
                       *(p for p in (ROOT / 'src').iterdir() if p.is_dir() and p.name != 'IP')]
        args += ['-y {' + p.as_posix() + '}' for p in directories]
    args += ['+incdir+' + (ROOT / p).as_posix() for p in ('src', 'src/include', 'src/SD')]
    args += ['{' + (ROOT / f).as_posix() + '}' for f in files]
    if name == 'audio_prefill':
        signals = ['audio_valid', 'acr_valid', 'audio_silent', 'wav_startup_ready',
                   'cache_playback_ready_video', 'stream_enable_vid', 'wav_sample_consumed']
        wave = '\n'.join('log /' + top + '/dut/' + s + '\nadd wave /' + top + '/dut/' + s for s in signals)
    else:
        wave = 'log -r /*\nadd wave -r /*'
    (folder / 'wave.do').write_text(wave + '\n', encoding='utf-8')
    (folder / 'compile.f').write_text('\n'.join((ROOT / f).as_posix() for f in files) + '\n', encoding='utf-8')
    script = ['onerror {quit -force -code 1}', 'vlib work', 'vmap work work',
              'vlog ' + ' '.join(args),
              'vsim -voptargs=+acc -wlf waves.wlf work.' + top + ' ' + ' '.join(options),
              'onfinish stop', 'do wave.do', 'run -all', 'quit -force -code 0']
    (folder / 'run.do').write_text('\n'.join(script) + '\n', encoding='utf-8')
    ran = subprocess.run([str(vsim), '-c', '-do', 'run.do'], cwd=folder,
                         text=True, capture_output=True, errors='replace', timeout=180)
    log = ran.stdout + ran.stderr
    code = ran.returncode
    wlf = folder / 'waves.wlf'
    if wlf.is_file() and wlf.stat().st_size > 0:
        converted = subprocess.run([str(vsim.with_name('wlf2vcd.exe')), '-o', 'waveform.vcd', 'waves.wlf'],
                                   cwd=folder, text=True, capture_output=True, errors='replace', timeout=90)
        log += converted.stdout + converted.stderr
        if converted.returncode:
            code = converted.returncode
    if not all((folder / f).is_file() and (folder / f).stat().st_size > 0
               for f in ('waves.wlf', 'waveform.vcd')):
        code = code or 1
    return code, log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=CASES, action='append')
    parser.add_argument('--simulator', choices=('icarus', 'modelsim'), default='icarus')
    parser.add_argument('--vsim', type=Path, default=Path('D:/modeltech64_10.6e/win64/vsim.exe'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    for name in args.case or CASES:
        top, sources, options = CASES[name]
        if top == 'tb_final_ui_boundaries':
            sources = [*sources, 'src/io/ec2_event_replay.v']
        files = [*sources, 'sim/' + top + '.v']
        inputs = set(files) | {'src/include/exp_event_defs.vh'}
        if name == 'audio_prefill':
            inputs.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'src').rglob('*') if p.is_file())
        hashes = {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in sorted(inputs)}
        target = (args.output / (name + '.vvp')).resolve()
        compile_options = top_compile_options() if name == 'audio_prefill' else []
        language = '-g2005' if name in ('browse_text', 'audio_prefill') else '-g2012'
        if args.simulator == 'modelsim':
            code, log = modelsim_case((args.output / name).resolve(), name, top, files, options, args.vsim)
        else:
            compiled = subprocess.run(['iverilog', language, *compile_options, '-Isrc/include', '-s', top, '-o', str(target), *files],
                                      cwd=ROOT, text=True, capture_output=True)
            log = compiled.stdout + compiled.stderr
            code = compiled.returncode
            if not code:
                ran = subprocess.run(['vvp', str(target), *options], cwd=ROOT, text=True, capture_output=True, timeout=180)
                log += ran.stdout + ran.stderr
                code = ran.returncode
        stable = all(hashlib.sha256((ROOT / f).read_bytes()).hexdigest() == h for f, h in hashes.items())
        passed = (stable and code == 0 and re.search(r'\bPASS\b', log) is not None
                  and re.search(r'\b(?:FAIL|FATAL|Fatal|ERROR)\b|\*\* Error:', log) is None)
        (args.output / (name + '.log')).write_text(log, encoding='utf-8')
        results.append({'test': name, 'passed': passed, 'exit': code,
                        'simulator': args.simulator, 'inputs_unchanged': stable, 'inputs_sha256': hashes})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(log[-1500:], flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
