"""S6 directed checks, with logs and hard failure on any assertion."""
from pathlib import Path
import subprocess
R=Path(__file__).resolve().parents[1]
O=R/'sim/s6_20261006';O.mkdir(exist_ok=True)
assets=subprocess.run(['python','-X','utf8','tools/test_s6_assets.py'],cwd=R,capture_output=True,text=True,encoding='utf-8',errors='replace')
(O/'assets.log').write_text(assets.stdout+assets.stderr,encoding='utf-8')
if assets.returncode:raise RuntimeError(assets.stdout+assets.stderr)
for top in ['tb_mv_sector_mux','tb_mv_stream_player','tb_mv_frame_scheduler','tb_mv_index','tb_mv_linear_write','tb_mv_bandwidth','tb_s6_video_layer','tb_mv_audio_shared']:
 out=O/(top+'.vvp')
 cmd=['iverilog','-g2005-sv','-I.','-Isrc/include','-y','src/video','-y','src/display','-y','src/SD','-y','src/io','-y','src/audio','-s',top,'-o',str(out),'sim/'+top+'.v']
 c=subprocess.run(cmd,cwd=R,capture_output=True,text=True,encoding='utf-8',errors='replace')
 r=subprocess.run(['vvp',str(out)],cwd=R,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90) if c.returncode==0 else c
 log=c.stdout+c.stderr+r.stdout+r.stderr
 (O/(top+'.log')).write_text(log,encoding='utf-8')
 print(top+': '+r.stdout,flush=True)
 if c.returncode or r.returncode or 'TEST_PASS' not in log:raise RuntimeError(log)
