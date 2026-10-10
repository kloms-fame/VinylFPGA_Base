"""S7 acceptance fixes: observable behavior, error injection and data scoreboards."""
from pathlib import Path
import argparse, subprocess, json, sys
R=Path(__file__).resolve().parents[1]
PRODUCTION_TESTS = (
    'tb_s7_ir_encoder','tb_browse_fsm','tb_s3_browse_integration','tb_video_fade_transition','tb_boot_window','tb_s7_media_lifecycle','tb_s7_wav_restart','tb_s7_encoder','tb_health_monitor','tb_media_supervisor','tb_s7_recovery_clear','tb_s7_browse_semantics','tb_s7_play_policy','tb_s7_switch',
    'tb_s7_probe_mux','tb_s7_probe','tb_s7_session','tb_s7_top','tb_wav_stream_player','tb_wav_stream_player_flow',
    'tb_wav_underrun','tb_mv_sector_mux','tb_mv_stream_player','tb_mv_frame_scheduler',
    'tb_mv_audio_shared','tb_s6_video_layer','tb_sd_sector_adapter_timeout','tb_sd_card_bmp_fourbank',
    'tb_fat32_index_loader','tb_fat32_file_streamer','tb_fat32_volume_scanner',
    'tb_thumbnail_view_reader','tb_sdram_rd_arbiter','tb_s5_play','tb_expansion_s1','tb_io_startup_dip',
    'tb_x2_seek','tb_x2_seek_wav','tb_opt_no_uart','tb_opt_osd_bypass','tb_debounce_bank','tb_debounce_monitors','tb_lrc_font_sync','tb_lrc_osd_equiv','tb_x1x2_display','tb_opt_metadata','tb_cdc_bundle_latest','tb_frame_read_ack_cdc','tb_ui_encoder_gap','tb_x1x2_lights','tb_ws_vu_only','tb_visual_feedback_top')
TOP_LEVEL_TESTS = frozenset(('tb_s7_top','tb_opt_osd_bypass','tb_opt_metadata','tb_visual_feedback_top'))

def is_archived_accepted(output):
    return any((output / marker).exists() for marker in ('ACCEPTED', 'accepted.json', 'accepted.md'))

def run(name, output, path=None):
    src=path or R/'sim'/f'{name}.v'
    cmd=['iverilog','-g2005','-I.','-Isrc','-Isrc/include','-Isrc/SD']
    for d in ['src','sim',*[str(p.relative_to(R)) for p in (R/'src').iterdir() if p.is_dir() and p.name != 'IP']]:
        cmd+=['-y',d]
    if name in ('tb_lrc_font_sync','tb_lrc_osd_equiv'): cmd+=['-y','sim/legacy']
    cmd+=['-s',name,'-o',str(output/f'{name}.vvp'),str(src)]
    if name in TOP_LEVEL_TESTS: cmd+=['src/top_tf_hdmi_audio.v','sim/integration/vendor_control_stubs.v']
    c=subprocess.run(cmd,cwd=R,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
    log=c.stdout+c.stderr
    if c.returncode==0:
        r=subprocess.run(['vvp',str(output/f'{name}.vvp')],cwd=R,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=150)
        log+=r.stdout+r.stderr
        ok=r.returncode==0 and 'PASS' in r.stdout and 'FAIL' not in log
    else: ok=False
    (output/f'{name}.log').write_text(log,encoding='utf-8')
    print(name+': '+('PASS' if ok else 'FAIL')+' '+ '\n'.join(x for x in log.splitlines() if 'PASS' in x or 'FAIL' in x),flush=True)
    if not ok: print(log[-6000:],flush=True)
    return ok
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('tests',nargs='*'); p.add_argument('--output',type=Path,default=Path('sim/s7_acceptance_fix'),help='independent output directory for this round'); a=p.parse_args()
    O=(R/a.output).resolve() if not a.output.is_absolute() else a.output.resolve()
    if is_archived_accepted(O):
        print(f'Refusing to overwrite accepted results in {O}',file=sys.stderr)
        raise SystemExit(2)
    O.mkdir(parents=True,exist_ok=True)
    names=list(a.tests or PRODUCTION_TESTS)
    results={name:run(name,O) for name in names}
    if not a.tests:
        # 48 sectors = 12288 samples, three complete wraps of the 4096-sample FIFO.
        src=(R/'sim/tb_wav_stream_player_flow.v').read_text(encoding='utf-8').replace('tb_wav_stream_player_flow','tb_s7_wav_wrap').replace('SECTORS = 12','SECTORS = 48')
        path=O/'tb_s7_wav_wrap.v';path.write_text(src,encoding='utf-8')
        results['tb_s7_wav_wrap']=run('tb_s7_wav_wrap',O,path)
    (O/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    raise SystemExit(0 if all(results.values()) else 1)
