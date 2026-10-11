from pathlib import Path
from collections import Counter
import hashlib
import json
import re

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
ctx = json.loads((OUT/'isolated_context.json').read_text(encoding='utf-8'))
net = Path(ctx['isolated'])/'prj/current_gate.v'
text = net.read_text(encoding='utf-8', errors='replace')
# TD writes one top-level parameterized primitive per block with named ports.
rx = re.compile(r'^  (\w+)\s*#\(.*?\)\s+\\(\S+)\s+\(.*?\);', re.M|re.S)
cells = [(m[1],m[2],m[0]) for m in rx.finditer(text)]
queries = {
    'encoder1_stable_counter':'/u_enc1/stable_count_reg[',
    'encoder2_stable_counter':'/u_enc2/stable_count_reg[',
    'directory_name':'/u_volume_scanner/dir_name',
    'font':'/u_shared_song_font/',
    'index_db':'/u_song_index_db/',
    'lyric_window':'u_lrc_window_controller/',
    'progress':'u_playback_progress/',
}
result = {'netlist':str(net),'primitive_count':len(cells),'primitive_types':dict(Counter(t for t,n,b in cells)),'queries':{}}
for key,part in queries.items():
    group = [(t,n,b) for t,n,b in cells if part in n]
    result['queries'][key] = {'types':dict(Counter(t for t,n,b in group)),'example_names':[n for t,n,b in group[:8]],'seq_names':[n for t,n,b in group if t=='AL_MAP_SEQ']}
rows = dict((int(i),int(v,16)) for i,v in re.findall(r'row_mem\[(\d+)\]\s*=\s*16\x27h([0-9a-fA-F]+)',(ROOT/'src/display/song_font_rom.v').read_text(encoding='utf-8')))
result['font_data'] = {'initialized_rows':len(rows),'unique_rows':len(set(rows.values())),'zero_rows':sum(v==0 for v in rows.values()),'bits':len(rows)*16}
result['source_invariance'] = []
for entry in json.loads((OUT/'input_manifest.json').read_text(encoding='utf-8')):
    actual=hashlib.sha256((ROOT/entry['path']).read_bytes()).hexdigest().upper()
    if actual!=entry['sha256']:
        result['source_invariance'].append(entry['path'])
(OUT/'netlist_inspection.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='queries'},ensure_ascii=True,indent=2))
for key,group in result['queries'].items():
    print(key,group['types'])
font_luts=[b for t,n,b in cells if '/u_shared_song_font/' in n and t.startswith('AL_MAP_LUT')]
(OUT/'font_address_examples.txt').write_text('\n\n'.join(font_luts[:5]),encoding='utf-8')
