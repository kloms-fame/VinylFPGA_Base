from pathlib import Path
import json
import re

OUT=Path(__file__).resolve().parent
ctx=json.loads((OUT/'isolated_context.json').read_text(encoding='utf-8'))
p=Path(ctx['native_isolated'])/'prj/native_final.v'
text=p.read_text(encoding='utf-8',errors='replace')
name=r'\u_brightness_contrast_steps/blue_adj[5]_syn_48  ('
start=text.find(name)
assert start>=0
begin=text.rfind('\n  EG_PHY_',0,start)
end=text.find(');',start)+2
block=text[begin:end]
assert '.clk(sd_card_clk)' in block
assert '/u_song_index_db/hdr_version [7]' in block
(OUT/'native_critical_start_cell.txt').write_text(block,encoding='utf-8')
timing=(OUT/'current_native/final.timing').read_text(errors='replace')
first=timing.find('Slack               : 0.116ns')
last=timing.find('Slack               : 0.147ns',first)
(OUT/'native_critical_path.txt').write_text(timing[first:last],encoding='utf-8')
print('Verified: physical start cell q[0] is INDEX hdr_version[7], clocked by sd_card_clk.')
