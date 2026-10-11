from pathlib import Path
import json, re

BASE=Path('C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501')
OUT=Path(__file__).resolve().parent
rx=re.compile(r'^  (\w+)\s*#\(.*?\)\s+\\(\S+)\s+\(.*?\);',re.M|re.S)
result={}
for name in ('N1_before','N1_after','N2_before','N2_after','N2_polarity_after'):
    folder=BASE/name
    net=folder/('prj/mcp_gate_fresh.v' if name=='N1_before' else 'prj/mcp_gate.v')
    if not net.is_file():continue
    selected=[]
    for m in rx.finditer(net.read_text(encoding='utf-8',errors='replace')):
        if m[1]=='AL_MAP_SEQ' and any(s in m[2] for s in ('/dir_name','/dir_pos','/dir_pic_digit','/hdr_version')):
            selected.append({'name':m[2],'block':m[0]})
    result[name]={'count':len(selected),'cells':selected}
(OUT/'predicate_registers.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({n:v['count'] for n,v in result.items()},indent=2))
for name in ('N2_after','N2_polarity_after'):
    for cell in result.get(name,{}).get('cells',[]):
        if '/hdr_version' in cell['name']:
            print(name+' '+cell['block'])
